import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/ai.dart';
import '../../services/rag.dart';
import '../shell.dart';
import '../shell_dialogs.dart';

const _uuid = Uuid();

class ResourceViewerPage extends StatefulWidget {
  const ResourceViewerPage({super.key, required this.resourceId});
  final String resourceId;

  @override
  State<ResourceViewerPage> createState() => _ResourceViewerPageState();
}

class _ResourceViewerPageState extends State<ResourceViewerPage> {
  LibraryResource? _resource;
  List<Note> _notes = const [];
  List<StudyExtract> _extracts = const [];
  int _page = 1;
  bool _indexing = false;
  bool _focusMode = false;
  int _sideTab = 0; // 0: Notes, 1: Keywords & Formulas, 2: Passage AI
  String? _indexMessage;
  String _text = '';
  String _aiOutput = '';
  bool _aiBusy = false;
  final _passageCtrl = TextEditingController();
  Player? _player;
  VideoController? _video;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _passageCtrl.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await Store.i.resource(widget.resourceId);
    if (r == null) return;
    await Store.i.touchResource(r.id);
    final notes = await Store.i.notes();
    final mine = notes.where((n) => n.resourceId == r.id).toList();
    final extracts = await Store.i.extracts(resourceId: r.id);
    if (r.kind == 'document' || r.kind == 'code') {
      try {
        _text = await File(r.path).readAsString();
      } catch (_) {}
    }
    if ((r.kind == 'video' || r.kind == 'audio') && File(r.path).existsSync()) {
      _player = Player();
      _video = VideoController(_player!);
      await _player!.open(Media(r.path));
    }
    if (!mounted) return;
    setState(() {
      _resource = r;
      _notes = mine;
      _extracts = extracts;
    });
  }

  Future<void> _index() async {
    final r = _resource;
    if (r == null) return;
    setState(() {
      _indexing = true;
      _indexMessage = 'Reading the document…';
    });
    try {
      final provider = await Store.i.defaultProvider();
      final rag = RagService(Store.i, AiClient());
      if (r.kind == 'pdf') {
        await rag.indexPdf(
          resourceId: r.id,
          title: r.title,
          path: r.path,
          provider: provider,
          onProgress: (page, total) {
            if (mounted)
              setState(() => _indexMessage = 'Indexing page $page of $total…');
          },
        );
      } else if (r.kind == 'document' || r.kind == 'code') {
        await rag.indexTextFile(
          resourceId: r.id,
          title: r.title,
          path: r.path,
          provider: provider,
        );
      } else {
        if (mounted) setState(() => _indexing = false);
        return;
      }
      if (mounted) {
        setState(() {
          _indexing = false;
          _indexMessage = provider?.embeddingModel == null
              ? 'Indexed for keyword retrieval. Add an embedding model to enable semantic search.'
              : 'Indexed with embeddings.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _indexing = false;
          _indexMessage = 'Indexing failed: $e';
        });
      }
    }
  }

  Future<void> _note() async {
    final r = _resource;
    if (r == null) return;
    await showNoteEditor(
      context,
      courseId: r.courseId,
      resourceId: r.id,
      page: r.kind == 'pdf' ? _page : null,
      initialBody: r.kind == 'pdf' ? 'Page $_page — ' : null,
    );
    final notes = await Store.i.notes();
    if (mounted)
      setState(
        () => _notes = notes.where((n) => n.resourceId == r.id).toList(),
      );
  }

  Future<void> _addExtract(String kind) async {
    final r = _resource;
    if (r == null) return;
    final contentCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final tagsCtrl = TextEditingController();
    final title = switch (kind) {
      'formula' => 'Collect formula (LaTeX)',
      'quote' => 'Collect key sentence',
      'question' => 'Collect study question',
      _ => 'Collect keyword',
    };
    final hint = switch (kind) {
      'formula' => r'e.g. Q = \Delta m c^2 = (m_i - m_f) c^2',
      'quote' => 'Paste or write the key passage from this page…',
      'question' => 'e.g. Why does chlorophyll absorb red and blue light?',
      _ => 'e.g. uranium-235, Calvin cycle, chlorophyll',
    };
    final ok = await showMSheet<bool>(
      context,
      maxWidth: 480,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: MType.h2.copyWith(color: context.c.ink)),
            const SizedBox(height: 4),
            Text(
              r.kind == 'pdf'
                  ? 'Linked to ${r.title} · page $_page'
                  : 'Linked to ${r.title}',
              style: MType.small.copyWith(color: context.c.inkMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: contentCtrl,
              autofocus: true,
              style: kind == 'formula' ? MType.mono : MType.body,
              decoration: InputDecoration(hintText: hint),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Explanation in your own words (optional)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tagsCtrl,
              decoration: const InputDecoration(
                hintText: 'Tags, comma-separated (optional)',
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
                  label: 'Save to collection',
                  kind: MButtonKind.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || contentCtrl.text.trim().isEmpty) return;
    await Store.i.saveExtract(
      StudyExtract(
        id: _uuid.v4(),
        kind: kind,
        content: contentCtrl.text.trim(),
        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        tags: tagsCtrl.text.trim(),
        courseId: r.courseId,
        resourceId: r.id,
        page: r.kind == 'pdf' ? _page : null,
        createdAt: DateTime.now(),
      ),
    );
    if (kind == 'question' && descCtrl.text.trim().isNotEmpty) {
      await Store.i.saveCard(
        Flashcard(
          id: _uuid.v4(),
          deck: r.title,
          front: contentCtrl.text.trim(),
          back: descCtrl.text.trim(),
          courseId: r.courseId,
          resourceId: r.id,
          page: r.kind == 'pdf' ? _page : null,
          dueAt: DateTime.now(),
          createdAt: DateTime.now(),
        ),
      );
    }
    AppState.i.bump();
    final extracts = await Store.i.extracts(resourceId: r.id);
    if (mounted) {
      setState(() {
        _extracts = extracts;
        _sideTab = 1;
      });
    }
  }

  Future<void> _runPassageAction(String action) async {
    final passage = _passageCtrl.text.trim();
    if (passage.isEmpty || _aiBusy) return;
    final provider = await Store.i.defaultProvider();
    if (provider == null) {
      setState(
        () => _aiOutput =
            'Configure a local or cloud AI provider in Settings first.',
      );
      return;
    }
    setState(() {
      _aiBusy = true;
      _aiOutput = '';
    });
    final instruction = switch (action) {
      'simplify' => 'Simplify this passage in clear, plain language without losing technical accuracy.',
      'explain' => 'Explain the underlying mechanism of this passage step by step, using an analogy.',
      'translate' => 'Translate this passage between English and Italian and clarify technical terms.',
      'questions' => 'Generate 3 active-recall questions and concise answers from this passage.',
      'keywords' =>
        'Identify the core takeaway of this passage and extract: '
            '(1) concise key concepts (short terms and relationships) for notes or outlines, and '
            '(2) exact technical details (formulas, numbers, dates, definitions) worth remembering.',
      _ => 'Summarize the core idea of this passage.',
    };
    final buf = StringBuffer();
    await AiClient().streamChat(
      provider: provider,
      messages: [
        ChatTurn(
          role: 'system',
          content:
              'You are klaro. Tutor assisting a student reading "${_resource?.title}" (page $_page). $instruction',
        ),
        ChatTurn(role: 'user', content: passage),
      ],
      onDelta: (d) {
        buf.write(d);
        if (mounted) setState(() => _aiOutput = buf.toString());
      },
      onDone: () {
        if (mounted) setState(() => _aiBusy = false);
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _aiBusy = false;
            _aiOutput = 'Error: $e';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = _resource;
    if (r == null) {
      return Scaffold(
        backgroundColor: c.canvas,
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final exists = File(r.path).existsSync();
    return Scaffold(
      backgroundColor: c.canvas,
      body: Column(
        children: [
          Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                MButton(
                  label: 'Library',
                  icon: Icons.arrow_back_rounded,
                  kind: MButtonKind.ghost,
                  dense: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MType.bodyStrong.copyWith(
                          color: c.ink,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        r.kind == 'pdf'
                            ? 'PDF · page $_page'
                            : '${r.kind.toUpperCase()} · ${humanFileSize(r.size)}',
                        style: MType.small.copyWith(
                          color: c.inkFaint,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                MIconButton(
                  icon: _focusMode
                      ? Icons.fullscreen_exit_rounded
                      : Icons.center_focus_strong_outlined,
                  tooltip: _focusMode
                      ? 'Exit Focus mode'
                      : 'Focus mode (hide side panel)',
                  selected: _focusMode,
                  onPressed: () => setState(() => _focusMode = !_focusMode),
                ),
                const SizedBox(width: 6),
                MButton(
                  label: 'Question',
                  icon: Icons.help_outline_rounded,
                  dense: true,
                  onPressed: () => _addExtract('question'),
                ),
                const SizedBox(width: 6),
                MButton(
                  label: 'Keyword',
                  icon: Icons.label_outline_rounded,
                  dense: true,
                  onPressed: () => _addExtract('keyword'),
                ),
                const SizedBox(width: 6),
                MButton(
                  label: 'Formula LaTeX',
                  icon: Icons.functions_rounded,
                  dense: true,
                  onPressed: () => _addExtract('formula'),
                ),
                const SizedBox(width: 6),
                if (r.kind == 'pdf' || r.kind == 'document' || r.kind == 'code')
                  MButton(
                    label: _indexing ? 'Indexing…' : 'Index for tutor',
                    icon: Icons.auto_awesome_outlined,
                    dense: true,
                    onPressed: _indexing ? null : _index,
                  ),
                const SizedBox(width: 8),
                MButton(
                  label: r.kind == 'pdf' ? 'Note p. $_page' : 'Note',
                  icon: Icons.note_add_outlined,
                  dense: true,
                  kind: MButtonKind.primary,
                  onPressed: _note,
                ),
              ],
            ),
          ),
          if (_indexMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color: c.surfaceAlt,
              child: Text(
                _indexMessage!,
                style: MType.small.copyWith(color: c.inkMuted, fontSize: 11),
              ),
            ),
          Expanded(
            child: !exists
                ? Center(
                    child: MEmpty(
                      framed: false,
                      icon: Icons.link_off_rounded,
                      title: 'File not found',
                      message:
                          'klaro. references files where they are. This one moved or was deleted.\n\n${r.path}',
                      action: MButton(
                        label: 'Reveal folder',
                        onPressed: () =>
                            launchUrl(Uri.file(File(r.path).parent.path)),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(child: _body(r)),
                      if (!_focusMode) _sidePanel(r),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _body(LibraryResource r) {
    final c = context.c;
    switch (r.kind) {
      case 'pdf':
        return Container(
          color: c.surfaceSunken,
          child: PdfViewer.file(
            r.path,
            params: PdfViewerParams(
              backgroundColor: c.surfaceSunken,
              margin: 10,
              onPageChanged: (page) {
                final p = page ?? _page;
                if (mounted && p != _page) setState(() => _page = p);
              },
            ),
          ),
        );
      case 'image':
        return Container(
          color: c.surfaceSunken,
          child: InteractiveViewer(
            maxScale: 6,
            child: Center(child: Image.file(File(r.path))),
          ),
        );
      case 'video':
      case 'audio':
        return Container(
          color: Colors.black,
          child: Center(
            child: _player == null
                ? const CircularProgressIndicator(strokeWidth: 2)
                : r.kind == 'video'
                ? Video(controller: _video!, controls: AdaptiveVideoControls)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.graphic_eq_rounded,
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        r.title,
                        style: MType.body.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 20),
                      _AudioControls(player: _player!),
                    ],
                  ),
          ),
        );
      case 'document':
      case 'code':
        return Container(
          color: c.surface,
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                _text.isEmpty ? 'This file could not be read as text.' : _text,
                style: r.kind == 'code'
                    ? MType.mono.copyWith(color: c.ink, fontSize: 12.5)
                    : MType.body.copyWith(
                        color: c.ink,
                        height: 1.65,
                        fontSize: 13.5,
                      ),
              ),
            ),
          ),
        );
      default:
        return Center(
          child: MEmpty(
            framed: false,
            icon: Icons.open_in_new_rounded,
            title: 'Preview not available',
            message: 'This format opens in its default application.',
            action: MButton(
              label: 'Open file',
              kind: MButtonKind.primary,
              onPressed: () => launchUrl(Uri.file(r.path)),
            ),
          ),
        );
    }
  }

  Widget _sidePanel(LibraryResource r) {
    final c = context.c;
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        border: Border(left: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                MChip(
                  label: 'Notes (${_notes.length})',
                  selected: _sideTab == 0,
                  onTap: () => setState(() => _sideTab = 0),
                ),
                const SizedBox(width: 4),
                MChip(
                  label: 'Extracts (${_extracts.length})',
                  selected: _sideTab == 1,
                  onTap: () => setState(() => _sideTab = 1),
                ),
                const SizedBox(width: 4),
                MChip(
                  label: 'Tutor',
                  selected: _sideTab == 2,
                  onTap: () => setState(() => _sideTab = 2),
                ),
              ],
            ),
          ),
          Expanded(
            child: _sideTab == 0
                ? _buildNotesList(r, c)
                : _sideTab == 1
                ? _buildExtractsList(c)
                : _buildPassageTutor(r, c),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesList(LibraryResource r, MColors c) {
    if (_notes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          r.kind == 'pdf'
              ? 'Write a note on the page you are reading. It keeps the page number.'
              : 'Notes attached to this file appear here.',
          style: MType.small.copyWith(
            color: c.inkMuted,
            height: 1.5,
            fontSize: 11.5,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _notes.length,
      itemBuilder: (context, i) {
        final n = _notes[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(MSpace.x2),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (n.page != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'PAGE ${n.page}',
                    style: MType.label.copyWith(color: c.accent, fontSize: 8.5),
                  ),
                ),
              Text(
                n.title,
                style: MType.bodyStrong.copyWith(color: c.ink, fontSize: 11.5),
              ),
              const SizedBox(height: 3),
              Text(
                n.body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: MType.small.copyWith(color: c.inkMuted, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExtractsList(MColors c) {
    if (_extracts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Collect keywords, LaTeX formulas and key quotes while reading. Each stays linked to its exact page.',
          style: MType.small.copyWith(
            color: c.inkMuted,
            height: 1.5,
            fontSize: 11.5,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _extracts.length,
      itemBuilder: (context, i) {
        final ex = _extracts[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(MSpace.x2),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${ex.kind.toUpperCase()}${ex.page != null ? ' · P. ${ex.page}' : ''}',
                    style: MType.label.copyWith(color: c.accent, fontSize: 8.5),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () async {
                      await Store.i.deleteExtract(ex.id);
                      final list = await Store.i.extracts(
                        resourceId: widget.resourceId,
                      );
                      if (mounted) setState(() => _extracts = list);
                    },
                    child: Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: c.inkFaint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                ex.content,
                style: ex.kind == 'formula'
                    ? MType.mono.copyWith(color: c.ink, fontSize: 12)
                    : MType.bodyStrong.copyWith(color: c.ink, fontSize: 12),
              ),
              if (ex.description != null) ...[
                const SizedBox(height: 3),
                Text(
                  ex.description!,
                  style: MType.small.copyWith(color: c.inkMuted, fontSize: 11),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  MChip(
                    label: '+ Flashcard',
                    icon: Icons.style_outlined,
                    onTap: () async {
                      await Store.i.saveCard(
                        Flashcard(
                          id: _uuid.v4(),
                          deck: _resource?.title ?? 'Library',
                          front: ex.kind == 'question'
                              ? ex.content
                              : 'Explain "${ex.content}" (${_resource?.title ?? 'source'}${ex.page != null ? ', p. ${ex.page}' : ''})',
                          back: ex.description?.isNotEmpty == true
                              ? ex.description!
                              : ex.content,
                          courseId: ex.courseId,
                          resourceId: ex.resourceId,
                          page: ex.page,
                          dueAt: DateTime.now(),
                          createdAt: DateTime.now(),
                        ),
                      );
                      AppState.i.bump();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Added to your Review flashcards.'),
                          ),
                        );
                      }
                    },
                  ),
                  MChip(
                    label: '+ Map Node',
                    icon: Icons.account_tree_outlined,
                    onTap: () async {
                      final maps = await Store.i.conceptMaps();
                      ConceptMapDoc target;
                      if (maps.isEmpty) {
                        final now = DateTime.now();
                        target = ConceptMapDoc(
                          id: _uuid.v4(),
                          title: _resource?.title ?? 'Study Schema',
                          courseId: ex.courseId,
                          resourceId: ex.resourceId,
                          createdAt: now,
                          updatedAt: now,
                        );
                        await Store.i.saveConceptMap(target);
                      } else {
                        target = maps.first;
                      }
                      final existing = await Store.i.conceptNodes(target.id);
                      await Store.i.saveConceptNode(
                        ConceptNode(
                          id: _uuid.v4(),
                          mapId: target.id,
                          parentId: existing.firstOrNull?.id,
                          title: ex.content,
                          body: ex.description ?? '',
                          x: 240.0 + (existing.length % 4) * 160.0,
                          y: 120.0 + (existing.length ~/ 4) * 100.0,
                          sourceLabel: ex.page != null
                              ? 'p. ${ex.page}'
                              : ex.kind.toUpperCase(),
                        ),
                      );
                      AppState.i.bump();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Added node to schema "${target.title}".',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPassageTutor(LibraryResource r, MColors c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Paste or type a sentence or formula from page $_page:',
            style: MType.small.copyWith(color: c.inkMuted, fontSize: 11),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _passageCtrl,
            minLines: 3,
            maxLines: 5,
            style: MType.small.copyWith(color: c.ink, fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Ask on this sentence…',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              MChip(
                label: 'Pinpoint & Keywords',
                tone: MChipTone.accent,
                onTap: () => _runPassageAction('keywords'),
              ),
              MChip(
                label: 'Explain',
                tone: MChipTone.accent,
                onTap: () => _runPassageAction('explain'),
              ),
              MChip(
                label: 'Simplify',
                tone: MChipTone.accent,
                onTap: () => _runPassageAction('simplify'),
              ),
              MChip(
                label: 'Questions',
                tone: MChipTone.accent,
                onTap: () => _runPassageAction('questions'),
              ),
              MChip(
                label: 'Translate',
                tone: MChipTone.accent,
                onTap: () => _runPassageAction('translate'),
              ),
            ],
          ),
          if (_aiOutput.isNotEmpty || _aiBusy) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(MSpace.x2),
                border: Border.all(color: c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _aiOutput.isEmpty ? 'Thinking…' : _aiOutput,
                    style: MType.small.copyWith(
                      color: c.ink,
                      height: 1.5,
                      fontSize: 11.5,
                    ),
                  ),
                  if (!_aiBusy && _aiOutput.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    MButton(
                      label: 'Save as note on p. $_page',
                      icon: Icons.bookmark_add_outlined,
                      dense: true,
                      onPressed: () async {
                        final now = DateTime.now();
                        await Store.i.saveNote(
                          Note(
                            id: _uuid.v4(),
                            title: 'Tutor note · p. $_page',
                            body: _aiOutput,
                            courseId: r.courseId,
                            resourceId: r.id,
                            page: _page,
                            createdAt: now,
                            updatedAt: now,
                          ),
                        );
                        final notes = await Store.i.notes();
                        if (mounted) {
                          setState(() {
                            _notes = notes
                                .where((n) => n.resourceId == r.id)
                                .toList();
                            _sideTab = 0;
                          });
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AudioControls extends StatelessWidget {
  const _AudioControls({required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<bool>(
          stream: player.stream.playing,
          builder: (context, snap) => IconButton(
            onPressed: () => player.playOrPause(),
            icon: Icon(
              snap.data == true
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              size: 46,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
