import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/paths.dart';

/// Whisper.cpp models Klaro can manage itself.
///
/// Every multilingual v3 model is offered except `large`, which is replaced by
/// `large-v3-turbo`: same language coverage, far faster on a laptop.
class WhisperModel {
  const WhisperModel(this.id, this.label, this.sizeLabel);
  final String id;
  final String label;
  final String sizeLabel;
}

const whisperModels = <WhisperModel>[
  WhisperModel('tiny', 'Tiny', '39 MB'),
  WhisperModel('base', 'Base', '74 MB'),
  WhisperModel('small', 'Small', '244 MB'),
  WhisperModel('medium', 'Medium', '769 MB'),
  WhisperModel('large-v3-turbo', 'Large v3 Turbo', '1.6 GB'),
];

String whisperModelFileName(String id) => 'ggml-$id.bin';

Directory get _modelsDir => Directory(p.join(AppPaths.i.modelsDir, 'whisper'));

String whisperModelPath(String id) =>
    p.join(_modelsDir.path, whisperModelFileName(id));

bool isWhisperModelDownloaded(String id) => File(whisperModelPath(id)).existsSync();

String? firstDownloadedWhisperModel() {
  for (final m in whisperModels.reversed) {
    if (isWhisperModelDownloaded(m.id)) return whisperModelPath(m.id);
  }
  return null;
}

/// Streams a model into `<app>/models/whisper`, reporting 0..1 progress.
Future<void> downloadWhisperModel(
  String id, {
  void Function(double progress)? onProgress,
}) async {
  await _modelsDir.create(recursive: true);
  final target = File(whisperModelPath(id));
  final tmp = File('${target.path}.part');
  final uri = Uri.parse(
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${whisperModelFileName(id)}');
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', uri));
    if (response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = tmp.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (target.existsSync()) target.deleteSync();
    tmp.renameSync(target.path);
    onProgress?.call(1);
  } catch (_) {
    if (tmp.existsSync()) {
      try {
        tmp.deleteSync();
      } catch (_) {}
    }
    rethrow;
  } finally {
    client.close();
  }
}

Future<void> deleteWhisperModel(String id) async {
  final f = File(whisperModelPath(id));
  if (f.existsSync()) f.deleteSync();
}
