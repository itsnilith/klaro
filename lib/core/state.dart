import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'db.dart';

/// Application-wide state: persisted preferences plus a revision counter that
/// screens listen to in order to reload their data after a mutation.
class AppState extends ChangeNotifier {
  AppState._();

  static final AppState i = AppState._();

  int revision = 0;
  bool ready = false;

  ThemeMode themeMode = ThemeMode.light;
  bool reduceMotion = false;
  bool compactDensity = false;

  // Playback
  double playbackSpeed = 1.0;
  bool autoplayNext = true;
  bool resumePlayback = true;
  int skipSeconds = 10;
  bool subtitlesEnabled = true;

  // Navigation
  Set<String> hiddenSections = {};

  // AI
  static const String defaultGlobalAiPrompt = '''
You are an evidence-based learning coach and tutor inside klaro.
Keep explanations clear, practical, and easy to follow while applying research-backed study principles:
1. Preview Before Reading in Detail:
   - Before diving into a long text or lesson, encourage a quick overview: scan headings, figures, summaries, and guiding questions so the learner knows what to look for.
2. Active Reading & Key Concepts:
   - Help the learner restate each passage in their own words instead of copying sentences verbatim.
   - Distinguish concise key concepts (core terms and relationships) from exact technical details that must be remembered accurately (formulas, dates, numbers, definitions).
3. Structured Maps & Outlines (Never replace the learner):
   - A concept map or outline is an active thinking tool, not a ready-made essay. Never draw or write a complete map in place of the learner.
   - Guide the learner to organize ideas into a Mind Map, Hierarchical Outline, Flowchart/Diagram, or Timeline using short labels and Socratic questions that reveal missing links.
4. Active Note-Taking:
   - Encourage structured notes (prior knowledge, open questions, key takeaways, and a brief summary in the learner's own words) rather than passive transcription.
5. Retrieval Practice & Spaced Repetition:
   - Prioritize active recall over passive rereading; suggest rereading only to clarify specific gaps uncovered during self-testing.
   - Support atomic Flashcards (one clear question, one concise answer), Free Recall (writing down everything remembered from memory), Feynman-style Simple Explanations (explaining with plain language and analogies to spot gaps), and Mock Q&A practice.
6. Source Fidelity:
   - Ground every explanation, flashcard, and question strictly in the learner's own study materials; if something is not covered in their sources, state so explicitly before offering general context.''';

  bool aiSimpleMode = true;
  bool onboardingDone = false;
  String aiGlobalInstructions = defaultGlobalAiPrompt;

  // Live Context Awareness (tracks what the user is currently viewing)
  String activeSectionLabel = 'Home';
  String? activeCourseId;
  String? activeLessonId;
  String? activeResourceId;
  String? activeNoteId;
  String? activeMapId;
  String? pendingSettingsTab;

  void setActiveWorkspaceContext({
    String? section,
    String? courseId,
    String? lessonId,
    String? resourceId,
    String? noteId,
    String? mapId,
  }) {
    if (section != null) activeSectionLabel = section;
    if (courseId != null) activeCourseId = courseId;
    if (lessonId != null) activeLessonId = lessonId;
    if (resourceId != null) activeResourceId = resourceId;
    if (noteId != null) activeNoteId = noteId;
    if (mapId != null) activeMapId = mapId;
  }

  /// Drops the deep-focus context when the user returns to a top-level section,
  /// so the tutor never claims to see a page that is no longer open.
  void clearFocusContext() {
    activeCourseId = null;
    activeLessonId = null;
    activeResourceId = null;
    activeNoteId = null;
    activeMapId = null;
  }

  // Transcription
  String transcriptionBackend = 'none'; // none | openai | whispercpp
  String transcriptionEndpoint = 'http://127.0.0.1:8080/v1';
  String transcriptionApiKey = '';
  String transcriptionModel = 'whisper-1';
  String whisperPath = '';
  String whisperModel = 'base';
  String whisperModelPath = '';
  String transcriptionLanguage = 'auto';
  String language = 'en';

  // Sync
  String deviceName = 'This device';
  int syncPort = 47821;
  bool syncActive = false;
  String syncPairingCode = '';

  void bump() {
    revision++;
    notifyListeners();
  }

  Future<void> load() async {
    final m = await Store.i.metaAll();
    String? s(String k) => m[k];
    bool b(String k, bool d) => s(k) == null ? d : s(k) == '1';
    double d(String k, double def) =>
        s(k) == null ? def : double.tryParse(s(k)!) ?? def;
    int n(String k, int def) => s(k) == null ? def : int.tryParse(s(k)!) ?? def;

    // Theme is an explicit Light/Dark choice controlled by the header toggle.
    // Older builds could persist "system"; resolve it once to a concrete mode
    // and store it, so the app never depends on a broken system lookup again.
    final storedTheme = s('theme');
    if (storedTheme == 'system') {
      final isDark =
          PlatformDispatcher.instance.platformBrightness == Brightness.dark;
      themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      await Store.i.metaSet('theme', isDark ? 'dark' : 'light');
    } else {
      themeMode = storedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;
    }
    reduceMotion = b('reduce_motion', false);
    compactDensity = b('compact', false);
    playbackSpeed = d('playback_speed', 1.0);
    autoplayNext = b('autoplay_next', true);
    resumePlayback = b('resume', true);
    skipSeconds = n('skip_seconds', 10);
    subtitlesEnabled = b('subtitles', true);
    aiSimpleMode = b('ai_simple', true);
    onboardingDone = b('onboarding', false);
    aiGlobalInstructions = s('ai_global_instructions') ?? defaultGlobalAiPrompt;
    // The study-method prompt is versioned: an older install must receive the
    // current method guidance instead of keeping a stale one-paragraph prompt.
    final promptVersion = s('ai_prompt_version');
    if (promptVersion != '3') {
      aiGlobalInstructions = defaultGlobalAiPrompt;
      await Store.i.metaSet('ai_global_instructions', defaultGlobalAiPrompt);
      await Store.i.metaSet('ai_prompt_version', '3');
    }
    transcriptionBackend = s('transcription_backend') ?? 'none';
    transcriptionEndpoint =
        s('transcription_endpoint') ?? 'http://127.0.0.1:8080/v1';
    transcriptionApiKey = s('transcription_key') ?? '';
    transcriptionModel = s('transcription_model') ?? 'whisper-1';
    whisperPath = s('whisper_path') ?? '';
    whisperModel = s('whisper_model') ?? 'base';
    whisperModelPath = s('whisper_model_path') ?? '';
    transcriptionLanguage = s('transcription_language') ?? 'auto';
    language = s('language') ?? 'en';
    deviceName = s('device_name') ?? 'This device';
    syncPort = n('sync_port', 47821);
    syncActive = b('sync_active', false);
    syncPairingCode = s('sync_pairing_code') ?? '';
    final hidden = s('hidden_sections');
    if (hidden != null && hidden.isNotEmpty) {
      try {
        hiddenSections = (jsonDecode(hidden) as List).cast<String>().toSet();
      } catch (_) {}
    }
    ready = true;
    notifyListeners();
  }

  Future<void> _set(String key, String value) async {
    await Store.i.metaSet(key, value);
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    await _set('theme', themeMode == ThemeMode.dark ? 'dark' : 'light');
  }

  Future<void> setBool(String key, bool value) async {
    switch (key) {
      case 'reduce_motion':
        reduceMotion = value;
      case 'compact':
        compactDensity = value;
      case 'autoplay_next':
        autoplayNext = value;
      case 'resume':
        resumePlayback = value;
      case 'subtitles':
        subtitlesEnabled = value;
      case 'ai_simple':
        aiSimpleMode = value;
      case 'onboarding':
        onboardingDone = value;
      case 'sync_active':
        syncActive = value;
    }
    await _set(key, value ? '1' : '0');
  }

  Future<void> setDouble(String key, double value) async {
    if (key == 'playback_speed') playbackSpeed = value;
    await _set(key, value.toString());
  }

  Future<void> setInt(String key, int value) async {
    if (key == 'skip_seconds') skipSeconds = value;
    if (key == 'sync_port') syncPort = value;
    await _set(key, value.toString());
  }

  Future<void> setString(String key, String value) async {
    switch (key) {
      case 'transcription_backend':
        transcriptionBackend = value;
      case 'transcription_endpoint':
        transcriptionEndpoint = value;
      case 'transcription_key':
        transcriptionApiKey = value;
      case 'transcription_model':
        transcriptionModel = value;
      case 'whisper_path':
        whisperPath = value;
      case 'whisper_model':
        whisperModel = value;
      case 'whisper_model_path':
        whisperModelPath = value;
      case 'transcription_language':
        transcriptionLanguage = value;
      case 'language':
        language = value;
      case 'device_name':
        deviceName = value;
      case 'sync_pairing_code':
        syncPairingCode = value;
      case 'ai_global_instructions':
        aiGlobalInstructions = value;
    }
    await _set(key, value);
  }

  Future<void> toggleSection(String id) async {
    if (hiddenSections.contains(id)) {
      hiddenSections.remove(id);
    } else {
      hiddenSections.add(id);
    }
    await _set('hidden_sections', jsonEncode(hiddenSections.toList()));
  }
}
