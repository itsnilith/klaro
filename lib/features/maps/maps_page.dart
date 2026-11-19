import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/paths.dart';
import '../../core/state.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/ai.dart';

const _uuid = Uuid();

const _mapKinds = <(String, String, IconData)>[
  ('mindmap', 'Mind map', Icons.bubble_chart_outlined),
  ('linear', 'Hierarchical outline', Icons.format_list_bulleted_rounded),
  ('diagram', 'Flowchart / diagram', Icons.schema_outlined),
  ('timeline', 'Timeline', Icons.timeline_rounded),
];

class ConceptMapsPage extends StatefulWidget {
  const ConceptMapsPage({super.key});

  @override
  State<ConceptMapsPage> createState() => _ConceptMapsPageState();
}

class _ConceptMapsPageState extends State<ConceptMapsPage> {
  List<ConceptMapDoc> _maps = const [];
  ConceptMapDoc? _selected;
  List<ConceptNode> _nodes = const [];
  List<StudyExtract> _extracts = const [];
  String? _selectedNodeId;
  bool _loading = true;
  bool _aiBusy = false;
  double _timelinePxPerYear = 14;
  final FocusNode _canvasFocus = FocusNode();
  final TransformationController _viewCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _load();
    AppState.i.addListener(_load);
  }

  @override
  void dispose() {
    _canvasFocus.dispose();
    _viewCtrl.dispose();
    AppState.i.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final maps = await Store.i.conceptMaps();
    final extracts = await Store.i.extracts();
    ConceptMapDoc? current = _selected;
    if (current != null) {
      current = maps.where((m) => m.id == current!.id).firstOrNull;
    }
    current ??= maps.firstOrNull;
    final nodes = current == null
        ? const <ConceptNode>[]
        : await Store.i.conceptNodes(current.id);
    if (!mounted) return;
    setState(() {
      _maps = maps;
      _selected = current;
      _nodes = nodes;
      _extracts = extracts;
      _loading = false;
    });
  }

  ConceptNode? get _selectedNode =>
      _nodes.where((n) => n.id == _selectedNodeId).firstOrNull;

  // -------------------------------------------------------------- maps

  Future<void> _newMap() async {
    final titleCtrl = TextEditingController();
    var kind = 'mindmap';
    final ok = await showMSheet<bool>(
      context,
      maxWidth: 520,
      child: StatefulBuilder(
        builder: (context, setModal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New schema',
                style: MType.h2.copyWith(color: context.c.ink),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose the structure that fits the material. You build the content; the AI only helps you verify and continue.',
                style: MType.small.copyWith(
                  color: context.c.inkMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'e.g. Photosynthesis & Calvin cycle',
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in _mapKinds)
                    MChip(
                      label: k.$2,
                      icon: k.$3,
                      selected: kind == k.$1,
                      onTap: () => setModal(() => kind = k.$1),
                    ),
                ],
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
                    label: 'Create',
                    kind: MButtonKind.primary,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    final now = DateTime.now();
    final map = ConceptMapDoc(
      id: _uuid.v4(),
      title: titleCtrl.text.trim().isEmpty
          ? 'Untitled schema'
          : titleCtrl.text.trim(),
      kind: kind,
      createdAt: now,
      updatedAt: now,
    );
    await Store.i.saveConceptMap(map);
    final root = ConceptNode(
      id: _uuid.v4(),
      mapId: map.id,
      title: map.title,
      body: 'Central topic',
      x: 320,
      y: 220,
      startYear: kind == 'timeline' ? DateTime.now().year.toDouble() : null,
      endYear: kind == 'timeline' ? DateTime.now().year + 1.0 : null,
    );
    await Store.i.saveConceptNode(root);
    _selected = map;
    _selectedNodeId = root.id;
    AppState.i.bump();
    await _load();
  }

  Future<void> _setMapKind(String kind) async {
    final map = _selected;
    if (map == null) return;
    await Store.i.saveConceptMap(
      map.copyWith(kind: kind, updatedAt: DateTime.now()),
    );
    await _load();
    await _autoArrange();
  }

  // -------------------------------------------------------------- nodes

  Future<void> _addNode({
    String? parentId,
    String? presetTitle,
    String? presetBody,
    String? sourceLabel,
    String kind = 'normal',
  }) async {
    final map = _selected;
    if (map == null) return;
    final titleCtrl = TextEditingController(text: presetTitle ?? '');
    final bodyCtrl = TextEditingController(text: presetBody ?? '');
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();
    final laneCtrl = TextEditingController();

    if (presetTitle == null) {
      final ok = await showMSheet<bool>(
        context,
        maxWidth: 500,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MDialogHeader(
                title: parentId == null ? 'New node' : 'New branch',
                subtitle: 'Keep keywords and technical details concise. One idea per node.',
              ),
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Concept, keyword or event',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bodyCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Details, formula or note (optional)',
                ),
              ),
              if (map.kind == 'timeline') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: startCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Start year',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: endCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'End year',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: laneCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Level',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
                    label: 'Add',
                    kind: MButtonKind.primary,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      if (ok != true || titleCtrl.text.trim().isEmpty) return;
    }

    final parent = _nodes.where((n) => n.id == parentId).firstOrNull;
    final siblingCount = _nodes.where((n) => n.parentId == parentId).length;
    final now = DateTime.now();
    final node = ConceptNode(
      id: _uuid.v4(),
      mapId: map.id,
      parentId: parentId,
      title: titleCtrl.text.trim(),
      body: bodyCtrl.text.trim(),
      x: (parent?.x ?? 240) + 220,
      y: (parent?.y ?? 160) + siblingCount * 74 - 40,
      sourceLabel: sourceLabel,
      kind: kind,
      startYear:
          double.tryParse(startCtrl.text.trim()) ??
          (map.kind == 'timeline' ? now.year.toDouble() : null),
      endYear:
          double.tryParse(endCtrl.text.trim()) ??
          (map.kind == 'timeline' ? now.year + 1.0 : null),
      lane: int.tryParse(laneCtrl.text.trim()) ?? (parent?.lane ?? 0) + 1,
    );
    await Store.i.saveConceptNode(node);
    _selectedNodeId = node.id;
    await _load();
    await _autoArrange();
  }

  Future<void> _editNode(ConceptNode node) async {
    final titleCtrl = TextEditingController(text: node.title);
    final bodyCtrl = TextEditingController(text: node.body);
    final startCtrl = TextEditingController(
      text: node.startYear?.toString() ?? '',
    );
    final endCtrl = TextEditingController(text: node.endYear?.toString() ?? '');
    final laneCtrl = TextEditingController(text: node.lane.toString());
    final ok = await showMSheet<bool>(
      context,
      maxWidth: 520,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MDialogHeader(
              title: node.isHint ? 'Hint branch' : 'Edit node',
              subtitle: node.isHint
                  ? 'Hints stay open: the answer is written by you, never by the AI.'
                  : 'Refine the wording so it stays a schema, not a summary.',
            ),
            TextField(
              controller: titleCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Title / prompt'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bodyCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: node.isHint
                    ? 'Your answer in your own words…'
                    : 'Details or note',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: startCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Start year',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: endCtrl,
                    decoration: const InputDecoration(
                      hintText: 'End year',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: laneCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Level',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
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
                  label: 'Save',
                  kind: MButtonKind.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await Store.i.saveConceptNode(
      node.copyWith(
        title: titleCtrl.text.trim(),
        body: bodyCtrl.text.trim(),
        startYear: double.tryParse(startCtrl.text.trim()),
        endYear: double.tryParse(endCtrl.text.trim()),
        lane: int.tryParse(laneCtrl.text.trim()) ?? node.lane,
      ),
    );
    await _load();
  }

  Future<void> _deleteNode(ConceptNode node) async {
    await Store.i.deleteConceptNode(node.id);
    _selectedNodeId = null;
    await _load();
  }

  Future<void> _answerHint(ConceptNode node) async {
    final ctrl = TextEditingController(text: node.body);
    final ok = await showMSheet<bool>(
      context,
      maxWidth: 520,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MDialogHeader(title: 'Your answer', subtitle: node.title),
            Text(
              'Write the connection in your own words. This is the step that actually builds memory.',
              style: MType.small.copyWith(
                color: context.c.inkMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(hintText: 'In my own words…'),
            ),
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
                  label: 'Save answer',
                  kind: MButtonKind.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await Store.i.saveConceptNode(node.copyWith(body: ctrl.text.trim()));
    await _load();
  }

  Future<void> _linkNodes() async {
    final selected = _selectedNode;
    if (selected == null) return;
    final others = _nodes.where((n) => n.id != selected.id).toList();
    if (others.isEmpty) return;
    final labelCtrl = TextEditingController();
    ConceptNode? target;
    final labelSuggestion = await showMSheet<(ConceptNode, String)?>(
      context,
      maxWidth: 520,
      child: StatefulBuilder(
        builder: (context, setModal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Connect "${selected.title}" to…',
                style: MType.h2.copyWith(color: context.c.ink),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final n in others)
                        InkWell(
                          onTap: () => setModal(() => target = n),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: target?.id == n.id
                                  ? context.c.surfaceSunken
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(MRadius.md),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    n.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MType.body.copyWith(
                                      color: context.c.ink,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                                if (target?.id == n.id)
                                  Icon(
                                    Icons.check_rounded,
                                    size: 15,
                                    color: context.c.ink,
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  hintText:
                      'Relation label (optional, e.g. "causes", "contradicts")',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                  const SizedBox(width: 8),
                  MButton(
                    label: 'Connect',
                    kind: MButtonKind.primary,
                    onPressed: () {
                      if (target == null) return;
                      Navigator.of(context)
                          .pop((target!, labelCtrl.text.trim()));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (labelSuggestion == null) return;
    final (chosenTarget, label) = labelSuggestion;
    await Store.i.saveConceptNode(
      selected.copyWith(
        linkedNodeId: chosenTarget.id,
        linkLabel: label.isEmpty ? null : label,
      ),
    );
    await _load();
  }

  // -------------------------------------------------------------- AI next step (hints only)

  Future<void> _suggestNextStep() async {
    final map = _selected;
    final node =
        _selectedNode ?? _nodes.where((n) => n.parentId == null).firstOrNull;
    if (map == null || node == null) return;
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
    setState(() => _aiBusy = true);
    final schemaSummary = _nodes
        .map((n) => '- ${n.title}${n.body.isNotEmpty ? ' :: ${n.body}' : ''}')
        .join('\n');
    final sourceSummary = _extracts
        .take(25)
        .map(
          (e) =>
              '[${e.kind}] ${e.content}${e.description != null ? ' :: ${e.description}' : ''}',
        )
        .join('\n');
    final buf = StringBuffer();
    try {
      await AiClient().streamChat(
        provider: provider,
        messages: [
          ChatTurn(
            role: 'system',
            content:
                'You are a schema coach for a student who is building their own schema. '
                'You must NEVER provide the answer, the content, or the drawing. '
                'Instead you propose the next reasoning step as guidance: 1 to 3 short prompts '
                'that make the student think about a missing connection, an unplaced technical detail, '
                'a causal chain, or a contrasting pair. Each prompt must be a question or an instruction '
                'that ends with an empty slot the student fills in. '
                'Return ONLY a JSON array of objects with keys "prompt" and "why" '
                '(max 3 items, each prompt under 140 characters).',
          ),
          ChatTurn(
            role: 'user',
            content:
                'Schema kind: ${map.kind}\nSchema title: ${map.title}\n'
                'Selected node: ${node.title}${node.body.isNotEmpty ? ' (${node.body})' : ''}\n\n'
                'Current schema nodes:\n$schemaSummary\n\n'
                'Details the student already collected:\n$sourceSummary',
          ),
        ],
        onDelta: (d) => buf.write(d),
        onDone: () {},
        onError: (e) => buf.write('\nError: $e'),
        temperature: 0.5,
      );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }

    final raw = buf.toString();
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    final suggestions = <(String, String)>[];
    if (start >= 0 && end > start) {
      try {
        for (final item in (jsonDecode(
          raw.substring(start, end + 1),
        ) as List).whereType<Map>()) {
          final prompt = item['prompt']?.toString().trim() ?? '';
          final why = item['why']?.toString().trim() ?? '';
          if (prompt.isNotEmpty) suggestions.add((prompt, why));
        }
      } catch (_) {}
    }
    if (suggestions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No usable step was returned. Try again or refine the prompt.',
          ),
        ),
      );
      return;
    }

    var added = 0;
    for (final (prompt, why) in suggestions) {
      final parentSiblings = _nodes.where((n) => n.parentId == node.id).length;
      await Store.i.saveConceptNode(
        ConceptNode(
          id: _uuid.v4(),
          mapId: map.id,
          parentId: node.id,
          title: prompt,
          body: '',
          x: node.x + 240,
          y: node.y + parentSiblings * 86 - 40,
          kind: 'hint',
          sourceLabel: why.isEmpty ? 'Next step' : why,
          lane: node.lane + 1,
          startYear: node.startYear,
          endYear: node.endYear,
        ),
      );
      added++;
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$added guided step${added == 1 ? '' : 's'} added as open branches. '
          'Write your own answer inside each one.',
        ),
      ),
    );
  }

  // -------------------------------------------------------------- layout

  Future<void> _autoArrange() async {
    final map = _selected;
    if (map == null || _nodes.isEmpty) return;
    if (map.kind == 'timeline') {
      await _load();
      return;
    }
    final byParent = <String?, List<ConceptNode>>{};
    for (final n in _nodes) {
      byParent.putIfAbsent(n.parentId, () => []).add(n);
    }
    final positioned = <ConceptNode>[];
    if (map.kind == 'linear') {
      var rowCursor = <int, double>{};
      void walk(String? parentId, int depth) {
        final children = byParent[parentId] ?? const <ConceptNode>[];
        for (final child in children) {
          final row = rowCursor[depth] ?? 0;
          rowCursor[depth] = row + 1;
          positioned.add(
            child.copyWith(x: 60.0 + depth * 260.0, y: 60.0 + row * 96.0),
          );
          walk(child.id, depth + 1);
        }
      }

      walk(null, 0);
    } else {
      void walk(
        String? parentId,
        double x,
        double yMin,
        double yMax,
        int depth,
      ) {
        final children = byParent[parentId] ?? const <ConceptNode>[];
        if (children.isEmpty) return;
        final step = (yMax - yMin) / children.length;
        for (var i = 0; i < children.length; i++) {
          final child = children[i];
          final cy = yMin + step * (i + 0.5);
          positioned.add(child.copyWith(x: x, y: cy));
          walk(child.id, x + 260.0, cy - step / 2, cy + step / 2, depth + 1);
        }
      }

      final roots = byParent[null] ?? const <ConceptNode>[];
      final totalHeight = math.max(
        (byParent.values.fold<int>(0, (s, l) => s + l.length)) * 90.0,
        900.0,
      );
      for (var i = 0; i < roots.length; i++) {
        final root = roots[i];
        final ry = totalHeight / (roots.length + 1) * (i + 1);
        positioned.add(root.copyWith(x: 60, y: ry));
        walk(root.id, 320, 60, totalHeight - 60, 1);
      }
    }
    for (final n in positioned) {
      await Store.i.saveConceptNode(n);
    }
    await _load();
  }

  // -------------------------------------------------------------- knowledge card

  Future<void> _exportBundle() async {
    final map = _selected;
    final bundle = await Store.i.exportKnowledgeBundle(
      title: map?.title ?? 'klaro. Knowledge Card',
      courseId: map?.courseId,
      resourceId: map?.resourceId,
    );
    final fileName =
        'klaro-card-${DateTime.now().millisecondsSinceEpoch}.klaro.json';
    final outFile = File(p.join(AppPaths.i.backupsDir, fileName));
    await outFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(bundle),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Knowledge Card exported to ${outFile.path}')),
    );
  }

  Future<void> _importBundle() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import a klaro. Knowledge Card (.json)',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = res?.files.single.path;
    if (path == null) return;
    try {
      final raw =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final counts = await Store.i.importKnowledgeBundle(
        raw.cast<String, Object?>(),
      );
      AppState.i.bump();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${counts['maps']} schemas, ${counts['notes']} notes, '
            '${counts['extracts']} extracts, ${counts['cards']} flashcards.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not import card: $e')));
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sidebar = MCard(
      padding: EdgeInsets.zero,
      radius: MRadius.xl,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 12),
            child: Row(
              children: [
                Text(
                  'Schemas',
                  style: MType.h2.copyWith(color: c.ink, fontSize: 19),
                ),
                const Spacer(),
                MButton(
                  label: 'New',
                  icon: Icons.add_rounded,
                  kind: MButtonKind.primary,
                  dense: true,
                  onPressed: _newMap,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: MButton(
                    label: 'Share Card',
                    icon: Icons.ios_share_rounded,
                    dense: true,
                    onPressed: _exportBundle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: MButton(
                    label: 'Import',
                    icon: Icons.download_rounded,
                    dense: true,
                    onPressed: _importBundle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'YOUR SCHEMAS',
              style: MType.label.copyWith(color: c.inkFaint, fontSize: 9.5),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            flex: 3,
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _maps.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Create a schema to organise keywords, formulas and events in your own structure.',
                      style: MType.small.copyWith(color: c.inkMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: _maps.length,
                    itemBuilder: (context, i) {
                      final m = _maps[i];
                      final sel = m.id == _selected?.id;
                      final kindIcon = _mapKinds
                          .where((k) => k.$1 == m.kind)
                          .map((k) => k.$3)
                          .firstOrNull;
                      return InkWell(
                        onTap: () async {
                          _selected = m;
                          _selectedNodeId = null;
                          AppState.i.setActiveWorkspaceContext(
                            section: 'Schema editor',
                            mapId: m.id,
                          );
                          final nodes = await Store.i.conceptNodes(m.id);
                          if (mounted) setState(() => _nodes = nodes);
                        },
                        borderRadius: BorderRadius.circular(MRadius.md),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: sel ? c.surfaceSunken : Colors.transparent,
                            borderRadius: BorderRadius.circular(MRadius.md),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                kindIcon ?? Icons.account_tree_outlined,
                                size: 15,
                                color: sel ? c.ink : c.inkMuted,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  m.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: MType.small.copyWith(
                                    color: sel ? c.ink : c.inkMuted,
                                    fontWeight: sel
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const MDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              'COLLECTED DETAILS (${_extracts.length})',
              style: MType.label.copyWith(color: c.inkFaint, fontSize: 9.5),
            ),
          ),
          Expanded(
            flex: 2,
            child: _extracts.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Keywords, formulas and questions saved while reading appear here. Tap one to drop it into the schema.',
                      style: MType.small.copyWith(
                        color: c.inkFaint,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: _extracts.length,
                    itemBuilder: (context, i) {
                      final ex = _extracts[i];
                      return InkWell(
                        onTap: () => _addNode(
                          parentId: _selectedNodeId,
                          presetTitle: ex.content,
                          presetBody: ex.description ?? '',
                          sourceLabel: ex.page != null
                              ? 'p. ${ex.page}'
                              : ex.kind.toUpperCase(),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: c.surfaceAlt,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: c.line),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                ex.kind == 'formula'
                                    ? Icons.functions_rounded
                                    : ex.kind == 'quote'
                                    ? Icons.format_quote_rounded
                                    : ex.kind == 'question'
                                    ? Icons.help_outline_rounded
                                    : Icons.label_outline_rounded,
                                size: 13,
                                color: c.ink,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  ex.content,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ex.kind == 'formula'
                                      ? MType.mono.copyWith(
                                          fontSize: 11,
                                          color: c.ink,
                                        )
                                      : MType.small.copyWith(
                                          fontSize: 11,
                                          color: c.ink,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
    final pane = MCard(
      padding: EdgeInsets.zero,
      radius: MRadius.xl,
      clip: true,
      child: _selected == null
          ? Center(
              child: MEmpty(
                framed: false,
                icon: Icons.account_tree_outlined,
                title: 'Build your own concept maps',
                message: 'Mind maps, hierarchical outlines, flowcharts and timelines. The AI suggests guiding questions — the structure stays yours.',
                action: MButton(
                  label: 'Create first schema',
                  kind: MButtonKind.primary,
                  onPressed: _newMap,
                ),
              ),
            )
          : _canvas(context),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 28, 22),
      child: LayoutBuilder(
        builder: (context, cons) {
          if (cons.maxWidth < 820) {
            return Column(
              children: [
                SizedBox(height: 220, child: sidebar),
                const SizedBox(height: 12),
                Expanded(child: pane),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 268, child: sidebar),
              const SizedBox(width: 16),
              Expanded(child: pane),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------- canvas

  Widget _canvas(BuildContext context) {
    final c = context.c;
    final map = _selected!;
    return Focus(
      focusNode: _canvasFocus,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final selected = _selectedNode;
        if (event.logicalKey == LogicalKeyboardKey.tab && selected != null) {
          _addNode(parentId: selected.id);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter && selected != null) {
          _addNode(parentId: selected.parentId);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.delete && selected != null) {
          _deleteNode(selected);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        map.title,
                        style: MType.h3.copyWith(color: c.ink, fontSize: 15),
                      ),
                      Text(
                        'Tab: branch child · Enter: sibling · Del: delete · drag to arrange',
                        style: MType.small.copyWith(
                          color: c.inkFaint,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final k in _mapKinds)
                      MChip(
                        label: k.$2,
                        icon: k.$3,
                        selected: map.kind == k.$1,
                        onTap: () => _setMapKind(k.$1),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                MButton(
                  label: _aiBusy ? 'Thinking…' : 'Next guided step',
                  icon: Icons.auto_awesome_outlined,
                  kind: MButtonKind.primary,
                  dense: true,
                  onPressed: _aiBusy ? null : _suggestNextStep,
                ),
                const SizedBox(width: 8),
                MButton(
                  label: 'Add node',
                  icon: Icons.add_circle_outline_rounded,
                  dense: true,
                  onPressed: () => _addNode(),
                ),
                const SizedBox(width: 8),
                if (_selectedNode != null)
                  MButton(
                    label: 'Branch child',
                    icon: Icons.subdirectory_arrow_right_rounded,
                    dense: true,
                    onPressed: () => _addNode(parentId: _selectedNode!.id),
                  ),
                const SizedBox(width: 8),
                if (_selectedNode != null)
                  MButton(
                    label: 'Add hint',
                    icon: Icons.help_outline_rounded,
                    dense: true,
                    onPressed: () =>
                        _addNode(parentId: _selectedNode!.id, kind: 'hint'),
                  ),
                const SizedBox(width: 8),
                if (map.kind == 'diagram' && _selectedNode != null)
                  MButton(
                    label: 'Connect to…',
                    icon: Icons.timeline_rounded,
                    dense: true,
                    onPressed: _linkNodes,
                  ),
                const Spacer(),
                if (map.kind == 'timeline') ...[
                  Text(
                    'Zoom',
                    style: MType.small.copyWith(
                      color: c.inkMuted,
                      fontSize: 11,
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Slider(
                      value: _timelinePxPerYear,
                      min: 3,
                      max: 90,
                      onChanged: (v) => setState(() => _timelinePxPerYear = v),
                    ),
                  ),
                  Text(
                    '${_timelinePxPerYear.round()} px/yr',
                    style: MType.small.copyWith(
                      color: c.inkFaint,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                MIconButton(
                  icon: Icons.zoom_out_rounded,
                  tooltip: 'Zoom out',
                  onPressed: () => _zoomBy(0.85),
                ),
                MIconButton(
                  icon: Icons.zoom_in_rounded,
                  tooltip: 'Zoom in',
                  onPressed: () => _zoomBy(1.18),
                ),
                MIconButton(
                  icon: Icons.center_focus_strong_rounded,
                  tooltip: 'Reset view',
                  onPressed: () => _viewCtrl.value = Matrix4.identity(),
                ),
                const SizedBox(width: 6),
                MButton(
                  label: 'Auto-arrange',
                  icon: Icons.auto_fix_high_rounded,
                  dense: true,
                  onPressed: _autoArrange,
                ),
                const SizedBox(width: 6),
                MIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete schema',
                  onPressed: () async {
                    await Store.i.deleteConceptMap(map.id);
                    _selected = null;
                    await _load();
                  },
                ),
              ],
            ),
          ),
          Expanded(child: _canvasBody(map, c)),
        ],
      ),
    );
  }

  void _zoomBy(double factor) {
    final current = _viewCtrl.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.25, 3.0);
    _viewCtrl.value = Matrix4.diagonal3Values(next, next, 1.0);
  }

  Widget _canvasBody(ConceptMapDoc map, MColors c) {
    if (map.kind == 'timeline') {
      return _timelineCanvas(map, c);
    }
    return Container(
      color: c.surfaceSunken,
      child: InteractiveViewer(
        transformationController: _viewCtrl,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(600),
        minScale: 0.25,
        maxScale: 3.0,
        child: SizedBox(
          width: 2600,
          height: 1700,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _EdgesPainter(
                    nodes: _nodes,
                    lineColor: c.lineStrong,
                    accent: c.ink,
                    dashed: c.inkFaint,
                  ),
                ),
              ),
              for (final node in _nodes)
                Positioned(
                  left: node.x,
                  top: node.y,
                  child: _NodeCard(
                    node: node,
                    selected: _selectedNodeId == node.id,
                    onSelect: () {
                      _canvasFocus.requestFocus();
                      setState(() => _selectedNodeId = node.id);
                    },
                    onMove: (dx, dy) {
                      setState(() {
                        _nodes = [
                          for (final n in _nodes)
                            if (n.id == node.id)
                              n.copyWith(
                                x: (n.x + dx).clamp(8, 2500),
                                y: (n.y + dy).clamp(8, 1600),
                              )
                            else
                              n,
                        ];
                      });
                    },
                    onMoveEnd: () async {
                      final current = _nodes
                          .where((n) => n.id == node.id)
                          .firstOrNull;
                      if (current != null) {
                        await Store.i.saveConceptNode(current);
                      }
                    },
                    onEdit: () => _editNode(node),
                    onDelete: () => _deleteNode(node),
                    onAnswer: () => _answerHint(node),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timelineCanvas(ConceptMapDoc map, MColors c) {
    final dated = _nodes.where((n) => n.startYear != null).toList();
    final minYear = dated.isEmpty
        ? DateTime.now().year.toDouble()
        : dated.map((n) => n.startYear!).reduce(math.min);
    final maxYear = dated.isEmpty
        ? DateTime.now().year + 5.0
        : dated.map((n) => n.endYear ?? n.startYear!).reduce(math.max);
    final origin = math.min(minYear, maxYear) - 1.0;
    final span = math.max<double>(maxYear - origin + 1.0, 4.0);
    final width = (span * _timelinePxPerYear) + 320;
    final lanes = _nodes.isEmpty
        ? 2
        : _nodes.map((n) => n.lane).reduce(math.max) + 1;
    final height = math.max(lanes * 110.0 + 160, 520.0);

    return Container(
      color: c.surfaceSunken,
      child: InteractiveViewer(
        transformationController: _viewCtrl,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(400),
        minScale: 0.3,
        maxScale: 2.5,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _TimelineAxisPainter(
                    origin: origin,
                    span: span,
                    pxPerYear: _timelinePxPerYear,
                    gridColor: c.line,
                    textColor: c.inkFaint,
                  ),
                ),
              ),
              for (final node in _nodes)
                Positioned(
                  left:
                      120 +
                      ((node.startYear ?? origin) - origin) *
                          _timelinePxPerYear,
                  top: 56 + node.lane * 110.0,
                  child: SizedBox(
                    width: math.max(
                      90,
                      (((node.endYear ?? (node.startYear ?? origin) + 1) -
                                      (node.startYear ?? origin)) *
                                  _timelinePxPerYear)
                              .abs() +
                          24,
                    ),
                    child: _NodeCard(
                      node: node,
                      selected: _selectedNodeId == node.id,
                      compact: true,
                      onSelect: () {
                        _canvasFocus.requestFocus();
                        setState(() => _selectedNodeId = node.id);
                      },
                      onMove: (dx, dy) {},
                      onMoveEnd: () async {},
                      onEdit: () => _editNode(node),
                      onDelete: () => _deleteNode(node),
                      onAnswer: () => _answerHint(node),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeCard extends StatefulWidget {
  const _NodeCard({
    required this.node,
    required this.selected,
    required this.onSelect,
    required this.onMove,
    required this.onMoveEnd,
    required this.onEdit,
    required this.onDelete,
    required this.onAnswer,
    this.compact = false,
  });

  final ConceptNode node;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(double dx, double dy) onMove;
  final Future<void> Function() onMoveEnd;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAnswer;
  final bool compact;

  @override
  State<_NodeCard> createState() => _NodeCardState();
}

class _NodeCardState extends State<_NodeCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final node = widget.node;
    final isHint = node.isHint;
    final answered = isHint && node.body.trim().isNotEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.move,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        onDoubleTap: widget.onEdit,
        onPanUpdate: (d) => widget.onMove(d.delta.dx, d.delta.dy),
        onPanEnd: (_) => widget.onMoveEnd(),
        child: Container(
          constraints: BoxConstraints(
            minWidth: widget.compact ? 90 : 170,
            maxWidth: widget.compact ? 240 : 250,
          ),
          padding: const EdgeInsets.fromLTRB(13, 10, 11, 10),
          decoration: BoxDecoration(
            color: isHint ? (answered ? c.surfaceAlt : c.surface) : c.surface,
            borderRadius: BorderRadius.circular(MRadius.md),
            border: Border.all(
              color: widget.selected
                  ? c.ink
                  : isHint
                  ? c.lineStrong
                  : c.line,
              width: widget.selected ? 1.8 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: context.elevationShadow(
                  _hover ? 0.10 : 0.05,
                  darkAlpha: _hover ? 0.36 : 0.28,
                ),
                blurRadius: _hover ? 18 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (isHint)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        answered
                            ? Icons.check_circle_outline_rounded
                            : Icons.help_outline_rounded,
                        size: 13,
                        color: c.ink,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      node.title,
                      style: MType.bodyStrong.copyWith(
                        color: c.ink,
                        fontSize: widget.compact ? 11.5 : 12.5,
                      ),
                    ),
                  ),
                  if (_hover) ...[
                    InkWell(
                      onTap: widget.onEdit,
                      child: Icon(
                        Icons.edit_outlined,
                        size: 12,
                        color: c.inkFaint,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: widget.onDelete,
                      child: Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: c.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
              if (node.body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  node.body,
                  maxLines: widget.compact ? 3 : 6,
                  overflow: TextOverflow.ellipsis,
                  style: MType.small.copyWith(
                    color: answered ? c.ink : c.inkMuted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
              if (isHint && !answered) ...[
                const SizedBox(height: 8),
                MButton(
                  label: 'Write your answer',
                  icon: Icons.edit_note_rounded,
                  dense: true,
                  onPressed: widget.onAnswer,
                ),
              ],
              if (node.sourceLabel != null) ...[
                const SizedBox(height: 5),
                Text(
                  node.sourceLabel!,
                  style: MType.small.copyWith(color: c.inkFaint, fontSize: 9.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.nodes,
    required this.lineColor,
    required this.accent,
    required this.dashed,
  });

  final List<ConceptNode> nodes;
  final Color lineColor;
  final Color accent;
  final Color dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (final n in nodes) n.id: n};
    final solid = Paint()
      ..color = accent.withValues(alpha: 0.42)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final relation = Paint()
      ..color = lineColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    for (final n in nodes) {
      if (n.parentId == null) continue;
      final parent = byId[n.parentId!];
      if (parent == null) continue;
      _drawCurve(canvas, parent, n, n.isHint ? _dashPaint(dashed, 1.6) : solid);
    }
    for (final n in nodes) {
      if (n.linkedNodeId == null) continue;
      final other = byId[n.linkedNodeId!];
      if (other == null) continue;
      _drawCurve(
        canvas,
        n,
        other,
        _dashPaint(relation.color, 1.3),
        fromRight: false,
      );
      if (n.linkLabel != null && n.linkLabel!.isNotEmpty) {
        final mid = Offset((n.x + other.x) / 2 + 90, (n.y + other.y) / 2 + 24);
        final tp = TextPainter(
          text: TextSpan(
            text: n.linkLabel,
            style: TextStyle(
              fontSize: 10,
              color: relation.color,
              fontFamily: 'Inter',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, mid);
      }
    }
  }

  void _drawCurve(
    Canvas canvas,
    ConceptNode from,
    ConceptNode to,
    Paint paint, {
    bool fromRight = true,
  }) {
    final p1 = Offset(from.x + (fromRight ? 200 : 0), from.y + 26);
    final p2 = Offset(to.x + (fromRight ? 0 : 200), to.y + 26);
    final midX = (p1.dx + p2.dx) / 2;
    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(midX, p1.dy, midX, p2.dy, p2.dx, p2.dy),
      paint,
    );
  }

  Paint _dashPaint(Color color, double width) => Paint()
    ..color = color
    ..strokeWidth = width
    ..style = PaintingStyle.stroke;

  @override
  bool shouldRepaint(covariant _EdgesPainter old) =>
      old.nodes != nodes ||
      old.lineColor != lineColor ||
      old.accent != accent ||
      old.dashed != dashed;
}

class _TimelineAxisPainter extends CustomPainter {
  _TimelineAxisPainter({
    required this.origin,
    required this.span,
    required this.pxPerYear,
    required this.gridColor,
    required this.textColor,
  });

  final double origin;
  final double span;
  final double pxPerYear;
  final Color gridColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final majorPaint = Paint()
      ..color = gridColor.withValues(alpha: 1.0)
      ..strokeWidth = 1.4;
    final labelEvery = pxPerYear < 8
        ? 10
        : pxPerYear < 18
        ? 5
        : pxPerYear < 40
        ? 2
        : 1;

    for (var i = 0; i <= span.ceil() + 1; i++) {
      final year = origin + i;
      final x = 120 + i * pxPerYear;
      if (x > size.width) break;
      final isMajor = year % labelEvery == 0;
      canvas.drawLine(
        Offset(x, 40),
        Offset(x, size.height - 20),
        isMajor ? majorPaint : gridPaint,
      );
      if (isMajor) {
        final tp = TextPainter(
          text: TextSpan(
            text: year.toInt().toString(),
            style: TextStyle(
              fontSize: 10.5,
              color: textColor,
              fontFamily: 'Inter',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 3, 18));
      }
    }
    canvas.drawLine(
      Offset(120, 40),
      Offset(size.width, 40),
      Paint()
        ..color = gridColor
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TimelineAxisPainter old) =>
      old.pxPerYear != pxPerYear ||
      old.span != span ||
      old.origin != origin ||
      old.gridColor != gridColor ||
      old.textColor != textColor;
}
