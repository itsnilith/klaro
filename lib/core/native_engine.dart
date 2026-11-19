import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef _VersionC = ffi.Pointer<Utf8> Function();
typedef _VersionDart = ffi.Pointer<Utf8> Function();

typedef _FreeStringC = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8>);

typedef _Fnv1a64C = ffi.Uint64 Function(ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _Fnv1a64Dart = int Function(ffi.Pointer<ffi.Uint8>, int);

typedef _Sha256HexC = ffi.Pointer<Utf8> Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
);
typedef _Sha256HexDart = ffi.Pointer<Utf8> Function(
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef _CosineF32C = ffi.Double Function(
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Float>,
  ffi.Size,
);
typedef _CosineF32Dart = double Function(
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Float>,
  int,
);

typedef _Bm25ScoreC = ffi.Double Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _Bm25ScoreDart = double Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

typedef _ChunkTextJsonC = ffi.Pointer<Utf8> Function(
  ffi.Pointer<Utf8>,
  ffi.Size,
  ffi.Size,
);
typedef _ChunkTextJsonDart = ffi.Pointer<Utf8> Function(
  ffi.Pointer<Utf8>,
  int,
  int,
);

/// FFI bridge to the Rust `klaro_engine` library with automatic Dart fallback.
class NativeEngine {
  NativeEngine._() {
    _tryLoad();
  }

  static final NativeEngine i = NativeEngine._();

  ffi.DynamicLibrary? _lib;
  _VersionDart? _version;
  _FreeStringDart? _freeString;
  _Fnv1a64Dart? _fnv1a64;
  _Sha256HexDart? _sha256Hex;
  _CosineF32Dart? _cosineF32;
  _Bm25ScoreDart? _bm25Score;
  _ChunkTextJsonDart? _chunkTextJson;

  bool get isNativeLoaded => _lib != null;

  String get version {
    final fn = _version;
    if (fn == null) return '1.0.0-dart-fallback';
    return fn().toDartString();
  }

  void _tryLoad() {
    if (!Platform.isWindows) return;
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      p.join(exeDir, 'klaro_engine.dll'),
      p.join(
        Directory.current.path,
        'native',
        'klaro_engine',
        'target',
        'release',
        'klaro_engine.dll',
      ),
      'klaro_engine.dll',
    ];
    for (final candidate in candidates) {
      try {
        if (candidate != 'klaro_engine.dll' && !File(candidate).existsSync()) {
          continue;
        }
        final lib = ffi.DynamicLibrary.open(candidate);
        _version = lib.lookupFunction<_VersionC, _VersionDart>(
          'klaro_engine_version',
        );
        _freeString = lib.lookupFunction<_FreeStringC, _FreeStringDart>(
          'klaro_free_string',
        );
        _fnv1a64 = lib.lookupFunction<_Fnv1a64C, _Fnv1a64Dart>('klaro_fnv1a64');
        _sha256Hex = lib.lookupFunction<_Sha256HexC, _Sha256HexDart>(
          'klaro_sha256_hex',
        );
        _cosineF32 = lib.lookupFunction<_CosineF32C, _CosineF32Dart>(
          'klaro_cosine_f32',
        );
        _bm25Score = lib.lookupFunction<_Bm25ScoreC, _Bm25ScoreDart>(
          'klaro_bm25_score',
        );
        _chunkTextJson = lib
            .lookupFunction<_ChunkTextJsonC, _ChunkTextJsonDart>(
              'klaro_chunk_text_json',
            );
        _lib = lib;
        break;
      } catch (_) {
        // Fallback to pure Dart if loading fails.
      }
    }
  }

  /// Computes a 64-bit FNV-1a fingerprint of [bytes].
  int fnv1a64(Uint8List bytes) {
    final fn = _fnv1a64;
    if (fn != null) {
      final ptr = malloc<ffi.Uint8>(bytes.length);
      try {
        ptr.asTypedList(bytes.length).setAll(0, bytes);
        return fn(ptr, bytes.length);
      } finally {
        malloc.free(ptr);
      }
    }
    var hash = 0xcbf29ce484222325;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash;
  }

  /// Computes the SHA-256 hex digest of [bytes].
  String sha256Hex(Uint8List bytes) {
    final fn = _sha256Hex;
    final freeFn = _freeString;
    if (fn != null && freeFn != null) {
      final ptr = malloc<ffi.Uint8>(bytes.length);
      try {
        ptr.asTypedList(bytes.length).setAll(0, bytes);
        final outPtr = fn(ptr, bytes.length);
        if (outPtr != ffi.nullptr) {
          try {
            return outPtr.toDartString();
          } finally {
            freeFn(outPtr);
          }
        }
      } finally {
        malloc.free(ptr);
      }
    }
    return crypto.sha256.convert(bytes).toString();
  }

  /// Computes cosine similarity between [a] and [b].
  double cosineSimilarity(List<double> a, Float32List b) {
    final n = math.min(a.length, b.length);
    if (n == 0) return 0;
    final fn = _cosineF32;
    if (fn != null) {
      final pa = malloc<ffi.Float>(n);
      final pb = malloc<ffi.Float>(n);
      try {
        final la = pa.asTypedList(n);
        for (var i = 0; i < n; i++) {
          la[i] = a[i];
        }
        pb.asTypedList(n).setAll(0, b.sublist(0, n));
        return fn(pa, pb, n);
      } finally {
        malloc.free(pa);
        malloc.free(pb);
      }
    }
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  /// Computes a BM25 lexical relevance score between [query] and [document].
  double bm25Score(String query, String document) {
    final fn = _bm25Score;
    if (fn != null) {
      final qPtr = query.toNativeUtf8();
      final dPtr = document.toNativeUtf8();
      try {
        return fn(qPtr, dPtr);
      } finally {
        malloc.free(qPtr);
        malloc.free(dPtr);
      }
    }
    final qTerms = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();
    if (qTerms.isEmpty) return 0;
    final dTerms = document
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();
    if (dTerms.isEmpty) return 0;
    var score = 0.0;
    for (final qt in qTerms) {
      final tf = dTerms.where((t) => t == qt).length;
      if (tf > 0) {
        score += 1.0 + math.log(tf);
      }
    }
    return score;
  }

  /// Splits [text] into overlapping chunks on paragraph/sentence boundaries.
  List<String> chunkText(String text, {int maxChars = 900, int overlap = 140}) {
    final fn = _chunkTextJson;
    final freeFn = _freeString;
    if (fn != null && freeFn != null) {
      final ptr = text.toNativeUtf8();
      try {
        final resPtr = fn(ptr, maxChars, overlap);
        if (resPtr != ffi.nullptr) {
          try {
            final jsonStr = resPtr.toDartString();
            final decoded = jsonDecode(jsonStr) as List<dynamic>;
            return decoded.cast<String>();
          } finally {
            freeFn(resPtr);
          }
        }
      } finally {
        malloc.free(ptr);
      }
    }
    final clean = text
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (clean.isEmpty) return [];
    final out = <String>[];
    var start = 0;
    while (start < clean.length) {
      var end = math.min(start + maxChars, clean.length);
      if (end < clean.length) {
        final window = clean.substring(start, end);
        final cut = [
          window.lastIndexOf('\n\n'),
          window.lastIndexOf('. '),
          window.lastIndexOf('? '),
          window.lastIndexOf('! '),
        ].reduce(math.max);
        if (cut > maxChars * 0.5) end = start + cut + 1;
      }
      final piece = clean.substring(start, end).trim();
      if (piece.isNotEmpty) out.add(piece);
      if (end >= clean.length) break;
      start = math.max(end - overlap, start + 1);
    }
    return out;
  }
}
