import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:klaro/core/db.dart';
import 'package:klaro/core/models.dart';
import 'package:klaro/design/tokens.dart';
import 'package:klaro/features/courses/courses_page.dart';

import 'test_paths.dart';

class _FakeFilePicker extends FilePicker {
  List<String> paths = const [];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return FilePickerResult([
      for (final path in paths)
        PlatformFile(path: path, name: p.basename(path), size: 1),
    ]);
  }
}

void main() {
  late Directory root;
  late Course course;
  late Module module;
  late _FakeFilePicker picker;

  setUpAll(() async {
    testPaths();
    await Store.open();
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('klaro-module-content-');
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch;
    course = Course(
      id: 'course-$id',
      title: 'Authoring course',
      createdAt: now,
      updatedAt: now,
    );
    module = Module(
      id: 'module-$id',
      courseId: course.id,
      title: 'Module A',
      position: 0,
    );
    await Store.i.saveCourse(course);
    await Store.i.saveModule(module);
    await Store.i.saveLesson(
      Lesson(
        id: 'existing-$id',
        courseId: course.id,
        moduleId: module.id,
        title: 'Existing lesson',
        position: 0,
        createdAt: now,
      ),
    );
    picker = _FakeFilePicker();
    FilePicker.platform = picker;
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> settleDb(WidgetTester tester) async {
    // Finish the route/sheet transition first: its new page starts database
    // work only once mounted. Then give that real async work time to finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Bounded frames avoid confusing repeating animations with a blocked UI.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }

  Future<void> pumpCourse(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: CourseDetailPage(courseId: course.id)),
      ),
    );
    await settleDb(tester);
  }

  Future<void> chooseModuleAction(WidgetTester tester, String action) async {
    final add = find.byTooltip('Add content to ${module.title}');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  test('deleting a quiz cleans only its own questions', () async {
    final now = DateTime.now();
    final existing = (await Store.i.lessons(course.id)).single;
    final regularCard = Flashcard(
      id: 'regular-card-${course.id}',
      deck: 'Independent study',
      front: 'Keep this question',
      back: 'Keep this answer',
      courseId: course.id,
      lessonId: existing.id,
      dueAt: now,
      createdAt: now,
    );
    await Store.i.saveCard(regularCard);
    await Store.i.deleteLesson(existing.id);
    expect(
      (await Store.i.cardsForLesson(existing.id)).single.id,
      regularCard.id,
    );

    final quiz = Lesson(
      id: 'quiz-${course.id}',
      courseId: course.id,
      moduleId: module.id,
      title: 'Disposable quiz',
      kind: 'quiz',
      position: 1,
      createdAt: now,
    );
    final quizCard = Flashcard(
      id: 'quiz-card-${course.id}',
      deck: 'Quiz: Disposable quiz',
      front: 'Delete this question',
      back: 'Delete this answer',
      courseId: course.id,
      lessonId: quiz.id,
      dueAt: now,
      createdAt: now,
    );
    await Store.i.createQuiz(quiz, [quizCard]);
    await Store.i.deleteLesson(quiz.id);
    expect(await Store.i.cardsForLesson(quiz.id), isEmpty);
  });

  testWidgets('module + imports media into that module', (tester) async {
    final video = File(p.join(root.path, 'New lesson.mp4'))
      ..writeAsStringSync('video');
    final audio = File(p.join(root.path, 'Audio lesson.mp3'))
      ..writeAsStringSync('audio');
    await pumpCourse(tester);
    expect(find.byTooltip('Add content to ${module.title}'), findsOneWidget);
    picker.paths = [video.path, audio.path];

    await chooseModuleAction(tester, 'Add video or audio lessons');
    await settleDb(tester);

    final lessons =
        await tester.runAsync(() => Store.i.lessons(course.id)) ?? [];
    final videoLesson = lessons.singleWhere((l) => l.title == 'New lesson');
    final audioLesson = lessons.singleWhere((l) => l.title == 'Audio lesson');
    expect(videoLesson.moduleId, module.id);
    expect(videoLesson.kind, 'video');
    expect(audioLesson.moduleId, module.id);
    expect(audioLesson.kind, 'audio');
    expect(find.text('New lesson'), findsOneWidget);
  });

  testWidgets('module + creates a readable text lesson in that module', (
    tester,
  ) async {
    await pumpCourse(tester);
    await chooseModuleAction(tester, 'Add text lesson');
    await tester.enterText(
      find.byKey(const Key('text-lesson-title-field')),
      'Reading notes',
    );
    await tester.enterText(
      find.byKey(const Key('text-lesson-body-field')),
      'The text to study.',
    );
    await tester.tap(find.byKey(const Key('add-text-lesson-submit')));
    await settleDb(tester);

    final lessons =
        await tester.runAsync(() => Store.i.lessons(course.id)) ?? [];
    final lesson = lessons.singleWhere((l) => l.title == 'Reading notes');
    expect(lesson.moduleId, module.id);
    expect(lesson.kind, 'text');
    expect(lesson.description, 'The text to study.');

    await tester.tap(find.text('Reading notes'));
    await settleDb(tester);
    expect(find.text('The text to study.'), findsOneWidget);
    expect(
      find.byTooltip('Float the video while you take notes'),
      findsNothing,
    );
    expect(
      find.text('The media file is missing at its original location.'),
      findsNothing,
    );
  });

  testWidgets('module + creates and runs a persistent quiz', (tester) async {
    await pumpCourse(tester);
    await chooseModuleAction(tester, 'Add quiz');
    await tester.enterText(
      find.byKey(const Key('quiz-title-field')),
      'Chapter check',
    );
    await tester.enterText(
      find.byKey(const Key('quiz-question-field')),
      'First question?',
    );
    await tester.enterText(
      find.byKey(const Key('quiz-answer-field')),
      'First answer.',
    );
    await tester.tap(find.byKey(const Key('quiz-add-question')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quiz-question-field')).last,
      'Second question?',
    );
    await tester.enterText(
      find.byKey(const Key('quiz-answer-field')).last,
      'Second answer.',
    );
    await tester.tap(find.byKey(const Key('add-quiz-submit')));
    await settleDb(tester);

    final lessons =
        await tester.runAsync(() => Store.i.lessons(course.id)) ?? [];
    final lesson = lessons.singleWhere((l) => l.title == 'Chapter check');
    expect(lesson.moduleId, module.id);
    expect(lesson.kind, 'quiz');
    final questions =
        await tester.runAsync(() => Store.i.cardsForLesson(lesson.id)) ?? [];
    expect(questions.map((q) => q.front), [
      'First question?',
      'Second question?',
    ]);
    expect(
      questions.every(
        (q) => q.courseId == course.id && q.lessonId == lesson.id,
      ),
      isTrue,
    );

    await tester.tap(find.text('Chapter check'));
    await settleDb(tester);
    expect(find.text('First question?'), findsOneWidget);
    expect(find.text('First answer.'), findsNothing);

    await tester.tap(find.byKey(const Key('show-quiz-answer')));
    await tester.pumpAndSettle();
    expect(find.text('First answer.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quiz-review-again')));
    await settleDb(tester);
    expect(find.text('Second question?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('show-quiz-answer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quiz-knew-answer')));
    await settleDb(tester);
    expect(find.text('Quiz complete'), findsOneWidget);
    expect(
      (await tester.runAsync(() => Store.i.progress(lesson.id)))?.completed,
      isTrue,
    );
  });

  testWidgets('empty modules keep an add-content action', (tester) async {
    final lessons =
        await tester.runAsync(() => Store.i.lessons(course.id)) ?? [];
    await tester.runAsync(() => Store.i.deleteLesson(lessons.single.id));
    await pumpCourse(tester);
    expect(find.text('Add the first content'), findsOneWidget);
    await tester.tap(find.text('Add the first content'));
    await tester.pumpAndSettle();
    expect(find.text('Quiz'), findsOneWidget);
    expect(find.text('Text lesson'), findsOneWidget);
    expect(find.text('Video or audio lessons'), findsOneWidget);
  });
}
