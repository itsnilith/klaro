import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../shell.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<LibraryResource> _items = const [];
  Map<String, bool> _exists = const {};
  String _kind = 'all';
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    AppState.i.addListener(_load);
  }

  @override
  void dispose() {
    AppState.i.removeListener(_load);
    super.dispose();
  }

  /// Standalone books and documents only: course attachments live inside their
  /// course, so the Library stays small and fast.
  Future<void> _load() async {
    final list = await Store.i.resources(standaloneOnly: true);
    // Resolve existence once, off the build path: calling existsSync per tile on
    // every rebuild made scrolling and tab switches stutter.
    final exists = <String, bool>{
      for (final r in list) r.id: File(r.path).existsSync(),
    };
    if (!mounted) return;
    setState(() {
      _items = list;
      _exists = exists;
      _loading = false;
    });
  }

  List<LibraryResource> get _visible {
    var list = _items;
    if (_kind != 'all') list = list.where((r) => r.kind == _kind).toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((r) => r.title.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final visible = _visible;
    final kinds = <String, int>{};
    for (final r in _items) {
      kinds[r.kind] = (kinds[r.kind] ?? 0) + 1;
    }
    return MSmoothScrollView(
      padding: const EdgeInsets.fromLTRB(22, 10, 32, 32),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, cons) {
                  final title = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Library', style: MType.h1.copyWith(color: c.ink)),
                      const SizedBox(height: 4),
                      Text(
                        '${_items.length} books and documents you added - course attachments stay inside their course',
                        style: MType.small.copyWith(color: c.inkMuted),
                      ),
                    ],
                  );
                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      MButton(
                        label: 'Add files',
                        icon: Icons.upload_file_outlined,
                        kind: MButtonKind.primary,
                        onPressed: () async {
                          await importLibraryFiles(context);
                          _load();
                        },
                      ),
                    ],
                  );
                  if (cons.maxWidth < 640) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 12), actions],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 12),
                      actions,
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  SizedBox(
                    width: 300,
                    child: TextField(
                      style: MType.body.copyWith(color: c.ink, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Search the library',
                        prefixIcon: Icon(Icons.search_rounded, size: 17),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          MChip(
                            label: 'All ${_items.length}',
                            selected: _kind == 'all',
                            onTap: () => setState(() => _kind = 'all'),
                          ),
                          for (final k in kinds.keys) ...[
                            const SizedBox(width: 6),
                            MChip(
                              label: '${_label(k)} ${kinds[k]}',
                              selected: _kind == k,
                              onTap: () => setState(() => _kind = k),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (visible.isEmpty)
                MEmpty(
                  icon: Icons.folder_copy_outlined,
                  title: _items.isEmpty ? 'Your library is empty' : 'Nothing matches',
                  message: _items.isEmpty
                      ? 'Add a PDF, a slide deck, a code file or an image. Files are referenced in place; nothing is copied.'
                      : 'Try another filter or clear the search.',
                  action: MButton(
                    label: 'Add files',
                    kind: MButtonKind.primary,
                    onPressed: () async {
                      await importLibraryFiles(context);
                      _load();
                    },
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth > 1100 ? 4 : constraints.maxWidth > 820 ? 3 : 2;
                    final w = (constraints.maxWidth - (cols - 1) * 14) / cols;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        for (final r in visible)
                          SizedBox(
                            width: w,
                            child: _ResourceTile(
                              resource: r,
                              exists: _exists[r.id] ?? true,
                              onOpen: () => Nav.resource(context, r.id),
                              onDelete: () async {
                                await Store.i.deleteResource(r.id);
                                AppState.i.bump();
                                _load();
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _label(String kind) => switch (kind) {
        'pdf' => 'PDFs',
        'video' => 'Video',
        'audio' => 'Audio',
        'image' => 'Images',
        'document' => 'Documents',
        'code' => 'Code',
        _ => 'Other',
      };
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({
    required this.resource,
    required this.onOpen,
    required this.onDelete,
    this.exists = true,
  });
  final LibraryResource resource;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final bool exists;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MCard(
      padding: EdgeInsets.zero,
      onTap: onOpen,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 92,
            color: c.surfaceAlt,
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    _icon(resource.kind),
                    size: 28,
                    color: exists ? c.inkMuted : c.danger,
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: PopupMenuButton<String>(
                    color: c.surface,
                    icon: Icon(Icons.more_horiz_rounded, size: 15, color: c.inkFaint),
                    onSelected: (v) {
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'delete',
                        height: 36,
                        child: Text('Remove from library',
                            style: MType.small.copyWith(color: c.danger, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                if (!exists)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.dangerSoft,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Missing',
                          style: MType.small.copyWith(color: c.danger, fontSize: 9.5)),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(resource.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MType.bodyStrong.copyWith(color: c.ink, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(
                  '${resource.kind.toUpperCase()} · ${humanFileSize(resource.size)}',
                  style: MType.small.copyWith(color: c.inkFaint, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon(String kind) => switch (kind) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'video' => Icons.movie_outlined,
        'audio' => Icons.graphic_eq_rounded,
        'image' => Icons.image_outlined,
        'code' => Icons.code_rounded,
        'document' => Icons.description_outlined,
        _ => Icons.insert_drive_file_outlined,
      };
}