import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:klaro/features/notes/block_model.dart';
import 'package:klaro/features/notes/database_block.dart';

void main() {
  group('sibling keys', () {
    test('stay ordered between neighbours', () {
      final a = SKeys.between(null, null);
      final b = SKeys.between(a, null);
      final mid = SKeys.between(a, b);
      expect(a.compareTo(mid), lessThan(0));
      expect(mid.compareTo(b), lessThan(0));
    });
  });

  group('markdown import', () {
    const md = '''
# Notes
Intro.

- one
  - nested
- two

1. first
2. second

- [x] done
- [ ] open

> quote

```dart
final x = 1;
```

---
''';

    test('maps every supported block type', () {
      final doc = BlockDoc.fromMarkdown('n', md);
      final types = doc.outline().map((l) => l.block.type).toSet();
      expect(types, containsAll(<String>[
        BType.h1,
        BType.text,
        BType.bulleted,
        BType.numbered,
        BType.todo,
        BType.quote,
        BType.code,
        BType.divider,
      ]));
    });

    test('keeps nesting and checked state', () {
      final doc = BlockDoc.fromMarkdown('n', md);
      final lines = doc.outline();
      expect(lines.any((l) => l.depth == 1), isTrue);
      expect(lines.firstWhere((l) => l.block.text == 'done').block.checked, isTrue);
      expect(lines.firstWhere((l) => l.block.text == 'open').block.checked, isFalse);
    });

    test('round-trips through the markdown projection', () {
      final first = BlockDoc.fromMarkdown('n', md).outline();
      final second = BlockDoc.fromMarkdown(
        'n',
        BlockDoc.fromMarkdown('n', md).markdown(),
      ).outline();
      expect(second.length, first.length);
      for (var i = 0; i < first.length; i++) {
        expect(second[i].block.type, first[i].block.type, reason: 'type at $i');
        expect(second[i].depth, first[i].depth, reason: 'depth at $i');
      }
    });
  });

  group('editing operations', () {
    test('split creates a tail block with the remainder', () {
      final doc = BlockDoc('n');
      final block = doc.append(text: 'hello world');
      final tail = doc.split(block.id, 5)!;
      expect(block.text, 'hello');
      expect(tail.text, ' world');
      expect(doc.outline().length, 2);
    });

    test('merge back joins text and removes the block', () {
      final doc = BlockDoc('n');
      final block = doc.append(text: 'hello world');
      final tail = doc.split(block.id, 5)!;
      expect(doc.mergeBack(tail.id), isTrue);
      expect(doc.outline().length, 1);
      expect(doc.outline().first.block.text, 'hello world');
    });

    test('indent and outdent change depth', () {
      final doc = BlockDoc('n');
      doc.append(text: 'parent');
      final child = doc.append(text: 'child');
      expect(doc.indent(child.id), isTrue);
      expect(doc.outline().firstWhere((l) => l.block.id == child.id).depth, 1);
      expect(doc.outdent(child.id), isTrue);
      expect(doc.outline().firstWhere((l) => l.block.id == child.id).depth, 0);
    });

    test('collapsible headings hide and show their children', () {
      final doc = BlockDoc('n');
      final heading = doc.append(type: BType.h1, text: 'Part one');
      doc.append(parentId: heading.id, text: 'child');
      expect(doc.outline().length, 2);
      expect(BType.canNest(BType.h1), isTrue);
      doc.toggleOpen(heading.id);
      expect(doc.outline().length, 1, reason: 'collapsed heading hides the child');
      doc.toggleOpen(heading.id);
      expect(doc.outline().length, 2, reason: 'expanded heading shows the child');
    });

    test('a collapsed toggle hides its children', () {
      final doc = BlockDoc('n');
      final toggle = doc.append(type: BType.toggle, text: 'toggle');
      doc.append(parentId: toggle.id, text: 'inside');
      expect(doc.outline().length, 2);
      doc.toggleOpen(toggle.id);
      expect(doc.outline().length, 1);
      doc.toggleOpen(toggle.id);
      expect(doc.outline().length, 2);
    });

    test('deleting a block lifts its children to the parent', () {
      final doc = BlockDoc('n');
      doc.append(text: 'top');
      final mid = doc.append(text: 'mid');
      final kid = doc.append(parentId: mid.id, text: 'kid');
      doc.delete(mid.id);
      expect(doc.byId(kid.id)?.parentId, isNull);
      expect(doc.outline().length, 2);
    });

    test('duplicate copies the subtree with new ids after the original', () {
      final doc = BlockDoc('n');
      final first = doc.append(text: 'a');
      doc.append(parentId: first.id, text: 'a-child');
      final copyId = doc.duplicate(first.id)!;
      final copy = doc.byId(copyId)!;
      expect(copy.id, isNot(first.id));
      expect(copy.text, 'a');
      expect(doc.childrenOf(copyId).single.text, 'a-child');
      expect(doc.childrenOf(first.id).single.id, isNot(doc.childrenOf(copyId).single.id));
      expect(doc.childrenOf(null).map((b) => b.text).toList(), ['a', 'a']);
      expect(copy.sortKey.compareTo(first.sortKey), greaterThan(0));
    });

    test('snapshot and restore reproduce the tree', () {
      final doc = BlockDoc('n');
      final a = doc.append(text: 'keep');
      doc.append(parentId: a.id, text: 'child');
      final snap = doc.snapshot();
      doc.append(text: 'discard');
      doc.setType(a.id, BType.h1);
      doc.restoreSnapshot(snap);
      expect(doc.raw.length, 2);
      expect(doc.byId(a.id)?.type, BType.text);
      expect(doc.outline().first.block.text, 'keep');
    });

    test('colours set and clear', () {
      final doc = BlockDoc('n');
      final block = doc.append(text: 'x');
      doc.setColor(block.id, 'red');
      expect(block.props['color'], 'red');
      doc.setColor(block.id, 'blue', background: true);
      expect(block.props['background'], 'blue');
      doc.setColor(block.id, 'default');
      expect(block.props.containsKey('color'), isFalse);
      expect(block.props['background'], 'blue');
    });

    test('moveBlock reorders, reparents and refuses cycles', () {
      final doc = BlockDoc('n');
      final a = doc.append(text: 'a');
      final b = doc.append(text: 'b');
      final c = doc.append(text: 'c');

      expect(doc.moveBlock(c.id, a.id, before: true), isTrue);
      expect(doc.childrenOf(null).map((x) => x.text).toList(), ['c', 'a', 'b']);

      // move b under a
      expect(doc.indent(b.id), isTrue);
      expect(doc.childrenOf(a.id).single.id, b.id);

      // a block cannot be dropped inside its own subtree
      final parent = doc.append(text: 'parent');
      final kid = doc.append(parentId: parent.id, text: 'kid');
      expect(doc.moveBlock(parent.id, kid.id, before: true), isFalse);
      expect(doc.byId(kid.id)?.parentId, parent.id);
      expect(c.id, isNotEmpty);
    });

    test('database blocks round-trip through a markdown table', () {
      final doc = BlockDoc('n');
      final block = doc.append(type: BType.database);
      block.props['columns'] = jsonEncode([
        {'id': 'c1', 'name': 'Task', 'type': 'text'},
        {'id': 'c2', 'name': 'Score', 'type': 'number'},
      ]);
      block.props['rows'] = jsonEncode([
        {'id': 'r1', 'cells': {'c1': 'Read chapter', 'c2': '3'}},
        {'id': 'r2', 'cells': {'c1': 'Practice', 'c2': '4.5'}},
      ]);

      final md = doc.markdown();
      expect(md.contains('| Task | Score |'), isTrue);
      expect(md.contains('| Read chapter | 3 |'), isTrue);

      final parsed = BlockDoc.fromMarkdown('n', md);
      final db = parsed.outline().first.block;
      expect(db.type, BType.database);
      final columns = jsonDecode(db.props['columns'] as String) as List;
      expect(columns.length, 2);
      expect((columns[1] as Map)['type'], 'number');
      final rows = jsonDecode(db.props['rows'] as String) as List;
      expect(rows.length, 2);
      final firstColumnId = (columns.first as Map)['id'];
      expect(((rows.first as Map)['cells'] as Map)[firstColumnId], 'Read chapter');
    });

    test('database sorts and groups by column type', () {
      final data = DbData.blank();
      final score = data.columns.firstWhere((c) => c.type == DbType.number);
      final status = data.columns.firstWhere((c) => c.type == DbType.select);
      data.rows[0].cells[score.id] = '5';
      data.rows[1].cells[score.id] = '2';
      data.rows[0].cells[status.id] = 'Done';

      data.sortColumn = score.id;
      data.sortDesc = false;
      expect(data.sortedRows.first.cells[score.id], '2');
      data.sortDesc = true;
      expect(data.sortedRows.first.cells[score.id], '5');

      data.sortColumn = null;
      final groups = data.groupValues(status.id);
      expect(groups, contains('Done'));
      expect(groups, contains(''), reason: 'rows without a value form their own group');

      data.filterColumn = status.id;
      data.filterValue = 'done';
      expect(data.visibleRows.length, 1, reason: 'case-insensitive contains filter');
      expect(data.visibleRows.single.cells[status.id], 'Done');
      data.filterValue = '';

      data.sortColumn = score.id;
      data.sortDesc = true;
      data.view = 'board';
      final props = <String, Object?>{};
      data.writeTo(props);
      final restored = DbData.fromProps(props);
      expect(restored.view, 'board');
      expect(restored.sortColumn, score.id);
      expect(restored.sortDesc, isTrue);
    });

    test('cloneWithNewIds rewrites ids and parent links', () {
      final doc = BlockDoc('source');
      final parent = doc.append(text: 'parent');
      final child = doc.append(parentId: parent.id, text: 'child');
      var counter = 0;
      final clones = NoteBlock.cloneWithNewIds(
        doc.raw,
        'target',
        () => 'new${counter++}',
      );
      expect(clones.length, 2);
      expect(clones.any((b) => b.id == parent.id), isFalse);
      expect(clones.every((b) => b.noteId == 'target'), isTrue);
      final clonedParent = clones.firstWhere((b) => b.text == 'parent');
      final clonedChild = clones.firstWhere((b) => b.text == 'child');
      expect(clonedChild.parentId, clonedParent.id);
      expect(child.parentId, parent.id, reason: 'source untouched');
    });

    test('image blocks round-trip through markdown', () {
      final doc = BlockDoc('n');
      final block = doc.append(type: BType.image, text: 'diagram.png');
      block.props['path'] = r'C:\notes\diagram.png';
      final md = doc.markdown();
      expect(md.contains('![diagram.png]'), isTrue);
      final parsed = BlockDoc.fromMarkdown('n', md);
      final image = parsed.outline().first.block;
      expect(image.type, BType.image);
      expect(image.text, 'diagram.png');
      expect(image.props['path'], r'C:\notes\diagram.png');
    });

    test('replaceRange edits text and reports the caret', () {
      final doc = BlockDoc('n');
      final block = doc.append(text: 'hello world');
      final caret = doc.replaceRange(block.id, 6, 11, 'there');
      expect(block.text, 'hello there');
      expect(caret, 11);
    });
  });
}