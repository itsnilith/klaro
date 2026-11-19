import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../core/db.dart';
import '../core/models.dart';
import '../core/native_engine.dart';
import 'ai.dart';

class RetrievedChunk {
  RetrievedChunk({
    required this.text,
    required this.label,
    required this.sourceType,
    required this.sourceId,
    this.locator,
    this.score = 0,
  });
  final String text;
  final String label;
  final String sourceType;
  final String sourceId;
  final String? locator;
  final double score;
}

class RagService {
  RagService(this.store, this.ai);
  final Store store;
  final AiClient ai;

  static const _maxChunk = 900;
  static const _overlap = 140;

  /// Splits text on paragraph and sentence boundaries via the Rust native
  /// engine (or Dart fallback), keeping a small overlap so a fact that
  /// straddles a boundary is still retrievable.
  static List<String> chunk(String text) {
    return NativeEngine.i.chunkText(
      text,
      maxChars: _maxChunk,
      overlap: _overlap,
    );
  }

  Future<void> indexNote(Note note, {AiProvider? provider}) async {
    final text = '${note.title}\n\n${note.body}';
    final pieces = chunk(text);
    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < pieces.length; i++) {
      rows.add({
        'label': 'Note · ${note.title}',
        'text': pieces[i],
        'locator': 'part ${i + 1}',
        'embedding': await _embed(provider, pieces[i]),
      });
    }
    await store.replaceChunks('note', note.id, rows);
  }

  Future<void> indexTranscript({
    required String lessonId,
    required String lessonTitle,
    required String courseTitle,
    required List<TranscriptSegment> segments,
    AiProvider? provider,
  }) async {
    final rows = <Map<String, Object?>>[];
    var buffer = StringBuffer();
    var bufferStart = 0;
    Future<void> flush() async {
      final text = buffer.toString().trim();
      if (text.isEmpty) return;
      rows.add({
        'label': '$courseTitle · $lessonTitle · ${_clock(bufferStart)}',
        'text': text,
        'locator': _clock(bufferStart),
        'embedding': await _embed(provider, text),
      });
      buffer = StringBuffer();
    }

    for (final s in segments) {
      if (buffer.isEmpty) bufferStart = s.startMs;
      buffer.writeln(s.text);
      if (buffer.length > _maxChunk) await flush();
    }
    await flush();
    await store.replaceChunks('lesson', lessonId, rows);
  }

  Future<void> indexPdf({
    required String resourceId,
    required String title,
    required String path,
    AiProvider? provider,
    void Function(int page, int total)? onProgress,
  }) async {
    final doc = await PdfDocument.openFile(path);
    try {
      final rows = <Map<String, Object?>>[];
      for (var i = 0; i < doc.pages.length; i++) {
        final page = doc.pages[i];
        final raw = await page.loadText();
        final text = raw?.fullText ?? '';
        if (text.trim().length < 40) continue;
        final pieces = chunk(text);
        for (var j = 0; j < pieces.length; j++) {
          rows.add({
            'label': '$title · p. ${i + 1}',
            'text': pieces[j],
            'locator': 'p. ${i + 1}',
            'embedding': await _embed(provider, pieces[j]),
          });
        }
        onProgress?.call(i + 1, doc.pages.length);
      }
      await store.replaceChunks('resource', resourceId, rows);
    } finally {
      await doc.dispose();
    }
  }

  Future<void> indexTextFile({
    required String resourceId,
    required String title,
    required String path,
    AiProvider? provider,
  }) async {
    final file = File(path);
    if (!await file.exists()) return;
    final text = await file.readAsString();
    final pieces = chunk(text);
    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < pieces.length; i++) {
      rows.add({
        'label': '$title · part ${i + 1}',
        'text': pieces[i],
        'locator': 'part ${i + 1}',
        'embedding': await _embed(provider, pieces[i]),
      });
    }
    await store.replaceChunks('resource', resourceId, rows);
  }

  Future<Uint8List?> _embed(AiProvider? provider, String text) async {
    if (provider == null) return null;
    final v = await ai.embed(provider, text);
    if (v == null) return null;
    final f = Float32List.fromList(v);
    return f.buffer.asUint8List();
  }

  Future<List<RetrievedChunk>> retrieve(String query, {int limit = 6, AiProvider? provider}) async {
    final results = <String, RetrievedChunk>{};
    final lexical = await store.searchChunks(query, limit: limit * 2);
    for (final r in lexical) {
      final text = r['text'] as String;
      final bm25 = NativeEngine.i.bm25Score(query, text);
      final id = '${r['source_type']}:${r['source_id']}:${r['label']}:${text.hashCode}';
      results[id] = RetrievedChunk(
        text: text,
        label: r['label'] as String,
        sourceType: r['source_type'] as String,
        sourceId: r['source_id'] as String,
        locator: r['locator'] as String?,
        score: math.max(0.5, bm25),
      );
    }
    if (provider != null && provider.embeddingModel != null && provider.embeddingModel!.isNotEmpty) {
      final qv = await ai.embed(provider, query);
      if (qv != null) {
        final rows = await store.db.query('chunks',
            where: 'embedding IS NOT NULL', orderBy: 'updated_at DESC', limit: 1200);
        final scored = <(double, Map<String, Object?>)>[];
        for (final r in rows) {
          final blob = r['embedding'] as Uint8List?;
          if (blob == null) continue;
          final vec = blob.buffer.asFloat32List(blob.offsetInBytes, blob.lengthInBytes ~/ 4);
          if (vec.length != qv.length) continue;
          scored.add((_cosine(qv, vec), r));
        }
        scored.sort((a, b) => b.$1.compareTo(a.$1));
        for (final (score, r) in scored.take(limit * 2)) {
          if (score < 0.2) continue;
          final text = r['text'] as String;
          final id = '${r['source_type']}:${r['source_id']}:${r['label']}:${text.hashCode}';
          final existing = results[id];
          results[id] = RetrievedChunk(
            text: text,
            label: r['label'] as String,
            sourceType: r['source_type'] as String,
            sourceId: r['source_id'] as String,
            locator: r['locator'] as String?,
            score: math.max(score, existing?.score ?? 0),
          );
        }
      }
    }
    final list = results.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    return list.take(limit).toList();
  }

  static double _cosine(List<double> a, Float32List b) {
    return NativeEngine.i.cosineSimilarity(a, b);
  }

  static String _clock(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Builds the numbered context block and the citation list for a turn.
  static (String, List<Citation>) buildContext(List<RetrievedChunk> chunks) {
    if (chunks.isEmpty) return ('', const []);
    final b = StringBuffer();
    final citations = <Citation>[];
    for (var i = 0; i < chunks.length; i++) {
      final c = chunks[i];
      b.writeln('[${i + 1}] ${c.label}');
      b.writeln(c.text);
      b.writeln();
      citations.add(Citation(
        label: c.label,
        sourceType: c.sourceType,
        sourceId: c.sourceId,
        locator: c.locator,
      ));
    }
    return (b.toString(), citations);
  }
}
