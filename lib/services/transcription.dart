import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import 'whisper_models.dart';

class TranscriptionException implements Exception {
  TranscriptionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Speech-to-text backends.
///
/// 1. Any OpenAI-compatible `/audio/transcriptions` endpoint (cloud, self-hosted
///    faster-whisper, or another local app that exposes one).
/// 2. A whisper.cpp executable already installed on the machine, invoked
///    directly with `-osrt` so no model needs to be bundled here.
class TranscriptionService {
  TranscriptionService();

  Future<List<TranscriptSegment>> transcribe({
    required String filePath,
    required String backend,
    String endpoint = '',
    String apiKey = '',
    String model = 'whisper-1',
    String language = 'auto',
    String executable = '',
    String modelPath = '',
  }) async {
    if (backend == 'openai') {
      return _openAi(filePath, endpoint, apiKey, model, language);
    }
    if (backend == 'whispercpp') {
      return _whisperCpp(filePath, executable, language, modelPath);
    }
    throw TranscriptionException('No transcription backend is configured.');
  }

  Future<List<TranscriptSegment>> _openAi(
    String filePath,
    String endpoint,
    String apiKey,
    String model,
    String language,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) throw TranscriptionException('The media file is missing.');
    final uri = Uri.parse('${endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint}/audio/transcriptions');
    final req = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', filePath))
      ..fields['model'] = model
      ..fields['response_format'] = 'verbose_json';
    if (language != 'auto') req.fields['language'] = language;
    if (apiKey.isNotEmpty) req.headers['Authorization'] = 'Bearer $apiKey';
    final streamed = await req.send().timeout(const Duration(minutes: 10));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      throw TranscriptionException('The transcriber answered ${streamed.statusCode}: ${body.substring(0, body.length.clamp(0, 240))}');
    }
    final obj = jsonDecode(body) as Map<String, dynamic>;
    final segs = obj['segments'] as List?;
    if (segs == null || segs.isEmpty) {
      final text = obj['text'] as String? ?? '';
      if (text.isEmpty) return [];
      return [TranscriptSegment(startMs: 0, endMs: 0, text: text)];
    }
    return segs.map((s) => TranscriptSegment(
      startMs: ((s['start'] as num) * 1000).round(),
      endMs: ((s['end'] as num) * 1000).round(),
      text: (s['text'] as String).trim(),
    )).toList();
  }

  Future<List<TranscriptSegment>> _whisperCpp(
    String filePath,
    String executable,
    String language,
    String modelPath,
  ) async {
    if (executable.isEmpty || !File(executable).existsSync()) {
      throw TranscriptionException(
          'Choose the whisper.cpp executable in Settings, or download Klaro’s own Whisper.');
    }
    var resolvedModel = modelPath;
    if (resolvedModel.isEmpty) {
      resolvedModel = firstDownloadedWhisperModel() ?? '';
    }
    if (resolvedModel.isEmpty || !File(resolvedModel).existsSync()) {
      throw TranscriptionException(
          'No Whisper model selected. Download one in Settings → Subtitles.');
    }
    final srt = File('${filePath}_${DateTime.now().millisecondsSinceEpoch}.srt');
    final args = [
      '-m', resolvedModel,
      '-f', filePath,
      '-osrt',
      '-of', srt.path.replaceAll('.srt', ''),
      if (language != 'auto') '-l', language,
    ];
    final result = await Process.run(executable, args, runInShell: false);
    if (result.exitCode != 0) {
      throw TranscriptionException('whisper.cpp exited with ${result.exitCode}.');
    }
    if (!await srt.exists()) {
      throw TranscriptionException('whisper.cpp produced no subtitle file.');
    }
    final content = await srt.readAsString();
    await srt.delete();
    return parseSrt(content);
  }

  static List<TranscriptSegment> parseSrt(String content) {
    final out = <TranscriptSegment>[];
    final blocks = content.split(RegExp(r'\r?\n\r?\n'));
    final time = RegExp(r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})');
    for (final block in blocks) {
      final lines = block.trim().split(RegExp(r'\r?\n'));
      for (final line in lines) {
        final m = time.firstMatch(line);
        if (m != null) {
          final start = _toMs(m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!);
          final end = _toMs(m.group(5)!, m.group(6)!, m.group(7)!, m.group(8)!);
          final text = lines.where((l) => l != line && !RegExp(r'^\d+$').hasMatch(l)).join(' ').trim();
          if (text.isNotEmpty) out.add(TranscriptSegment(startMs: start, endMs: end, text: text));
          break;
        }
      }
    }
    return out;
  }

  static int _toMs(String h, String m, String s, String ms) =>
      (int.parse(h) * 3600 + int.parse(m) * 60 + int.parse(s)) * 1000 + int.parse(ms);

  /// WebVTT output for the player's subtitle track.
  static String toVtt(List<TranscriptSegment> segments) {
    final b = StringBuffer('WEBVTT\n\n');
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      b.writeln('${i + 1}');
      b.writeln('${_vtt(s.startMs)} --> ${_vtt(s.endMs)}');
      b.writeln(s.text);
      b.writeln();
    }
    return b.toString();
  }

  static String _vtt(int ms) {
    final d = Duration(milliseconds: ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}.${d.inMilliseconds.remainder(1000).toString().padLeft(3, '0')}';
  }
}