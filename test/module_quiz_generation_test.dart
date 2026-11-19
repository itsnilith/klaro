import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klaro/core/db.dart';
import 'package:klaro/core/models.dart';
import 'package:klaro/design/tokens.dart';
import 'package:klaro/design/widgets.dart';
import 'package:klaro/features/courses/courses_page.dart';
import 'package:klaro/features/courses/module_quiz_generator.dart';
import 'package:klaro/features/notes/block_model.dart';
import 'package:klaro/services/ai.dart';

import 'test_paths.dart';

const _validResponse =
    '{"title":" Generated quiz ","questions":['
    '{"question":" First question? ","answer":" First answer. "},'
    '{"question":"Second question?","answer":"Second answer."}]}';

class _FakeTransport implements QuizAiTransport {
  String response = _validResponse;
  Object? callbackError;
  Object? thrownError;
  var calls = 0;
  AiProvider? provider;
  List<ChatTurn> messages = const [];
  double? temperature;
  bool? globalInstructions;

  @override
  Future<void> streamChat({
    required AiProvider provider,
    required List<ChatTurn> messages,
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(Object error) onError,
    double? temperature,
    bool applyGlobalInstructions = true,
  }) async {
    calls++;
    this.provider = provider;
    this.messages = messages;
    this.temperature = temperature;
    globalInstructions = applyGlobalInstructions;
    if (thrownError != null) throw thrownError!;
    onDelta(response);
    if (callbackError != null) {
      onError(callbackError!);
      return;
    }
    onDone();
  }
}

class _Fixture {
  const _Fixture({required this.course, required this.module});

  final Course course;
  final Module module;
}

var _sequence = 0;

Future<_Fixture> _createFixture() async {
  final id =
      'quiz-generation-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
  final now = DateTime.now();
  final course = Course(
    id: 'course-$id',
    title: 'AI quiz course',
    createdAt: now,
    updatedAt: now,
  );
  final module = Module(
    id: 'module-$id',
    courseId: course.id,
    title: 'Module A',
    position: 0,
  );
  await Store.i.saveCourse(course);
  await Store.i.saveModule(module);
  await Store.i.saveLesson(
    Lesson(
      id: 'initial-$id',
      courseId: course.id,
      moduleId: module.id,
      title: 'Initial lesson',
      position: 0,
      createdAt: now,
    ),
  );
  return _Fixture(course: course, module: module);
}

Future<AiProvider> _saveProvider(
  _Fixture fixture, {
  int contextWindow = 8192,
  String apiKey = 'test-api-key',
}) {
  final provider = AiProvider(
    id: 'provider-${fixture.course.id}',
    name: 'Test provider',
    kind: 'openai',
    baseUrl: 'https://provider.invalid/v1',
    model: 'test-model',
    apiKey: apiKey,
    contextWindow: contextWindow,
    isDefault: true,
  );
  return Store.i.saveProvider(provider).then((_) => provider);
}

Future<void> _addSource(
  _Fixture fixture, [
  String text = 'Usable source text.',
]) async {
  final lesson = (await Store.i.lessons(fixture.course.id)).singleWhere(
    (item) =>
        item.moduleId == fixture.module.id && item.title == 'Initial lesson',
  );
  await Store.i.saveLesson(lesson.copyWith(description: text));
}

Future<Lesson> _saveLesson({
  required Course course,
  required Module module,
  required String id,
  required String title,
  int position = 0,
  String kind = 'text',
  String? description,
}) {
  final lesson = Lesson(
    id: id,
    courseId: course.id,
    moduleId: module.id,
    title: title,
    kind: kind,
    description: description,
    position: position,
    createdAt: DateTime.now(),
  );
  return Store.i.saveLesson(lesson).then((_) => lesson);
}

Future<Note> _saveNote({
  required String id,
  required String courseId,
  required String lessonId,
  required String title,
  String body = '',
}) {
  final now = DateTime.now();
  final note = Note(
    id: id,
    title: title,
    body: body,
    courseId: courseId,
    lessonId: lessonId,
    createdAt: now,
    updatedAt: now,
  );
  return Store.i.saveNote(note).then((_) => note);
}

Future<void> _saveTranscript(Lesson lesson, String text) {
  return Store.i.saveTranscript(
    ownerType: 'lesson',
    ownerId: lesson.id,
    language: 'en',
    source: 'test',
    segments: [TranscriptSegment(startMs: 0, endMs: 1, text: text)],
  );
}

TypeMatcher<ModuleQuizException> _errorOfType(ModuleQuizError kind) =>
    isA<ModuleQuizException>()
        .having((error) => error.kind, 'kind', kind)
        .having((error) => error.message.trim(), 'message', isNotEmpty);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Fixture fixture;

  setUpAll(() async {
    testPaths();
    await Store.open();
  });

  setUp(() async {
    for (final provider in await Store.i.providers()) {
      await Store.i.deleteProvider(provider.id);
    }
    fixture = await _createFixture();
  });

  group('ModuleQuizGenerator', () {
    test(
      'uses only selected non-quiz module material, including ordered blocks',
      () async {
        final transport = _FakeTransport();
        await _saveProvider(fixture);
        final first = await _saveLesson(
          course: fixture.course,
          module: fixture.module,
          id: 'selected-transcript-${fixture.course.id}',
          title: 'Selected transcript lesson',
          position: 1,
        );
        await _saveTranscript(first, 'Selected transcript body');
        final second = await _saveLesson(
          course: fixture.course,
          module: fixture.module,
          id: 'selected-text-${fixture.course.id}',
          title: 'Selected text lesson',
          description: 'Selected lesson description',
          position: 2,
        );
        final note = await _saveNote(
          id: 'selected-note-${fixture.course.id}',
          courseId: fixture.course.id,
          lessonId: second.id,
          title: 'Selected note',
          body: 'Selected note body',
        );
        await Store.i.replaceBlocks(note.id, [
          NoteBlock(
            id: 'block-b-${fixture.course.id}',
            noteId: note.id,
            sortKey: 'b',
            type: BType.text,
            text: 'Second block marker',
          ),
          NoteBlock(
            id: 'block-a-${fixture.course.id}',
            noteId: note.id,
            sortKey: 'a',
            type: BType.text,
            text: 'First block marker',
          ),
        ]);

        final otherModule = Module(
          id: 'other-module-${fixture.course.id}',
          courseId: fixture.course.id,
          title: 'Other module',
          position: 1,
        );
        await Store.i.saveModule(otherModule);
        final otherModuleLesson = await _saveLesson(
          course: fixture.course,
          module: otherModule,
          id: 'other-module-lesson-${fixture.course.id}',
          title: 'EXCLUDED_OTHER_MODULE_TITLE',
          description: 'EXCLUDED_OTHER_MODULE_DESCRIPTION',
        );
        await _saveTranscript(
          otherModuleLesson,
          'EXCLUDED_OTHER_MODULE_TRANSCRIPT',
        );
        await _saveNote(
          id: 'other-module-note-${fixture.course.id}',
          courseId: fixture.course.id,
          lessonId: otherModuleLesson.id,
          title: 'EXCLUDED_OTHER_MODULE_NOTE',
          body: 'EXCLUDED_OTHER_MODULE_NOTE_BODY',
        );

        final quiz = await _saveLesson(
          course: fixture.course,
          module: fixture.module,
          id: 'existing-quiz-${fixture.course.id}',
          title: 'EXCLUDED_QUIZ_TITLE',
          description: 'EXCLUDED_QUIZ_DESCRIPTION',
          kind: 'quiz',
          position: 3,
        );
        await _saveTranscript(quiz, 'EXCLUDED_QUIZ_TRANSCRIPT');
        await _saveNote(
          id: 'quiz-note-${fixture.course.id}',
          courseId: fixture.course.id,
          lessonId: quiz.id,
          title: 'EXCLUDED_QUIZ_NOTE',
          body: 'EXCLUDED_QUIZ_NOTE_BODY',
        );

        final now = DateTime.now();
        final otherCourse = Course(
          id: 'other-course-${fixture.course.id}',
          title: 'Other course',
          createdAt: now,
          updatedAt: now,
        );
        final otherCourseModule = Module(
          id: 'other-course-module-${fixture.course.id}',
          courseId: otherCourse.id,
          title: 'Other course module',
          position: 0,
        );
        await Store.i.saveCourse(otherCourse);
        await Store.i.saveModule(otherCourseModule);
        await _saveLesson(
          course: otherCourse,
          module: otherCourseModule,
          id: 'other-course-lesson-${fixture.course.id}',
          title: 'EXCLUDED_OTHER_COURSE_TITLE',
          description: 'EXCLUDED_OTHER_COURSE_DESCRIPTION',
        );
        final nowNote = DateTime.now();
        await Store.i.saveNote(
          Note(
            id: 'course-only-${fixture.course.id}',
            title: 'EXCLUDED_COURSE_ONLY_NOTE',
            body: 'EXCLUDED_COURSE_ONLY_BODY',
            courseId: fixture.course.id,
            createdAt: nowNote,
            updatedAt: nowNote,
          ),
        );

        transport.response =
            '{"title":"","questions":[{"question":"Q","answer":"A"}]}';
        final draft = await ModuleQuizGenerator(
          module: fixture.module,
          transport: transport,
        ).generate();

        final prompt = transport.messages
            .map((message) => message.content)
            .join('\n');
        for (final included in [
          'Selected transcript lesson',
          'Selected transcript body',
          'Selected text lesson',
          'Selected lesson description',
          'Selected note',
          'Selected note body',
          'First block marker',
          'Second block marker',
        ]) {
          expect(prompt, contains(included));
        }
        expect(
          prompt.indexOf('First block marker'),
          lessThan(prompt.indexOf('Second block marker')),
        );
        for (final excluded in [
          'EXCLUDED_OTHER_MODULE',
          'EXCLUDED_QUIZ',
          'EXCLUDED_OTHER_COURSE',
          'EXCLUDED_COURSE_ONLY',
        ]) {
          expect(prompt, isNot(contains(excluded)));
        }
        expect(draft.title, 'Module A quiz');
        expect(transport.temperature, 0.2);
        expect(transport.globalInstructions, isFalse);
        expect(transport.messages.first.role, 'system');
        expect(transport.messages.first.content, contains('exactly 5'));
        expect(transport.messages.first.content, contains('grounded only'));
        expect(
          transport.messages.first.content,
          contains('Do not use Markdown'),
        );
      },
    );

    test(
      'bounds long early material without dropping later lesson coverage',
      () async {
        final transport = _FakeTransport();
        await _saveProvider(fixture, contextWindow: 1024);
        await _addSource(fixture, '${'Early source. ' * 1000}EARLY_SOURCE_END');
        await _saveLesson(
          course: fixture.course,
          module: fixture.module,
          id: 'later-${fixture.course.id}',
          title: 'Later lesson title',
          description: 'LATER_LESSON_DESCRIPTION',
          position: 1,
        );

        await ModuleQuizGenerator(
          module: fixture.module,
          transport: transport,
        ).generate();

        final userPrompt = transport.messages.last.content;
        expect(userPrompt.length, lessThan(4000));
        expect(userPrompt, contains('Initial lesson'));
        expect(userPrompt, contains('EARLY_SOURCE_END'));
        expect(userPrompt, contains('Later lesson title'));
        expect(userPrompt, contains('LATER_LESSON_DESCRIPTION'));
      },
    );

    test('reports a missing default provider without calling AI', () async {
      final transport = _FakeTransport();
      await _addSource(fixture);
      await expectLater(
        ModuleQuizGenerator(
          module: fixture.module,
          transport: transport,
        ).generate(),
        throwsA(_errorOfType(ModuleQuizError.noDefaultProvider)),
      );
      expect(transport.calls, 0);
    });

    test(
      'reports no usable source when only an empty lesson and a quiz exist',
      () async {
        final transport = _FakeTransport();
        await _saveProvider(fixture);
        await _saveLesson(
          course: fixture.course,
          module: fixture.module,
          id: 'only-quiz-${fixture.course.id}',
          title: 'Quiz with hidden source',
          description: 'This must not make generation possible.',
          kind: 'quiz',
        );

        await expectLater(
          ModuleQuizGenerator(
            module: fixture.module,
            transport: transport,
          ).generate(),
          throwsA(_errorOfType(ModuleQuizError.noSourceText)),
        );
        expect(transport.calls, 0);
      },
    );

    test(
      'turns a provider onError callback into a redacted typed failure',
      () async {
        const secret = 'callback-secret-key';
        final transport = _FakeTransport()
          ..callbackError = Exception('HTTP 401 with apiKey=$secret');
        await _saveProvider(fixture, apiKey: secret);
        await _addSource(fixture);

        try {
          await ModuleQuizGenerator(
            module: fixture.module,
            transport: transport,
          ).generate();
          fail('Generation should have failed');
        } on ModuleQuizException catch (error) {
          expect(error.kind, ModuleQuizError.providerFailure);
          expect(error.message, contains('HTTP 401'));
          expect(error.message, contains('[redacted]'));
          expect(error.message, isNot(contains(secret)));
        }
      },
    );

    test(
      'turns thrown provider exceptions into typed user-readable failures',
      () async {
        final transport = _FakeTransport()
          ..thrownError = StateError('Provider is offline.');
        await _saveProvider(fixture);
        await _addSource(fixture);

        await expectLater(
          ModuleQuizGenerator(
            module: fixture.module,
            transport: transport,
          ).generate(),
          throwsA(
            _errorOfType(ModuleQuizError.providerFailure).having(
              (error) => error.message,
              'message',
              contains('Provider is offline.'),
            ),
          ),
        );
      },
    );
  });

  group('parseModuleQuizDraft', () {
    test('parses and trims a single surrounding JSON fence', () {
      final draft = parseModuleQuizDraft(
        '```json\n$_validResponse\n```',
        moduleTitle: 'Module A',
      );
      expect(draft.title, 'Generated quiz');
      expect(draft.questions, hasLength(2));
      expect(draft.questions.first.question, 'First question?');
      expect(draft.questions.first.answer, 'First answer.');
    });

    test('rejects malformed JSON and invalid schema types', () {
      for (final response in [
        'not JSON',
        'prefix $_validResponse suffix',
        '[]',
        '{"title":3,"questions":[]}',
        '{"title":"Quiz","questions":[{"question":3,"answer":"A"}]}',
        '```text\n$_validResponse\n```',
      ]) {
        expect(
          () => parseModuleQuizDraft(response, moduleTitle: 'Module A'),
          throwsA(_errorOfType(ModuleQuizError.malformedResponse)),
          reason: response,
        );
      }
    });

    test('rejects a response with zero complete questions', () {
      expect(
        () => parseModuleQuizDraft(
          '{"title":"Quiz","questions":['
          '{"question":" ","answer":"A"},'
          '{"question":"Q","answer":"  "}]}',
          moduleTitle: 'Module A',
        ),
        throwsA(_errorOfType(ModuleQuizError.noValidQuestions)),
      );
    });
  });

  group('quiz creator AI drafting', () {
    Future<void> settleDb(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 450)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    Future<void> pumpCourse(
      WidgetTester tester, {
      ModuleQuizGeneratorOverride? generator,
    }) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: CourseDetailPage(
              courseId: fixture.course.id,
              quizGenerator: generator,
            ),
          ),
        ),
      );
      await settleDb(tester);
    }

    Future<void> openQuizCreator(WidgetTester tester) async {
      final add = find.byTooltip('Add content to ${fixture.module.title}');
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add quiz'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quiz-generate-ai')), findsOneWidget);
    }

    Future<List<Lesson>> quizzes(WidgetTester tester) async {
      final lessons =
          await tester.runAsync(() => Store.i.lessons(fixture.course.id)) ??
          <Lesson>[];
      return lessons.where((lesson) => lesson.kind == 'quiz').toList();
    }

    testWidgets('generated fields stay editable and save only on Create quiz', (
      tester,
    ) async {
      String? generatedModuleId;
      await pumpCourse(
        tester,
        generator: (module) async {
          generatedModuleId = module.id;
          return (
            title: 'AI generated title',
            questions: [
              (question: 'Generated question 1', answer: 'Generated answer 1'),
              (question: 'Generated question 2', answer: 'Generated answer 2'),
            ],
          );
        },
      );
      await openQuizCreator(tester);
      await tester.tap(find.byKey(const Key('quiz-generate-ai')));
      await tester.pumpAndSettle();

      expect(generatedModuleId, fixture.module.id);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('quiz-title-field')))
            .controller!
            .text,
        'AI generated title',
      );
      expect(find.byKey(const Key('quiz-question-field')), findsNWidgets(2));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('quiz-question-field')).first,
            )
            .controller!
            .text,
        'Generated question 1',
      );
      expect(await quizzes(tester), isEmpty);

      await tester.enterText(
        find.byKey(const Key('quiz-title-field')),
        'Edited generated title',
      );
      await tester.enterText(
        find.byKey(const Key('quiz-question-field')).first,
        'Edited generated question',
      );
      await tester.enterText(
        find.byKey(const Key('quiz-answer-field')).first,
        'Edited generated answer',
      );
      expect(await quizzes(tester), isEmpty);

      await tester.tap(find.byKey(const Key('add-quiz-submit')));
      await settleDb(tester);
      final saved = (await quizzes(tester)).single;
      expect(saved.title, 'Edited generated title');
      expect(saved.moduleId, fixture.module.id);
      final questions = await tester.runAsync(
        () => Store.i.cardsForLesson(saved.id),
      );
      expect(questions!.map((question) => question.front), [
        'Edited generated question',
        'Generated question 2',
      ]);
      expect(questions.first.back, 'Edited generated answer');
    });

    testWidgets(
      'replacement requires confirmation and failure preserves manual content',
      (tester) async {
        var calls = 0;
        var failGeneration = true;
        await pumpCourse(
          tester,
          generator: (_) async {
            calls++;
            if (failGeneration) {
              throw const ModuleQuizException(
                ModuleQuizError.providerFailure,
                'The provider is offline; try again.',
              );
            }
            return (
              title: 'Retry draft',
              questions: [(question: 'Retry question', answer: 'Retry answer')],
            );
          },
        );
        await openQuizCreator(tester);
        await tester.enterText(
          find.byKey(const Key('quiz-title-field')),
          'Manual title',
        );
        await tester.enterText(
          find.byKey(const Key('quiz-question-field')),
          'Manual question',
        );
        await tester.enterText(
          find.byKey(const Key('quiz-answer-field')),
          'Manual answer',
        );

        await tester.tap(find.byKey(const Key('quiz-generate-ai')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quiz-replace-cancel')));
        await tester.pumpAndSettle();
        expect(calls, 0);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('quiz-title-field')))
              .controller!
              .text,
          'Manual title',
        );

        await tester.tap(find.byKey(const Key('quiz-generate-ai')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quiz-replace-confirm')));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(find.byKey(const Key('quiz-generation-error')), findsOneWidget);
        expect(
          find.text('The provider is offline; try again.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('quiz-title-field')))
              .controller!
              .text,
          'Manual title',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('quiz-question-field')))
              .controller!
              .text,
          'Manual question',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('quiz-answer-field')))
              .controller!
              .text,
          'Manual answer',
        );
        expect(
          tester
              .widget<MButton>(find.byKey(const Key('quiz-generate-ai')))
              .onPressed,
          isNotNull,
        );
        expect(await quizzes(tester), isEmpty);

        failGeneration = false;
        await tester.tap(find.byKey(const Key('quiz-generate-ai')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quiz-replace-confirm')));
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(find.byKey(const Key('quiz-generation-error')), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('quiz-title-field')))
              .controller!
              .text,
          'Retry draft',
        );
        expect(await quizzes(tester), isEmpty);
        await tester.tap(find.byKey(const Key('quiz-cancel')));
        await tester.pumpAndSettle();
        expect(await quizzes(tester), isEmpty);
      },
    );

    testWidgets('generation cannot overlap and Cancel remains usable', (
      tester,
    ) async {
      final pending = Completer<QuizDraft>();
      var calls = 0;
      await pumpCourse(
        tester,
        generator: (_) {
          calls++;
          return pending.future;
        },
      );
      await openQuizCreator(tester);
      await tester.tap(find.byKey(const Key('quiz-generate-ai')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('quiz-generate-ai')));
      await tester.pump();

      expect(calls, 1);
      expect(find.byKey(const Key('quiz-generation-progress')), findsOneWidget);
      expect(find.text('Generating quiz draft…'), findsOneWidget);
      expect(
        tester
            .widget<MButton>(find.byKey(const Key('add-quiz-submit')))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<MButton>(find.byKey(const Key('quiz-cancel'))).onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('quiz-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quiz-generate-ai')), findsNothing);
      pending.complete((
        title: 'Late result',
        questions: [(question: 'Late question', answer: 'Late answer')],
      ));
      await tester.pump();
      await tester.pump();
      expect(await quizzes(tester), isEmpty);
    });
  });
}
