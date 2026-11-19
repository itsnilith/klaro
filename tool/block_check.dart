// ignore_for_file: avoid_print
// Pure-Dart checks for the note block model. Run:
//   dart run tool/block_check.dart
// Exits non-zero on the first failed expectation.
import 'package:klaro/features/notes/block_model.dart';

int _checks = 0;

void expect(bool ok, String label) {
  _checks++;
  if (!ok) {
    throw StateError('FAILED: $label');
  }
}

void main() {
  // ---- sibling keys stay ordered
  var a = SKeys.between(null, null);
  var b = SKeys.between(a, null);
  var mid = SKeys.between(a, b);
  expect(a.compareTo(mid) < 0 && mid.compareTo(b) < 0, 'fractional key ordering');

  // ---- markdown -> tree
  const md = '''
# Course notes
Intro paragraph.

- first
  - nested bullet
- second

1. one
2. two

- [x] done task
- [ ] open task

> quoted

```dart
final x = 1;
```

---
## Recap
''';
  final doc = BlockDoc.fromMarkdown('n1', md);
  final lines = doc.outline();
  final types = lines.map((l) => l.block.type).toList();
  expect(types.first == BType.h1, 'h1 first');
  expect(types.contains(BType.bulleted), 'bulleted parsed');
  expect(types.contains(BType.numbered), 'numbered parsed');
  expect(types.contains(BType.todo), 'todo parsed');
  expect(types.contains(BType.quote), 'quote parsed');
  expect(types.contains(BType.code), 'code parsed');
  expect(types.contains(BType.divider), 'divider parsed');
  expect(lines.any((l) => l.depth == 1), 'nested bullet has depth 1');
  expect(lines.firstWhere((l) => l.block.text == 'done task').block.checked, 'checked todo');
  expect(lines.firstWhere((l) => l.block.text == 'open task').block.checked == false, 'open todo');
  expect(
      lines.firstWhere((l) => l.block.type == BType.code).block.language == 'dart',
      'code language');

  // ---- numbering resets and increments
  final numbered = lines.where((l) => l.block.type == BType.numbered).toList();
  expect(numbered.length == 2, 'two numbered items');
  expect(numbered[0].number == 1 && numbered[1].number == 2, 'numbering increments');

  // ---- markdown -> blocks -> markdown -> blocks keeps shape
  final projected = doc.markdown();
  final doc2 = BlockDoc.fromMarkdown('n1', projected);
  final lines2 = doc2.outline();
  expect(lines2.length == lines.length, 'round-trip block count');
  for (var i = 0; i < lines.length; i++) {
    expect(lines2[i].block.type == lines[i].block.type, 'round-trip type at $i');
    expect(lines2[i].depth == lines[i].depth, 'round-trip depth at $i');
    expect(lines2[i].block.text.trimRight() == lines[i].block.text.trimRight(),
        'round-trip text at $i');
  }

  // ---- split
  final d = BlockDoc('n2');
  final first = d.append(text: 'hello world');
  final tail = d.split(first.id, 5)!;
  expect(first.text == 'hello', 'split head');
  expect(tail.text == ' world', 'split tail');
  expect(d.outline().length == 2, 'split adds a block');
  expect(d.outline()[1].block.id == tail.id, 'tail is second');

  // ---- merge back
  final merged = d.mergeBack(tail.id);
  expect(merged, 'merge reports handled');
  expect(d.outline().length == 1, 'merge removes the block');
  expect(d.outline().first.block.text == 'hello world', 'merge joins text');

  // ---- indent / outdent
  final d2 = BlockDoc('n3');
  d2.append(text: 'parent');
  final c1 = d2.append(text: 'child');
  expect(d2.indent(c1.id), 'indent works');
  expect(d2.outline().firstWhere((l) => l.block.id == c1.id).depth == 1, 'child depth 1');
  expect(d2.outdent(c1.id), 'outdent works');
  expect(d2.outline().firstWhere((l) => l.block.id == c1.id).depth == 0, 'child depth 0');

  // ---- toggle collapse hides descendants
  final d3 = BlockDoc('n4');
  final t = d3.append(type: BType.toggle, text: 'toggle');
  d3.append(parentId: t.id, text: 'inside');
  expect(d3.outline().length == 2, 'toggle child visible');
  d3.toggleOpen(t.id);
  expect(d3.outline().length == 1, 'collapsed toggle hides child');
  d3.toggleOpen(t.id);
  expect(d3.outline().length == 2, 'reopened toggle shows child');

  // ---- delete lifts children
  final d4 = BlockDoc('n5');
  d4.append(text: 'top');
  final mid2 = d4.append(text: 'mid');
  final kid = d4.append(parentId: mid2.id, text: 'kid');
  d4.delete(mid2.id);
  expect(d4.byId(kid.id)?.parentId == null, 'child lifted to the deleted block parent');
  expect(d4.outline().length == 2, 'only the deleted block is gone');

  // ---- markdown escapes unseen text kinds
  final d5 = BlockDoc('n6');
  d5.append(type: BType.callout, text: 'note');
  expect(d5.markdown().contains('[!TIP]'), 'callout projection');

  print('block model: $_checks checks passed');
}