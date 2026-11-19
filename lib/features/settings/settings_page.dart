import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/db.dart';
import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../services/whisper_models.dart';
import '../../core/native_engine.dart';
import '../../core/paths.dart';
import '../../core/state.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/ai.dart';
import '../shell.dart';
import 'sync_page.dart';

const _uuid = Uuid();

const _settingsSections = [
  ('general', 'General', Icons.tune_rounded),
  ('playback', 'Playback', Icons.play_circle_outline),
  ('ai', 'AI providers', Icons.memory_rounded),
  ('transcription', 'Transcription', Icons.graphic_eq_rounded),
  ('sync', 'Device sync', Icons.devices_outlined),
  ('storage', 'Storage & backup', Icons.folder_outlined),
  ('about', 'About', Icons.info_outline_rounded),
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _sectionIdx = 0;
  List<AiProvider> _providers = const [];
  Map<String, Object?>? _hardware;
  bool _detecting = false;
  late final TextEditingController _deviceNameCtrl;
  late final TextEditingController _aiGlobalCtrl;
  late final TextEditingController _transEndpointCtrl;
  late final TextEditingController _transModelCtrl;
  late final TextEditingController _transKeyCtrl;
  late final TextEditingController _whisperPathCtrl;

  @override
  void initState() {
    super.initState();
    _deviceNameCtrl = TextEditingController(text: AppState.i.deviceName);
    _aiGlobalCtrl = TextEditingController(
      text: AppState.i.aiGlobalInstructions,
    );
    _transEndpointCtrl = TextEditingController(
      text: AppState.i.transcriptionEndpoint,
    );
    _transModelCtrl = TextEditingController(
      text: AppState.i.transcriptionModel,
    );
    _transKeyCtrl = TextEditingController(text: AppState.i.transcriptionApiKey);
    _whisperPathCtrl = TextEditingController(text: AppState.i.whisperPath);
    _consumePendingTab();
    AppState.i.addListener(_onAppStateChanged);
    _load();
  }

  void _consumePendingTab() {
    final pending = AppState.i.pendingSettingsTab;
    if (pending != null) {
      AppState.i.pendingSettingsTab = null;
      final idx = _settingsSections.indexWhere((s) => s.$1 == pending);
      if (idx >= 0) _sectionIdx = idx;
    }
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    setState(() {
      _consumePendingTab();
    });
  }

  @override
  void dispose() {
    AppState.i.removeListener(_onAppStateChanged);
    _deviceNameCtrl.dispose();
    _aiGlobalCtrl.dispose();
    _transEndpointCtrl.dispose();
    _transModelCtrl.dispose();
    _transKeyCtrl.dispose();
    _whisperPathCtrl.dispose();
    super.dispose();
  }

  void _selectSubSection(int idx) {
    if (idx == _sectionIdx) return;
    setState(() => _sectionIdx = idx);
  }

  Future<void> _load() async {
    final providers = await Store.i.providers();
    if (mounted) setState(() => _providers = providers);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final nav = MCard(
      padding: const EdgeInsets.all(12),
      radius: MRadius.xl,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Text(
              'Settings',
              style: MType.h3.copyWith(color: c.ink, fontSize: 15),
            ),
          ),
          SizedBox(
            height: _settingsSections.length * 42.0,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  top: _sectionIdx * 42.0,
                  left: 0,
                  right: 0,
                  height: 38,
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.surfaceSunken,
                      borderRadius: BorderRadius.circular(MRadius.md),
                    ),
                  ),
                ),
                Column(
                  children: [
                    for (var i = 0; i < _settingsSections.length; i++)
                      SizedBox(
                        height: 42,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _selectSubSection(i),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _settingsSections[i].$3,
                                      size: 16,
                                      color: _sectionIdx == i
                                          ? c.ink
                                          : c.inkMuted,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _settingsSections[i].$2,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: MType.small.copyWith(
                                          fontSize: 12.5,
                                          color: _sectionIdx == i
                                              ? c.ink
                                              : c.inkMuted,
                                          fontWeight: _sectionIdx == i
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final content = ClipRect(
      child: MFadeIn(
        key: ValueKey(_sectionIdx),
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(
          key: ValueKey(_sectionIdx),
          child: MSmoothScrollView(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: switch (_settingsSections[_sectionIdx].$1) {
                  'general' => _general(context),
                  'playback' => _playback(context),
                  'ai' => _ai(context),
                  'transcription' => _transcription(context),
                  'sync' => const SyncSettings(),
                  'storage' => _storage(context),
                  _ => _about(context),
                },
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 28, 22),
      child: LayoutBuilder(
        builder: (context, cons) {
          // Narrow windows get a horizontal section switcher instead of a
          // fixed sidebar that would leave the content a few pixels wide.
          if (cons.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _settingsSections.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, i) => MChip(
                      label: _settingsSections[i].$2,
                      selected: _sectionIdx == i,
                      onTap: () => _selectSubSection(i),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(child: content),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 224, child: nav),
              const SizedBox(width: 18),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  Widget _heading(BuildContext context, String title, String subtitle) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: MType.h1.copyWith(color: c.ink, fontSize: 26)),
          const SizedBox(height: 4),
          Text(subtitle, style: MType.small.copyWith(color: c.inkMuted)),
        ],
      ),
    );
  }

  Widget _general(BuildContext context) {
    final c = context.c;
    final s = AppState.i;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, 'General', 'How klaro. behaves on this computer.'),
        MCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row(
                title: 'Device name',
                subtitle: 'Shown to devices you pair with.',
                trailing: SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _deviceNameCtrl,
                    style: MType.small.copyWith(color: c.ink),
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (v) => s.setString('device_name', v.trim()),
                    onSubmitted: (v) => s.setString('device_name', v.trim()),
                  ),
                ),
              ),
              const MDivider(),
              _Row(
                title: L.of(context).t('language'),
                subtitle: 'Interface language. Text that is not translated yet stays in English.',
                trailing: PopupMenuButton<String>(
                  tooltip: 'Language',
                  color: c.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(MRadius.md),
                    side: BorderSide(color: c.line),
                  ),
                  onSelected: (v) {
                    s.setString('language', v);
                    L.current = languageFromCode(v);
                    setState(() {});
                  },
                  itemBuilder: (_) => [
                    for (final l in AppLanguage.values)
                      PopupMenuItem(
                        value: l.code,
                        height: 36,
                        child: Row(
                          children: [
                            Icon(
                              l.code == s.language
                                  ? Icons.check_rounded
                                  : Icons.translate_rounded,
                              size: 14,
                              color: l.code == s.language ? c.ink : c.inkFaint,
                            ),
                            const SizedBox(width: 9),
                            Text(
                              l.label,
                              style: MType.small.copyWith(
                                color: c.ink,
                                fontSize: 12.5,
                                fontWeight: l.code == s.language
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.line),
                      boxShadow: [
                        BoxShadow(
                          color: context.elevationShadow(0.08, darkAlpha: 0.32),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          languageFromCode(s.language).label,
                          style: MType.small.copyWith(
                            color: c.ink,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: c.inkMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const MDivider(),
              _ToggleRow(
                title: 'Reduce motion',
                subtitle:
                    'Removes page transitions and non-essential animation.',
                value: s.reduceMotion,
                onChanged: (v) => s.setBool('reduce_motion', v),
              ),
              const MDivider(),
              _ToggleRow(
                title: 'Compact density',
                subtitle:
                    'Tighter spacing for large libraries on small screens.',
                value: s.compactDensity,
                onChanged: (v) => s.setBool('compact', v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sidebar sections',
                style: MType.bodyStrong.copyWith(color: c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                'Hide what you do not use. Nothing is deleted.',
                style: MType.small.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final sec in sections)
                    MChip(
                      label: sec.label,
                      selected: !s.hiddenSections.contains(sec.label),
                      onTap: () => s.toggleSection(sec.label),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _playback(BuildContext context) {
    final s = AppState.i;
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, 'Playback', 'Defaults for every lesson.'),
        MCard(
          child: Column(
            children: [
              _Row(
                title: 'Playback speed',
                subtitle: 'Remembered for new lessons.',
                trailing: Text(
                  '${s.playbackSpeed}x',
                  style: MType.bodyStrong.copyWith(color: c.ink),
                ),
              ),
              Slider(
                value: s.playbackSpeed.clamp(0.5, 2.0),
                min: 0.5,
                max: 2.0,
                divisions: 6,
                onChanged: (v) => s.setDouble('playback_speed', v),
              ),
              const MDivider(),
              _ToggleRow(
                title: 'Resume where I stopped',
                subtitle: 'Continues from the last saved position.',
                value: s.resumePlayback,
                onChanged: (v) => s.setBool('resume', v),
              ),
              const MDivider(),
              _ToggleRow(
                title: 'Play the next lesson automatically',
                subtitle: 'Only when a lesson finishes.',
                value: s.autoplayNext,
                onChanged: (v) => s.setBool('autoplay_next', v),
              ),
              const MDivider(),
              _ToggleRow(
                title: 'Show subtitles when available',
                subtitle: 'Uses generated transcripts as a subtitle track.',
                value: s.subtitlesEnabled,
                onChanged: (v) => s.setBool('subtitles', v),
              ),
              const MDivider(),
              _Row(
                title: 'Skip interval',
                subtitle: 'Arrow keys and the skip buttons.',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final v in [5, 10, 15, 30])
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: MChip(
                          label: '${v}s',
                          selected: s.skipSeconds == v,
                          onTap: () => s.setInt('skip_seconds', v),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ai(BuildContext context) {
    final c = context.c;
    final s = AppState.i;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          'AI providers',
          'Connect Ollama locally or any OpenAI-compatible endpoint.',
        ),
        Row(
          children: [
            Text(
              '${_providers.length} configured',
              style: MType.small.copyWith(color: c.inkMuted, fontSize: 11.5),
            ),
            const Spacer(),
            MButton(
              label: 'Add provider',
              icon: Icons.add_rounded,
              dense: true,
              onPressed: () async {
                await _editProvider(context, null);
                _load();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_providers.isEmpty)
          MEmpty(
            icon: Icons.memory_rounded,
            title: 'No AI provider yet',
            message: 'klaro. is fully usable without AI. Add a local model when you want the tutor.',
            compact: true,
            action: MButton(
              label: 'Find the right setup',
              kind: MButtonKind.primary,
              onPressed: () => _runSimpleSetup(context),
            ),
          )
        else
          for (final p in _providers) ...[
            MCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: p.isDefault ? c.accentSoft : c.surfaceAlt,
                      borderRadius: BorderRadius.circular(MSpace.x2),
                      border: Border.all(color: c.line),
                    ),
                    child: Icon(
                      p.kind == 'ollama'
                          ? Icons.dns_outlined
                          : Icons.cloud_outlined,
                      size: 16,
                      color: p.isDefault ? c.accent : c.inkMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              p.name,
                              style: MType.bodyStrong.copyWith(
                                color: c.ink,
                                fontSize: 12.5,
                              ),
                            ),
                            if (p.isDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: c.accentSoft,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'DEFAULT',
                                  style: MType.label.copyWith(
                                    color: c.accent,
                                    fontSize: 8,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${p.model} · ${p.baseUrl}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MType.small.copyWith(
                            color: c.inkFaint,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  MButton(
                    label: 'Test',
                    dense: true,
                    onPressed: () async {
                      final ok = await AiClient.ping(p);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? '${p.name} answered correctly.'
                                  : '${p.name} did not answer. Check the address and that the server is running.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  MIconButton(
                    icon: Icons.edit_outlined,
                    size: 30,
                    onPressed: () async {
                      await _editProvider(context, p);
                      _load();
                    },
                  ),
                  MIconButton(
                    icon: Icons.delete_outline_rounded,
                    size: 30,
                    onPressed: () async {
                      await Store.i.deleteProvider(p.id);
                      _load();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 12),
        MCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Guided setup',
                            style: MType.bodyStrong.copyWith(
                              color: c.ink,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Detects this computer and suggests a model that fits.',
                            style: MType.small.copyWith(
                              color: c.inkMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    MButton(
                      label: _detecting ? 'Checking…' : 'Scan',
                      dense: true,
                      onPressed: _detecting
                          ? null
                          : () async {
                              setState(() => _detecting = true);
                              final result = await AiSetup.detect();
                              if (mounted) {
                                setState(() {
                                  _hardware = result;
                                  _detecting = false;
                                });
                              }
                            },
                    ),
                  ],
                ),
              ),
              if (_hardware != null) ...[
                _HardwareResult(
                  data: _hardware!,
                  onAdd: () => _runSimpleSetup(context, preset: _hardware),
                ),
                const SizedBox(height: 14),
              ],
              const MDivider(),
              const SizedBox(height: 6),
              _ToggleRow(
                title: 'Simple mode',
                subtitle: 'Hides advanced sampling, context window, and raw system prompt controls behind smart defaults.',
                value: s.aiSimpleMode,
                onChanged: (v) => s.setBool('ai_simple', v),
              ),
            ],
          ),
        ),
        if (!s.aiSimpleMode) ...[
          const SizedBox(height: 14),
          MCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Global Study Method Instructions (Advanced)',
                            style: MType.bodyStrong.copyWith(color: c.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Applied automatically to the AI Tutor and study tools across the app. '
                            'You can customize them freely or restore the recommended defaults.',
                            style: MType.small.copyWith(
                              color: c.inkMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    MButton(
                      label: 'Restore default',
                      icon: Icons.restart_alt_rounded,
                      dense: true,
                      onPressed: () {
                        _aiGlobalCtrl.text = AppState.defaultGlobalAiPrompt;
                        s.setString(
                          'ai_global_instructions',
                          AppState.defaultGlobalAiPrompt,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _aiGlobalCtrl,
                  minLines: 6,
                  maxLines: 10,
                  style: MType.small.copyWith(
                    color: c.ink,
                    fontSize: 12,
                    height: 1.45,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Enter global system instructions for the AI…',
                  ),
                  onChanged: (v) => s.setString('ai_global_instructions', v),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _runSimpleSetup(
    BuildContext context, {
    Map<String, Object?>? preset,
  }) async {
    final data = preset ?? await AiSetup.detect();
    if (!context.mounted) return;
    final hasOllama = data['ollama'] == true;
    final ram = data['ram_gb'] as double?;
    final recommended = data['recommended'] as String? ?? 'qwen3:8b';
    final models = (data['models'] as List?)?.cast<String>() ?? const [];
    await showMSheet<void>(
      context,
      maxWidth: 560,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A tutor that fits this computer',
              style: MType.h2.copyWith(color: context.c.ink),
            ),
            const SizedBox(height: 6),
            Text(
              ram == null
                  ? 'We could not read the installed memory.'
                  : 'This computer has about ${ram.toStringAsFixed(0)} GB of RAM. '
                        'That is enough for ${ram >= 15 ? 'a capable 7–8B model' : 'a small, fast model'}.',
              style: MType.small.copyWith(
                color: context.c.inkMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            if (hasOllama) ...[
              _Option(
                title: 'Ollama detected',
                subtitle: models.isEmpty
                    ? 'Running, but no model installed yet.'
                    : 'Installed: ${models.take(3).join(', ')}',
                selected: true,
              ),
              const SizedBox(height: 8),
              for (final m in models.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: MButton(
                    label: 'Use $m',
                    expand: true,
                    dense: true,
                    onPressed: () async {
                      await _useOllamaModel(context, m);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ),
              if (!models.contains(recommended))
                MButton(
                  label: 'Download $recommended (recommended for this RAM)',
                  kind: MButtonKind.primary,
                  expand: true,
                  onPressed: () => _pullModel(context, recommended),
                ),
            ] else ...[
              _Option(
                title: 'No local AI server found',
                subtitle:
                    'Ollama is free and runs models entirely on this computer.',
                selected: false,
              ),
              const SizedBox(height: 12),
              MButton(
                label: 'Get Ollama',
                icon: Icons.open_in_new_rounded,
                onPressed: () =>
                    launchUrl(Uri.parse('https://ollama.com/download')),
              ),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 10),
              Text(
                'Or use a cloud endpoint',
                style: MType.bodyStrong.copyWith(
                  color: context.c.ink,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Any OpenAI-compatible API works. Your prompts and the passages you select leave this computer.',
                style: MType.small.copyWith(
                  color: context.c.inkMuted,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              MButton(
                label: 'Configure a cloud provider',
                onPressed: () {
                  Navigator.of(context).pop();
                  _editProvider(context, null, cloudPreset: true);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _useOllamaModel(BuildContext context, String model) async {
    final provider = AiProvider(
      id: _uuid.v4(),
      name: 'Ollama (local)',
      kind: 'ollama',
      baseUrl: 'http://127.0.0.1:11434',
      model: model,
      isDefault: true,
      embeddingModel: null,
    );
    await Store.i.saveProvider(provider);
    await _load();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Using $model from your local Ollama.')),
      );
    }
  }

  Future<void> _pullModel(BuildContext context, String model) async {
    final progress = ValueNotifier<(double?, String)>((null, 'Starting…'));
    showMSheet<void>(
      context,
      maxWidth: 460,
      child: ValueListenableBuilder<(double?, String)>(
        valueListenable: progress,
        builder: (context, value, _) {
          final c = context.c;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Downloading $model',
                  style: MType.h2.copyWith(color: c.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ollama stores the model on this computer.',
                  style: MType.small.copyWith(color: c.inkMuted),
                ),
                const SizedBox(height: 16),
                MProgress(value: value.$1 ?? 0, height: 6),
                const SizedBox(height: 8),
                Text(
                  '${value.$2}${value.$1 == null ? '' : '  ${(value.$1! * 100).round()}%'}',
                  style: MType.small.copyWith(color: c.inkFaint, fontSize: 11),
                ),
              ],
            ),
          );
        },
      ),
    );
    try {
      await AiClient().pullOllamaModel(
        baseUrl: 'http://127.0.0.1:11434',
        model: model,
        onProgress: (p, s) => progress.value = (p, s),
      );
      if (context.mounted) await _useOllamaModel(context, model);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      progress.dispose();
    }
  }

  Future<void> _editProvider(
    BuildContext context,
    AiProvider? existing, {
    bool cloudPreset = false,
  }) async {
    final name = TextEditingController(
      text: existing?.name ?? (cloudPreset ? 'OpenAI-compatible' : 'Ollama'),
    );
    final base = TextEditingController(
      text:
          existing?.baseUrl ??
          (cloudPreset
              ? 'https://api.openai.com/v1'
              : 'http://127.0.0.1:11434'),
    );
    final model = TextEditingController(text: existing?.model ?? '');
    final key = TextEditingController(text: existing?.apiKey ?? '');
    final embed = TextEditingController(text: existing?.embeddingModel ?? '');
    var kind = existing?.kind ?? (cloudPreset ? 'openai' : 'ollama');
    var isDefault = existing?.isDefault ?? true;
    var temp = existing?.temperature ?? 0.4;
    final saved = await showMSheet<bool>(
      context,
      maxWidth: 560,
      child: StatefulBuilder(
        builder: (context, setState) {
          final c = context.c;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MDialogHeader(
                  title: existing == null ? 'Add AI provider' : 'Edit provider',
                  subtitle: 'Capabilities differ: validate before relying on embeddings or vision.',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          MChip(
                            label: 'Ollama',
                            selected: kind == 'ollama',
                            onTap: () => setState(() {
                              kind = 'ollama';
                              base.text = 'http://127.0.0.1:11434';
                            }),
                          ),
                          const SizedBox(width: 6),
                          MChip(
                            label: 'OpenAI-compatible',
                            selected: kind == 'openai',
                            onTap: () => setState(() {
                              kind = 'openai';
                              base.text = 'https://api.openai.com/v1';
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _Field(
                        label: 'Name',
                        controller: name,
                        hint: 'My local model',
                      ),
                      _Field(
                        label: 'Base URL',
                        controller: base,
                        hint: 'http://127.0.0.1:11434',
                      ),
                      _Field(
                        label: 'Model',
                        controller: model,
                        hint: 'qwen3:8b',
                      ),
                      if (kind == 'openai')
                        _Field(
                          label: 'API key',
                          controller: key,
                          hint: 'sk-…',
                          obscure: true,
                        ),
                      _Field(
                        label: 'Embedding model (optional)',
                        controller: embed,
                        hint: 'nomic-embed-text — enables semantic retrieval',
                      ),
                      if (!AppState.i.aiSimpleMode) ...[
                        Text(
                          'TEMPERATURE  ${temp.toStringAsFixed(2)}',
                          style: MType.label.copyWith(
                            color: c.inkFaint,
                            fontSize: 9.5,
                          ),
                        ),
                        Slider(
                          value: temp,
                          min: 0,
                          max: 1.2,
                          divisions: 12,
                          onChanged: (v) => setState(() => temp = v),
                        ),
                      ],
                      Row(
                        children: [
                          Checkbox(
                            value: isDefault,
                            onChanged: (v) =>
                                setState(() => isDefault = v ?? false),
                            visualDensity: VisualDensity.compact,
                          ),
                          Text(
                            'Use for the tutor by default',
                            style: MType.small.copyWith(color: c.ink),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      MButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      const SizedBox(width: 8),
                      MButton(
                        label: 'Save provider',
                        kind: MButtonKind.primary,
                        onPressed: () {
                          if (base.text.trim().isEmpty ||
                              model.text.trim().isEmpty) {
                            return;
                          }
                          Navigator.of(context).pop(true);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (saved != true) return;
    await Store.i.saveProvider(
      AiProvider(
        id: existing?.id ?? _uuid.v4(),
        name: name.text.trim().isEmpty ? 'Provider' : name.text.trim(),
        kind: kind,
        baseUrl: base.text.trim(),
        model: model.text.trim(),
        apiKey: key.text.trim(),
        temperature: temp,
        isDefault: isDefault,
        embeddingModel: embed.text.trim().isEmpty ? null : embed.text.trim(),
      ),
    );
    await _load();
  }

  Future<void> _downloadModel(BuildContext context, WhisperModel model) async {
    final c = context.c;
    final progress = ValueNotifier<double>(0);
    var failed = false;
    String? error;
    showMSheet<void>(
      context,
      maxWidth: 420,
      child: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, value, _) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Downloading ${model.label}',
                  style: MType.h2.copyWith(color: c.ink, fontSize: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  '${model.sizeLabel} · stored in Klaro’s models folder',
                  style: MType.small.copyWith(
                    color: c.inkMuted,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 16),
                MProgress(value: failed ? 0 : value, height: 6),
                const SizedBox(height: 8),
                Text(
                  error ?? '${(value * 100).round()}%',
                  style: MType.small.copyWith(
                    color: failed ? c.danger : c.inkMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).then((_) {});
    try {
      await downloadWhisperModel(
        model.id,
        onProgress: (v) => progress.value = v,
      );
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await AppState.i.setString('whisper_model', model.id);
      await AppState.i.setString('whisper_model_path', '');
      if (!mounted) return;
      setState(() {});
      final messenger = ScaffoldMessenger.of(this.context);
      messenger.showSnackBar(
        SnackBar(content: Text('${model.label} is ready for transcription.')),
      );
    } catch (e) {
      failed = true;
      error = 'Download failed: $e';
      progress.value = progress.value;
    }
  }

  Widget _transcription(BuildContext context) {
    final c = context.c;
    final s = AppState.i;
    final labels = {
      'none': 'Off',
      'openai': 'OpenAI-compatible endpoint',
      'whispercpp': 'Local whisper.cpp executable',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          'Transcription',
          'Turn lessons into searchable, timestamped text. Nothing is uploaded unless you choose a cloud endpoint.',
        ),
        MCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BACKEND',
                style: MType.label.copyWith(color: c.inkFaint, fontSize: 9.5),
              ),
              const SizedBox(height: 10),
              for (final entry in labels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () {
                      s.setString('transcription_backend', entry.key);
                      setState(() {});
                    },
                    borderRadius: BorderRadius.circular(MRadius.md),
                    child: _Option(
                      title: entry.value,
                      subtitle: entry.key == 'openai'
                          ? 'Works with self-hosted faster-whisper, LM Studio, or another local app exposing /audio/transcriptions'
                          : entry.key == 'whispercpp'
                          ? 'Reuses a whisper.cpp build and model you already have. No model is bundled.'
                          : 'Transcription disabled.',
                      selected: s.transcriptionBackend == entry.key,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (s.transcriptionBackend == 'openai') ...[
                _Field(
                  label: 'Endpoint',
                  controller: _transEndpointCtrl,
                  hint: 'http://127.0.0.1:8080/v1',
                  onChanged: (v) => s.setString('transcription_endpoint', v),
                ),
                _Field(
                  label: 'Model',
                  controller: _transModelCtrl,
                  hint: 'whisper-1',
                  onChanged: (v) => s.setString('transcription_model', v),
                ),
                _Field(
                  label: 'API key (optional)',
                  controller: _transKeyCtrl,
                  hint: 'Leave empty for local servers',
                  obscure: true,
                  onChanged: (v) => s.setString('transcription_key', v),
                ),
                MButton(
                  label: 'Check endpoint',
                  icon: Icons.wifi_tethering_rounded,
                  onPressed: () async {
                    final p = AiProvider(
                      id: 'test',
                      name: 'Transcriber',
                      kind: 'openai',
                      baseUrl: s.transcriptionEndpoint,
                      model: s.transcriptionModel,
                      apiKey: s.transcriptionApiKey,
                    );
                    final ok = await AiClient.ping(p);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok ? 'The endpoint answered.' : 'No answer. Check the URL and that the server is running.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
              if (s.transcriptionBackend == 'whispercpp') ...[
                _Field(
                  label: 'whisper.cpp executable',
                  controller: _whisperPathCtrl,
                  hint: r'C:\tools\whisper\whisper-cli.exe',
                  onChanged: (v) => s.setString('whisper_path', v),
                ),
                Row(
                  children: [
                    MButton(
                      label: 'Use an existing install',
                      icon: Icons.folder_open_outlined,
                      dense: true,
                      onPressed: () async {
                        final f = await FilePicker.platform.pickFiles(
                          dialogTitle: 'Select whisper-cli executable',
                        );
                        if (f != null && f.files.single.path != null) {
                          final picked = f.files.single.path!;
                          _whisperPathCtrl.text = picked;
                          await s.setString('whisper_path', picked);
                          setState(() {});
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    MButton(
                      label: 'Use a model file',
                      icon: Icons.memory_rounded,
                      dense: true,
                      onPressed: () async {
                        final f = await FilePicker.platform.pickFiles(
                          dialogTitle: 'Select a ggml Whisper model',
                          type: FileType.custom,
                          allowedExtensions: ['bin'],
                        );
                        if (f != null && f.files.single.path != null) {
                          await s.setString(
                            'whisper_model_path',
                            f.files.single.path!,
                          );
                          setState(() {});
                        }
                      },
                    ),
                  ],
                ),
                if (s.whisperModelPath.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Using ${s.whisperModelPath}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MType.small.copyWith(
                              color: c.inkMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        MIconButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Clear the model file',
                          size: 28,
                          onPressed: () async {
                            await s.setString('whisper_model_path', '');
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  'OR DOWNLOAD A MODEL FOR KLARO',
                  style: MType.label.copyWith(color: c.inkFaint, fontSize: 9.5),
                ),
                const SizedBox(height: 8),
                for (final model in whisperModels)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _WhisperModelRow(
                      model: model,
                      selected:
                          s.whisperModel == model.id &&
                          s.whisperModelPath.isEmpty,
                      downloaded: isWhisperModelDownloaded(model.id),
                      onUse: () async {
                        await s.setString('whisper_model', model.id);
                        await s.setString('whisper_model_path', '');
                        setState(() {});
                      },
                      onDownload: () => _downloadModel(context, model),
                      onDelete: () async {
                        await deleteWhisperModel(model.id);
                        setState(() {});
                      },
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Klaro stores models in its own folder. Nothing is written outside the app, and an existing whisper.cpp installation keeps working.',
                  style: MType.small.copyWith(
                    color: c.inkFaint,
                    fontSize: 10.5,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const MDivider(),
              _Row(
                title: 'Language',
                subtitle: 'Automatic detection is slower but safer.',
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    for (final (code, label) in const [
                      ('auto', 'Auto'),
                      ('en', 'English'),
                      ('it', 'Italian'),
                    ])
                      MChip(
                        label: label,
                        selected: s.transcriptionLanguage == code,
                        onTap: () =>
                            s.setString('transcription_language', code),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        MCard(
          color: c.surfaceAlt,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vibe and other installed apps',
                style: MType.bodyStrong.copyWith(color: c.ink, fontSize: 12.5),
              ),
              const SizedBox(height: 4),
              Text(
                'If another application exposes an OpenAI-compatible transcription endpoint, point the endpoint above at it. '
                'klaro. does not assume an undocumented API: nothing is detected automatically.',
                style: MType.small.copyWith(
                  color: c.inkMuted,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _storage(BuildContext context) {
    final c = context.c;
    final db = File(AppPaths.i.dbPath);
    final size = db.existsSync() ? db.lengthSync() : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          'Storage & backup',
          'Portable by design: everything lives in one folder.',
        ),
        MCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row(
                title: AppPaths.i.portable
                    ? 'Portable mode'
                    : 'Fallback storage',
                subtitle: AppPaths.i.root,
                trailing: MChip(
                  label: AppPaths.i.portable ? 'Portable' : 'AppData',
                  tone: AppPaths.i.portable
                      ? MChipTone.accent
                      : MChipTone.amber,
                ),
              ),
              const MDivider(),
              _Row(
                title: 'Database',
                subtitle: '${humanFileSize(size)} · ${AppPaths.i.dbPath}',
                trailing: MButton(
                  label: 'Open folder',
                  dense: true,
                  onPressed: () => launchUrl(Uri.file(AppPaths.i.dataDir)),
                ),
              ),
              const MDivider(),
              _Row(
                title: 'Backups',
                subtitle: 'Copy the data folder, or export a single archive.',
                trailing: MButton(
                  label: 'Create backup',
                  dense: true,
                  onPressed: () async {
                    final name =
                        'klaro-backup-${DateTime.now().toIso8601String().substring(0, 10)}.db';
                    final src = File(AppPaths.i.dbPath);
                    final dst = File(p.join(AppPaths.i.backupsDir, name));
                    await src.copy(dst.path);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Backup written to ${dst.path}'),
                        ),
                      );
                    }
                  },
                ),
              ),
              const MDivider(),
              _Row(
                title: 'Models and cache',
                subtitle:
                    '${AppPaths.i.modelsDir}\nNothing is deleted without asking.',
                trailing: MButton(
                  label: 'Open',
                  dense: true,
                  onPressed: () => launchUrl(Uri.file(AppPaths.i.root)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        MCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Integrity',
                style: MType.bodyStrong.copyWith(color: c.ink, fontSize: 12.5),
              ),
              const SizedBox(height: 4),
              Text(
                'Check that referenced files still exist and rebuild retrieval indexes.',
                style: MType.small.copyWith(color: c.inkMuted, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              MButton(
                label: 'Check library files',
                icon: Icons.fact_check_outlined,
                onPressed: () async {
                  final resources = await Store.i.resources();
                  final missing = resources
                      .where((r) => !File(r.path).existsSync())
                      .toList();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          missing.isEmpty
                              ? 'All ${resources.length} files are where they were.'
                              : '${missing.length} files are missing. Open the library to locate them.',
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  MButton(
                    label: 'Open data folder',
                    icon: Icons.folder_open_outlined,
                    dense: true,
                    onPressed: () => launchUrl(Uri.file(AppPaths.i.dataDir)),
                  ),
                  const SizedBox(width: 8),
                  MButton(
                    label: 'Open logs',
                    dense: true,
                    onPressed: () => launchUrl(Uri.file(AppPaths.i.logsDir)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _about(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, 'About', 'klaro. 1.0.0'),
        MCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const KlaroMark(size: 44, tile: true),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('klaro.', style: MType.h2.copyWith(color: c.ink)),
                      Text(
                        'Learning, remembered.',
                        style: MType.small.copyWith(color: c.inkMuted),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'A local-first learning workspace: courses, a real video player, a document library, notes, '
                'spaced repetition and a tutor that cites your own material.',
                style: MType.body.copyWith(
                  color: c.inkMuted,
                  height: 1.6,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              const MDivider(),
              const SizedBox(height: 14),
              _kv('Created by', 'itsnilith'),
              _kv('License', 'GNU AGPL-3.0'),
              _kv('Built with', 'Flutter · Dart · Rust (FFI) · SQLite'),
              _kv('Native engine', NativeEngine.i.version),
              _kv('Platform', 'Windows desktop, portable'),
              _kv('Version', '1.0.0'),
              const SizedBox(height: 12),
              Text(
                'This program is free software: you can redistribute it and/or modify it under the terms of the '
                'GNU Affero General Public License as published by the Free Software Foundation, version 3.',
                style: MType.small.copyWith(
                  color: c.inkFaint,
                  fontSize: 10.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        MCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Third-party notices',
                style: MType.bodyStrong.copyWith(color: c.ink, fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              Text(
                'Inter and Fraunces (SIL OFL 1.1), Flutter and Dart (BSD-3-Clause), SQLite (public domain), '
                'media_kit and libmpv (LGPL/GPL components), pdfrx and PDFium (BSD-3-Clause), '
                'cryptography (Apache-2.0). See NOTICE.md in the application folder for the full inventory.',
                style: MType.small.copyWith(
                  color: c.inkMuted,
                  fontSize: 11,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k.toUpperCase(),
              style: MType.label.copyWith(
                color: context.c.inkFaint,
                fontSize: 9,
              ),
            ),
          ),
          Text(
            v,
            style: MType.small.copyWith(color: context.c.ink, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.subtitle, this.trailing});
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: MType.bodyStrong.copyWith(color: c.ink, fontSize: 12.5),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: MType.small.copyWith(
            color: c.inkMuted,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, cons) {
          // Narrow panes stack the control under its label instead of
          // squeezing both into one line and overflowing.
          if (trailing == null) return info;
          if (cons.maxWidth < 460) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 8), trailing!],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: info),
              const SizedBox(width: 16),
              trailing!,
            ],
          );
        },
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(MRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: MType.bodyStrong.copyWith(
                      color: c.ink,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: MType.small.copyWith(
                      color: c.inkMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: 44,
              height: 24,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? c.ink : c.surfaceSunken,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: value ? c.ink : c.lineStrong,
                  width: 1,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: value ? c.surface : c.inkMuted,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: MType.label.copyWith(color: c.inkFaint, fontSize: 9),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            obscureText: obscure,
            style: MType.body.copyWith(color: c.ink, fontSize: 12.5),
            decoration: InputDecoration(hintText: hint, isDense: true),
            onChanged: onChanged,
            onSubmitted: onChanged,
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.subtitle,
    required this.selected,
  });
  final String title;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? c.accentSoft : c.surfaceAlt,
        borderRadius: BorderRadius.circular(MRadius.md),
        border: Border.all(color: selected ? c.accent : c.line),
      ),
      child: Row(
        children: [
          Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 16,
            color: selected ? c.accent : c.inkFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MType.bodyStrong.copyWith(color: c.ink, fontSize: 12),
                ),
                Text(
                  subtitle,
                  style: MType.small.copyWith(color: c.inkMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HardwareResult extends StatelessWidget {
  const _HardwareResult({required this.data, required this.onAdd});
  final Map<String, Object?> data;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ram = data['ram_gb'] as double?;
    final ollama = data['ollama'] == true;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(MRadius.md),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This computer',
            style: MType.bodyStrong.copyWith(color: c.ink, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (ram != null) '${ram.toStringAsFixed(0)} GB RAM',
              ollama ? 'Ollama running' : 'Ollama not detected',
              'suggested: ${data['recommended']}',
            ].join('  ·  '),
            style: MType.small.copyWith(color: c.inkMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          MButton(
            label: ollama ? 'Choose a model' : 'See the options',
            dense: true,
            kind: MButtonKind.primary,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _WhisperModelRow extends StatelessWidget {
  const _WhisperModelRow({
    required this.model,
    required this.selected,
    required this.downloaded,
    required this.onUse,
    required this.onDownload,
    required this.onDelete,
  });

  final WhisperModel model;
  final bool selected;
  final bool downloaded;
  final VoidCallback onUse;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: selected ? c.surfaceAlt : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onUse,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c.lineStrong : c.line),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: selected ? c.ink : c.inkMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.label,
                      style: MType.small.copyWith(
                        color: c.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      downloaded
                          ? '${model.sizeLabel} · downloaded'
                          : model.sizeLabel,
                      style: MType.small.copyWith(
                        color: c.inkFaint,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (downloaded)
                MIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete this model',
                  size: 28,
                  onPressed: onDelete,
                )
              else
                MButton(
                  label: 'Download',
                  icon: Icons.download_rounded,
                  dense: true,
                  onPressed: onDownload,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
