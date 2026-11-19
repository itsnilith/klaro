import 'dart:convert';
import 'dart:math' as math;

import '../../core/db.dart';
import '../../core/models.dart';
import '../../services/ai.dart';
import '../notes/block_model.dart';

typedef QuizQuestionDraft = ({String question, String answer});
typedef QuizDraft = ({String title, List<QuizQuestionDraft> questions});
typedef QuizDraftGenerator = Future<QuizDraft> Function();
typedef ModuleQuizGeneratorOverride = Future<QuizDraft> Function(Module module);

enum ModuleQuizError {
  noDefaultProvider,
  noSourceText,
  providerFailure,
  malformedResponse,
  noValidQuestions,
}

class ModuleQuizException implements Exception {
  const ModuleQuizException(this.kind, this.message);

  final ModuleQuizError kind;
  final String message;

  @override
  String toString() => message;
}

/// The small part of [AiClient] needed by quiz generation.
///
/// Keeping the streaming callbacks here also makes callback-reported failures
/// testable without changing the app's global AI client.
abstract interface class QuizAiTransport {
  Future<void> streamChat({
    required AiProvider provider,
    required List<ChatTurn> messages,
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(Object error) onError,
    double? temperature,
    bool applyGlobalInstructions = true,
  });
}

class _AiClientQuizTransport implements QuizAiTransport {
  final _client = AiClient();

  @override
  Future<void> streamChat({
    required AiProvider provider,
    required List<ChatTurn> messages,
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(Object error) onError,
    double? temperature,
    bool applyGlobalInstructions = true,
  }) {
    return _client.streamChat(
      provider: provider,
      messages: messages,
      onDelta: onDelta,
      onDone: onDone,
      onError: onError,
      temperature: temperature,
      applyGlobalInstructions: applyGlobalInstructions,
    );
  }
}

class ModuleQuizGenerator {
  ModuleQuizGenerator({
    required this.module,
    Store? store,
    QuizAiTransport? transport,
  }) : _store = store ?? Store.i,
       _transport = transport ?? _AiClientQuizTransport();

  final Module module;
  final Store _store;
  final QuizAiTransport _transport;

  Future<QuizDraft> generate() async {
    final provider = await _store.defaultProvider();
    if (provider == null) {
      throw const ModuleQuizException(
        ModuleQuizError.noDefaultProvider,
        'Choose a default AI provider in Settings before generating a quiz.',
      );
    }

    final collected = await _collectSource();
    if (!collected.hasUsableText) {
      throw const ModuleQuizException(
        ModuleQuizError.noSourceText,
        'This module has no usable lesson text, transcripts, or notes to generate from.',
      );
    }
    final source = _boundSource(collected.entries, provider.contextWindow);
    final output = StringBuffer();
    Object? callbackError;
    var callbackFailed = false;

    try {
      await _transport.streamChat(
        provider: provider,
        messages: [
          ChatTurn(
            role: 'system',
            content:
                'Write exactly 5 concise retrieval-practice question-and-answer pairs grounded only in the supplied module material. '
                'Questions should test understanding rather than wording, and answers should be brief and self-contained. '
                'Return ONLY one strict JSON object with this shape: {"title":"...","questions":[{"question":"...","answer":"..."}]}. '
                'Use the module name for a useful title. Do not use Markdown, code fences, commentary, or extra text; do not use Markdown inside any field.',
          ),
          ChatTurn(
            role: 'user',
            content:
                'Create a five-question quiz for the module "${module.title.trim()}". '
                'Use only this material; do not import outside knowledge:\n\n$source',
          ),
        ],
        onDelta: output.write,
        onDone: () {},
        onError: (error) {
          callbackFailed = true;
          callbackError = error;
        },
        temperature: 0.2,
        applyGlobalInstructions: false,
      );
    } catch (error) {
      throw _providerFailure(error, provider);
    }

    if (callbackFailed) {
      throw _providerFailure(callbackError!, provider);
    }
    return parseModuleQuizDraft(output.toString(), moduleTitle: module.title);
  }

  Future<_CollectedSource> _collectSource() async {
    final lessons =
        (await _store.lessons(module.courseId))
            .where(
              (lesson) => lesson.moduleId == module.id && lesson.kind != 'quiz',
            )
            .toList()
          ..sort((a, b) {
            final byPosition = a.position.compareTo(b.position);
            return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
          });

    final entries = <String>[];
    var hasUsableText = false;
    for (final lesson in lessons) {
      entries.add('Lesson: ${lesson.title.trim()}');

      final description = lesson.description?.trim() ?? '';
      if (description.isNotEmpty) {
        hasUsableText = true;
        entries.add('Lesson description:\n$description');
      }

      final transcript = await _store.transcriptFor('lesson', lesson.id);
      final transcriptText = transcript?.segments
          .map((segment) => segment.text.trim())
          .where((text) => text.isNotEmpty)
          .join('\n');
      if (transcriptText != null && transcriptText.isNotEmpty) {
        hasUsableText = true;
        entries.add('Lesson transcript:\n$transcriptText');
      }

      final notes = await _store.notes(lessonId: lesson.id);
      notes.sort((a, b) {
        final byPosition = a.position.compareTo(b.position);
        if (byPosition != 0) return byPosition;
        final byCreation = a.createdAt.compareTo(b.createdAt);
        return byCreation != 0 ? byCreation : a.id.compareTo(b.id);
      });
      for (final note in notes) {
        final blocks = _orderedBlocks(await _store.blocksFor(note.id));
        final blockText = blocks
            .map((block) => block.text.trim())
            .where((text) => text.isNotEmpty)
            .join('\n');
        final body = note.body.trim();
        final noteTitle = note.title.trim();
        if (body.isNotEmpty || blockText.isNotEmpty) hasUsableText = true;
        if (noteTitle.isEmpty && body.isEmpty && blockText.isEmpty) continue;
        final noteBody = [
          body,
          blockText,
        ].where((text) => text.isNotEmpty).join('\n');
        entries.add(
          'Linked note${noteTitle.isEmpty ? '' : ': $noteTitle'}'
          '${noteBody.isEmpty ? '' : '\n$noteBody'}',
        );
      }
    }
    return (entries: entries, hasUsableText: hasUsableText);
  }
}

typedef _CollectedSource = ({List<String> entries, bool hasUsableText});

ModuleQuizException _providerFailure(Object error, AiProvider provider) {
  var detail = error is AiException ? error.message : error.toString();
  if (provider.apiKey.isNotEmpty) {
    detail = detail.replaceAll(provider.apiKey, '[redacted]');
  }
  detail = detail
      .replaceAllMapped(
        RegExp(r'(bearer\s+)[^\s,;}"]+', caseSensitive: false),
        (match) => '${match[1]}[redacted]',
      )
      .replaceAllMapped(
        RegExp(r'(api[_ -]?key\s*[:=]\s*)[^\s,;}"]+', caseSensitive: false),
        (match) => '${match[1]}[redacted]',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (detail.startsWith('Exception: ')) {
    detail = detail.substring('Exception: '.length);
  }
  if (detail.isEmpty) detail = 'The provider did not complete the request.';
  if (detail.length > 400) detail = '${detail.substring(0, 400)}…';
  return ModuleQuizException(
    ModuleQuizError.providerFailure,
    'The AI provider could not generate the quiz: $detail',
  );
}

QuizDraft parseModuleQuizDraft(String raw, {required String moduleTitle}) {
  var text = raw.trim();
  final fence = RegExp(
    r'^```(?:json)?[\t ]*\r?\n(.*?)\r?\n?```$',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(text);
  if (fence != null) text = fence[1]!.trim();

  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw _malformedResponse;
  }
  if (decoded is! Map) throw _malformedResponse;
  final rawTitle = decoded['title'];
  final rawQuestions = decoded['questions'];
  if (rawTitle is! String || rawQuestions is! List) {
    throw _malformedResponse;
  }

  final questions = <QuizQuestionDraft>[];
  for (final item in rawQuestions) {
    if (item is! Map) throw _malformedResponse;
    final question = item['question'];
    final answer = item['answer'];
    if (question is! String || answer is! String) {
      throw _malformedResponse;
    }
    final trimmedQuestion = question.trim();
    final trimmedAnswer = answer.trim();
    if (trimmedQuestion.isNotEmpty && trimmedAnswer.isNotEmpty) {
      questions.add((question: trimmedQuestion, answer: trimmedAnswer));
    }
  }
  if (questions.isEmpty) {
    throw const ModuleQuizException(
      ModuleQuizError.noValidQuestions,
      'The AI response did not contain any complete questions and answers. Try again.',
    );
  }
  final title = rawTitle.trim();
  return (
    title: title.isEmpty ? '${moduleTitle.trim()} quiz' : title,
    questions: questions,
  );
}

const _malformedResponse = ModuleQuizException(
  ModuleQuizError.malformedResponse,
  'The AI response was not valid quiz JSON. Try generating again.',
);

/// Gives every collected item a share of the budget and truncates long items
/// from the middle, so a long early transcript cannot crowd out later lessons.
String _boundSource(List<String> entries, int contextWindow) {
  if (entries.isEmpty) return '';
  final window = math.max(1024, contextWindow);
  final budget = math.min(180000, math.max(1024, (window * 0.60).floor() * 3));
  const separator = '\n\n';
  final separatorSpace = separator.length * (entries.length - 1);
  final contentBudget = math.max(entries.length, budget - separatorSpace);
  final share = contentBudget ~/ entries.length;
  final remainder = contentBudget % entries.length;
  final bounded = <String>[
    for (var i = 0; i < entries.length; i++)
      _truncateMiddle(entries[i].trim(), share + (i < remainder ? 1 : 0)),
  ];
  final result = bounded.join(separator);
  return result.length <= budget ? result : result.substring(0, budget);
}

String _truncateMiddle(String text, int maximum) {
  if (text.length <= maximum) return text;
  if (maximum <= 1) return text.substring(0, maximum);
  const marker = ' … ';
  final available = maximum - marker.length;
  if (available <= 0) return text.substring(0, maximum);
  final headLength = (available + 1) ~/ 2;
  final tailLength = available - headLength;
  final head = text.substring(0, headLength).trimRight();
  final tail = tailLength == 0
      ? ''
      : text.substring(text.length - tailLength).trimLeft();
  return '$head$marker$tail';
}

/// Depth-first document order with stable tie-breaking for SQLite rows whose
/// order is unspecified. Orphaned and cyclic records remain usable source text.
List<NoteBlock> _orderedBlocks(List<NoteBlock> source) {
  final byId = <String, NoteBlock>{for (final block in source) block.id: block};
  final ordered = <NoteBlock>[];
  final visited = <String>{};

  int compare(NoteBlock a, NoteBlock b) {
    final bySortKey = a.sortKey.compareTo(b.sortKey);
    return bySortKey != 0 ? bySortKey : a.id.compareTo(b.id);
  }

  void visit(NoteBlock block) {
    if (!visited.add(block.id)) return;
    ordered.add(block);
    final children =
        source.where((candidate) => candidate.parentId == block.id).toList()
          ..sort(compare);
    for (final child in children) {
      visit(child);
    }
  }

  final roots =
      source
          .where(
            (block) =>
                block.parentId == null || !byId.containsKey(block.parentId),
          )
          .toList()
        ..sort(compare);
  for (final root in roots) {
    visit(root);
  }
  final remaining =
      source.where((block) => !visited.contains(block.id)).toList()
        ..sort((a, b) {
          final byParent = (a.parentId ?? '').compareTo(b.parentId ?? '');
          return byParent != 0 ? byParent : compare(a, b);
        });
  for (final block in remaining) {
    visit(block);
  }
  return ordered;
}
