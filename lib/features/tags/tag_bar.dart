import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';

Color tagColor(TagModel tag, MColors c) {
  final raw = tag.color;
  if (raw != null && raw.startsWith('#') && raw.length == 7) {
    final value = int.tryParse(raw.substring(1), radix: 16);
    if (value != null) return Color(0xFF000000 | value);
  }
  return c.inkMuted;
}

/// Tag pills for one entity, with an inline editor to create, assign, rename
/// and delete tags. Tags are purely Klaro metadata: nothing is written to the
/// files they label.
class TagBar extends StatefulWidget {
  const TagBar({
    super.key,
    required this.entityType,
    required this.entityId,
    this.compact = false,
  });

  final String entityType;
  final String entityId;
  final bool compact;

  @override
  State<TagBar> createState() => _TagBarState();
}

class _TagBarState extends State<TagBar> {
  List<TagModel> _assigned = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TagBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entityId != widget.entityId || oldWidget.entityType != widget.entityType) {
      _load();
    }
  }

  Future<void> _load() async {
    final assigned = await Store.i.tagsFor(widget.entityType, widget.entityId);
    if (!mounted) return;
    setState(() {
      _assigned = assigned;
      _loaded = true;
    });
  }

  Future<void> _openEditor() async {
    await showMSheet<void>(
      context,
      maxWidth: 460,
      child: _TagEditor(
        entityType: widget.entityType,
        entityId: widget.entityId,
        onChanged: _load,
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 24);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in _assigned) _TagPill(tag: tag, onTap: _openEditor),
        _AddTagPill(onTap: _openEditor, compact: widget.compact),
      ],
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.tag, required this.onTap});

  final TagModel tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = tagColor(tag, c);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                tag.name,
                style: MType.small.copyWith(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTagPill extends StatelessWidget {
  const _AddTagPill({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 12, color: c.inkMuted),
              const SizedBox(width: 4),
              Text(
                compact ? 'Tag' : 'Add tag',
                style: MType.small.copyWith(color: c.inkMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagEditor extends StatefulWidget {
  const _TagEditor({
    required this.entityType,
    required this.entityId,
    required this.onChanged,
  });

  final String entityType;
  final String entityId;
  final VoidCallback onChanged;

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  final _controller = TextEditingController();
  List<TagModel> _all = const [];
  Set<String> _selected = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await Store.i.tags();
    final selected = await Store.i.tagIdsFor(widget.entityType, widget.entityId);
    if (!mounted) return;
    setState(() {
      _all = all;
      _selected = selected;
    });
  }

  Future<void> _create() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    final tag = await Store.i.createTag(name);
    _controller.clear();
    await Store.i.setTagIdsFor(widget.entityType, widget.entityId, {..._selected, tag.id});
    AppState.i.bump();
    widget.onChanged();
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggle(TagModel tag) async {
    final next = {..._selected};
    if (next.contains(tag.id)) {
      next.remove(tag.id);
    } else {
      next.add(tag.id);
    }
    setState(() => _selected = next);
    await Store.i.setTagIdsFor(widget.entityType, widget.entityId, next);
    AppState.i.bump();
    widget.onChanged();
  }

  Future<void> _rename(TagModel tag) async {
    final ctrl = TextEditingController(text: tag.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename tag'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await Store.i.renameTag(tag.id, name);
    AppState.i.bump();
    widget.onChanged();
    await _load();
  }

  Future<void> _delete(TagModel tag) async {
    await Store.i.deleteTag(tag.id);
    AppState.i.bump();
    widget.onChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tags', style: MType.h2.copyWith(color: c.ink)),
          const SizedBox(height: 4),
          Text(
            'Tags only live in Klaro: adding or removing one never touches the file.',
            style: MType.small.copyWith(color: c.inkMuted, fontSize: 11.5, height: 1.45),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: MType.body.copyWith(fontSize: 13, color: c.ink),
                  decoration: const InputDecoration(hintText: 'New tag name'),
                  onSubmitted: (_) => _create(),
                ),
              ),
              const SizedBox(width: 8),
              MButton(
                label: 'Create',
                kind: MButtonKind.primary,
                dense: true,
                onPressed: _busy ? null : _create,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_all.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No tags yet. Create one above.',
                textAlign: TextAlign.center,
                style: MType.small.copyWith(color: c.inkFaint, fontSize: 12),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _all.length,
                itemBuilder: (context, i) {
                  final tag = _all[i];
                  final on = _selected.contains(tag.id);
                  final color = tagColor(tag, c);
                  return InkWell(
                    onTap: () => _toggle(tag),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: on ? color : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: on ? color : c.lineStrong,
                                width: 1.4,
                              ),
                            ),
                            child: on
                                ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tag.name,
                              style: MType.small.copyWith(color: c.ink, fontSize: 12.5),
                            ),
                          ),
                          MIconButton(
                            icon: Icons.edit_outlined,
                            tooltip: 'Rename tag',
                            size: 26,
                            onPressed: () => _rename(tag),
                          ),
                          MIconButton(
                            icon: Icons.delete_outline_rounded,
                            tooltip: 'Delete tag',
                            size: 26,
                            onPressed: () => _delete(tag),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: MButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}