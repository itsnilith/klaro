import 'dart:convert';

/// Block types, stored with the same names the workspace convention uses so
/// that exported JSON stays readable and portable.
abstract final class BType {
  static const text = 'text';
  static const h1 = 'header';
  static const h2 = 'sub_header';
  static const h3 = 'sub_sub_header';
  static const h4 = 'header_4';
  static const bulleted = 'bulleted_list';
  static const numbered = 'numbered_list';
  static const todo = 'to_do';
  static const toggle = 'toggle';
  static const quote = 'quote';
  static const callout = 'callout';
  static const code = 'code';
  static const divider = 'divider';
  static const image = 'image';
  static const database = 'collection';
  static const chart = 'chart';
  static const columnList = 'column_list';
  static const column = 'column';
  static const toc = 'table_of_contents';
  static const file = 'file';
  static const bookmark = 'bookmark';
  static const embed = 'embed';
  static const equation = 'equation';

  static const all = <String>[
    text, h1, h2, h3, h4, bulleted, numbered, todo, toggle, quote, callout, code, divider, image,
    database, chart, columnList, column, toc, file, bookmark, embed, equation,
  ];

  /// Types that hold editable text (a divider does not).
  static bool hasText(String type) =>
      type != divider &&
      type != image &&
      type != database &&
      type != chart &&
      type != columnList &&
      type != column &&
      type != toc &&
      type != file &&
      type != bookmark &&
      type != embed;

  /// Types that can take children through indentation.
  static bool canNest(String type) =>
      type == text ||
      type == bulleted ||
      type == numbered ||
      type == todo ||
      type == toggle ||
      type == quote ||
      type == callout ||
      type == h1 ||
      type == h2 ||
      type == h3;
}

/// One block row. Mirrors `note_blocks` in SQLite.
class NoteBlock {
  NoteBlock({
    required this.id,
    required this.noteId,
    this.parentId,
    required this.sortKey,
    required this.type,
    this.text = '',
    Map<String, Object?>? props,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : props = props ?? <String, Object?>{},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String noteId;
  String? parentId;
  String sortKey;
  String type;
  String text;
  final Map<String, Object?> props;
  final DateTime createdAt;
  DateTime updatedAt;

  bool get checked => props['checked'] == true;
  bool get open => props['open'] != false;
  int get depth => (props['depth'] as int?) ?? 0; // cached for rendering only
  String get language => (props['language'] as String?) ?? 'plaintext';

  NoteBlock copyWith({
    String? parentId,
    bool clearParent = false,
    String? sortKey,
    String? type,
    String? text,
    Map<String, Object?>? props,
    DateTime? updatedAt,
  }) =>
      NoteBlock(
        id: id,
        noteId: noteId,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        sortKey: sortKey ?? this.sortKey,
        type: type ?? this.type,
        text: text ?? this.text,
        props: props ?? Map<String, Object?>.from(this.props),
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'note_id': noteId,
        'parent_id': parentId,
        'sort_key': sortKey,
        'type': type,
        'text': text,
        'props': jsonEncode(props),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static NoteBlock fromMap(Map<String, Object?> m) => NoteBlock(
        id: m['id'] as String,
        noteId: m['note_id'] as String,
        parentId: m['parent_id'] as String?,
        sortKey: m['sort_key'] as String,
        type: m['type'] as String,
        text: m['text'] as String? ?? '',
        props: _decodeProps(m['props'] as String?),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );

  /// Copies a block list into another page, assigning fresh ids and rewriting
  /// parent links. Used by template instantiation.
  static List<NoteBlock> cloneWithNewIds(
    List<NoteBlock> source,
    String noteId,
    String Function() newId,
  ) {
    final idMap = <String, String>{for (final b in source) b.id: newId()};
    return source
        .map((b) => NoteBlock(
              id: idMap[b.id]!,
              noteId: noteId,
              parentId: b.parentId == null ? null : idMap[b.parentId],
              sortKey: b.sortKey,
              type: b.type,
              text: b.text,
              props: Map<String, Object?>.from(b.props),
            ))
        .toList();
  }

  static Map<String, Object?> _decodeProps(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (_) {
      return {};
    }
  }
}

/// Sibling ordering: base-36 fractional keys. Inserting between two blocks is a
/// single key, never a renumbering pass.
abstract final class SKeys {
  static const _digits = '0123456789abcdefghijklmnopqrstuvwxyz';

  static int _val(String c) => _digits.indexOf(c);

  static String between(String? a, String? b) {
    a ??= '';
    b ??= '';
    final out = StringBuffer();
    for (var i = 0; i < 48; i++) {
      final ca = i < a.length ? _val(a[i]) : 0;
      final cb = i < b.length ? _val(b[i]) : 36;
      if (cb - ca > 1) {
        out.write(_digits[(ca + cb) ~/ 2]);
        return out.toString();
      }
      out.write(i < a.length ? a[i] : _digits[0]);
    }
    out.write(_digits[17]);
    return out.toString();
  }

  static String after(String? key) => between(key, null);
}

/// A block plus its computed depth, in document order.
class BlockLine {
  const BlockLine(this.block, this.depth, this.number);
  final NoteBlock block;
  final int depth;

  /// 1-based index for numbered lists, 0 otherwise.
  final int number;
}

/// The document tree plus the operations the editor needs. Pure Dart: no
/// Flutter imports, so it can be exercised by a plain script.
class BlockDoc {
  BlockDoc(this.noteId, [List<NoteBlock>? blocks, String Function()? idGen])
      : _blocks = List<NoteBlock>.from(blocks ?? const []),
        _newId = idGen ?? (() => 'b${DateTime.now().microsecondsSinceEpoch}${_seq++}');

  final String noteId;
  final List<NoteBlock> _blocks;
  final String Function() _newId;
  static int _seq = 0;

  List<NoteBlock> get raw => List<NoteBlock>.unmodifiable(_blocks);
  bool get isEmpty => _blocks.isEmpty;

  NoteBlock? byId(String id) {
    for (final b in _blocks) {
      if (b.id == id) return b;
    }
    return null;
  }

  // ---------------------------------------------------------------- ordering

  List<NoteBlock> childrenOf(String? parentId) {
    final list = _blocks.where((b) => b.parentId == parentId).toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return list;
  }

  /// Depth-first document order, with collapsed toggles hiding their subtree.
  List<BlockLine> outline() {
    final out = <BlockLine>[];
    void walk(String? parent, int depth) {
      if (parent != null) {
        final p = byId(parent);
        if (p != null) {
          final collapsible = p.type == BType.toggle ||
              p.type == BType.h1 ||
              p.type == BType.h2 ||
              p.type == BType.h3;
          if (collapsible && !p.open) return;
        }
      }
      final kids = childrenOf(parent);
      var counter = 0;
      for (final b in kids) {
        if (b.type == BType.numbered) {
          counter++;
        } else {
          counter = 0;
        }
        out.add(BlockLine(b, depth, b.type == BType.numbered ? counter : 0));
        walk(b.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }

  /// Ancestor chain, root first.
  List<NoteBlock> ancestorsOf(String id) {
    final out = <NoteBlock>[];
    var cur = byId(id)?.parentId;
    while (cur != null) {
      final b = byId(cur);
      if (b == null) break;
      out.insert(0, b);
      cur = b.parentId;
    }
    return out;
  }

  bool isDescendant(String candidate, String ancestor) {
    var cur = byId(candidate)?.parentId;
    while (cur != null) {
      if (cur == ancestor) return true;
      cur = byId(cur)?.parentId;
    }
    return false;
  }

  // ---------------------------------------------------------------- mutation

  NoteBlock append({String? parentId, String type = BType.text, String text = ''}) {
    final siblings = childrenOf(parentId);
    final key = SKeys.after(siblings.isEmpty ? null : siblings.last.sortKey);
    final b = NoteBlock(
      id: _newId(),
      noteId: noteId,
      parentId: parentId,
      sortKey: key,
      type: type,
      text: text,
    );
    _blocks.add(b);
    return b;
  }

  NoteBlock insertAfter(String afterId, {String? type, String? text}) {
    final anchor = byId(afterId);
    if (anchor == null) return append(type: type ?? BType.text, text: text ?? '');
    final siblings = childrenOf(anchor.parentId);
    final i = siblings.indexWhere((b) => b.id == afterId);
    final next = i >= 0 && i + 1 < siblings.length ? siblings[i + 1].sortKey : null;
    final b = NoteBlock(
      id: _newId(),
      noteId: noteId,
      parentId: anchor.parentId,
      sortKey: SKeys.between(anchor.sortKey, next),
      type: type ?? BType.text,
      text: text ?? '',
    );
    _blocks.add(b);
    return b;
  }

  NoteBlock insertBefore(String beforeId, {String? type, String? text}) {
    final anchor = byId(beforeId);
    if (anchor == null) return append(type: type ?? BType.text, text: text ?? '');
    final siblings = childrenOf(anchor.parentId);
    final i = siblings.indexWhere((b) => b.id == beforeId);
    final prev = i > 0 ? siblings[i - 1].sortKey : null;
    final b = NoteBlock(
      id: _newId(),
      noteId: noteId,
      parentId: anchor.parentId,
      sortKey: SKeys.between(prev, anchor.sortKey),
      type: type ?? BType.text,
      text: text ?? '',
    );
    _blocks.add(b);
    return b;
  }

  /// Splits [id] at [offset] (character index), returning the new tail block.
  NoteBlock? split(String id, int offset) {
    final b = byId(id);
    if (b == null) return null;
    final safe = offset.clamp(0, b.text.length);
    if (safe == 0) return insertAfter(id);
    final head = b.text.substring(0, safe);
    final tail = b.text.substring(safe);
    b.text = head;
    b.updatedAt = DateTime.now();
    final created = insertAfter(id, type: b.type == BType.code ? BType.text : b.type, text: tail);
    if (b.type == BType.todo) created.props['checked'] = false;
    return created;
  }

  /// Backspace at offset 0: merge into the previous text block, convert a
  /// heading/list to text, or delete an empty block.
  bool mergeBack(String id) {
    final b = byId(id);
    if (b == null) return false;
    final siblings = childrenOf(b.parentId);
    final i = siblings.indexWhere((x) => x.id == id);

    if (b.text.isEmpty && siblings.length > 1 && i > 0) {
      // first press on an empty block: convert to text, keep the caret there
      if (b.type != BType.text) {
        b.type = BType.text;
        b.props.remove('checked');
        b.updatedAt = DateTime.now();
        return true;
      }
      _blocks.remove(b);
      return true;
    }

    if (b.type != BType.text) {
      b.type = BType.text;
      b.props.remove('checked');
      b.updatedAt = DateTime.now();
      return true;
    }

    if (i <= 0) return false;
    final prev = siblings[i - 1];
    if (prev.type == BType.divider || !BType.hasText(prev.type)) return false;
    prev.text = prev.text + b.text;
    prev.updatedAt = DateTime.now();
    // move children up to the previous block so nothing is orphaned
    final moved = childrenOf(b.id);
    var key = childrenOf(prev.id).isEmpty ? null : childrenOf(prev.id).last.sortKey;
    for (final child in moved) {
      key = SKeys.after(key);
      child.parentId = prev.id;
      child.sortKey = key;
    }
    _blocks.remove(b);
    return true;
  }

  bool indent(String id) {
    final b = byId(id);
    if (b == null || !BType.canNest(b.type)) return false;
    final siblings = childrenOf(b.parentId);
    final i = siblings.indexWhere((x) => x.id == id);
    if (i <= 0) return false;
    final target = siblings[i - 1];
    b.parentId = target.id;
    b.sortKey = SKeys.after(
        childrenOf(target.id).isEmpty ? null : childrenOf(target.id).last.sortKey);
    b.updatedAt = DateTime.now();
    return true;
  }

  bool outdent(String id) {
    final b = byId(id);
    if (b == null || b.parentId == null) return false;
    final parent = byId(b.parentId!);
    if (parent == null) return false;
    final grand = parent.parentId;
    final siblings = childrenOf(grand);
    final idx = siblings.indexWhere((x) => x.id == parent.id);
    final next = idx >= 0 && idx + 1 < siblings.length ? siblings[idx + 1].sortKey : null;
    b.parentId = grand;
    b.sortKey = SKeys.between(parent.sortKey, next);
    b.updatedAt = DateTime.now();
    return true;
  }

  bool moveWithinSiblings(String id, int delta) {
    final b = byId(id);
    if (b == null) return false;
    final siblings = childrenOf(b.parentId);
    final i = siblings.indexWhere((x) => x.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= siblings.length) return false;
    final other = siblings[j];
    final tmp = b.sortKey;
    b.sortKey = other.sortKey;
    other.sortKey = tmp;
    return true;
  }

  /// Drops [id] next to [targetId] (before or after it), reparenting when the
  /// target lives elsewhere. Refuses to drop a block inside its own subtree.
  bool moveBlock(String id, String targetId, {bool before = true}) {
    if (id == targetId) return false;
    final block = byId(id);
    final target = byId(targetId);
    if (block == null || target == null) return false;
    if (isDescendant(targetId, id)) return false;
    if (target.parentId == id) return false;

    final siblings = childrenOf(target.parentId).where((b) => b.id != id).toList();
    final i = siblings.indexWhere((b) => b.id == targetId);
    if (i < 0) return false;
    final nextKey = before ? siblings[i].sortKey : (i + 1 < siblings.length ? siblings[i + 1].sortKey : null);
    final prevKey = before ? (i > 0 ? siblings[i - 1].sortKey : null) : siblings[i].sortKey;

    block.parentId = target.parentId;
    block.sortKey = SKeys.between(prevKey, nextKey);
    block.updatedAt = DateTime.now();
    return true;
  }

  void setType(String id, String type) {
    final b = byId(id);
    if (b == null) return;
    b.type = type;
    if (type != BType.todo) b.props.remove('checked');
    if (type == BType.toggle) b.props['open'] = b.props['open'] ?? true;
    b.updatedAt = DateTime.now();
  }

  void toggleChecked(String id) {
    final b = byId(id);
    if (b == null) return;
    b.props['checked'] = !(b.props['checked'] == true);
    b.updatedAt = DateTime.now();
  }

  void toggleOpen(String id) {
    final b = byId(id);
    if (b == null) return;
    b.props['open'] = !(b.props['open'] != false);
    b.updatedAt = DateTime.now();
  }

  /// Deletes a block. Divider and text blocks delete themselves; a block with
  /// children hands them to its parent.
  void delete(String id) {
    final b = byId(id);
    if (b == null) return;
    final kids = childrenOf(id);
    if (kids.isNotEmpty) {
      final parent = b.parentId;
      var key = b.sortKey;
      for (final k in kids) {
        k.parentId = parent;
        k.sortKey = SKeys.after(key);
        key = k.sortKey;
      }
    }
    _blocks.remove(b);
  }

  /// Duplicates [id] and its subtree right after the original subtree.
  /// Returns the id of the new root, or null when the block is gone.
  String? duplicate(String id) {
    final source = byId(id);
    if (source == null) return null;

    // last key occupied by the original subtree, so the copy lands after it
    var lastKey = source.sortKey;
    for (final b in _blocks) {
      if (b.id != source.id && isDescendant(b.id, source.id)) {
        if (b.sortKey.compareTo(lastKey) > 0) lastKey = b.sortKey;
      }
    }
    final siblings = childrenOf(source.parentId);
    final i = siblings.indexWhere((x) => x.id == id);
    final nextKey = i >= 0 && i + 1 < siblings.length ? siblings[i + 1].sortKey : null;
    final rootKey = SKeys.between(lastKey, nextKey);

    final created = <NoteBlock>[];
    NoteBlock copyNode(NoteBlock src, String? parentId, String key) {
      final copy = NoteBlock(
        id: _newId(),
        noteId: noteId,
        parentId: parentId,
        sortKey: key,
        type: src.type,
        text: src.text,
        props: Map<String, Object?>.from(src.props),
      );
      created.add(copy);
      // Keys only need to be ordered among their new siblings, and the
      // children's own keys already are, so they are copied verbatim.
      for (final child in childrenOf(src.id)) {
        copyNode(child, copy.id, child.sortKey);
      }
      return copy;
    }

    copyNode(source, source.parentId, rootKey);
    _blocks.addAll(created);
    return created.first.id;
  }

  /// Sets a text colour or background token; `null` resets to default.
  void setColor(String id, String token, {bool background = false}) {
    final b = byId(id);
    if (b == null) return;
    if (token.isEmpty || token == 'default') {
      b.props.remove(background ? 'background' : 'color');
    } else {
      b.props[background ? 'background' : 'color'] = token;
    }
    b.updatedAt = DateTime.now();
  }

  /// Deep copy for the undo stack.
  List<Map<String, Object?>> snapshot() => _blocks.map((b) => b.toMap()).toList();

  void restoreSnapshot(List<Map<String, Object?>> rows) {
    _blocks
      ..clear()
      ..addAll(rows.map(NoteBlock.fromMap));
  }

  /// Replaces the text of [id] between [start] and [end]. Returns the caret
  /// position after the replacement.
  int replaceRange(String id, int start, int end, String replacement) {
    final b = byId(id);
    if (b == null) return 0;
    final safeStart = start.clamp(0, b.text.length);
    final safeEnd = end.clamp(safeStart, b.text.length);
    b.text = b.text.replaceRange(safeStart, safeEnd, replacement);
    b.updatedAt = DateTime.now();
    return safeStart + replacement.length;
  }

  bool get hasVisibleChildren {
    for (final b in _blocks) {
      if (b.type == BType.toggle && childrenOf(b.id).isNotEmpty) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- markdown

  String _databaseMarkdown(NoteBlock b, String pad) {
    List<Object?> cols;
    List<Object?> rows;
    try {
      cols = jsonDecode(b.props['columns'] as String? ?? '[]') as List;
      rows = jsonDecode(b.props['rows'] as String? ?? '[]') as List;
    } catch (_) {
      return '';
    }
    if (cols.isEmpty) return '';
    String name(Object? c) => (c is Map ? (c['name'] as String?) : null) ?? 'Column';
    String id(Object? c) => (c is Map ? (c['id'] as String?) : null) ?? '';
    String cell(Object? r, String cid) {
      final cells = (r is Map ? r['cells'] : null);
      if (cells is! Map) return '';
      return (cells[cid] ?? '').toString().replaceAll('|', '/');
    }

    final buffer = StringBuffer();
    buffer.writeln('$pad| ${cols.map(name).join(' | ')} |');
    buffer.writeln('$pad|${cols.map((_) => ' --- |').join()}');
    for (final r in rows) {
      buffer.writeln('$pad| ${cols.map((c) => cell(r, id(c))).join(' | ')} |');
    }
    return buffer.toString();
  }

  /// Markdown projection used for preview, export and the full-text index.
  String markdown() {
    final out = StringBuffer();
    final lines = outline();
    var fenceOpen = false;
    var fenceDepth = -1;
    for (final line in lines) {
      final b = line.block;
      final pad = '  ' * line.depth;

      if (b.type == BType.code) {
        if (!fenceOpen || fenceDepth != line.depth) {
          if (fenceOpen) out.writeln('```');
          out.writeln('$pad```${b.language}');
          fenceOpen = true;
          fenceDepth = line.depth;
        }
        out.writeln(b.text);
        continue;
      }
      if (fenceOpen) {
        out.writeln('```');
        fenceOpen = false;
      }

      switch (b.type) {
        case BType.h1:
          out.writeln('$pad# ${b.text}');
        case BType.h2:
          out.writeln('$pad## ${b.text}');
        case BType.h3:
          out.writeln('$pad### ${b.text}');
        case BType.h4:
          out.writeln('$pad#### ${b.text}');
        case BType.bulleted:
          out.writeln('$pad- ${b.text}');
        case BType.numbered:
          out.writeln('${pad}1. ${b.text}');
        case BType.todo:
          out.writeln('$pad- [${b.checked ? 'x' : ' '}] ${b.text}');
        case BType.toggle:
          out.writeln('$pad- ${b.text}');
        case BType.quote:
          out.writeln('$pad> ${b.text}');
        case BType.callout:
          out.writeln('$pad> [!TIP] ${b.text}');
        case BType.divider:
          out.writeln('$pad---');
        case BType.image:
          final path = b.props['path'] as String? ?? '';
          final alt = b.text.isEmpty ? 'image' : b.text;
          out.writeln('$pad![$alt]($path)');
        case BType.database:
          out.write(_databaseMarkdown(b, pad));
        case BType.chart:
          out.writeln('$pad[chart]');
        case BType.toc:
          out.writeln('$pad[toc]');
        case BType.file:
          final path = b.props['path'] as String? ?? '';
          out.writeln('$pad[file]($path)');
        case BType.bookmark:
          final url = b.props['url'] as String? ?? '';
          out.writeln('$pad[bookmark]($url)');
        case BType.embed:
          final url = b.props['url'] as String? ?? '';
          out.writeln('$pad[embed]($url)');
        case BType.equation:
          out.writeln('$pad\$\$ ${b.text} \$\$');
        default:
          out.writeln('$pad${b.text}');
      }
    }
    if (fenceOpen) out.writeln('```');
    return out.toString().trimRight();
  }

  /// Parses markdown into blocks. Indentation (2 spaces or a tab per level)
  /// builds the parent chain, so a migrated page keeps its outline.
  static BlockDoc fromMarkdown(String noteId, String markdown,
      {String Function()? idGen}) {
    final doc = BlockDoc(noteId, const [], idGen);
    final stack = <MapEntry<int, String>>[]; // indent -> block id
    final tableLines = <String>[];
    var tableLevel = 0;
    var fence = '';
    final codeBuffer = StringBuffer();
    String? codeParent;

    void add(String type, String text, int indent) {
      while (stack.isNotEmpty && stack.last.key >= indent) {
        stack.removeLast();
      }
      final parentId = stack.isEmpty ? null : stack.last.value;
      final siblings = doc.childrenOf(parentId);
      final key = SKeys.after(siblings.isEmpty ? null : siblings.last.sortKey);
      final b = NoteBlock(
        id: doc._newId(),
        noteId: noteId,
        parentId: parentId,
        sortKey: key,
        type: type,
        text: text,
      );
      doc._blocks.add(b);
      if (BType.canNest(type)) stack.add(MapEntry(indent, b.id));
    }

    List<String> splitRow(String line) {
      var body = line.trim();
      if (body.startsWith('|')) body = body.substring(1);
      if (body.endsWith('|')) body = body.substring(0, body.length - 1);
      return body.split('|').map((c) => c.trim()).toList();
    }

    bool isSeparator(String line) {
      final cells = splitRow(line);
      return cells.isNotEmpty &&
          cells.every((c) => RegExp(r'^:?-{3,}:?$').hasMatch(c));
    }

    String inferType(List<String> lines, int index) {
      final values = <String>[];
      for (final line in lines) {
        final cells = splitRow(line);
        if (index < cells.length && cells[index].isNotEmpty) values.add(cells[index]);
      }
      if (values.isEmpty) return BType.text;
      if (values.every((v) => double.tryParse(v.replaceAll(',', '.')) != null)) {
        return 'number';
      }
      if (values.every((v) => v.toLowerCase() == 'true' || v.toLowerCase() == 'false')) {
        return 'checkbox';
      }
      return BType.text;
    }

    void flushTable() {
      if (tableLines.isEmpty) return;
      final header = splitRow(tableLines.first);
      final data = tableLines.skip(1).where((l) => !isSeparator(l)).toList();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final columns = <Map<String, Object?>>[];
      final ids = <String>[];
      for (var i = 0; i < header.length; i++) {
        final id = 'c${stamp}_$i';
        ids.add(id);
        columns.add({
          'id': id,
          'name': header[i].isEmpty ? 'Column ${i + 1}' : header[i],
          'type': inferType(data, i),
        });
      }
      final rows = <Map<String, Object?>>[];
      var r = 0;
      for (final line in data) {
        final cells = splitRow(line);
        final map = <String, String>{};
        for (var i = 0; i < ids.length && i < cells.length; i++) {
          if (cells[i].isNotEmpty) map[ids[i]] = cells[i];
        }
        rows.add({'id': 'r${stamp}_${r++}', 'cells': map});
      }
      add(BType.database, '', tableLevel);
      doc._blocks.last.props['columns'] = jsonEncode(columns);
      doc._blocks.last.props['rows'] = jsonEncode(rows);
      tableLines.clear();
    }

    for (final rawLine in markdown.split('\n')) {
      if (rawLine.trimLeft().startsWith('```')) {
        if (fence.isEmpty) {
          var fenceIndent = 0;
          while (fenceIndent < rawLine.length && rawLine[fenceIndent] == ' ') {
            fenceIndent++;
          }
          final fenceLevel = fenceIndent ~/ 2;
          while (stack.isNotEmpty && stack.last.key >= fenceLevel) {
            stack.removeLast();
          }
          codeParent = stack.isEmpty ? null : stack.last.value;
          fence = rawLine.trim().substring(3).trim();
          codeBuffer.clear();
          continue;
        } else {
          final b = NoteBlock(
            id: doc._newId(),
            noteId: noteId,
            parentId: codeParent,
            sortKey: SKeys.after(doc.childrenOf(codeParent).isEmpty
                ? null
                : doc.childrenOf(codeParent).last.sortKey),
            type: BType.code,
            text: codeBuffer.toString().trimRight(),
            props: {'language': fence.isEmpty ? 'plaintext' : fence},
          );
          doc._blocks.add(b);
          fence = '';
          codeBuffer.clear();
          continue;
        }
      }
      if (fence.isNotEmpty) {
        codeBuffer.writeln(rawLine);
        continue;
      }
      if (rawLine.trim().isEmpty) continue;

      var indent = 0;
      var i = 0;
      while (i < rawLine.length) {
        if (rawLine[i] == ' ') {
          indent++;
          i++;
        } else if (rawLine[i] == '\t') {
          indent += 2;
          i++;
        } else {
          break;
        }
      }
      final level = indent ~/ 2;
      final t = rawLine.substring(i);

      if (t.startsWith('|') && t.endsWith('|')) {
        if (tableLines.isEmpty) tableLevel = level;
        tableLines.add(t);
        continue;
      }
      if (tableLines.isNotEmpty) flushTable();

      if (t == '[chart]') {
        add(BType.chart, '', level);
      } else if (t == '[toc]') {
        add(BType.toc, '', level);
      } else if (t.startsWith(r'$$') && t.endsWith(r'$$') && t.length >= 4) {
        add(BType.equation, t.substring(2, t.length - 2).trim(), level);
      } else if (t.startsWith('[file](') || t.startsWith('[bookmark](') || t.startsWith('[embed](')) {
        final close = t.lastIndexOf(')');
        final open = t.indexOf('(');
        final url = close > open ? t.substring(open + 1, close) : '';
        final type = t.startsWith('[file]')
            ? BType.file
            : t.startsWith('[bookmark]')
                ? BType.bookmark
                : BType.embed;
        add(type, '', level);
        if (type == BType.file) {
          doc._blocks.last.props['path'] = url;
          doc._blocks.last.text = url.split(RegExp(r'[\\\\/]')).last;
        } else {
          doc._blocks.last.props['url'] = url;
          doc._blocks.last.text = url;
        }
      } else if (t.startsWith('#### ')) {
        add(BType.h4, t.substring(5), level);
      } else if (t.startsWith('### ')) {
        add(BType.h3, t.substring(4), level);
      } else if (t.startsWith('## ')) {
        add(BType.h2, t.substring(3), level);
      } else if (t.startsWith('# ')) {
        add(BType.h1, t.substring(2), level);
      } else if (t == '---' || t == '***' || t == '___') {
        add(BType.divider, '', level);
      } else if (RegExp(r'^- \[[ xX]\] ').hasMatch(t)) {
        add(BType.todo, t.substring(6), level);
        doc._blocks.last.props['checked'] = t[3].toLowerCase() == 'x';
      } else if (t.startsWith('- ') || t.startsWith('* ') || t.startsWith('+ ')) {
        add(BType.bulleted, t.substring(2), level);
      } else if (RegExp(r'^\d+[.)] ').hasMatch(t)) {
        add(BType.numbered, t.replaceFirst(RegExp(r'^\d+[.)] '), ''), level);
      } else if (t.startsWith('![')) {
        final closeBracket = t.indexOf(']');
        final openParen = closeBracket >= 0 ? t.indexOf('(', closeBracket) : -1;
        final closeParen = t.lastIndexOf(')');
        if (closeBracket > 1 && openParen > 0 && closeParen > openParen) {
          final alt = t.substring(2, closeBracket);
          final path = t.substring(openParen + 1, closeParen);
          add(BType.image, alt, level);
          doc._blocks.last.props['path'] = path;
        } else {
          add(BType.text, t, level);
        }
      } else if (t.startsWith('> [!')) {
        final close = t.indexOf(']');
        final body = close >= 0 && close + 2 <= t.length ? t.substring(close + 2) : t.substring(2);
        add(BType.callout, body, level);
      } else if (t.startsWith('> ')) {
        add(BType.quote, t.substring(2), level);
      } else {
        add(BType.text, t, level);
      }
    }
    if (tableLines.isNotEmpty) flushTable();
    if (fence.isNotEmpty) {
      final b = NoteBlock(
        id: doc._newId(),
        noteId: noteId,
        parentId: codeParent,
        sortKey: SKeys.after(doc.childrenOf(codeParent).isEmpty
            ? null
            : doc.childrenOf(codeParent).last.sortKey),
        type: BType.code,
        text: codeBuffer.toString().trimRight(),
        props: {'language': fence},
      );
      doc._blocks.add(b);
    }
    return doc;
  }

  Map<String, Object?> toJson() => {
        'note_id': noteId,
        'blocks': _blocks.map((b) => b.toMap()).toList(),
      };
}