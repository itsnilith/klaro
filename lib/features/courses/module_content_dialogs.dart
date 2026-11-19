import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../design/widgets.dart';
import 'module_quiz_generator.dart';

export 'module_quiz_generator.dart' show QuizDraft, QuizQuestionDraft;

typedef TextLessonDraft = ({String title, String text});
typedef _QuestionControllers = ({
  TextEditingController question,
  TextEditingController answer,
});

Future<TextLessonDraft?> showTextLessonCreator(
  BuildContext context, {
  required String moduleTitle,
}) {
  return showMSheet<TextLessonDraft>(
    context,
    maxWidth: 560,
    child: _TextLessonCreator(moduleTitle: moduleTitle),
  );
}

class _TextLessonCreator extends StatefulWidget {
  const _TextLessonCreator({required this.moduleTitle});

  final String moduleTitle;

  @override
  State<_TextLessonCreator> createState() => _TextLessonCreatorState();
}

class _TextLessonCreatorState extends State<_TextLessonCreator> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  var _invalid = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    if (_title.text.trim().isEmpty) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context)
        .pop((title: _title.text.trim(), text: _body.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add a text lesson',
            style: MType.h2.copyWith(color: context.c.ink),
          ),
          const SizedBox(height: 5),
          Text(
            'In ${widget.moduleTitle}',
            style: MType.small.copyWith(color: context.c.inkMuted),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const Key('text-lesson-title-field'),
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('text-lesson-body-field'),
            controller: _body,
            minLines: 6,
            maxLines: 12,
            maxLength: 20000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Lesson text',
              hintText: 'Write the material to study…',
              alignLabelWithHint: true,
            ),
          ),
          if (_invalid) ...[
            const SizedBox(height: 4),
            Text(
              'Enter a title for this lesson.',
              style: MType.small.copyWith(color: context.c.danger),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              MButton(
                key: const Key('add-text-lesson-submit'),
                label: 'Add lesson',
                kind: MButtonKind.primary,
                onPressed: _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<QuizDraft?> showQuizCreator(
  BuildContext context, {
  required String moduleTitle,
  QuizDraftGenerator? generateWithAi,
}) {
  return showMSheet<QuizDraft>(
    context,
    maxWidth: 600,
    child: _QuizCreator(
      moduleTitle: moduleTitle,
      generateWithAi: generateWithAi,
    ),
  );
}

class _QuizCreator extends StatefulWidget {
  const _QuizCreator({required this.moduleTitle, this.generateWithAi});

  final String moduleTitle;
  final QuizDraftGenerator? generateWithAi;

  @override
  State<_QuizCreator> createState() => _QuizCreatorState();
}

class _QuizCreatorState extends State<_QuizCreator> {
  final _title = TextEditingController();
  final _fields = <_QuestionControllers>[_newQuestionControllers()];
  final _removedFields = <_QuestionControllers>[];
  var _invalid = false;
  var _generationActive = false;
  var _generating = false;
  String? _generationError;

  static _QuestionControllers _newQuestionControllers() =>
      (question: TextEditingController(), answer: TextEditingController());

  bool get _hasContent =>
      _title.text.trim().isNotEmpty ||
      _fields.any(
        (field) =>
            field.question.text.trim().isNotEmpty ||
            field.answer.text.trim().isNotEmpty,
      );

  @override
  void dispose() {
    _title.dispose();
    for (final field in [..._fields, ..._removedFields]) {
      field.question.dispose();
      field.answer.dispose();
    }
    super.dispose();
  }

  Future<void> _generate() async {
    final generate = widget.generateWithAi;
    if (generate == null || _generationActive) return;
    _generationActive = true;
    try {
      if (_hasContent && !await _confirmReplacement()) return;
      if (!mounted) return;
      setState(() {
        _generating = true;
        _generationError = null;
        _invalid = false;
      });

      final draft = await generate();
      if (!mounted) return;
      if (draft.questions.isEmpty) {
        throw const ModuleQuizException(
          ModuleQuizError.noValidQuestions,
          'The AI response did not contain any complete questions and answers. Try again.',
        );
      }
      setState(() {
        _removedFields.addAll(_fields);
        _fields.clear();
        _title.text = draft.title;
        for (final question in draft.questions) {
          _fields.add((
            question: TextEditingController(text: question.question),
            answer: TextEditingController(text: question.answer),
          ));
        }
      });
    } on ModuleQuizException catch (error) {
      if (mounted) setState(() => _generationError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _generationError = 'The quiz could not be generated. Check the AI provider and try again.',
        );
      }
    } finally {
      _generationActive = false;
      if (mounted && _generating) setState(() => _generating = false);
    }
  }

  Future<bool> _confirmReplacement() async {
    final result = await showMSheet<bool>(
      context,
      maxWidth: 430,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Replace the current quiz draft?',
              style: MType.h2.copyWith(color: context.c.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Generating with AI replaces the title and questions already entered. '
              'If generation fails, your current draft stays unchanged.',
              style: MType.small.copyWith(
                color: context.c.inkMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                MButton(
                  key: const Key('quiz-replace-cancel'),
                  label: 'Keep my draft',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                MButton(
                  key: const Key('quiz-replace-confirm'),
                  label: 'Replace draft',
                  kind: MButtonKind.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  void _addQuestion() {
    setState(() => _fields.add(_newQuestionControllers()));
  }

  void _removeQuestion(int index) {
    setState(() => _removedFields.add(_fields.removeAt(index)));
  }

  void _submit() {
    final questions = _fields
        .map(
          (field) => (
            question: field.question.text.trim(),
            answer: field.answer.text.trim(),
          ),
        )
        .toList();
    if (_title.text.trim().isEmpty ||
        questions.any((q) => q.question.isEmpty || q.answer.isEmpty)) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context)
        .pop((title: _title.text.trim(), questions: questions));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MDialogHeader(
          title: 'Create a quiz',
          subtitle:
              'In ${widget.moduleTitle} · Answers also appear in Flashcards & Review',
        ),
        const MDivider(),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.generateWithAi != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: MButton(
                      key: const Key('quiz-generate-ai'),
                      label: 'Generate with AI',
                      icon: Icons.auto_awesome_rounded,
                      dense: true,
                      onPressed: _generating ? null : _generate,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Drafts use only this module\'s lessons, transcripts, and notes. '
                    'Nothing is saved until you create the quiz.',
                    style: MType.small.copyWith(
                      color: context.c.inkMuted,
                      height: 1.4,
                    ),
                  ),
                  if (_generating) ...[
                    const SizedBox(height: 12),
                    const Row(
                      key: Key('quiz-generation-progress'),
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Expanded(child: Text('Generating quiz draft…')),
                      ],
                    ),
                  ],
                  if (_generationError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _generationError!,
                      key: const Key('quiz-generation-error'),
                      style: MType.small.copyWith(
                        color: context.c.danger,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                ],
                TextField(
                  key: const Key('quiz-title-field'),
                  controller: _title,
                  enabled: !_generating,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Quiz title'),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < _fields.length; i++) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Question ${i + 1}',
                          style: MType.bodyStrong.copyWith(
                            color: context.c.ink,
                          ),
                        ),
                      ),
                      if (_fields.length > 1)
                        MIconButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Remove question',
                          size: 28,
                          onPressed: _generating
                              ? null
                              : () => _removeQuestion(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _questionFields(_fields[i], enabled: !_generating),
                  const SizedBox(height: 18),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: MButton(
                    key: const Key('quiz-add-question'),
                    label: 'Add another question',
                    icon: Icons.add_rounded,
                    dense: true,
                    onPressed: _generating ? null : _addQuestion,
                  ),
                ),
                if (_invalid) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Enter a quiz title and complete every question and answer.',
                    style: MType.small.copyWith(
                      color: context.c.danger,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MButton(
                key: const Key('quiz-cancel'),
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              MButton(
                key: const Key('add-quiz-submit'),
                label: 'Create quiz',
                kind: MButtonKind.primary,
                onPressed: _generating ? null : _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<QuizQuestionDraft?> showQuizQuestionEditor(BuildContext context) {
  return showMSheet<QuizQuestionDraft>(
    context,
    maxWidth: 500,
    child: const _QuizQuestionEditor(),
  );
}

class _QuizQuestionEditor extends StatefulWidget {
  const _QuizQuestionEditor();

  @override
  State<_QuizQuestionEditor> createState() => _QuizQuestionEditorState();
}

class _QuizQuestionEditorState extends State<_QuizQuestionEditor> {
  final _fields = _QuizCreatorState._newQuestionControllers();
  var _invalid = false;

  @override
  void dispose() {
    _fields.question.dispose();
    _fields.answer.dispose();
    super.dispose();
  }

  void _submit() {
    final question = _fields.question.text.trim();
    final answer = _fields.answer.text.trim();
    if (question.isEmpty || answer.isEmpty) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop((question: question, answer: answer));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add a quiz question',
            style: MType.h2.copyWith(color: context.c.ink),
          ),
          const SizedBox(height: 16),
          _questionFields(_fields),
          if (_invalid) ...[
            const SizedBox(height: 10),
            Text(
              'Complete both the question and its answer.',
              style: MType.small.copyWith(color: context.c.danger),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              MButton(
                key: const Key('add-quiz-question-submit'),
                label: 'Add question',
                kind: MButtonKind.primary,
                onPressed: _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _questionFields(_QuestionControllers fields, {bool enabled = true}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('quiz-question-field'),
        controller: fields.question,
        enabled: enabled,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Question',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        key: const Key('quiz-answer-field'),
        controller: fields.answer,
        enabled: enabled,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Answer',
          alignLabelWithHint: true,
        ),
      ),
    ],
  );
}
