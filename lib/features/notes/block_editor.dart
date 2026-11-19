import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../core/db.dart';
import '../../design/tokens.dart';
import 'block_model.dart';
import 'chart_block.dart';
import 'database_block.dart';

/// A block editor over `note_blocks`: each line is a block with its own type,
/// nesting and shortcuts, and the whole document is projected to markdown for
/// preview, export and search.
///
/// Behaviour follows the workspace convention:
///  - Enter splits a block, Backspace at offset 0 merges it upward
///  - Tab / Shift+Tab nest and lift a block
///  - `/` opens the insert menu, Ctrl+/ reopens it anywhere
///  - Ctrl+B / I / U / E / Shift+S wrap the selection in markdown marks
///  - Ctrl+Enter toggles a to-do
class BlockEditor extends StatefulWidget {
  const BlockEditor({
    super.key,
    required this.noteId,
    required this.initialMarkdown,
    required this.onChanged,
    this.token = 0,
  });

  final String noteId;
  final String initialMarkdown;
  final ValueChanged<String> onChanged;

  /// Bumped by the host to force a reload from the database (version restore).
  final int token;

  @override
  State<BlockEditor> createState() => BlockEditorState();
}

class _MenuItem {
  const _MenuItem(
    this.type,
    this.label,
    this.icon,
    this.keywords, {
    this.subtitle = '',
    this.category = 'Basic blocks',
  });
  final String type;
  final String label;
  final IconData icon;
  final String keywords;
  final String subtitle;
  final String category;
}

const _menuItems = <_MenuItem>[
  _MenuItem(
    BType.text,
    'Text',
    Icons.notes_rounded,
    'text plain paragraph',
    subtitle: 'Just start writing with plain text',
    category: 'Basic blocks',
  ),
  _MenuItem(
    BType.h1,
    'Heading 1',
    Icons.title_rounded,
    'h1 heading one big',
    subtitle: 'Big section heading',
    category: 'Basic blocks',
  ),
  _MenuItem(
    BType.h2,
    'Heading 2',
    Icons.text_fields_rounded,
    'h2 heading two',
    subtitle: 'Medium section heading',
    category: 'Basic blocks',
  ),
  _MenuItem(
    BType.h3,
    'Heading 3',
    Icons.short_text_rounded,
    'h3 heading three',
    subtitle: 'Small section heading',
    category: 'Basic blocks',
  ),
  _MenuItem(
    BType.h4,
    'Heading 4',
    Icons.subject_rounded,
    'h4 heading four',
    subtitle: 'Compact subsection heading',
    category: 'Basic blocks',
  ),
  _MenuItem(
    BType.bulleted,
    'Bulleted list',
    Icons.format_list_bulleted_rounded,
    'bullet list ul',
    subtitle: 'Create a simple bulleted list',
    category: 'Basic blocks',
  ),
  _MenuItem(
    BType.numbered,
    'Numbered list',
    Icons.format_list_numbered_rounded,
    'number list ol',
    subtitle: 'Create a list with numbering',
    category: 'Basic blocks',
  ),
  _MenuItem(
    BType.todo,
    'To-do list',
    Icons.check_box_outlined,
    'todo task checkbox',
    subtitle: 'Track tasks with a to-do list',
    category: 'Basic blocks',
  ),
  _MenuItem(
    BType.toggle,
    'Toggle list',
    Icons.expand_more_rounded,
    'toggle collapse details',
    subtitle: 'Toggles can hide and show content inside',
    category: 'Basic blocks',
  ),
  _MenuItem(
    BType.quote,
    'Quote',
    Icons.format_quote_rounded,
    'quote blockquote',
    subtitle: 'Capture a quote',
    category: 'Basic blocks',
  ),
  _MenuItem(
    BType.callout,
    'Callout',
    Icons.tips_and_updates_outlined,
    'callout note aside',
    subtitle: 'Make writing stand out',
    category: 'Basic blocks',
  ),
  _MenuItem(
    BType.divider,
    'Divider',
    Icons.horizontal_rule_rounded,
    'divider hr line separator',
    subtitle: 'Visually divide blocks',
    category: 'Basic blocks',
  ),
  _MenuItem(
    BType.code,
    'Code',
    Icons.code_rounded,
    'code snippet mono',
    subtitle: 'Capture a code snippet with language label',
    category: 'Advanced & study',
  ),
  _MenuItem(
    BType.equation,
    'Equation',
    Icons.functions_rounded,
    'equation math latex formula tex',
    subtitle: 'Display a TeX / math equation',
    category: 'Advanced & study',
  ),
  _MenuItem(
    BType.toc,
    'Table of contents',
    Icons.list_alt_rounded,
    'toc outline headings contents',
    subtitle: 'Show an outline of all headings',
    category: 'Advanced & study',
  ),
  _MenuItem(
    'link_page',
    'Link to page',
    Icons.link_rounded,
    'link page wiki subpage ltp',
    subtitle: 'Link to an existing page in your notes',
    category: 'Advanced & study',
  ),
  _MenuItem(
    'kwl',
    'Study notes template',
    Icons.view_quilt_outlined,
    'study notes template know questions summary kwl',
    subtitle: 'Prior knowledge · Questions · Summary',
    category: 'Advanced & study',
  ),
  _MenuItem(
    BType.database,
    'Database',
    Icons.table_chart_outlined,
    'database table collection rows properties',
    subtitle: 'Inline table with properties & board view',
    category: 'Database & layout',
  ),
  _MenuItem(
    BType.chart,
    'Chart',
    Icons.insights_rounded,
    'chart graph bar line plot analytics',
    subtitle: 'Bar or line chart bound to a database',
    category: 'Database & layout',
  ),
  _MenuItem(
    'columns2',
    '2 columns',
    Icons.view_column_outlined,
    'columns two layout side',
    subtitle: 'Create 2 columns of blocks',
    category: 'Database & layout',
  ),
  _MenuItem(
    'columns3',
    '3 columns',
    Icons.view_week_outlined,
    'columns three layout side',
    subtitle: 'Create 3 columns of blocks',
    category: 'Database & layout',
  ),
  _MenuItem(
    BType.image,
    'Image',
    Icons.image_outlined,
    'image picture photo file',
    subtitle: 'Embed an image from your computer',
    category: 'Media & files',
  ),
  _MenuItem(
    BType.file,
    'File',
    Icons.insert_drive_file_outlined,
    'file attachment upload document',
    subtitle: 'Attach a local file or PDF',
    category: 'Media & files',
  ),
  _MenuItem(
    BType.bookmark,
    'Web bookmark',
    Icons.bookmark_border_rounded,
    'bookmark link web url',
    subtitle: 'Save a link as a visual bookmark',
    category: 'Media & files',
  ),
  _MenuItem(
    BType.embed,
    'Embed',
    Icons.open_in_new_rounded,
    'embed iframe url link',
    subtitle: 'Embed an external link',
    category: 'Media & files',
  ),
];

class BlockEditorState extends State<BlockEditor> {
  BlockDoc? _doc;
  bool _loading = true;

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  Timer? _saveTimer;
  String? _menuBlockId;
  String _menuQuery = '';
  int _menuIndex = 0;

  // Undo/redo: snapshots of the block rows, with coalescing for typing.
  final List<List<Map<String, Object?>>> _undo = [];
  final List<List<Map<String, Object?>>> _redo = [];
  static const int _undoLimit = 120;
  String? _typingBlockId;
  DateTime _lastTypingSnapshot = DateTime.fromMillisecondsSinceEpoch(0);

  // In-page find and replace.
  bool _findOpen = false;
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _findFocus = FocusNode();
  List<_Match> _matches = const [];
  int _matchIndex = 0;

  // Drag and drop.
  String? _dragBlockId;
  String? _dropTargetId;
  String? _hoveredBlockId;
  bool _dropBefore = true;
  final Map<String, GlobalKey> _rowKeys = {};

  void _pushUndo({String? typingBlockId}) {
    final doc = _doc;
    if (doc == null) return;
    final now = DateTime.now();
    if (typingBlockId != null &&
        typingBlockId == _typingBlockId &&
        now.difference(_lastTypingSnapshot) <
            const Duration(milliseconds: 700)) {
      _lastTypingSnapshot = now;
      return;
    }
    _typingBlockId = typingBlockId;
    _lastTypingSnapshot = now;
    _undo.add(doc.snapshot());
    if (_undo.length > _undoLimit) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoAction() {
    final doc = _doc;
    if (doc == null || _undo.isEmpty) return;
    _redo.add(doc.snapshot());
    final rows = _undo.removeLast();
    _restoreRows(rows);
  }

  void _redoAction() {
    final doc = _doc;
    if (doc == null || _redo.isEmpty) return;
    _undo.add(doc.snapshot());
    final rows = _redo.removeLast();
    _restoreRows(rows);
  }

  void _restoreRows(List<Map<String, Object?>> rows) {
    final doc = _doc;
    if (doc == null) return;
    final focusId = _focusedBlockId();
    final caret = focusId == null
        ? 0
        : (_controllers[focusId]?.selection.baseOffset ?? 0);
    doc.restoreSnapshot(rows);
    final live = doc.raw.map((b) => b.id).toSet();
    for (final id in _controllers.keys.toList()) {
      if (!live.contains(id)) _forget(id);
    }
    for (final b in doc.raw) {
      final ctrl = _controllers[b.id];
      if (ctrl != null && ctrl.text != b.text) {
        ctrl.value = TextEditingValue(
          text: b.text,
          selection: TextSelection.collapsed(offset: b.text.length),
        );
      }
    }
    if (doc.raw.isEmpty) doc.append();
    setState(() {});
    _scheduleMicroSave();
    final target = focusId != null && doc.byId(focusId) != null
        ? focusId
        : doc.outline().first.block.id;
    _focusAfterFrame(target, caret);
  }

  String? _focusedBlockId() {
    for (final e in _focusNodes.entries) {
      if (e.value.hasFocus) return e.key;
    }
    return _lastFocusedId;
  }

  @override
  void initState() {
    super.initState();
    _findFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        closeFindBar();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _findController.addListener(_refreshMatches);
    _load();
  }

  Future<void> _load() async {
    List<NoteBlock> rows = const [];
    try {
      rows = await Store.i.blocksFor(widget.noteId);
    } catch (_) {
      rows = const [];
    }
    if (!mounted) return;

    final doc = rows.isEmpty
        ? (widget.initialMarkdown.trim().isEmpty
              ? BlockDoc(widget.noteId)
              : BlockDoc.fromMarkdown(widget.noteId, widget.initialMarkdown))
        : BlockDoc(widget.noteId, rows);
    if (doc.raw.isEmpty) doc.append();

    setState(() {
      _doc = doc;
      _loading = false;
    });
    if (rows.isEmpty) {
      unawaited(_persistNow());
    } else {
      // Keep the page's markdown projection in step after a crash or a quick
      // close that skipped the last debounce.
      final projected = doc.markdown();
      if (projected != widget.initialMarkdown) widget.onChanged(projected);
    }
    _focusAfterFrame(doc.outline().first.block.id, 0);
  }

  @override
  void didUpdateWidget(covariant BlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId == widget.noteId && oldWidget.token == widget.token)
      return;
    _saveTimer?.cancel();
    final previous = _doc;
    if (previous != null) unawaited(_persistDoc(previous, notify: false));
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
    _doc = null;
    _menuBlockId = null;
    _lastFocusedId = null;
    setState(() => _loading = true);
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(_persistNow(notify: false));
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ persistence

  void _scheduleMicroSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_persistNow()),
    );
  }

  Future<void> _persistNow({bool notify = true}) async {
    final doc = _doc;
    if (doc == null) return;
    await _persistDoc(doc, notify: notify);
  }

  Future<void> _persistDoc(BlockDoc doc, {bool notify = true}) async {
    final markdown = doc.markdown();
    if (notify) widget.onChanged(markdown);
    try {
      await Store.i.replaceBlocks(doc.noteId, doc.raw);
    } catch (_) {
      // The note row itself is saved by the host page; block persistence is
      // best effort and retried on the next edit.
    }
  }

  // ------------------------------------------------------------------ controllers

  TextEditingController _controllerFor(NoteBlock b) => _controllers.putIfAbsent(
    b.id,
    () =>
        TextEditingController(text: b.text)
          ..selection = const TextSelection.collapsed(offset: 0),
  );

  FocusNode _nodeFor(NoteBlock b) => _focusNodes.putIfAbsent(b.id, () {
    final node = FocusNode(
      debugLabel: 'block-${b.id}',
      onKeyEvent: (n, e) => _onKey(b.id, e),
    );
    node.addListener(() {
      if (node.hasFocus) _lastFocusedId = b.id;
    });
    return node;
  });

  String? _lastFocusedId;

  /// Inserts text at the caret of the focused block (used by the page-level
  /// command surface: Ctrl+K link, Ctrl+/ menu).
  void insertTextAtCaret(String text) {
    final doc = _doc;
    if (doc == null) return;
    _pushUndo();
    String? id;
    for (final e in _focusNodes.entries) {
      if (e.value.hasFocus) {
        id = e.key;
        break;
      }
    }
    id ??= _lastFocusedId;
    id ??= doc.outline().isEmpty ? null : doc.outline().first.block.id;
    if (id == null) return;
    final block = doc.byId(id);
    if (block == null) return;
    final ctrl = _controllerFor(block);
    final sel = ctrl.selection;
    final at = sel.isValid ? sel.start : ctrl.text.length;
    final end = sel.isValid ? sel.end : ctrl.text.length;
    final next = ctrl.text.replaceRange(at, end, text);
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + text.length),
    );
    block.text = next;
    block.updatedAt = DateTime.now();
    setState(() {});
    _scheduleMicroSave();
    _focusAfterFrame(id, at + text.length);
  }

  void _forget(String id) {
    _controllers.remove(id)?.dispose();
    _focusNodes.remove(id)?.dispose();
  }

  void _focusAfterFrame(String id, int caret) {
    final block = _doc?.byId(id);
    if (block != null) {
      _controllerFor(block);
      _nodeFor(block);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _focusNodes[id];
      final ctrl = _controllers[id];
      if (node == null || ctrl == null) return;
      node.requestFocus();
      final pos = caret.clamp(0, ctrl.text.length);
      ctrl.selection = TextSelection.collapsed(offset: pos);
    });
  }

  // ------------------------------------------------------------------ menu

  void showInsertMenu() {
    final doc = _doc;
    if (doc == null) return;
    final first = doc.outline().first.block;
    setState(() {
      _menuBlockId = first.id;
      _menuQuery = '';
      _menuIndex = 0;
    });
  }

  List<_MenuItem> get _filteredMenu {
    final q = _menuQuery.trim().toLowerCase();
    if (q.isEmpty) return _menuItems;
    return _menuItems
        .where(
          (m) => m.label.toLowerCase().contains(q) || m.keywords.contains(q),
        )
        .toList();
  }

  void _openMenuFor(String blockId, String text) {
    if (!text.startsWith('/')) {
      if (_menuBlockId != null) setState(() => _menuBlockId = null);
      return;
    }
    setState(() {
      _menuBlockId = blockId;
      _menuQuery = text.substring(1);
      _menuIndex = 0;
    });
  }

  void _applyMenu(_MenuItem item) {
    final doc = _doc;
    final id = _menuBlockId;
    if (doc == null || id == null) return;
    final block = doc.byId(id);
    if (block == null) return;

    final ctrl = _controllerFor(block);
    ctrl.text = '';
    block.text = '';

    if (item.type == BType.divider) {
      doc.setType(id, BType.divider);
      final next = doc.insertAfter(id);
      setState(() => _menuBlockId = null);
      _focusAfterFrame(next.id, 0);
      _scheduleMicroSave();
      return;
    }
    if (item.type == 'link_page') {
      doc.setType(id, BType.text);
      block.text = '[[';
      ctrl.value = const TextEditingValue(
        text: '[[',
        selection: TextSelection.collapsed(offset: 2),
      );
      setState(() => _menuBlockId = null);
      _focusAfterFrame(id, 2);
      _scheduleMicroSave();
      return;
    }
    if (item.type == 'kwl') {
      doc.setType(id, BType.h2);
      block.text = 'What I already know';
      ctrl.text = block.text;
      final b1 = doc.insertAfter(id, type: BType.bulleted, text: '');
      final h2 = doc.insertAfter(
        b1.id,
        type: BType.h2,
        text: 'Questions to answer',
      );
      final b2 = doc.insertAfter(h2.id, type: BType.bulleted, text: '');
      final h3 = doc.insertAfter(
        b2.id,
        type: BType.h2,
        text: 'Summary in my own words',
      );
      doc.insertAfter(h3.id, type: BType.bulleted, text: '');
      setState(() => _menuBlockId = null);
      _focusAfterFrame(b1.id, 0);
      _scheduleMicroSave();
      return;
    }

    doc.setType(id, item.type);
    if (item.type == BType.database) {
      DbData.blank().writeTo(block.props);
    } else if (item.type == BType.chart) {
      block.props['type'] = ChartType.bar;
      block.props['aggregate'] = DbAggregate.count;
    }
    setState(() => _menuBlockId = null);
    if (item.type == BType.image) {
      unawaited(_pickImage(block));
      return;
    }
    if (item.type == 'columns2' || item.type == 'columns3') {
      _makeColumns(block, item.type == 'columns2' ? 2 : 3);
      setState(() => _menuBlockId = null);
      _scheduleMicroSave();
      return;
    }
    if (item.type == BType.file) {
      unawaited(_pickFile(block));
      setState(() => _menuBlockId = null);
      return;
    }
    if (item.type == BType.bookmark || item.type == BType.embed) {
      unawaited(_promptUrl(block, item.type));
      setState(() => _menuBlockId = null);
      return;
    }
    if (BType.hasText(item.type)) {
      _focusAfterFrame(id, 0);
    }
    _scheduleMicroSave();
  }

  Future<void> _pickImage(NoteBlock block) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      dialogTitle: 'Choose an image',
    );
    final path = result?.files.single.path;
    if (!mounted) return;
    if (path == null) {
      _doc?.setType(block.id, BType.text);
      setState(() {});
      _scheduleMicroSave();
      return;
    }
    block.props['path'] = path;
    block.props['name'] = p.basename(path);
    block.text = p.basename(path);
    block.updatedAt = DateTime.now();
    setState(() {});
    _scheduleMicroSave();
  }

  // ------------------------------------------------------------------ key handling

  KeyEventResult _onKey(String id, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    final doc = _doc;
    if (doc == null) return KeyEventResult.ignored;
    final block = doc.byId(id);
    if (block == null) return KeyEventResult.ignored;
    final ctrl = _controllerFor(block);
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final ctrlDown =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // ---- document-level shortcuts
    if (ctrlDown && key == LogicalKeyboardKey.keyZ) {
      shift ? _redoAction() : _undoAction();
      return KeyEventResult.handled;
    }
    if (ctrlDown && key == LogicalKeyboardKey.keyY) {
      _redoAction();
      return KeyEventResult.handled;
    }
    if (ctrlDown && key == LogicalKeyboardKey.keyD) {
      _pushUndo();
      final copy = doc.duplicate(id);
      setState(() {});
      _scheduleMicroSave();
      if (copy != null) _focusAfterFrame(copy, 0);
      return KeyEventResult.handled;
    }
    if (ctrlDown &&
        shift &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      _pushUndo();
      if (doc.moveWithinSiblings(
        id,
        key == LogicalKeyboardKey.arrowUp ? -1 : 1,
      )) {
        setState(() {});
        _scheduleMicroSave();
        _focusAfterFrame(id, ctrl.selection.baseOffset);
      }
      return KeyEventResult.handled;
    }
    if (ctrlDown && key == LogicalKeyboardKey.keyF) {
      showFindBar();
      return KeyEventResult.handled;
    }
    if (ctrlDown && key == LogicalKeyboardKey.keyK) {
      unawaited(_insertLink(id));
      return KeyEventResult.handled;
    }

    // ---- insert menu navigation
    if (_menuBlockId == id) {
      final items = _filteredMenu;
      if (key == LogicalKeyboardKey.escape) {
        setState(() => _menuBlockId = null);
        return KeyEventResult.handled;
      }
      if (items.isNotEmpty && (key == LogicalKeyboardKey.arrowDown)) {
        setState(() => _menuIndex = (_menuIndex + 1) % items.length);
        return KeyEventResult.handled;
      }
      if (items.isNotEmpty && (key == LogicalKeyboardKey.arrowUp)) {
        setState(
          () => _menuIndex = (_menuIndex - 1 + items.length) % items.length,
        );
        return KeyEventResult.handled;
      }
      if (items.isNotEmpty &&
          (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter)) {
        _applyMenu(items[_menuIndex.clamp(0, items.length - 1)]);
        return KeyEventResult.handled;
      }
    }

    if (ctrlDown && key == LogicalKeyboardKey.keyB) {
      _wrap(id, '**');
      return KeyEventResult.handled;
    }
    if (ctrlDown && key == LogicalKeyboardKey.keyI) {
      _wrap(id, '*');
      return KeyEventResult.handled;
    }
    if (ctrlDown && key == LogicalKeyboardKey.keyU) {
      _wrap(id, '<u>', '</u>');
      return KeyEventResult.handled;
    }
    if (ctrlDown && key == LogicalKeyboardKey.keyE) {
      _wrap(id, '`');
      return KeyEventResult.handled;
    }
    if (ctrlDown && shift && key == LogicalKeyboardKey.keyS) {
      _wrap(id, '~~');
      return KeyEventResult.handled;
    }
    if (ctrlDown && key == LogicalKeyboardKey.slash) {
      setState(() {
        _menuBlockId = id;
        _menuQuery = '';
        _menuIndex = 0;
      });
      return KeyEventResult.handled;
    }
    if (ctrlDown &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      _pushUndo();
      doc.toggleChecked(id);
      setState(() {});
      _scheduleMicroSave();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (_menuBlockId != null) {
        setState(() => _menuBlockId = null);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.tab) {
      if (block.type == BType.code) {
        _insert(ctrl, '  ');
      } else {
        _pushUndo();
        final moved = shift ? doc.outdent(id) : doc.indent(id);
        if (moved) {
          setState(() {});
          _scheduleMicroSave();
          _focusAfterFrame(id, ctrl.selection.baseOffset);
        }
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (shift) {
        _insert(ctrl, '\n');
      } else if (block.type == BType.text &&
          const ['---', '***', '___'].contains(block.text.trim())) {
        // A horizontal rule typed on its own line becomes a divider.
        _pushUndo();
        doc.setType(id, BType.divider);
        block.text = '';
        ctrl.value = const TextEditingValue(text: '');
        final next = doc.insertAfter(id);
        setState(() {});
        _scheduleMicroSave();
        _focusAfterFrame(next.id, 0);
      } else {
        final offset = ctrl.selection.extentOffset.clamp(0, ctrl.text.length);
        _pushUndo();
        final tail = doc.split(id, offset);
        if (tail != null) {
          ctrl.text = block.text;
          ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
          setState(() {});
          _scheduleMicroSave();
          _focusAfterFrame(tail.id, 0);
        }
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.backspace) {
      final sel = ctrl.selection;
      if (sel.isCollapsed && sel.baseOffset == 0 && block.text.isEmpty) {
        final lines = doc.outline();
        final index = lines.indexWhere((l) => l.block.id == id);
        final prevId = index > 0 ? lines[index - 1].block.id : null;
        final before = prevId == null
            ? 0
            : (_controllers[prevId]?.text.length ?? 0);
        _pushUndo();
        if (doc.mergeBack(id)) {
          if (doc.byId(id) == null) {
            _forget(id);
            setState(() {});
            if (prevId != null) {
              final prevCtrl = _controllers[prevId];
              _focusAfterFrame(prevId, prevCtrl?.text.length ?? before);
            }
          } else {
            setState(() {});
          }
          _scheduleMicroSave();
          return KeyEventResult.handled;
        }
      }
      if (sel.isCollapsed && sel.baseOffset == 0) {
        final lines = doc.outline();
        final index = lines.indexWhere((l) => l.block.id == id);
        if (index > 0) {
          final prev = lines[index - 1].block;
          if (BType.hasText(prev.type) && prev.type != BType.code) {
            final prevCtrl = _controllerFor(prev);
            final caret = prevCtrl.text.length;
            _pushUndo();
            doc.mergeBack(id);
            _forget(id);
            setState(() {});
            _scheduleMicroSave();
            _focusAfterFrame(prev.id, caret);
            return KeyEventResult.handled;
          }
        }
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final sel = ctrl.selection;
      if (sel.isCollapsed) {
        final atStart = sel.baseOffset == 0;
        final atEnd = sel.baseOffset >= ctrl.text.length;
        if ((key == LogicalKeyboardKey.arrowUp && atStart) ||
            (key == LogicalKeyboardKey.arrowDown && atEnd)) {
          final lines = doc.outline();
          final index = lines.indexWhere((l) => l.block.id == id);
          final nextIndex = key == LogicalKeyboardKey.arrowUp
              ? index - 1
              : index + 1;
          if (index >= 0 && nextIndex >= 0 && nextIndex < lines.length) {
            final target = lines[nextIndex].block;
            final targetCtrl = _controllerFor(target);
            _focusAfterFrame(
              target.id,
              key == LogicalKeyboardKey.arrowUp ? targetCtrl.text.length : 0,
            );
            return KeyEventResult.handled;
          }
        }
      }
    }

    return KeyEventResult.ignored;
  }

  _MarkdownRule? _markdownRule(String value) {
    switch (value) {
      case '# ':
        return const _MarkdownRule(BType.h1);
      case '## ':
        return const _MarkdownRule(BType.h2);
      case '### ':
        return const _MarkdownRule(BType.h3);
      case '#### ':
        return const _MarkdownRule(BType.h4);
      case '- ':
      case '* ':
      case '+ ':
        return const _MarkdownRule(BType.bulleted);
      case '1. ':
      case '1) ':
        return const _MarkdownRule(BType.numbered);
      case '[] ':
      case '[ ] ':
        return const _MarkdownRule(BType.todo);
      case '[x] ':
      case '[X] ':
        return const _MarkdownRule(BType.todo, checked: true);
      case '> ':
        return const _MarkdownRule(BType.quote);
      case '```':
        return const _MarkdownRule(BType.code, language: 'plaintext');
      case r'$$ ':
      case r'$$':
        return const _MarkdownRule(BType.equation);
      default:
        return null;
    }
  }

  void _makeColumns(NoteBlock host, int count) {
    final doc = _doc;
    if (doc == null) return;
    doc.setType(host.id, BType.columnList);
    host.text = '';
    String? firstText;
    for (var i = 0; i < count; i++) {
      final column = doc.append(parentId: host.id, type: BType.column);
      final text = doc.append(parentId: column.id, type: BType.text);
      firstText ??= text.id;
    }
    if (firstText != null) _focusAfterFrame(firstText, 0);
  }

  Future<void> _pickFile(NoteBlock block) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      dialogTitle: 'Attach a file',
    );
    final file = result?.files.single;
    if (!mounted) return;
    if (file == null || file.path == null) {
      _doc?.setType(block.id, BType.text);
      setState(() {});
      _scheduleMicroSave();
      return;
    }
    block.props['path'] = file.path!;
    block.props['name'] = file.name;
    block.props['size'] = file.size;
    block.props['mime'] = p.extension(file.name).replaceFirst('.', '');
    block.text = file.name;
    block.updatedAt = DateTime.now();
    setState(() {});
    _scheduleMicroSave();
  }

  Future<void> _promptUrl(NoteBlock block, String type) async {
    final c = context.c;
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          type == BType.embed ? 'Embed a URL' : 'Bookmark a URL',
          style: MType.h3.copyWith(color: c.ink),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (!mounted || value == null) {
      _doc?.setType(block.id, BType.text);
      setState(() {});
      return;
    }
    final url = value.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _doc?.setType(block.id, BType.text);
      block.text = url;
      setState(() {});
      _scheduleMicroSave();
      return;
    }
    block.props['url'] = url;
    block.text = url;
    block.updatedAt = DateTime.now();
    setState(() {});
    _scheduleMicroSave();
  }

  static const _codeLanguages = <String>[
    'plaintext',
    'dart',
    'python',
    'javascript',
    'typescript',
    'java',
    'kotlin',
    'swift',
    'c',
    'c++',
    'c#',
    'go',
    'rust',
    'ruby',
    'php',
    'scala',
    'haskell',
    'elixir',
    'erlang',
    'clojure',
    'shell',
    'bash',
    'powershell',
    'sql',
    'json',
    'yaml',
    'toml',
    'xml',
    'html',
    'css',
    'scss',
    'less',
    'markdown',
    'latex',
    'r',
    'matlab',
    'julia',
    'lua',
    'perl',
    'objective-c',
    'assembly',
    'docker',
    'graphql',
    'protobuf',
    'solidity',
    'verilog',
    'vhdl',
    'mermaid',
  ];

  Future<void> _pickLanguage(NoteBlock block) async {
    final c = context.c;
    final controller = TextEditingController();
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) {
          final query = controller.text.trim().toLowerCase();
          final list = _codeLanguages
              .where((l) => query.isEmpty || l.contains(query))
              .toList();
          return AlertDialog(
            backgroundColor: c.surface,
            title: Text(
              'Code language',
              style: MType.h3.copyWith(color: c.ink),
            ),
            content: SizedBox(
              width: 320,
              height: 380,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search languages',
                      isDense: true,
                    ),
                    onChanged: (_) => setDialog(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        title: Text(
                          list[i],
                          style: MType.small.copyWith(
                            fontSize: 12,
                            color: c.ink,
                          ),
                        ),
                        trailing: list[i] == block.language
                            ? Icon(Icons.check_rounded, size: 15, color: c.ink)
                            : null,
                        onTap: () => Navigator.pop(context, list[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || chosen == null) return;
    _pushUndo();
    block.props['language'] = chosen;
    block.updatedAt = DateTime.now();
    setState(() {});
    _scheduleMicroSave();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _jumpToBlock(String id) {
    final ctx = _rowKeys[id]?.currentContext;
    if (ctx == null) {
      _focusAfterFrame(id, 0);
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: 0.15,
    );
    _focusAfterFrame(id, 0);
  }

  /// Ctrl+K: wraps the selection in a markdown link. A URL already on the
  /// clipboard is used when it looks like one; otherwise the caret lands in
  /// the URL slot.
  Future<void> _insertLink(String id) async {
    final ctrl = _controllers[id];
    final doc = _doc;
    if (ctrl == null || doc == null) return;
    final block = doc.byId(id);
    if (block == null) return;
    _pushUndo();

    final text = ctrl.text;
    final sel = ctrl.selection;
    final hasRange = sel.isValid && !sel.isCollapsed;
    final label = hasRange ? text.substring(sel.start, sel.end) : '';
    final start = hasRange
        ? sel.start
        : (sel.isValid ? sel.baseOffset : text.length);
    final end = hasRange ? sel.end : start;

    var url = '';
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final candidate = clip?.text?.trim() ?? '';
      if (candidate.startsWith('http://') || candidate.startsWith('https://')) {
        url = candidate;
      }
    } catch (_) {}

    final snippet = '[$label]($url)';
    final next = text.replaceRange(start, end, snippet);
    final caret = url.isEmpty
        ? start + label.length + 3
        : start + snippet.length;
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret.clamp(0, next.length)),
    );
    block.text = next;
    block.updatedAt = DateTime.now();
    setState(() {});
    _scheduleMicroSave();
    _focusAfterFrame(id, caret.clamp(0, next.length));
  }

  void _insert(TextEditingController ctrl, String text) {
    final sel = ctrl.selection;
    final value = ctrl.text;
    final start = sel.start < 0 ? value.length : sel.start;
    final end = sel.end < 0 ? value.length : sel.end;
    final next = value.replaceRange(start, end, text);
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    final id = _idForController(ctrl);
    final block = id == null ? null : _doc?.byId(id);
    if (block != null) {
      block.text = next;
      block.updatedAt = DateTime.now();
      _scheduleMicroSave();
    }
  }

  String? _idForController(TextEditingController ctrl) {
    for (final e in _controllers.entries) {
      if (identical(e.value, ctrl)) return e.key;
    }
    return null;
  }

  void _wrap(String id, String open, [String? close]) {
    final ctrl = _controllers[id];
    final doc = _doc;
    if (ctrl == null || doc == null) return;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    final text = ctrl.text;
    final a = sel.start.clamp(0, text.length);
    final b = sel.end.clamp(0, text.length);
    final selected = text.substring(a, b);
    final end = close ?? open;
    final replacement = '$open$selected$end';
    final next = text.replaceRange(a, b, replacement);
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: a + open.length,
        extentOffset: a + open.length + selected.length,
      ),
    );
    final block = doc.byId(id);
    if (block != null) {
      block.text = next;
      block.updatedAt = DateTime.now();
    }
    setState(() {});
    _scheduleMicroSave();
  }

  void _onTextChanged(NoteBlock b, String value) {
    if (b.text != value) _pushUndo(typingBlockId: b.id);
    b.text = value;

    // Markdown block prefixes, applied only when the whole block is the prefix
    // so typing "#" mid-word never converts anything.
    final rule = _markdownRule(value);
    if (rule != null) {
      final ctrl = _controllers[b.id];
      _doc?.setType(b.id, rule.type);
      b.text = '';
      if (rule.checked) b.props['checked'] = true;
      if (rule.language != null) b.props['language'] = rule.language;
      if (ctrl != null) {
        ctrl.value = const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );
      }
      setState(() {});
      _scheduleMicroSave();
      return;
    }
    b.updatedAt = DateTime.now();
    if (value.startsWith('/')) {
      if (_menuBlockId == b.id) _menuIndex = 0;
      _openMenuFor(b.id, value);
    } else if (_menuBlockId == b.id) {
      setState(() => _menuBlockId = null);
    }
    _scheduleMicroSave();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final doc = _doc!;
    final allLines = doc.outline();
    final hidden = <String>{};
    for (final host in doc.raw.where((b) => b.type == BType.columnList)) {
      for (final column in doc.childrenOf(host.id)) {
        hidden.add(column.id);
        for (final candidate in doc.raw) {
          if (doc.isDescendant(candidate.id, column.id))
            hidden.add(candidate.id);
        }
      }
    }
    final lines = allLines.where((l) => !hidden.contains(l.block.id)).toList();
    final items = _filteredMenu;
    final firstId = lines.isEmpty ? '' : lines.first.block.id;
    final brightness = Theme.of(context).brightness;

    final list = ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 24, 60),
      itemCount: lines.length + 1,
      itemBuilder: (context, index) {
        if (index == lines.length) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (lines.isEmpty) {
                final b = doc.append();
                setState(() {});
                _focusAfterFrame(b.id, 0);
                return;
              }
              final last = lines.last.block;
              if (last.type == BType.text && last.text.isEmpty) {
                _focusAfterFrame(last.id, 0);
              } else {
                _pushUndo();
                final created = doc.append();
                setState(() {});
                _scheduleMicroSave();
                _focusAfterFrame(created.id, 0);
              }
            },
            child: const SizedBox(height: 160, width: double.infinity),
          );
        }
        final line = lines[index];
        final b = line.block;
        final background = _backgroundOf(b, brightness);
        Widget content = _blockRow(context, b, line, isFirst: b.id == firstId);
        if (background != null) {
          content = Container(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: content,
          );
        }
        final rowKey = _rowKeys.putIfAbsent(b.id, () => GlobalKey());
        final rowHovered = _hoveredBlockId == b.id;
        final row = KeyedSubtree(
          key: rowKey,
          child: MouseRegion(
            onEnter: (_) {
              if (_hoveredBlockId != b.id)
                setState(() => _hoveredBlockId = b.id);
            },
            onExit: (_) {
              if (_hoveredBlockId == b.id)
                setState(() => _hoveredBlockId = null);
            },
            child: Padding(
              key: ValueKey(b.id),
              padding: EdgeInsets.only(
                left: 22.0 * line.depth,
                top: 1.5,
                bottom: 1.5,
              ),
              child: Opacity(
                opacity: _dragBlockId == b.id ? 0.35 : 1,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 110),
                      opacity: rowHovered ? 1.0 : 0.0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _AddBlockGutterButton(
                            onTap: () {
                              _pushUndo();
                              final target =
                                  (b.type == BType.text && b.text.isEmpty)
                                  ? b
                                  : doc.insertAfter(b.id);
                              setState(() {
                                _menuBlockId = target.id;
                                _menuQuery = '';
                                _menuIndex = 0;
                              });
                              _focusAfterFrame(target.id, 0);
                            },
                          ),
                          Draggable<String>(
                            data: b.id,
                            dragAnchorStrategy: pointerDragAnchorStrategy,
                            feedback: _dragChip(context, b),
                            onDragStarted: () =>
                                setState(() => _dragBlockId = b.id),
                            onDragEnd: (_) => setState(() {
                              _dragBlockId = null;
                              _dropTargetId = null;
                            }),
                            child: _BlockHandle(
                              onOpen: (global) => _showBlockMenu(b, global),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: content),
                  ],
                ),
              ),
            ),
          ),
        );

        final target = DragTarget<String>(
          onWillAcceptWithDetails: (details) {
            final dragged = details.data;
            return dragged != b.id &&
                !doc.isDescendant(b.id, dragged) &&
                doc.byId(dragged)?.parentId != b.id;
          },
          onMove: (details) {
            final box = rowKey.currentContext?.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(details.offset);
            final before = local.dy < box.size.height / 2;
            if (_dropTargetId != b.id || _dropBefore != before) {
              setState(() {
                _dropTargetId = b.id;
                _dropBefore = before;
              });
            }
          },
          onAcceptWithDetails: (details) {
            final dragged = details.data;
            final before = _dropBefore;
            _pushUndo();
            if (doc.moveBlock(dragged, b.id, before: before)) {
              setState(() {});
              _scheduleMicroSave();
            }
            setState(() {
              _dragBlockId = null;
              _dropTargetId = null;
            });
          },
          builder: (context, candidate, rejected) {
            final active = candidate.isNotEmpty && _dropTargetId == b.id;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (active && _dropBefore) _dropLine(context),
                row,
                if (active && !_dropBefore) _dropLine(context),
              ],
            );
          },
        );

        if (_menuBlockId != b.id) return target;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            target,
            Padding(
              padding: EdgeInsets.only(
                left: 18.0 * line.depth + 44,
                top: 4,
                bottom: 8,
              ),
              child: _insertMenu(context, items),
            ),
          ],
        );
      },
    );

    if (!_findOpen) return list;
    return Column(
      children: [
        _findBar(context),
        Expanded(child: list),
      ],
    );
  }

  Widget _blockRow(
    BuildContext context,
    NoteBlock b,
    BlockLine line, {
    required bool isFirst,
  }) {
    final c = context.c;
    final textColor = _textColorOf(b, Theme.of(context).brightness);
    final bodyStyle = MType.body.copyWith(
      color: textColor,
      height: 1.6,
      fontSize: 13.5,
    );

    if (b.type == BType.divider) {
      return Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: c.lineStrong,
              margin: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
        ],
      );
    }

    Widget field({TextStyle? style, String? hint, bool mono = false}) {
      final ctrl = _controllerFor(b);
      final node = _nodeFor(b);
      final effectiveStyle =
          style ??
          (mono
              ? MType.mono.copyWith(
                  fontSize: 13,
                  height: 1.55,
                  color: textColor,
                )
              : bodyStyle);
      return TextField(
        controller: ctrl,
        focusNode: node,
        maxLines: null,
        style: effectiveStyle,
        cursorColor: c.ink,
        cursorWidth: 1.5,
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          hoverColor: Colors.transparent,
          fillColor: Colors.transparent,
          hintText: hint,
          hintStyle: effectiveStyle.copyWith(
            color: c.inkFaint.withValues(alpha: 0.65),
            fontWeight: FontWeight.w400,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 2),
        ),
        onChanged: (v) => _onTextChanged(b, v),
      );
    }

    switch (b.type) {
      case BType.h1:
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _headingChevron(b, c),
              Expanded(
                child: field(
                  hint: 'Heading 1',
                  style: MType.h1.copyWith(
                    fontSize: 26,
                    color: textColor,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        );
      case BType.h2:
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _headingChevron(b, c),
              Expanded(
                child: field(
                  hint: 'Heading 2',
                  style: MType.h2.copyWith(
                    fontSize: 20,
                    color: textColor,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );
      case BType.h3:
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _headingChevron(b, c),
              Expanded(
                child: field(
                  hint: 'Heading 3',
                  style: MType.h3.copyWith(
                    fontSize: 16.5,
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      case BType.h4:
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: field(
                  hint: 'Heading 4',
                  style: MType.body.copyWith(
                    fontSize: 14.5,
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      case BType.bulleted:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 9, left: 4, right: 10),
              child: Container(
                width: 5.5,
                height: 5.5,
                decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
              ),
            ),
            Expanded(child: field(hint: 'List')),
          ],
        );
      case BType.numbered:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${line.number}.',
                  style: bodyStyle.copyWith(
                    color: c.inkMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            Expanded(child: field(hint: 'List')),
          ],
        );
      case BType.todo:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 8),
              child: InkWell(
                onTap: () {
                  _doc?.toggleChecked(b.id);
                  setState(() {});
                  _scheduleMicroSave();
                },
                borderRadius: BorderRadius.circular(4),
                child: Icon(
                  b.checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 18,
                  color: b.checked ? c.accent : c.inkMuted,
                ),
              ),
            ),
            Expanded(
              child: field(
                hint: 'To-do',
                style: b.checked
                    ? bodyStyle.copyWith(
                        color: c.inkFaint,
                        decoration: TextDecoration.lineThrough,
                      )
                    : bodyStyle,
              ),
            ),
          ],
        );
      case BType.toggle:
        final hasKids = _doc?.childrenOf(b.id).isNotEmpty ?? false;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 6),
              child: InkWell(
                onTap: () {
                  _doc?.toggleOpen(b.id);
                  setState(() {});
                  _scheduleMicroSave();
                },
                borderRadius: BorderRadius.circular(4),
                child: Icon(
                  b.open
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded,
                  size: 18,
                  color: hasKids ? c.ink : c.inkMuted,
                ),
              ),
            ),
            Expanded(
              child: field(
                hint: 'Toggle',
                style: bodyStyle.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        );
      case BType.quote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: c.ink, width: 3)),
          ),
          child: field(
            hint: 'Empty quote',
            style: bodyStyle.copyWith(
              color: textColor == c.ink ? c.inkMuted : textColor,
            ),
          ),
        );
      case BType.callout:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(MRadius.sm),
            border: Border.all(color: c.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 10),
                child: Icon(
                  Icons.tips_and_updates_outlined,
                  size: 16,
                  color: c.inkMuted,
                ),
              ),
              Expanded(child: field(hint: 'Type something…')),
            ],
          ),
        );
      case BType.columnList:
        final doc = _doc!;
        final columns = doc
            .childrenOf(b.id)
            .where((x) => x.type == BType.column)
            .toList();
        if (columns.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              'Empty columns',
              style: MType.small.copyWith(fontSize: 11, color: c.inkFaint),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < columns.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: c.line.withValues(alpha: 0.7)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final child in doc.childrenOf(columns[i].id))
                          KeyedSubtree(
                            key: _rowKeys.putIfAbsent(
                              child.id,
                              () => GlobalKey(),
                            ),
                            child: _blockRow(
                              context,
                              child,
                              BlockLine(child, 0, 0),
                              isFirst: false,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      case BType.toc:
        final headings = _doc!.raw
            .where(
              (x) => const [
                BType.h1,
                BType.h2,
                BType.h3,
                BType.h4,
              ].contains(x.type),
            )
            .toList();
        return Container(
          margin: const EdgeInsets.only(top: 4, bottom: 4, right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.line),
          ),
          child: headings.isEmpty
              ? Text(
                  'Headings you add to the page appear here',
                  style: MType.small.copyWith(fontSize: 11, color: c.inkFaint),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final h in headings)
                      InkWell(
                        onTap: () => _jumpToBlock(h.id),
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: h.type == BType.h2
                                ? 12
                                : h.type == BType.h3
                                ? 24
                                : h.type == BType.h4
                                ? 36
                                : 0,
                            top: 2,
                            bottom: 2,
                          ),
                          child: Text(
                            h.text.isEmpty ? 'Untitled heading' : h.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MType.small.copyWith(
                              fontSize: h.type == BType.h1 ? 12 : 11,
                              color: c.inkMuted,
                              fontWeight: h.type == BType.h1
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        );
      case BType.file:
        final path = b.props['path'] as String?;
        final name = (b.props['name'] as String?) ?? b.text;
        final size = b.props['size'];
        final exists = path != null && File(path).existsSync();
        return Container(
          margin: const EdgeInsets.only(top: 3, bottom: 3, right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.line),
            color: c.surfaceAlt,
          ),
          child: ListTile(
            dense: true,
            leading: Icon(
              exists
                  ? Icons.insert_drive_file_outlined
                  : Icons.file_present_outlined,
              size: 18,
              color: exists ? c.ink : c.inkFaint,
            ),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MType.small.copyWith(fontSize: 11.5, color: c.ink),
            ),
            subtitle: Text(
              exists
                  ? '${size is int ? _formatBytes(size) : 'file'} · click to open'
                  : 'Missing file',
              style: MType.small.copyWith(fontSize: 9.5, color: c.inkFaint),
            ),
            trailing: IconButton(
              iconSize: 14,
              tooltip: 'Remove',
              onPressed: () {
                _pushUndo();
                _doc?.delete(b.id);
                _forget(b.id);
                setState(() {});
                _scheduleMicroSave();
              },
              icon: const Icon(Icons.close_rounded),
            ),
            onTap: exists ? () => Process.run('explorer.exe', [path]) : null,
          ),
        );
      case BType.bookmark:
      case BType.embed:
        final url = (b.props['url'] as String?) ?? b.text;
        final isEmbed = b.type == BType.embed;
        return Container(
          margin: const EdgeInsets.only(top: 3, bottom: 3, right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.line),
            color: c.surfaceAlt,
          ),
          child: ListTile(
            dense: true,
            leading: Icon(
              isEmbed
                  ? Icons.open_in_new_rounded
                  : Icons.bookmark_border_rounded,
              size: 18,
              color: c.inkMuted,
            ),
            title: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MType.small.copyWith(fontSize: 11.5, color: c.ink),
            ),
            subtitle: Text(
              isEmbed ? 'Embedded link' : 'Bookmark',
              style: MType.small.copyWith(fontSize: 9.5, color: c.inkFaint),
            ),
            trailing: IconButton(
              iconSize: 14,
              tooltip: 'Open',
              onPressed: () {
                final uri = Uri.tryParse(url);
                if (uri != null)
                  launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.north_east_rounded),
            ),
          ),
        );
      case BType.database:
        return DatabaseBlock(
          block: b,
          onEdit: _scheduleMicroSave,
          onBeforeEdit: () => _pushUndo(typingBlockId: b.id),
        );
      case BType.equation:
        return Container(
          margin: const EdgeInsets.only(top: 3, bottom: 3, right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(MRadius.md),
            border: Border.all(color: c.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.functions_rounded, size: 16, color: c.inkMuted),
              const SizedBox(width: 10),
              Expanded(
                child: field(
                  mono: true,
                  hint: r'E = mc^2  or  \int_0^\infty f(x)\,dx',
                ),
              ),
            ],
          ),
        );
      case BType.chart:
        return ChartBlock(
          block: b,
          doc: _doc!,
          onEdit: _scheduleMicroSave,
          onBeforeEdit: _pushUndo,
        );
      case BType.image:
        final path = b.props['path'] as String?;
        final exists = path != null && File(path).existsSync();
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4, right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (exists)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(path),
                    height: 240,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _missingImage(c, 'Image could not be read'),
                  ),
                )
              else
                _missingImage(
                  c,
                  path == null ? 'No image selected' : 'Missing: $path',
                ),
              const SizedBox(height: 4),
              Text(
                b.text,
                style: MType.small.copyWith(fontSize: 10.5, color: c.inkFaint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      case BType.code:
        return Container(
          margin: const EdgeInsets.only(top: 3, bottom: 3),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: BorderRadius.circular(MRadius.md),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => _pickLanguage(b),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      b.language.toUpperCase(),
                      style: MType.small.copyWith(
                        fontSize: 9,
                        letterSpacing: 0.8,
                        color: c.inkFaint,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 13,
                      color: c.inkFaint,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              field(mono: true),
            ],
          ),
        );
      default:
        final focused = _focusNodes[b.id]?.hasFocus ?? false;
        return field(
          hint: (isFirst || focused)
              ? "Write, or press '/' for commands…"
              : null,
        );
    }
  }

  // ------------------------------------------------------------------ block menu

  Widget _dragChip(BuildContext context, NoteBlock b) {
    final c = context.c;
    final label = b.text.isEmpty ? _typeLabel(b.type) : b.text;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.line),
          boxShadow: [
            BoxShadow(
              color: c.shadow,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drag_indicator_rounded, size: 13, color: c.inkMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MType.body.copyWith(fontSize: 12, color: c.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    for (final item in _menuItems) {
      if (item.type == type) return item.label;
    }
    return 'Block';
  }

  Widget _dropLine(BuildContext context) {
    final c = context.c;
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Future<void> _showBlockMenu(NoteBlock block, Offset global) async {
    final c = context.c;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final rect = overlay != null
        ? RelativeRect.fromRect(
            Rect.fromPoints(global, global),
            Offset.zero & overlay.size,
          )
        : const RelativeRect.fromLTRB(40, 120, 40, 40);

    final action = await showMenu<String>(
      context: context,
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MRadius.md),
        side: BorderSide(color: c.line),
      ),
      position: rect,
      items: [
        _menuTile('turn', Icons.sync_alt_rounded, 'Turn into', c),
        _menuTile('color', Icons.palette_outlined, 'Text colour', c),
        _menuTile(
          'background',
          Icons.format_color_fill_rounded,
          'Background',
          c,
        ),
        const PopupMenuDivider(),
        _menuTile(
          'duplicate',
          Icons.copy_all_outlined,
          'Duplicate',
          c,
          'Ctrl+D',
        ),
        _menuTile(
          'up',
          Icons.arrow_upward_rounded,
          'Move up',
          c,
          'Ctrl+Shift+Up',
        ),
        _menuTile(
          'down',
          Icons.arrow_downward_rounded,
          'Move down',
          c,
          'Ctrl+Shift+Down',
        ),
        const PopupMenuDivider(),
        _menuTile(
          'delete',
          Icons.delete_outline_rounded,
          'Delete',
          c,
          'Backspace',
        ),
      ],
    );
    if (!mounted || action == null) return;
    final doc = _doc;
    if (doc == null) return;

    switch (action) {
      case 'turn':
        await _pickType(block, rect);
      case 'color':
        await _pickColor(block, rect, background: false);
      case 'background':
        await _pickColor(block, rect, background: true);
      case 'duplicate':
        _pushUndo();
        final copy = doc.duplicate(block.id);
        setState(() {});
        _scheduleMicroSave();
        if (copy != null) _focusAfterFrame(copy, 0);
      case 'up':
      case 'down':
        _pushUndo();
        doc.moveWithinSiblings(block.id, action == 'up' ? -1 : 1);
        setState(() {});
        _scheduleMicroSave();
      case 'delete':
        _pushUndo();
        final lines = doc.outline();
        final index = lines.indexWhere((l) => l.block.id == block.id);
        final prev = index > 0 ? lines[index - 1].block.id : null;
        doc.delete(block.id);
        _forget(block.id);
        if (doc.raw.isEmpty) doc.append();
        setState(() {});
        _scheduleMicroSave();
        _focusAfterFrame(prev ?? doc.outline().first.block.id, 0);
    }
  }

  PopupMenuItem<String> _menuTile(
    String value,
    IconData icon,
    String label,
    MColors c, [
    String? shortcut,
  ]) => PopupMenuItem<String>(
    value: value,
    height: 38,
    child: Row(
      children: [
        Icon(icon, size: 15, color: c.inkMuted),
        const SizedBox(width: 10),
        Text(label, style: MType.body.copyWith(fontSize: 12.5, color: c.ink)),
        if (shortcut != null) ...[
          const Spacer(),
          Text(
            shortcut,
            style: MType.small.copyWith(fontSize: 10, color: c.inkFaint),
          ),
        ],
      ],
    ),
  );

  Future<void> _pickType(NoteBlock block, RelativeRect rect) async {
    final c = context.c;
    final type = await showMenu<String>(
      context: context,
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MRadius.md),
        side: BorderSide(color: c.line),
      ),
      position: rect,
      items: [
        for (final item in _menuItems)
          PopupMenuItem<String>(
            value: item.type,
            height: 34,
            child: Row(
              children: [
                Icon(item.icon, size: 14, color: c.inkMuted),
                const SizedBox(width: 9),
                Text(
                  item.label,
                  style: MType.body.copyWith(fontSize: 12.5, color: c.ink),
                ),
              ],
            ),
          ),
      ],
    );
    if (!mounted || type == null) return;
    _pushUndo();
    _doc?.setType(block.id, type);
    setState(() {});
    _scheduleMicroSave();
    _focusAfterFrame(block.id, _controllers[block.id]?.text.length ?? 0);
  }

  Future<void> _pickColor(
    NoteBlock block,
    RelativeRect rect, {
    required bool background,
  }) async {
    final c = context.c;
    final palette = _paletteFor(Theme.of(context).brightness);
    final token = await showMenu<String>(
      context: context,
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MRadius.md),
        side: BorderSide(color: c.line),
      ),
      position: rect,
      items: [
        for (final t in _colorTokens)
          PopupMenuItem<String>(
            value: t,
            height: 34,
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: background
                        ? (palette.background[t] ?? Colors.transparent)
                        : (palette.text[t] ?? c.ink),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: c.line),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _colorName(t),
                  style: MType.body.copyWith(fontSize: 12.5, color: c.ink),
                ),
                if (_currentColor(block, background) == t) ...[
                  const Spacer(),
                  Icon(Icons.check_rounded, size: 14, color: c.ink),
                ],
              ],
            ),
          ),
      ],
    );
    if (!mounted || token == null) return;
    _pushUndo();
    _doc?.setColor(block.id, token, background: background);
    setState(() {});
    _scheduleMicroSave();
  }

  String? _currentColor(NoteBlock b, bool background) =>
      b.props[background ? 'background' : 'color'] as String?;

  // ------------------------------------------------------------------ find

  void showFindBar() {
    setState(() => _findOpen = true);
    _refreshMatches();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocus.requestFocus();
    });
  }

  void closeFindBar() {
    setState(() {
      _findOpen = false;
      _matches = const [];
    });
    final id = _focusedBlockId();
    if (id != null)
      _focusAfterFrame(id, _controllers[id]?.selection.baseOffset ?? 0);
  }

  void _refreshMatches() {
    final doc = _doc;
    final query = _findController.text;
    if (doc == null || query.isEmpty) {
      _matches = const [];
      _matchIndex = 0;
      return;
    }
    final needle = query.toLowerCase();
    final found = <_Match>[];
    for (final line in doc.outline()) {
      final text = line.block.text.toLowerCase();
      var from = 0;
      while (found.length < 500) {
        final at = text.indexOf(needle, from);
        if (at < 0) break;
        found.add(_Match(line.block.id, at, at + query.length));
        from = at + needle.length;
      }
      if (found.length >= 500) break;
    }
    _matches = found;
    _matchIndex = found.isEmpty ? 0 : _matchIndex.clamp(0, found.length - 1);
  }

  void _goToMatch(int index) {
    if (_matches.isEmpty) return;
    final next = index % _matches.length;
    setState(() => _matchIndex = next);
    final match = _matches[next < 0 ? 0 : next];
    final ctrl = _controllers[match.blockId];
    if (ctrl == null) return;
    ctrl.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
    _focusRange(match.blockId, match.start, match.end);
  }

  void _focusRange(String id, int start, int end) {
    final block = _doc?.byId(id);
    if (block != null) {
      _controllerFor(block);
      _nodeFor(block);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _focusNodes[id];
      final ctrl = _controllers[id];
      if (node == null || ctrl == null) return;
      node.requestFocus();
      ctrl.selection = TextSelection(
        baseOffset: start.clamp(0, ctrl.text.length),
        extentOffset: end.clamp(0, ctrl.text.length),
      );
    });
  }

  void _replaceCurrent() {
    final doc = _doc;
    if (doc == null || _matches.isEmpty) return;
    final match = _matches[_matchIndex.clamp(0, _matches.length - 1)];
    _pushUndo();
    final caret = doc.replaceRange(
      match.blockId,
      match.start,
      match.end,
      _replaceController.text,
    );
    final block = doc.byId(match.blockId);
    final ctrl = _controllers[match.blockId];
    if (block != null && ctrl != null) {
      ctrl.value = TextEditingValue(
        text: block.text,
        selection: TextSelection.collapsed(offset: caret),
      );
    }
    _refreshMatches();
    setState(() {});
    _scheduleMicroSave();
    if (_matches.isNotEmpty)
      _goToMatch(_matchIndex.clamp(0, _matches.length - 1));
  }

  void _replaceAll() {
    final doc = _doc;
    final query = _findController.text;
    if (doc == null || query.isEmpty) return;
    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    var changed = false;
    _pushUndo();
    for (final line in doc.outline()) {
      final block = line.block;
      if (!pattern.hasMatch(block.text)) continue;
      final next = block.text.replaceAll(pattern, _replaceController.text);
      block.text = next;
      block.updatedAt = DateTime.now();
      final ctrl = _controllers[block.id];
      if (ctrl != null) {
        ctrl.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
      changed = true;
    }
    if (!changed) return;
    _refreshMatches();
    setState(() {});
    _scheduleMicroSave();
  }

  Widget _findBar(BuildContext context) {
    final c = context.c;
    final small = MType.body.copyWith(fontSize: 12, color: c.ink);
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(MRadius.md),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 15, color: c.inkMuted),
          const SizedBox(width: 8),
          SizedBox(
            width: 170,
            child: TextField(
              controller: _findController,
              focusNode: _findFocus,
              style: small,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Find in page',
                hintStyle: small.copyWith(color: c.inkFaint),
              ),
              onChanged: (_) {
                _refreshMatches();
                setState(() {});
              },
              onSubmitted: (_) => _goToMatch(_matchIndex + 1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _matches.isEmpty
                ? '0 / 0'
                : '${_matchIndex + 1} / ${_matches.length}',
            style: MType.small.copyWith(fontSize: 10.5, color: c.inkMuted),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 15,
            tooltip: 'Previous (Shift+Enter)',
            onPressed: () => _goToMatch(_matchIndex - 1),
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 15,
            tooltip: 'Next (Enter)',
            onPressed: () => _goToMatch(_matchIndex + 1),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 150,
            child: TextField(
              controller: _replaceController,
              style: small,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Replace with',
                hintStyle: small.copyWith(color: c.inkFaint),
              ),
              onSubmitted: (_) => _replaceCurrent(),
            ),
          ),
          TextButton(
            onPressed: _replaceCurrent,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: c.ink,
              textStyle: MType.small.copyWith(fontSize: 11),
            ),
            child: const Text('Replace'),
          ),
          TextButton(
            onPressed: _replaceAll,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: c.ink,
              textStyle: MType.small.copyWith(fontSize: 11),
            ),
            child: const Text('All'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 15,
            tooltip: 'Close',
            onPressed: closeFindBar,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Color _textColorOf(NoteBlock b, Brightness brightness) {
    final token = b.props['color'] as String?;
    if (token == null || token == 'default') {
      return Theme.of(context).extension<MColors>()?.ink ?? Colors.black;
    }
    return _paletteFor(brightness).text[token] ?? Colors.black;
  }

  Color? _backgroundOf(NoteBlock b, Brightness brightness) {
    final token = b.props['background'] as String?;
    if (token == null || token == 'default') return null;
    return _paletteFor(brightness).background[token];
  }

  /// A heading collapses like a toggle when it has children.
  Widget _headingChevron(NoteBlock b, MColors c) {
    final hasKids = (_doc?.childrenOf(b.id).isNotEmpty) ?? false;
    if (!hasKids) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: () {
          _pushUndo();
          _doc?.toggleOpen(b.id);
          setState(() {});
          _scheduleMicroSave();
        },
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 22,
          height: 22,
          child: Icon(
            b.open ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
            size: 17,
            color: c.inkMuted,
          ),
        ),
      ),
    );
  }

  Widget _missingImage(MColors c, String label) => Container(
    height: 96,
    width: double.infinity,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: c.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: c.line),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.image_not_supported_outlined, size: 20, color: c.inkFaint),
        const SizedBox(height: 6),
        Text(
          label,
          style: MType.small.copyWith(fontSize: 10.5, color: c.inkFaint),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );

  Widget _insertMenu(BuildContext context, List<_MenuItem> items) {
    final c = context.c;
    if (items.isEmpty) {
      return Container(
        width: 280,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(MRadius.md),
          border: Border.all(color: c.line),
          boxShadow: [
            BoxShadow(
              color: c.shadow,
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          'No matching block',
          style: MType.small.copyWith(color: c.inkMuted),
        ),
      );
    }
    return Container(
      width: 312,
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(MRadius.md),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          final active = i == _menuIndex;
          final showCategory = i == 0 || items[i - 1].category != item.category;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showCategory)
                Padding(
                  padding: EdgeInsets.fromLTRB(12, i == 0 ? 4 : 10, 12, 4),
                  child: Text(
                    item.category.toUpperCase(),
                    style: MType.small.copyWith(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: c.inkFaint,
                    ),
                  ),
                ),
              InkWell(
                onTap: () => _applyMenu(item),
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: active ? c.accentSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c.surfaceAlt,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: c.line),
                        ),
                        child: Icon(item.icon, size: 16, color: c.ink),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.label,
                              style: MType.bodyStrong.copyWith(
                                fontSize: 12.5,
                                color: c.ink,
                              ),
                            ),
                            if (item.subtitle.isNotEmpty)
                              Text(
                                item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MType.small.copyWith(
                                  fontSize: 10.5,
                                  color: c.inkMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AddBlockGutterButton extends StatefulWidget {
  const _AddBlockGutterButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_AddBlockGutterButton> createState() => _AddBlockGutterButtonState();
}

class _AddBlockGutterButtonState extends State<_AddBlockGutterButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: 'Click to add below',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 20,
            height: 24,
            decoration: BoxDecoration(
              color: _hover ? c.surfaceAlt : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.add_rounded,
              size: 15,
              color: _hover ? c.ink : c.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkdownRule {
  const _MarkdownRule(this.type, {this.checked = false, this.language});
  final String type;
  final bool checked;
  final String? language;
}

class _Match {
  const _Match(this.blockId, this.start, this.end);
  final String blockId;
  final int start;
  final int end;
}

const _colorTokens = <String>[
  'default',
  'gray',
  'brown',
  'orange',
  'yellow',
  'green',
  'blue',
  'purple',
  'pink',
  'red',
];

String _colorName(String token) => token == 'default'
    ? 'Default'
    : token[0].toUpperCase() + token.substring(1);

class _Palette {
  const _Palette(this.text, this.background);
  final Map<String, Color> text;
  final Map<String, Color> background;
}

_Palette _paletteFor(Brightness brightness) => brightness == Brightness.dark
    ? const _Palette(
        {
          'default': Color(0xFFFFFFFF),
          'gray': Color(0xFF9B9B9B),
          'brown': Color(0xFFBA856F),
          'orange': Color(0xFFFFA344),
          'yellow': Color(0xFFFFDC49),
          'green': Color(0xFF4DAB9A),
          'blue': Color(0xFF529CCA),
          'purple': Color(0xFF9A6DD7),
          'pink': Color(0xFFE255A1),
          'red': Color(0xFFFF7369),
        },
        {
          'gray': Color(0xFF2F2F2F),
          'brown': Color(0xFF4A3228),
          'orange': Color(0xFF5C3B23),
          'yellow': Color(0xFF564328),
          'green': Color(0xFF243D30),
          'blue': Color(0xFF143A4E),
          'purple': Color(0xFF3C2D49),
          'pink': Color(0xFF4E2C3C),
          'red': Color(0xFF4D2B29),
        },
      )
    : const _Palette(
        {
          'default': Color(0xFF161618),
          'gray': Color(0xFF787774),
          'brown': Color(0xFF9F6B53),
          'orange': Color(0xFFD9730D),
          'yellow': Color(0xFFCB912F),
          'green': Color(0xFF448361),
          'blue': Color(0xFF337EA9),
          'purple': Color(0xFF9065B0),
          'pink': Color(0xFFC14C8A),
          'red': Color(0xFFD44C47),
        },
        {
          'gray': Color(0xFFF1F1EF),
          'brown': Color(0xFFF4EEEE),
          'orange': Color(0xFFFAEBDD),
          'yellow': Color(0xFFFBF3DB),
          'green': Color(0xFFEDF3EC),
          'blue': Color(0xFFE7F3F8),
          'purple': Color(0xFFF6F3F9),
          'pink': Color(0xFFFAF1F5),
          'red': Color(0xFFFDEBEC),
        },
      );

/// Hover handle that opens the block menu.
class _BlockHandle extends StatefulWidget {
  const _BlockHandle({required this.onOpen});
  final ValueChanged<Offset> onOpen;

  @override
  State<_BlockHandle> createState() => _BlockHandleState();
}

class _BlockHandleState extends State<_BlockHandle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: 'Drag to move · Click for options',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => widget.onOpen(details.globalPosition),
          child: Container(
            width: 20,
            height: 24,
            decoration: BoxDecoration(
              color: _hover ? c.surfaceAlt : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 15,
                color: _hover ? c.ink : c.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
