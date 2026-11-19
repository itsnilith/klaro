import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/paths.dart';
import '../../core/state.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import 'block_editor.dart';
import 'block_model.dart';
import '../../services/ai.dart';

const _uuid = Uuid();

const _pageIcons = <(String, IconData)>[
  ('page', Icons.description_outlined),
  ('note', Icons.sticky_note_2_outlined),
  ('book', Icons.menu_book_rounded),
  ('idea', Icons.lightbulb_outline_rounded),
  ('lab', Icons.science_outlined),
  ('code', Icons.code_rounded),
  ('question', Icons.help_outline_rounded),
  ('quote', Icons.format_quote_rounded),
  ('map', Icons.account_tree_outlined),
  ('card', Icons.style_outlined),
];

const _coverColors = <String>[
  '#E7EDF3',
  '#EDE7F6',
  '#E8F5E9',
  '#FFF3E0',
  '#FCE4EC',
  '#E0F2F1',
  '#F3E5D8',
  '#E8EAF6',
];

IconData _iconFor(String name) =>
    _pageIcons.where((e) => e.$1 == name).map((e) => e.$2).firstOrNull ??
    Icons.description_outlined;

Color _coverColor(String hex) {
  final clean = hex.replaceAll('#', '');
  final value = int.tryParse(clean, radix: 16);
  if (value == null) return const Color(0xFFE7EDF3);
  return Color(0xFF000000 | value);
}

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  List<Note> _notes = const [];
  List<Note> _trash = const [];
  String? _selectedId;
  final Set<String> _expanded = {};
  final _title = TextEditingController();
  final _body = TextEditingController();
  final FocusNode _bodyFocus = FocusNode();
  final FocusNode _focus = FocusNode();
  final GlobalKey<BlockEditorState> _blockEditorKey =
      GlobalKey<BlockEditorState>();
  final Map<String, DateTime> _lastSnapshotAt = {};
  int _editorToken = 0;
  Timer? _saveTimer;
  bool _preview = false;
  String _query = '';
  String _tab = 'pages'; // pages | favorites | trash
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    AppState.i.addListener(_load);
    _title.addListener(_scheduleSave);
    _body.addListener(_scheduleSave);
  }

  @override
  void dispose() {
    AppState.i.removeListener(_load);
    _saveTimer?.cancel();
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    _focus.dispose();
    super.dispose();
  }

  Note? get _selected => _notes.where((n) => n.id == _selectedId).firstOrNull;

  List<Note> _childrenOf(String? parentId) =>
      _notes.where((n) => n.parentId == parentId).toList();

  Set<String> _descendantIds(String id) {
    final out = <String>{};
    for (final child in _childrenOf(id)) {
      out.add(child.id);
      out.addAll(_descendantIds(child.id));
    }
    return out;
  }

  /// Titles referenced from a body with Notion-style `[[Page]]` links.
  static List<String> _wikiTargets(String body) {
    final out = <String>[];
    for (final m in RegExp(r'\[\[([^\[\]]+)\]\]').allMatches(body)) {
      final t = m.group(1)?.trim() ?? '';
      if (t.isNotEmpty && !out.any((x) => x.toLowerCase() == t.toLowerCase())) {
        out.add(t);
      }
    }
    return out;
  }

  String _withWikiLinks(String body) => body.replaceAllMapped(
    RegExp(r'\[\[([^\[\]]+)\]\]'),
    (m) =>
        '[${m.group(1)}](klaro://page/${Uri.encodeComponent(m.group(1)!.trim())})',
  );

  List<Note> _linkedPages(Note n) {
    final targets = _wikiTargets(n.body).map((t) => t.toLowerCase()).toSet();
    return _notes
        .where(
          (x) => x.id != n.id && targets.contains(x.title.trim().toLowerCase()),
        )
        .toList();
  }

  List<Note> _backlinks(Note n) {
    final title = n.title.trim().toLowerCase();
    if (title.isEmpty) return const [];
    return _notes.where((x) {
      if (x.id == n.id) return false;
      return _wikiTargets(x.body).any((t) => t.toLowerCase() == title);
    }).toList();
  }

  void _openLinked(String target) {
    final note = _notes
        .where(
          (x) => x.title.trim().toLowerCase() == target.trim().toLowerCase(),
        )
        .firstOrNull;
    if (note != null) {
      _select(note);
    } else {
      _newPage(title: target);
    }
  }

  Future<void> _findInPage() async {
    final editor = _blockEditorKey.currentState;
    if (editor != null) {
      editor.showFindBar();
      return;
    }
    final ctrl = TextEditingController();
    final c = context.c;
    await showMSheet<void>(
      context,
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Find in page', style: MType.h2.copyWith(color: c.ink)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Search this page'),
              onSubmitted: (v) => _jumpToMatch(v),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                MButton(
                  label: 'Find',
                  kind: MButtonKind.primary,
                  onPressed: () {
                    _jumpToMatch(ctrl.text);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  void _jumpToMatch(String needle) {
    final text = _body.text;
    final q = needle.trim();
    if (q.isEmpty || text.isEmpty) return;
    final start = _body.selection.isValid ? _body.selection.end : 0;
    var index = text.toLowerCase().indexOf(q.toLowerCase(), start);
    if (index < 0) index = text.toLowerCase().indexOf(q.toLowerCase());
    if (index < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No match for “$q”.')));
      }
      return;
    }
    setState(() => _preview = false);
    _body.selection = TextSelection(
      baseOffset: index,
      extentOffset: index + q.length,
    );
    _focus.requestFocus();
  }

  int _maxPosition(String? parentId) {
    final siblings = _childrenOf(parentId);
    if (siblings.isEmpty) return 0;
    return siblings.map((n) => n.position).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> _load() async {
    final notes = await Store.i.notes(query: _query);
    final trash = await Store.i.notes(trashed: true);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _trash = trash;
      _loading = false;
      if (_selectedId != null && _selected == null) _selectedId = null;
    });
    final wantedId = AppState.i.activeNoteId;
    if (wantedId != null && wantedId != _selectedId) {
      final match = notes.where((n) => n.id == wantedId).firstOrNull;
      if (match != null) {
        _select(match);
      }
    }
  }

  void _select(Note n) {
    AppState.i.setActiveWorkspaceContext(section: 'Note page', noteId: n.id);
    setState(() {
      _selectedId = n.id;
      _tab = 'pages';
      _title.text = n.title;
      _body.text = n.body;
      _preview = false;
    });
    var parent = n.parentId;
    while (parent != null) {
      _expanded.add(parent);
      parent = _notes.where((x) => x.id == parent).firstOrNull?.parentId;
    }
  }

  void _scheduleSave() {
    if (_selected == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    final n = _selected;
    if (n == null) return;
    final updated = n.copyWith(
      title: _title.text.trim().isEmpty ? 'Untitled page' : _title.text.trim(),
      body: _body.text,
      updatedAt: DateTime.now(),
    );
    await Store.i.saveNote(updated);
    unawaited(_maybeSnapshot(updated));
    final notes = await Store.i.notes(query: _query);
    if (mounted) setState(() => _notes = notes);
  }

  Future<void> _maybeSnapshot(Note n) async {
    final now = DateTime.now();
    final last = _lastSnapshotAt[n.id];
    if (last != null && now.difference(last) < const Duration(minutes: 5))
      return;
    final blocks = await Store.i.blocksFor(n.id);
    if (blocks.isEmpty) return;
    _lastSnapshotAt[n.id] = now;
    final snapshot = jsonEncode({
      'title': n.title,
      'icon': n.icon,
      'cover': n.cover,
      'body': n.body,
      'taken_at': now.millisecondsSinceEpoch,
      'blocks': blocks.map((b) => b.toMap()).toList(),
    });
    await Store.i.saveVersion(n.id, snapshot);
    await Store.i.trimVersions(n.id);
  }

  Future<void> _showHistory(Note n) async {
    final versions = await Store.i.versions(n.id);
    if (!mounted) return;
    final c = context.c;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Version history', style: MType.h3.copyWith(color: c.ink)),
        content: SizedBox(
          width: 440,
          height: 420,
          child: versions.isEmpty
              ? Center(
                  child: Text(
                    'No versions yet. One is kept every five minutes of editing.',
                    textAlign: TextAlign.center,
                    style: MType.small.copyWith(color: c.inkMuted),
                  ),
                )
              : ListView.separated(
                  itemCount: versions.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: c.line),
                  itemBuilder: (context, index) {
                    final row = versions[index];
                    final at = DateTime.fromMillisecondsSinceEpoch(
                      row['created_at'] as int,
                    );
                    final bytes = (row['snapshot'] as String).length;
                    return ListTile(
                      dense: true,
                      title: Text(
                        relativeDate(at),
                        style: MType.small.copyWith(fontSize: 12, color: c.ink),
                      ),
                      subtitle: Text(
                        '${(bytes / 1024).toStringAsFixed(1)} KB snapshot',
                        style: MType.small.copyWith(
                          fontSize: 10,
                          color: c.inkFaint,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          await _restoreVersion(n, row);
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Restore'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreVersion(Note n, Map<String, Object?> row) async {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(row['snapshot'] as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final blocks = ((data['blocks'] as List?) ?? const [])
        .map((e) => NoteBlock.fromMap((e as Map).cast<String, Object?>()))
        .toList();
    await Store.i.replaceBlocks(n.id, blocks);
    final restored = n.copyWith(
      title: (data['title'] as String?) ?? n.title,
      body: (data['body'] as String?) ?? n.body,
      icon: (data['icon'] as String?) ?? n.icon,
      cover: (data['cover'] as String?) ?? n.cover,
      updatedAt: DateTime.now(),
    );
    await Store.i.saveNote(restored);
    if (!mounted) return;
    setState(() {
      _title.text = restored.title;
      _body.text = restored.body;
      _editorToken++;
    });
    await _load();
  }

  Future<void> _saveAsTemplate(Note n) async {
    final c = context.c;
    final controller = TextEditingController(text: n.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Save as template', style: MType.h3.copyWith(color: c.ink)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Template name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || name == null) return;
    final blocks = await Store.i.blocksFor(n.id);
    final snapshot = jsonEncode({
      'title': n.title,
      'icon': n.icon,
      'cover': n.cover,
      'blocks': blocks.map((b) => b.toMap()).toList(),
    });
    await Store.i.saveTemplate(
      name.trim().isEmpty ? n.title : name.trim(),
      snapshot,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Template saved')));
  }

  Future<void> _showTemplates() async {
    var templates = await Store.i.templates();
    if (!mounted) return;
    final c = context.c;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: c.surface,
          title: Text('Templates', style: MType.h3.copyWith(color: c.ink)),
          content: SizedBox(
            width: 460,
            height: 420,
            child: templates.isEmpty
                ? Center(
                    child: Text(
                      'No templates yet.\nSave any page as a template from its ... menu.',
                      textAlign: TextAlign.center,
                      style: MType.small.copyWith(color: c.inkMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: templates.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: c.line),
                    itemBuilder: (context, index) {
                      final row = templates[index];
                      final at = DateTime.fromMillisecondsSinceEpoch(
                        row['created_at'] as int,
                      );
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.description_outlined,
                          size: 16,
                          color: c.inkMuted,
                        ),
                        title: Text(
                          row['name'] as String,
                          style: MType.small.copyWith(
                            fontSize: 12,
                            color: c.ink,
                          ),
                        ),
                        subtitle: Text(
                          relativeDate(at),
                          style: MType.small.copyWith(
                            fontSize: 10,
                            color: c.inkFaint,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                await _createFromTemplate(row);
                              },
                              child: const Text('Use'),
                            ),
                            IconButton(
                              iconSize: 14,
                              tooltip: 'Delete template',
                              onPressed: () async {
                                await Store.i.deleteTemplate(
                                  row['id'] as String,
                                );
                                final refreshed = await Store.i.templates();
                                setDialog(() => templates = refreshed);
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createFromTemplate(Map<String, Object?> row) async {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(row['snapshot'] as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final page = await _createNote(
      title: (data['title'] as String?) ?? 'Untitled page',
      icon: (data['icon'] as String?) ?? 'page',
    );
    final raw = (data['blocks'] as List?) ?? const [];
    final source = raw
        .map(
          (entry) => NoteBlock.fromMap((entry as Map).cast<String, Object?>()),
        )
        .toList();
    final blocks = NoteBlock.cloneWithNewIds(source, page.id, () => _uuid.v4());
    await Store.i.replaceBlocks(page.id, blocks);
    await _load();
    if (!mounted) return;
    final created = _notes.where((x) => x.id == page.id).firstOrNull;
    if (created != null) _select(created);
  }

  Future<void> _exportHtml(Note n) async {
    final body = md.markdownToHtml(
      n.body,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    final html =
        '''
<!doctype html>
<html><head><meta charset="utf-8"><title>${_escapeHtml(n.title)}</title>
<style>
body{font-family:Inter,Segoe UI,sans-serif;max-width:760px;margin:48px auto;padding:0 20px;color:#161618;line-height:1.65}
h1{font-size:32px;letter-spacing:-.6px}h2{font-size:24px}h3{font-size:19px}
code{background:#f1f1ef;padding:2px 5px;border-radius:4px;font-size:90%}
pre{background:#f6f7fb;padding:14px;border-radius:8px;overflow:auto}
blockquote{border-left:3px solid #d5d8e0;margin:0;padding-left:14px;color:#6b7280}
table{border-collapse:collapse}td,th{border:1px solid #e5e7eb;padding:6px 10px}
img{max-width:100%}
</style></head><body>
<h1>${_escapeHtml(n.title)}</h1>
$body
</body></html>''';
    final name = n.title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(' ', '-');
    final file = File(
      p.join(
        AppPaths.i.backupsDir,
        '${name.isEmpty ? 'page' : name}-${DateTime.now().millisecondsSinceEpoch}.html',
      ),
    );
    await file.writeAsString(html);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Exported to ${file.path}')));
  }

  String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  Future<Note> _createNote({
    String? parentId,
    String? title,
    String icon = 'page',
  }) async {
    final now = DateTime.now();
    final n = Note(
      id: _uuid.v4(),
      title: title ?? 'Untitled page',
      body: '',
      parentId: parentId,
      icon: icon,
      position: _maxPosition(parentId),
      createdAt: now,
      updatedAt: now,
    );
    await Store.i.saveNote(n);
    if (parentId != null) _expanded.add(parentId);
    AppState.i.bump();
    await _load();
    return n;
  }

  Future<void> _newPage({String? parentId, String? title}) async {
    final n = await _createNote(parentId: parentId, title: title);
    _select(n);
  }

  Future<void> _rename(Note n) async {
    final ctrl = TextEditingController(text: n.title);
    final ok = await showMSheet<bool>(
      context,
      maxWidth: 440,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Rename page', style: MType.h2.copyWith(color: context.c.ink)),
            const SizedBox(height: 12),
            TextField(controller: ctrl, autofocus: true),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 8),
                MButton(
                  label: 'Rename',
                  kind: MButtonKind.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    await Store.i.saveNote(
      n.copyWith(title: ctrl.text.trim(), updatedAt: DateTime.now()),
    );
    if (_selectedId == n.id) _title.text = ctrl.text.trim();
    await _load();
  }

  Future<void> _duplicate(Note n) async {
    Future<void> copyTree(
      Note source,
      String? parentId, {
      bool labelCopy = false,
    }) async {
      final now = DateTime.now();
      final dup = Note(
        id: _uuid.v4(),
        title: labelCopy ? '${source.title} (copy)' : source.title,
        body: source.body,
        parentId: parentId,
        icon: source.icon,
        cover: source.cover,
        position: _maxPosition(parentId),
        createdAt: now,
        updatedAt: now,
      );
      await Store.i.saveNote(dup);
      for (final child in _childrenOf(source.id)) {
        await copyTree(child, dup.id);
      }
    }

    await copyTree(n, n.parentId, labelCopy: true);
    AppState.i.bump();
    await _load();
  }

  Future<void> _trashPage(Note n) async {
    final descendants = _descendantIds(n.id).length;
    final ok = await showMSheet<bool>(
      context,
      maxWidth: 460,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Move “${n.title}” to Trash?',
              style: MType.h2.copyWith(color: context.c.ink),
            ),
            const SizedBox(height: 8),
            Text(
              descendants > 0
                  ? '$descendants sub-page${descendants == 1 ? '' : 's'} move with it. You can restore them from Trash.'
                  : 'You can restore it from Trash at any time.',
              style: MType.small.copyWith(
                color: context.c.inkMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 8),
                MButton(
                  label: 'Move to Trash',
                  kind: MButtonKind.danger,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await Store.i.trashSubtree(n.id);
    if (_selectedId == n.id) _selectedId = null;
    AppState.i.bump();
    await _load();
  }

  Future<void> _restore(Note n) async {
    await Store.i.restoreSubtree(n.id);
    AppState.i.bump();
    await _load();
  }

  Future<void> _purge(Note n) async {
    final ok = await showMSheet<bool>(
      context,
      maxWidth: 440,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete forever?',
              style: MType.h2.copyWith(color: context.c.ink),
            ),
            const SizedBox(height: 8),
            Text(
              '“${n.title}” and its sub-pages will be permanently removed.',
              style: MType.small.copyWith(
                color: context.c.inkMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 8),
                MButton(
                  label: 'Delete forever',
                  kind: MButtonKind.danger,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await Store.i.purgeNote(n.id);
    AppState.i.bump();
    await _load();
  }

  Future<void> _movePage(Note n) async {
    final forbidden = {n.id, ..._descendantIds(n.id)};
    final destinations = _notes
        .where((x) => !forbidden.contains(x.id))
        .toList();
    final chosen = await showMSheet<String?>(
      context,
      maxWidth: 480,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MDialogHeader(
              title: 'Move page to…',
              subtitle:
                  'Nest it inside another page, or return it to the top level.',
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.vertical_align_top_rounded,
                      size: 17,
                    ),
                    title: const Text('Top level'),
                    onTap: () => Navigator.of(context).pop(''),
                  ),
                  for (final d in destinations)
                    ListTile(
                      dense: true,
                      leading: Icon(_iconFor(d.icon), size: 17),
                      title: Text(
                        d.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MType.small.copyWith(color: context.c.ink),
                      ),
                      onTap: () => Navigator.of(context).pop(d.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final parentId = chosen.isEmpty ? null : chosen;
    await Store.i.moveNote(n.id, parentId);
    await Store.i.setNotePosition(n.id, _maxPosition(parentId));
    if (parentId != null) _expanded.add(parentId);
    AppState.i.bump();
    await _load();
  }

  Future<void> _moveOrder(Note n, int delta) async {
    final siblings = _childrenOf(n.parentId);
    final index = siblings.indexWhere((x) => x.id == n.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= siblings.length) return;
    final other = siblings[target];
    await Store.i.setNotePosition(n.id, other.position);
    await Store.i.setNotePosition(other.id, n.position);
    await _load();
  }

  Future<void> _setIcon(Note n, String icon) async {
    await Store.i.saveNote(n.copyWith(icon: icon, updatedAt: DateTime.now()));
    await _load();
  }

  Future<void> _setCover(Note n, String cover) async {
    await Store.i.saveNote(n.copyWith(cover: cover, updatedAt: DateTime.now()));
    await _load();
  }

  Future<void> _exportMarkdown(Note n) async {
    final buffer = StringBuffer()
      ..writeln('# ${n.title}')
      ..writeln()
      ..writeln(n.body);
    for (final child in _childrenOf(n.id)) {
      buffer
        ..writeln()
        ..writeln('## ${child.title}')
        ..writeln()
        ..writeln(child.body);
    }
    final name = n.title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(' ', '-');
    final file = File(
      p.join(
        AppPaths.i.backupsDir,
        '${name.isEmpty ? 'page' : name}-${DateTime.now().millisecondsSinceEpoch}.md',
      ),
    );
    await file.writeAsString(buffer.toString());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Exported to ${file.path}')));
  }

  Future<void> _showContextMenu(Note n, Offset globalPos) async {
    final c = context.c;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final chosen = await showMenu<String>(
      context: context,
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 14,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MRadius.lg),
        side: BorderSide(color: c.line),
      ),
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        overlay.size.width - globalPos.dx + 8,
        overlay.size.height - globalPos.dy + 8,
      ),
      items: [
        _menuItem('open', Icons.open_in_new_rounded, 'Open', 'Enter'),
        _menuItem('rename', Icons.edit_outlined, 'Rename', 'F2'),
        _menuItem(
          'subpage',
          Icons.subdirectory_arrow_right_rounded,
          'Add sub-page',
          'Ctrl+Shift+N',
        ),
        _menuItem('duplicate', Icons.copy_all_outlined, 'Duplicate', 'Ctrl+D'),
        _menuItem('move', Icons.drive_file_move_outlined, 'Move to…', ''),
        _menuItem('up', Icons.arrow_upward_rounded, 'Move up', ''),
        _menuItem('down', Icons.arrow_downward_rounded, 'Move down', ''),
        _menuItem('icon', Icons.emoji_emotions_outlined, 'Change icon', ''),
        _menuItem(
          'cover',
          Icons.image_outlined,
          n.cover.isEmpty ? 'Add cover' : 'Change cover',
          '',
        ),
        _menuItem(
          'pin',
          n.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          n.pinned ? 'Remove from Favorites' : 'Add to Favorites',
          'Ctrl+Shift+B',
        ),
        _menuItem('history', Icons.history_rounded, 'Version history', ''),
        _menuItem(
          'template',
          Icons.bookmark_added_outlined,
          'Save as template',
          '',
        ),
        _menuItem(
          'templates',
          Icons.grid_view_rounded,
          'New from template',
          '',
        ),
        _menuItem('export', Icons.download_rounded, 'Export as Markdown', ''),
        _menuItem('exportHtml', Icons.code_rounded, 'Export as HTML', ''),
        _menuItem('link', Icons.link_rounded, 'Copy page link', ''),
        _menuItem(
          'shortcuts',
          Icons.keyboard_outlined,
          'Keyboard shortcuts',
          'Ctrl+Shift+/',
        ),
        const PopupMenuDivider(),
        _menuItem(
          'trash',
          Icons.delete_outline_rounded,
          'Move to Trash',
          'Del',
          danger: true,
        ),
      ],
    );
    if (chosen == null || !mounted) return;
    switch (chosen) {
      case 'open':
        _select(n);
      case 'rename':
        await _rename(n);
      case 'subpage':
        await _newPage(parentId: n.id);
      case 'duplicate':
        await _duplicate(n);
      case 'move':
        await _movePage(n);
      case 'up':
        await _moveOrder(n, -1);
      case 'down':
        await _moveOrder(n, 1);
      case 'icon':
        await _pickIcon(n);
      case 'cover':
        await _pickCover(n);
      case 'pin':
        await Store.i.saveNote(
          n.copyWith(pinned: !n.pinned, updatedAt: DateTime.now()),
        );
        await _load();
      case 'history':
        await _showHistory(n);
      case 'template':
        await _saveAsTemplate(n);
      case 'templates':
        await _showTemplates();
      case 'exportHtml':
        await _exportHtml(n);
      case 'export':
        await _exportMarkdown(n);
      case 'link':
        await _copyLink(n);
      case 'shortcuts':
        await _showShortcuts();
      case 'trash':
        await _trashPage(n);
    }
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    String shortcut, {
    bool danger = false,
  }) {
    final c = context.c;
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 15, color: danger ? c.danger : c.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: MType.small.copyWith(
                color: danger ? c.danger : c.ink,
                fontSize: 12.5,
              ),
            ),
          ),
          if (shortcut.isNotEmpty)
            Text(
              shortcut,
              style: MType.small.copyWith(color: c.inkFaint, fontSize: 10),
            ),
        ],
      ),
    );
  }

  Future<void> _pickIcon(Note n) async {
    final picked = await showMSheet<String>(
      context,
      maxWidth: 440,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Page icon', style: MType.h2.copyWith(color: context.c.ink)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in _pageIcons)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(entry.$1),
                    borderRadius: BorderRadius.circular(MRadius.md),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: n.icon == entry.$1
                            ? context.c.surfaceSunken
                            : context.c.surfaceAlt,
                        borderRadius: BorderRadius.circular(MRadius.md),
                        border: Border.all(
                          color: n.icon == entry.$1
                              ? context.c.ink
                              : context.c.line,
                        ),
                      ),
                      child: Icon(entry.$2, size: 20, color: context.c.ink),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked != null) await _setIcon(n, picked);
  }

  Future<void> _pickCover(Note n) async {
    final picked = await showMSheet<String>(
      context,
      maxWidth: 460,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Page cover', style: MType.h2.copyWith(color: context.c.ink)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).pop(''),
                  child: Container(
                    width: 54,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.c.surfaceAlt,
                      borderRadius: BorderRadius.circular(MSpace.x2),
                      border: Border.all(color: context.c.line),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: context.c.inkMuted,
                    ),
                  ),
                ),
                for (final hex in _coverColors)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(hex),
                    child: Container(
                      width: 54,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _coverColor(hex),
                        borderRadius: BorderRadius.circular(MSpace.x2),
                        border: Border.all(
                          color: n.cover == hex
                              ? context.c.ink
                              : context.c.line,
                          width: n.cover == hex ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked != null) await _setCover(n, picked);
  }

  // ------------------------------------------------------------ editor blocks

  void _insertBlock(String template) {
    final editor = _blockEditorKey.currentState;
    if (editor != null) {
      editor.insertTextAtCaret(template);
      return;
    }
    final selection = _body.selection;
    final text = _body.text;
    final offset = selection.isValid ? selection.start : text.length;
    final needsLeadingBreak = offset > 0 && text[offset - 1] != '\n';
    final insertion = '${needsLeadingBreak ? '\n' : ''}$template';
    _body.text = text.replaceRange(offset, offset, insertion);
    _body.selection = TextSelection.collapsed(
      offset: offset + insertion.length,
    );
    _scheduleSave();
  }

  Future<void> _showBlockMenu() async {
    final editor = _blockEditorKey.currentState;
    if (editor != null) {
      editor.showInsertMenu();
      return;
    }
    final c = context.c;
    final chosen = await showMenu<String>(
      context: context,
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 14,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MRadius.lg),
        side: BorderSide(color: c.line),
      ),
      items: [
        _blockItem('h1', Icons.title_rounded, 'Heading 1'),
        _blockItem('h2', Icons.text_fields_rounded, 'Heading 2'),
        _blockItem('h3', Icons.short_text_rounded, 'Heading 3'),
        _blockItem(
          'bullets',
          Icons.format_list_bulleted_rounded,
          'Bulleted list',
        ),
        _blockItem(
          'numbers',
          Icons.format_list_numbered_rounded,
          'Numbered list',
        ),
        _blockItem('todo', Icons.check_box_outlined, 'To-do list'),
        _blockItem('quote', Icons.format_quote_rounded, 'Quote'),
        _blockItem('callout', Icons.tips_and_updates_outlined, 'Callout'),
        _blockItem('code', Icons.code_rounded, 'Code'),
        _blockItem('divider', Icons.horizontal_rule_rounded, 'Divider'),
        _blockItem('table', Icons.table_chart_outlined, 'Table'),
        _blockItem('pagelink', Icons.link_rounded, 'Link to page'),
        _blockItem('kwl', Icons.view_quilt_outlined, 'Study notes template'),
      ],
    );
    if (chosen == null) return;
    switch (chosen) {
      case 'h1':
        _insertBlock('\n# ');
      case 'h2':
        _insertBlock('\n## ');
      case 'h3':
        _insertBlock('\n### ');
      case 'bullets':
        _insertBlock('\n- ');
      case 'numbers':
        _insertBlock('\n1. ');
      case 'todo':
        _insertBlock('\n- [ ] ');
      case 'quote':
        _insertBlock('\n> ');
      case 'callout':
        _insertBlock('\n> 💡 **Note:** ');
      case 'code':
        _insertBlock('\n```\n\n```\n');
      case 'divider':
        _insertBlock('\n\n---\n\n');
      case 'table':
        _insertBlock('\n| Column | Column |\n| --- | --- |\n|  |  |\n');
      case 'pagelink':
        _insertBlock('[[');
      case 'kwl':
        _insertBlock(
          '\n## What I already know\n- \n\n'
          '## Questions to answer\n- \n\n'
          '## Key concepts & details\n- \n\n'
          '## Summary in my own words\n- \n',
        );
    }
  }

  PopupMenuItem<String> _blockItem(String value, IconData icon, String label) {
    final c = context.c;
    return PopupMenuItem(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 15, color: c.inkMuted),
          const SizedBox(width: 10),
          Text(
            label,
            style: MType.small.copyWith(color: c.ink, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Future<void> _runNoteAi(String mode) async {
    final n = _selected;
    if (n == null || _body.text.trim().isEmpty) return;
    final provider = await Store.i.defaultProvider();
    if (provider == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configure an AI provider in Settings first.'),
        ),
      );
      return;
    }
    final client = AiClient();
    if (mode == 'cards') {
      final buf = StringBuffer();
      await client.streamChat(
        provider: provider,
        messages: [
          ChatTurn(
            role: 'system',
            content:
                'Generate up to 6 atomic retrieval-practice flashcards from the learner\'s note. '
                'Return ONLY a JSON array of objects with keys "q" and "a".',
          ),
          ChatTurn(role: 'user', content: '${_title.text}\n\n${_body.text}'),
        ],
        onDelta: (d) => buf.write(d),
        onDone: () {},
        onError: (_) {},
      );
      final raw = buf.toString();
      final s = raw.indexOf('[');
      final e = raw.lastIndexOf(']');
      var added = 0;
      if (s >= 0 && e > s) {
        try {
          final list = jsonDecode(raw.substring(s, e + 1)) as List;
          for (final item in list.whereType<Map>()) {
            final q = item['q']?.toString().trim() ?? '';
            final a = item['a']?.toString().trim() ?? '';
            if (q.isNotEmpty && a.isNotEmpty) {
              await Store.i.saveCard(
                Flashcard(
                  id: _uuid.v4(),
                  deck: _title.text.trim().isEmpty
                      ? 'Notes'
                      : _title.text.trim(),
                  front: q,
                  back: a,
                  courseId: n.courseId,
                  lessonId: n.lessonId,
                  resourceId: n.resourceId,
                  page: n.page,
                  dueAt: DateTime.now(),
                  createdAt: DateTime.now(),
                ),
              );
              added++;
            }
          }
        } catch (_) {}
      }
      AppState.i.bump();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created $added flashcards from this page.')),
      );
      return;
    }

    if (!mounted) return;
    final output = ValueNotifier<String>('');
    showMSheet<void>(
      context,
      maxWidth: 560,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MDialogHeader(
              title: 'Keywords, Technical Details & Cues',
              subtitle: _title.text,
            ),
            ValueListenableBuilder<String>(
              valueListenable: output,
              builder: (context, text, _) {
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.c.surfaceAlt,
                        borderRadius: BorderRadius.circular(MRadius.md),
                        border: Border.all(color: context.c.line),
                      ),
                      child: SelectableText(
                        text.isEmpty
                            ? 'Extracting keywords and technical details…'
                            : text,
                        style: MType.body.copyWith(
                          color: context.c.ink,
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: MButton(
                label: 'Append to page',
                icon: Icons.playlist_add_rounded,
                kind: MButtonKind.primary,
                dense: true,
                onPressed: () {
                  if (output.value.isNotEmpty) {
                    _body.text = '${_body.text}\n\n---\n${output.value}';
                    _scheduleSave();
                  }
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );

    final buf = StringBuffer();
    await client.streamChat(
      provider: provider,
      messages: [
        ChatTurn(
          role: 'system',
          content:
              'Analyze the learner\'s note. Separate and list: '
              '(1) High-information single keywords (nouns/verbs that compress meaning for scheming), '
              '(2) Specific technical details (formulas, numbers, dates, definitions that must be preserved), and '
              '(3) 3 Cornell-style cue questions for active recall.',
        ),
        ChatTurn(role: 'user', content: '${_title.text}\n\n${_body.text}'),
      ],
      onDelta: (d) {
        buf.write(d);
        output.value = buf.toString();
      },
      onDone: () {},
      onError: (e) => output.value = 'Error: $e',
    );
  }

  // ------------------------------------------------------------ shortcuts

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    final bodyFocused = _bodyFocus.hasFocus;
    if (!ctrl) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyN:
        _newPage(parentId: shift ? _selectedId : null);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyP:
        _quickSwitch();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        _findInPage();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyK:
        _insertBlock('[[');
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyD:
        if (_selected != null) _duplicate(_selected!);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.slash:
        if (shift) {
          _showShortcuts();
        } else {
          _showBlockMenu();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyB:
        if (shift) {
          if (bodyFocused) {
            _wrapSelection('**', '**');
          } else if (_selected != null) {
            final n = _selected!;
            Store.i
                .saveNote(
                  n.copyWith(pinned: !n.pinned, updatedAt: DateTime.now()),
                )
                .then((_) => _load());
          }
          return KeyEventResult.handled;
        }
        if (bodyFocused) {
          _wrapSelection('**', '**');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.keyI:
        if (bodyFocused) {
          _wrapSelection('*', '*');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.keyU:
        if (bodyFocused) {
          _wrapSelection('<u>', '</u>');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.keyE:
        if (bodyFocused) {
          _wrapSelection('`', '`');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.keyS:
        if (shift && bodyFocused) {
          _wrapSelection('~~', '~~');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  /// Wraps the current body selection, exactly like an inline formatting
  /// shortcut. Falls back to inserting the markers at the caret.
  void _wrapSelection(String left, String right) {
    final text = _body.text;
    final sel = _body.selection;
    if (!sel.isValid) {
      final at = text.length;
      _body.text = '$text$left$right';
      _body.selection = TextSelection.collapsed(offset: at + left.length);
      _scheduleSave();
      return;
    }
    final selected = text.substring(sel.start, sel.end);
    final replacement = '$left$selected$right';
    _body.text = text.replaceRange(sel.start, sel.end, replacement);
    _body.selection = selected.isEmpty
        ? TextSelection.collapsed(offset: sel.start + left.length)
        : TextSelection(
            baseOffset: sel.start + left.length,
            extentOffset: sel.start + left.length + selected.length,
          );
    _scheduleSave();
  }

  Future<void> _quickSwitch() async {
    final c = context.c;
    final ctrl = TextEditingController();
    var results = _notes;
    await showMSheet<void>(
      context,
      maxWidth: 520,
      child: StatefulBuilder(
        builder: (context, setLocal) {
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 540),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.search_rounded, size: 17, color: c.inkMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          autofocus: true,
                          style: MType.body.copyWith(
                            color: c.ink,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search pages by title…',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          onChanged: (v) {
                            final q = v.trim().toLowerCase();
                            setLocal(() {
                              results = q.isEmpty
                                  ? _notes
                                  : _notes
                                        .where(
                                          (n) =>
                                              n.title.toLowerCase().contains(q),
                                        )
                                        .toList();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  Flexible(
                    child: results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              'No page matches that title.',
                              style: MType.small.copyWith(color: c.inkFaint),
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: results.length,
                            itemBuilder: (context, i) {
                              final n = results[i];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  _iconFor(n.icon),
                                  size: 16,
                                  color: c.inkMuted,
                                ),
                                title: Text(
                                  n.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: MType.small.copyWith(
                                    color: c.ink,
                                    fontSize: 12.5,
                                  ),
                                ),
                                subtitle: n.parentId == null
                                    ? null
                                    : Text(
                                        _notes
                                                .where(
                                                  (x) => x.id == n.parentId,
                                                )
                                                .firstOrNull
                                                ?.title ??
                                            '',
                                        style: MType.small.copyWith(
                                          color: c.inkFaint,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _select(n);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    ctrl.dispose();
  }

  Future<void> _showShortcuts() async {
    final c = context.c;
    const rows = <(String, String)>[
      ('Ctrl + N', 'New page'),
      ('Ctrl + Shift + N', 'New sub-page inside the open page'),
      ('Ctrl + P', 'Search pages by title'),
      ('Ctrl + F', 'Find text in the current page'),
      ('Ctrl + D', 'Duplicate the current page and its sub-pages'),
      ('Ctrl + K', 'Start a [[page link]]'),
      ('Ctrl + /', 'Insert a block'),
      ('Ctrl + Shift + B', 'Add or remove from Favorites'),
      ('Ctrl + B / I / U', 'Bold, italic, underline'),
      ('Ctrl + Shift + S', 'Strikethrough'),
      ('Ctrl + E', 'Inline code'),
      ('[[Page title]]', 'Link to another page, typed in the body'),
      ('Right-click page', 'Rename, move, duplicate, cover, trash'),
    ];
    await showMSheet<void>(
      context,
      maxWidth: 560,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MDialogHeader(
              title: 'Keyboard shortcuts',
              subtitle: 'The same gestures you already use in a page-based workspace.',
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.$2,
                              style: MType.small.copyWith(
                                color: c.ink,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: c.surfaceAlt,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: c.line),
                            ),
                            child: Text(
                              r.$1,
                              style: MType.mono.copyWith(
                                color: c.inkMuted,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final selected = _selected;
    final sidebar = MCard(
      padding: const EdgeInsets.all(12),
      radius: MRadius.xl,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pages',
                        style: MType.h2.copyWith(color: c.ink, fontSize: 19),
                      ),
                      Text(
                        'Pages, sub-pages and favorites',
                        style: MType.small.copyWith(
                          color: c.inkFaint,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                MButton(
                  label: 'New',
                  icon: Icons.add_rounded,
                  kind: MButtonKind.primary,
                  dense: true,
                  onPressed: () => _newPage(),
                ),
              ],
            ),
          ),
          TextField(
            style: MType.body.copyWith(color: c.ink, fontSize: 12.5),
            decoration: const InputDecoration(
              hintText: 'Search pages',
              prefixIcon: Icon(Icons.search_rounded, size: 16),
              isDense: true,
            ),
            onChanged: (v) {
              _query = v;
              _load();
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 6,
            children: [
              MChip(
                label: 'Pages',
                selected: _tab == 'pages',
                onTap: () => setState(() => _tab = 'pages'),
              ),
              MChip(
                label: 'Favorites ${_notes.where((n) => n.pinned).length}',
                selected: _tab == 'favorites',
                onTap: () => setState(() => _tab = 'favorites'),
              ),
              MChip(
                label: 'Trash ${_trash.length}',
                selected: _tab == 'trash',
                onTap: () => setState(() => _tab = 'trash'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: _sidebarList()),
        ],
      ),
    );
    final editor = MCard(
      padding: EdgeInsets.zero,
      radius: MRadius.xl,
      clip: true,
      child: MFadeIn(
        key: ValueKey(selected?.id ?? 'none'),
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(
          key: ValueKey(selected?.id ?? 'none'),
          child: selected == null
              ? Center(
                  child: MEmpty(
                    framed: false,
                    icon: Icons.edit_note_rounded,
                    title: 'Select a page, or start a new one',
                    message: 'Pages can hold sub-pages, blocks, keywords and notes. Right-click a page for Rename, Duplicate, Move, Cover and Trash.',
                    action: MButton(
                      label: 'New page',
                      kind: MButtonKind.primary,
                      onPressed: () => _newPage(),
                    ),
                  ),
                )
              : _editor(context, selected),
        ),
      ),
    );
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 28, 22),
        child: LayoutBuilder(
          builder: (context, cons) {
            // One column when the window is narrow: the page list on top,
            // the editor below, instead of two squeezed panes.
            if (cons.maxWidth < 820) {
              return Column(
                children: [
                  SizedBox(height: 240, child: sidebar),
                  const SizedBox(height: 12),
                  Expanded(child: editor),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 312, child: sidebar),
                const SizedBox(width: 16),
                Expanded(child: editor),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sidebarList() {
    final c = context.c;
    if (_loading)
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_tab == 'trash') {
      if (_trash.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Trash is empty.',
            style: MType.small.copyWith(color: c.inkFaint, fontSize: 11.5),
          ),
        );
      }
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _trash.length,
        itemBuilder: (context, i) {
          final n = _trash[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(MRadius.md),
            ),
            child: Row(
              children: [
                Icon(_iconFor(n.icon), size: 14, color: c.inkFaint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MType.small.copyWith(
                      color: c.inkMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
                MIconButton(
                  icon: Icons.restore_rounded,
                  size: 26,
                  tooltip: 'Restore',
                  onPressed: () => _restore(n),
                ),
                MIconButton(
                  icon: Icons.delete_forever_rounded,
                  size: 26,
                  tooltip: 'Delete forever',
                  onPressed: () => _purge(n),
                ),
              ],
            ),
          );
        },
      );
    }
    if (_tab == 'favorites') {
      final pinned = _notes.where((n) => n.pinned).toList();
      if (pinned.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Pin pages to keep them here.',
            style: MType.small.copyWith(color: c.inkFaint, fontSize: 11.5),
          ),
        );
      }
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: pinned.length,
        itemBuilder: (context, i) =>
            _treeRow(pinned[i], 0, showChildren: false),
      );
    }
    final roots = _childrenOf(null);
    if (roots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Create your first page. Inside it you can add sub-pages, exactly like a notebook.',
          style: MType.small.copyWith(color: c.inkMuted, height: 1.45),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: roots.length,
      itemBuilder: (context, i) => _buildTreeItem(roots[i], 0),
    );
  }

  Widget _buildTreeItem(Note note, int depth) {
    final children = _childrenOf(note.id);
    final expanded = _expanded.contains(note.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _treeRow(note, depth, showChildren: children.isNotEmpty),
        if (expanded)
          for (final child in children) _buildTreeItem(child, depth + 1),
      ],
    );
  }

  Widget _treeRow(Note note, int depth, {bool showChildren = true}) {
    final c = context.c;
    final children = _childrenOf(note.id);
    final expanded = _expanded.contains(note.id);
    final active = note.id == _selectedId;

    final row = GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(note, details.globalPosition),
      onTap: () => _select(note),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.fromLTRB(5 + depth * 14.0, 6, 5, 6),
          decoration: BoxDecoration(
            color: active ? c.surfaceSunken : Colors.transparent,
            borderRadius: BorderRadius.circular(MRadius.md),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: showChildren && children.isNotEmpty
                    ? InkWell(
                        onTap: () => setState(() {
                          if (expanded) {
                            _expanded.remove(note.id);
                          } else {
                            _expanded.add(note.id);
                          }
                        }),
                        child: AnimatedRotation(
                          turns: expanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 15,
                            color: c.inkFaint,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Icon(
                _iconFor(note.icon),
                size: 15,
                color: active ? c.ink : c.inkMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: MType.small.copyWith(
                    fontSize: 12.5,
                    color: active ? c.ink : c.inkMuted,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (note.pinned)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Icon(
                    Icons.push_pin_rounded,
                    size: 11,
                    color: c.inkFaint,
                  ),
                ),
              if (children.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '${children.length}',
                    style: MType.small.copyWith(color: c.inkFaint, fontSize: 9),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final dragged = details.data;
        return dragged != note.id && !_descendantIds(dragged).contains(note.id);
      },
      onAcceptWithDetails: (details) async {
        final dragged = details.data;
        if (dragged == note.id) return;
        await Store.i.moveNote(dragged, note.id);
        await Store.i.setNotePosition(dragged, _maxPosition(note.id));
        _expanded.add(note.id);
        AppState.i.bump();
        await _load();
      },
      builder: (context, candidate, rejected) {
        return LongPressDraggable<String>(
          data: note.id,
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(MRadius.md),
                border: Border.all(color: c.line),
                boxShadow: [BoxShadow(color: c.shadow, blurRadius: 16)],
              ),
              child: Text(
                note.title,
                style: MType.small.copyWith(color: c.ink),
              ),
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MRadius.md),
              border: candidate.isNotEmpty
                  ? Border.all(color: c.ink, width: 1.2)
                  : null,
            ),
            child: row,
          ),
        );
      },
    );
  }

  Widget _referenceColumn(String label, IconData icon, List<Note> pages) {
    final c = context.c;
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: c.inkMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: MType.h3.copyWith(color: c.ink, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final page in pages)
            InkWell(
              onTap: () => _select(page),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  children: [
                    Icon(_iconFor(page.icon), size: 13, color: c.inkFaint),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        page.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MType.small.copyWith(
                          color: c.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _copyLink(Note n) async {
    final slug = n.title.trim().replaceAll(RegExp(r'\s+'), '-').toLowerCase();
    await Clipboard.setData(
      ClipboardData(text: '[[${n.title}]]  (klaro://page/$slug)'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Page link copied.')));
  }

  Widget _editor(BuildContext context, Note n) {
    final c = context.c;
    final children = _childrenOf(n.id);
    final parent = n.parentId == null
        ? null
        : _notes.where((x) => x.id == n.parentId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Notion-style bar: breadcrumb on the left, compact actions on the right.
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: c.line.withValues(alpha: 0.7)),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, cons) {
              // Compact toolbars drop the labels and keep the icons, so the
              // breadcrumb never gets squeezed out of the bar.
              final compact = cons.maxWidth < 660;
              Widget action(String label, IconData icon, VoidCallback onTap) {
                return compact
                    ? MIconButton(
                        icon: icon,
                        size: 30,
                        tooltip: label,
                        onPressed: onTap,
                      )
                    : MChip(label: label, icon: icon, onTap: onTap);
              }

              return Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (parent != null) ...[
                          InkWell(
                            onTap: () => _select(parent),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _iconFor(parent.icon),
                                    size: 13,
                                    color: c.inkMuted,
                                  ),
                                  const SizedBox(width: 5),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 150,
                                    ),
                                    child: Text(
                                      parent.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: MType.small.copyWith(
                                        color: c.inkMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 14,
                            color: c.inkFaint,
                          ),
                        ],
                        Icon(_iconFor(n.icon), size: 13, color: c.inkMuted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MType.small.copyWith(
                              color: c.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Edited ${relativeDate(n.updatedAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MType.small.copyWith(
                              color: c.inkFaint,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  action('Insert', Icons.add_rounded, _showBlockMenu),
                  if (!compact) const SizedBox(width: 6),
                  action(
                    'Sub-page',
                    Icons.subdirectory_arrow_right_rounded,
                    () => _newPage(parentId: n.id),
                  ),
                  if (!compact) const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    tooltip: 'Study & AI tools',
                    color: c.surface,
                    onSelected: (v) {
                      if (v == 'extract' || v == 'cards') {
                        _runNoteAi(v);
                      } else if (v == 'templates') {
                        _showTemplates();
                      } else if (v == 'shortcuts') {
                        _showShortcuts();
                      }
                    },
                    itemBuilder: (_) => [
                      _menuItem(
                        'extract',
                        Icons.auto_awesome_outlined,
                        'Extract AI keywords',
                        '',
                      ),
                      _menuItem(
                        'cards',
                        Icons.style_outlined,
                        'Generate AI flashcards',
                        '',
                      ),
                      const PopupMenuDivider(),
                      _menuItem(
                        'templates',
                        Icons.grid_view_rounded,
                        'Page templates',
                        '',
                      ),
                      _menuItem(
                        'shortcuts',
                        Icons.keyboard_outlined,
                        'Keyboard shortcuts',
                        'Ctrl+Shift+/',
                      ),
                    ],
                    child: AbsorbPointer(
                      child: compact
                          ? MIconButton(
                              icon: Icons.auto_awesome_outlined,
                              size: 30,
                              tooltip: 'Study & AI tools',
                              onPressed: () {},
                            )
                          : MChip(
                              label: 'AI & Tools',
                              icon: Icons.auto_awesome_outlined,
                              onTap: () {},
                            ),
                    ),
                  ),
                  if (!compact) const SizedBox(width: 6),
                  action(
                    _preview ? 'Edit' : 'Preview',
                    _preview ? Icons.edit_outlined : Icons.visibility_outlined,
                    () => setState(() => _preview = !_preview),
                  ),
                  const SizedBox(width: 4),
                  MIconButton(
                    icon: n.pinned
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    size: 30,
                    tooltip: n.pinned
                        ? 'Remove from Bookmarks'
                        : 'Pin to Bookmarks',
                    onPressed: () async {
                      await Store.i.saveNote(
                        n.copyWith(
                          pinned: !n.pinned,
                          updatedAt: DateTime.now(),
                        ),
                      );
                      AppState.i.bump();
                      await _load();
                    },
                  ),
                  MIconButton(
                    icon: Icons.more_horiz_rounded,
                    size: 30,
                    tooltip: 'Page actions',
                    onPressed: () {
                      final box = context.findRenderObject() as RenderBox?;
                      final pos = box == null
                          ? Offset.zero
                          : box.localToGlobal(const Offset(320, 40));
                      _showContextMenu(n, pos);
                    },
                  ),
                ],
              );
            },
          ),
        ),
        if (n.cover.isNotEmpty)
          Container(
            height: 112,
            decoration: BoxDecoration(color: _coverColor(n.cover)),
            alignment: Alignment.bottomRight,
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MChip(
                  label: 'Change cover',
                  icon: Icons.image_outlined,
                  onTap: () => _pickCover(n),
                ),
                const SizedBox(width: 6),
                MIconButton(
                  icon: Icons.close_rounded,
                  size: 28,
                  tooltip: 'Remove cover',
                  onPressed: () => _setCover(n, ''),
                ),
              ],
            ),
          ),
        // Page title + sub-pages header inside the document canvas.
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 22, 48, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  PopupMenuButton<String>(
                    tooltip: 'Change icon',
                    color: c.surface,
                    onSelected: (v) => _setIcon(n, v),
                    itemBuilder: (_) => [
                      for (final entry in _pageIcons)
                        PopupMenuItem(
                          value: entry.$1,
                          height: 36,
                          child: Row(
                            children: [
                              Icon(entry.$2, size: 15, color: c.inkMuted),
                              const SizedBox(width: 10),
                              Text(entry.$1),
                            ],
                          ),
                        ),
                    ],
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.line),
                      ),
                      child: Icon(_iconFor(n.icon), size: 19, color: c.ink),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _title,
                      style: MType.h1.copyWith(
                        color: c.ink,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.7,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Untitled',
                        hintStyle: MType.h1.copyWith(
                          color: c.inkFaint.withValues(alpha: 0.45),
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        hoverColor: Colors.transparent,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
              if (children.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final child in children)
                      InkWell(
                        onTap: () => _select(child),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: c.surfaceAlt,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: c.line),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _iconFor(child.icon),
                                size: 13,
                                color: c.inkMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                child.title,
                                style: MType.small.copyWith(
                                  color: c.ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _preview
              ? MSmoothScrollView(
                  padding: const EdgeInsets.fromLTRB(56, 14, 48, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MarkdownBody(
                        data: _body.text.isEmpty
                            ? '_Nothing written yet._'
                            : _withWikiLinks(_body.text),
                        onTapLink: (text, href, title) {
                          if (href == null) return;
                          if (href.startsWith('klaro://page/')) {
                            _openLinked(
                              Uri.decodeComponent(
                                href.substring('klaro://page/'.length),
                              ),
                            );
                          }
                        },
                        styleSheet: MarkdownStyleSheet(
                          p: MType.body.copyWith(
                            color: c.ink,
                            height: 1.7,
                            fontSize: 14,
                          ),
                          h1: MType.h1.copyWith(color: c.ink, fontSize: 25),
                          h2: MType.h2.copyWith(color: c.ink, fontSize: 19),
                          h3: MType.h3.copyWith(color: c.ink, fontSize: 16),
                          listBullet: MType.body.copyWith(color: c.ink),
                          checkbox: MType.body.copyWith(color: c.ink),
                          code: MType.mono.copyWith(
                            color: c.ink,
                            fontSize: 12.5,
                          ),
                          a: MType.body.copyWith(
                            color: c.ink,
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                            decorationColor: c.inkFaint,
                          ),
                          blockquoteDecoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: c.ink, width: 3),
                            ),
                          ),
                          blockquote: MType.body.copyWith(color: c.inkMuted),
                        ),
                      ),
                      if (_linkedPages(n).isNotEmpty ||
                          _backlinks(n).isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 12),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.start,
                          spacing: 32,
                          runSpacing: 16,
                          children: [
                            if (_linkedPages(n).isNotEmpty)
                              _referenceColumn(
                                'Linked pages',
                                Icons.north_east_rounded,
                                _linkedPages(n),
                              ),
                            if (_backlinks(n).isNotEmpty)
                              _referenceColumn(
                                'Backlinks',
                                Icons.south_west_rounded,
                                _backlinks(n),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 24, 0),
                  child: BlockEditor(
                    key: _blockEditorKey,
                    noteId: n.id,
                    token: _editorToken,
                    initialMarkdown: _body.text,
                    onChanged: (markdown) {
                      if (_body.text == markdown) return;
                      _body.value = TextEditingValue(
                        text: markdown,
                        selection: TextSelection.collapsed(
                          offset: markdown.length,
                        ),
                      );
                      _scheduleSave();
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
