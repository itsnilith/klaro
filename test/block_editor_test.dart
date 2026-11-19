import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klaro/core/db.dart';
import 'package:klaro/core/models.dart';
import 'test_paths.dart';
import 'package:klaro/design/tokens.dart';
import 'package:klaro/features/notes/block_editor.dart';
import 'package:klaro/features/notes/block_model.dart';

/// Runs real database work outside the widget test's fake-async zone.
Future<T> db<T>(WidgetTester tester, Future<T> Function() run) async {
  late T value;
  await tester.runAsync(() async {
    value = await run();
  });
  return value;
}

/// Lets pending database futures (started by the widget) complete and rebuilds.
Future<void> settleDb(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump();
}

/// Advances the editor's save debounce, then lets the write finish.
Future<void> fireSave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 700));
  await settleDb(tester);
}

void main() {
  testWidgets('block editor writes, splits, inserts a to-do and persists',
      (tester) async {
    late Store store;
    late Note note;

    await tester.runAsync(() async {
      testPaths();
      store = await Store.open();
      final now = DateTime.now();
      note = Note(
        id: 'test-editor-${now.microsecondsSinceEpoch}',
        title: 'Editor test',
        body: '',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveNote(note);
    });

    String projected = '';
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 520,
          child: BlockEditor(
            noteId: note.id,
            initialMarkdown: '',
            onChanged: (md) => projected = md,
          ),
        ),
      ),
    ));
    await settleDb(tester);

    expect(find.byType(TextField), findsOneWidget, reason: 'one empty block');

    // The block field must not inherit the app's outlined input theme: no ring,
    // no fill, no border around a text block.
    final blockField = tester.widget<TextField>(find.byType(TextField).first);
    expect(blockField.decoration?.border, InputBorder.none);
    expect(blockField.decoration?.enabledBorder, InputBorder.none);
    expect(blockField.decoration?.focusedBorder, InputBorder.none);
    expect(blockField.decoration?.filled, isFalse);

    await tester.enterText(find.byType(TextField).first, 'Hello world');
    await fireSave(tester);

    // Enter splits at the caret (end), creating a second block.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await fireSave(tester);

    expect(find.byType(TextField), findsNWidgets(2), reason: 'split added a block');
    final afterSplit = await db(tester, () => store.blocksFor(note.id));
    expect(afterSplit.length, 2);
    expect(projected.contains('Hello world'), isTrue);

    // Type "/" in the new block and pick To-do list from the insert menu.
    await tester.enterText(find.byType(TextField).last, '/todo');
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('To-do list'), findsOneWidget, reason: 'slash menu opens');

    await tester.tap(find.text('To-do list'));
    await fireSave(tester);

    final afterMenu = await db(tester, () => store.blocksFor(note.id));
    expect(afterMenu.any((b) => b.type == BType.todo), isTrue,
        reason: 'block converted to to-do');
    expect(find.byIcon(Icons.check_box_outline_blank_rounded), findsWidgets);

    // Toggle the checkbox and confirm persistence.
    await tester.tap(find.byIcon(Icons.check_box_outline_blank_rounded).last);
    await fireSave(tester);
    final afterCheck = await db(tester, () => store.blocksFor(note.id));
    expect(afterCheck.firstWhere((b) => b.type == BType.todo).checked, isTrue);

    await db(tester, () async {
      await store.db.delete('note_blocks', where: 'note_id = ?', whereArgs: [note.id]);
      await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    });
  });

  testWidgets('undo reverts a block split and redo reapplies it', (tester) async {
    late Store store;
    late Note note;
    await tester.runAsync(() async {
      testPaths();
      store = await Store.open();
      final now = DateTime.now();
      note = Note(
        id: 'test-undo-${now.microsecondsSinceEpoch}',
        title: 'Undo test',
        body: '',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveNote(note);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 520,
          child: BlockEditor(noteId: note.id, initialMarkdown: '', onChanged: (_) {}),
        ),
      ),
    ));
    await settleDb(tester);

    await tester.enterText(find.byType(TextField).first, 'one');
    await fireSave(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await fireSave(tester);
    expect(find.byType(TextField), findsNWidgets(2), reason: 'split happened');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await fireSave(tester);
    expect(find.byType(TextField), findsOneWidget, reason: 'undo removed the split');
    expect(find.text('one'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await fireSave(tester);
    expect(find.byType(TextField), findsNWidgets(2), reason: 'redo restored the split');

    await db(tester, () async {
      await store.db.delete('note_blocks', where: 'note_id = ?', whereArgs: [note.id]);
      await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    });
  });

  testWidgets('find bar replaces every occurrence in the page', (tester) async {
    late Store store;
    late Note note;
    await tester.runAsync(() async {
      testPaths();
      store = await Store.open();
      final now = DateTime.now();
      note = Note(
        id: 'test-find-${now.microsecondsSinceEpoch}',
        title: 'Find test',
        body: 'alpha beta\nalpha gamma',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveNote(note);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 520,
          child: BlockEditor(
            noteId: note.id,
            initialMarkdown: 'alpha beta\nalpha gamma',
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    await settleDb(tester);

    final state = tester.state<BlockEditorState>(find.byType(BlockEditor));
    state.showFindBar();
    await tester.pump();

    // With the bar open the first two text fields belong to it.
    await tester.enterText(find.byType(TextField).at(0), 'alpha');
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'omega');
    await tester.pump();
    await tester.tap(find.text('All'));
    await fireSave(tester);

    final rows = await db(tester, () => store.blocksFor(note.id));
    expect(rows.every((b) => !b.text.contains('alpha')), isTrue,
        reason: 'all occurrences replaced');
    expect(rows.map((b) => b.text).join(' ').contains('omega'), isTrue);

    await db(tester, () async {
      await store.db.delete('note_blocks', where: 'note_id = ?', whereArgs: [note.id]);
      await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    });
  });

  testWidgets('dragging the handle reorders blocks', (tester) async {
    late Store store;
    late Note note;
    await tester.runAsync(() async {
      testPaths();
      store = await Store.open();
      final now = DateTime.now();
      note = Note(
        id: 'test-drag-${now.microsecondsSinceEpoch}',
        title: 'Drag test',
        body: 'alpha\nbeta',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveNote(note);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 520,
          child: BlockEditor(
            noteId: note.id,
            initialMarkdown: 'alpha\nbeta',
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    await settleDb(tester);
    expect(find.byType(TextField), findsNWidgets(2));

    final handles = find.byIcon(Icons.drag_indicator_rounded);
    expect(handles, findsNWidgets(2));
    final firstRow = tester.getCenter(find.byType(TextField).first);
    final secondRow = tester.getCenter(find.byType(TextField).last);

    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(secondRow.translate(0, 8));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(secondRow.translate(0, 10));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await fireSave(tester);

    final rows = await db(tester, () => store.blocksFor(note.id));
    final ordered = BlockDoc(note.id, rows).outline().map((l) => l.block.text).toList();
    expect(ordered, ['beta', 'alpha'], reason: 'first block moved below the second');
    expect(firstRow.dy, lessThan(secondRow.dy));

    await db(tester, () async {
      await store.db.delete('note_blocks', where: 'note_id = ?', whereArgs: [note.id]);
      await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    });
  });

  testWidgets('markdown prefixes convert the block while typing', (tester) async {
    late Store store;
    late Note note;
    await tester.runAsync(() async {
      testPaths();
      store = await Store.open();
      final now = DateTime.now();
      note = Note(
        id: 'test-md-${now.microsecondsSinceEpoch}',
        title: 'Markdown test',
        body: '',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveNote(note);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 520,
          child: BlockEditor(noteId: note.id, initialMarkdown: '', onChanged: (_) {}),
        ),
      ),
    ));
    await settleDb(tester);

    await tester.enterText(find.byType(TextField).first, '# ');
    await fireSave(tester);
    var rows = await db(tester, () => store.blocksFor(note.id));
    expect(rows.single.type, BType.h1, reason: 'typed heading prefix');
    expect(rows.single.text, '');

    await tester.enterText(find.byType(TextField).first, 'Heading text');
    await fireSave(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await fireSave(tester);
    await tester.enterText(find.byType(TextField).last, '- ');
    await fireSave(tester);

    rows = await db(tester, () => store.blocksFor(note.id));
    expect(rows.any((b) => b.type == BType.bulleted), isTrue,
        reason: 'typed bullet prefix');
    expect(rows.any((b) => b.type == BType.h1 && b.text == 'Heading text'), isTrue);

    await db(tester, () async {
      await store.db.delete('note_blocks', where: 'note_id = ?', whereArgs: [note.id]);
      await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    });
  });

  testWidgets('slash menu inserts an editable database that persists cells',
      (tester) async {
    late Store store;
    late Note note;
    await tester.runAsync(() async {
      testPaths();
      store = await Store.open();
      final now = DateTime.now();
      note = Note(
        id: 'test-db-${now.microsecondsSinceEpoch}',
        title: 'Database test',
        body: '',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveNote(note);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 620,
          child: BlockEditor(noteId: note.id, initialMarkdown: '', onChanged: (_) {}),
        ),
      ),
    ));
    await settleDb(tester);

    await tester.enterText(find.byType(TextField).first, '/data');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Database'));
    await fireSave(tester);

    expect(find.text('New row'), findsOneWidget, reason: 'database rendered');
    final before = await db(tester, () => store.blocksFor(note.id));
    expect(before.single.type, BType.database);
    final cols = jsonDecode(before.single.props['columns'] as String) as List;
    expect(cols.length, 3);

    // Type into the first text cell of the first row.
    final cells = find.byType(TextFormField);
    expect(cells, findsWidgets);
    await tester.enterText(cells.first, 'Task A');
    await fireSave(tester);

    await tester.tap(find.text('New row'));
    await fireSave(tester);

    final after = await db(tester, () => store.blocksFor(note.id));
    final rows = jsonDecode(after.single.props['rows'] as String) as List;
    expect(rows.length, 3, reason: 'row added');
    expect(((rows.first as Map)['cells'] as Map).values, contains('Task A'));

    await db(tester, () async {
      await store.db.delete('note_blocks', where: 'note_id = ?', whereArgs: [note.id]);
      await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    });
  });

  testWidgets('chart block renders its empty state and binds to a database',
      (tester) async {
    late Store store;
    late Note note;
    await tester.runAsync(() async {
      testPaths();
      store = await Store.open();
      final now = DateTime.now();
      note = Note(
        id: 'test-chart-${now.microsecondsSinceEpoch}',
        title: 'Chart test',
        body: '',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveNote(note);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 620,
          child: BlockEditor(noteId: note.id, initialMarkdown: '', onChanged: (_) {}),
        ),
      ),
    ));
    await settleDb(tester);

    await tester.enterText(find.byType(TextField).first, '/chart');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Chart'));
    await fireSave(tester);

    expect(find.textContaining('Add a database block'), findsOneWidget,
        reason: 'chart explains what it needs');

    final rows = await db(tester, () => store.blocksFor(note.id));
    expect(rows.single.type, BType.chart);

    await db(tester, () async {
      await store.db.delete('note_blocks', where: 'note_id = ?', whereArgs: [note.id]);
      await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    });
  });

  testWidgets('typing --- then Enter creates a divider', (tester) async {
    late Store store;
    late Note note;
    await tester.runAsync(() async {
      testPaths();
      store = await Store.open();
      final now = DateTime.now();
      note = Note(
        id: 'test-div-${now.microsecondsSinceEpoch}',
        title: 'Divider test',
        body: '',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveNote(note);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 520,
          child: BlockEditor(noteId: note.id, initialMarkdown: '', onChanged: (_) {}),
        ),
      ),
    ));
    await settleDb(tester);

    await tester.enterText(find.byType(TextField).first, '---');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await fireSave(tester);

    final rows = await db(tester, () => store.blocksFor(note.id));
    expect(rows.any((b) => b.type == BType.divider), isTrue,
        reason: 'divider created from ---');
    expect(rows.any((b) => b.type == BType.text), isTrue,
        reason: 'a text block follows the divider');

    await db(tester, () async {
      await store.db.delete('note_blocks', where: 'note_id = ?', whereArgs: [note.id]);
      await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    });
  });

  testWidgets('two-column layout holds editable blocks', (tester) async {
    late Store store;
    late Note note;
    await tester.runAsync(() async {
      testPaths();
      store = await Store.open();
      final now = DateTime.now();
      note = Note(
        id: 'test-cols-${now.microsecondsSinceEpoch}',
        title: 'Columns test',
        body: '',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveNote(note);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 620,
          child: BlockEditor(noteId: note.id, initialMarkdown: '', onChanged: (_) {}),
        ),
      ),
    ));
    await settleDb(tester);

    await tester.enterText(find.byType(TextField).first, '/2 col');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('2 columns'));
    await fireSave(tester);

    expect(find.byType(TextField), findsNWidgets(2), reason: 'one field per column');
    await tester.enterText(find.byType(TextField).first, 'left side');
    await fireSave(tester);

    final rows = await db(tester, () => store.blocksFor(note.id));
    final layout = rows.firstWhere((b) => b.type == BType.columnList);
    final columns = rows.where((b) => b.parentId == layout.id).toList();
    expect(columns.length, 2);
    final leftText = rows.where((b) => b.parentId == columns.first.id).toList();
    expect(leftText.single.text, 'left side');

    await db(tester, () async {
      await store.db.delete('note_blocks', where: 'note_id = ?', whereArgs: [note.id]);
      await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    });
  });

  testWidgets('table of contents lists headings', (tester) async {
    late Store store;
    late Note note;
    await tester.runAsync(() async {
      testPaths();
      store = await Store.open();
      final now = DateTime.now();
      note = Note(
        id: 'test-toc-${now.microsecondsSinceEpoch}',
        title: 'TOC test',
        body: '',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveNote(note);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 620,
          child: BlockEditor(noteId: note.id, initialMarkdown: '# Intro\nBody', onChanged: (_) {}),
        ),
      ),
    ));
    await settleDb(tester);

    await tester.enterText(find.byType(TextField).last, '/toc');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Table of contents'));
    await fireSave(tester);

    expect(find.text('Intro'), findsNWidgets(2), reason: 'heading and TOC entry');

    final rows = await db(tester, () => store.blocksFor(note.id));
    expect(rows.any((b) => b.type == BType.toc), isTrue);

    await db(tester, () async {
      await store.db.delete('note_blocks', where: 'note_id = ?', whereArgs: [note.id]);
      await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    });
  });

  testWidgets('bookmark asks for a URL and keeps it', (tester) async {
    late Store store;
    late Note note;
    await tester.runAsync(() async {
      testPaths();
      store = await Store.open();
      final now = DateTime.now();
      note = Note(
        id: 'test-book-${now.microsecondsSinceEpoch}',
        title: 'Bookmark test',
        body: '',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveNote(note);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 620,
          child: BlockEditor(noteId: note.id, initialMarkdown: '', onChanged: (_) {}),
        ),
      ),
    ));
    await settleDb(tester);

    await tester.enterText(find.byType(TextField).first, '/book');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Web bookmark'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, 'https://example.com/notes');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await fireSave(tester);

    expect(find.text('https://example.com/notes'), findsOneWidget);
    final rows = await db(tester, () => store.blocksFor(note.id));
    expect(rows.single.type, BType.bookmark);
    expect(rows.single.props['url'], 'https://example.com/notes');

    await db(tester, () async {
      await store.db.delete('note_blocks', where: 'note_id = ?', whereArgs: [note.id]);
      await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    });
  });

  testWidgets('database switches to the board view and persists it', (tester) async {
    late Store store;
    late Note note;
    await tester.runAsync(() async {
      testPaths();
      store = await Store.open();
      final now = DateTime.now();
      note = Note(
        id: 'test-board-${now.microsecondsSinceEpoch}',
        title: 'Board test',
        body: '',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveNote(note);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 620,
          child: BlockEditor(noteId: note.id, initialMarkdown: '', onChanged: (_) {}),
        ),
      ),
    ));
    await settleDb(tester);

    await tester.enterText(find.byType(TextField).first, '/data');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Database'));
    await fireSave(tester);

    await tester.tap(find.byIcon(Icons.view_kanban_outlined));
    await fireSave(tester);

    expect(find.text('New card'), findsWidgets, reason: 'board columns rendered');
    expect(find.text('No Status'), findsOneWidget, reason: 'empty group column');
    expect(find.textContaining('Group: Status'), findsOneWidget);

    final rows = await db(tester, () => store.blocksFor(note.id));
    expect(rows.single.props['view'], 'board');

    await db(tester, () async {
      await store.db.delete('note_blocks', where: 'note_id = ?', whereArgs: [note.id]);
      await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    });
  });

  test('version snapshots are stored, listed and trimmed', () async {
    testPaths();
    final store = await Store.open();
    final now = DateTime.now();
    final note = Note(
      id: 'test-version-${now.microsecondsSinceEpoch}',
      title: 'Version test',
      body: '',
      createdAt: now,
      updatedAt: now,
    );
    await store.saveNote(note);

    await store.saveVersion(note.id, '{"a":1}');
    await store.saveVersion(note.id, '{"a":2}');
    var versions = await store.versions(note.id);
    expect(versions.length, 2);
    expect(versions.first['snapshot'], '{"a":2}', reason: 'newest first');

    for (var i = 0; i < 45; i++) {
      await store.saveVersion(note.id, '{"a":${i + 3}}');
    }
    await store.trimVersions(note.id, keep: 40);
    versions = await store.versions(note.id, limit: 100);
    expect(versions.length, 40);

    await store.db.delete('note_versions', where: 'note_id = ?', whereArgs: [note.id]);
    await store.db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
  });
}