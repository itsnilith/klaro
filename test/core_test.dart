import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klaro/core/db.dart';
import 'package:klaro/core/models.dart';
import 'package:klaro/core/native_engine.dart';
import 'package:klaro/services/rag.dart';
import 'package:klaro/services/sync.dart';
import 'package:klaro/services/transcription.dart';

import 'test_paths.dart';

void main() {
  group('Rust FFI native engine', () {
    test('loads native Rust DLL and reports version', () {
      expect(NativeEngine.i.isNativeLoaded, isTrue);
      expect(NativeEngine.i.version, '1.0.0-rust');
    });

    test('computes FIPS 180-4 SHA-256 and FNV-1a hashes', () {
      final bytes = Uint8List.fromList(utf8.encode('abc'));
      expect(
        NativeEngine.i.sha256Hex(bytes),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(NativeEngine.i.fnv1a64(bytes), isNonZero);
    });

    test('computes cosine similarity and BM25 lexical score', () {
      final sim = NativeEngine.i.cosineSimilarity(
        [1.0, 0.0, 1.0],
        Float32List.fromList([1.0, 0.0, 1.0]),
      );
      expect(sim, closeTo(1.0, 1e-6));

      final high = NativeEngine.i.bm25Score(
        'active recall spaced repetition',
        'Active recall and spaced repetition strengthen long-term memory traces.',
      );
      final low = NativeEngine.i.bm25Score(
        'active recall spaced repetition',
        'Matrix multiplication over complex eigenvalues.',
      );
      expect(high, greaterThan(low));
    });
  });

  group('chunking', () {
    test('keeps short text intact', () {
      expect(RagService.chunk('A short sentence.'), ['A short sentence.']);
    });

    test('splits long text and stays within the window', () {
      final text = List.generate(
        200,
        (i) => 'Sentence number $i about entropy and uncertainty.',
      ).join(' ');
      final chunks = RagService.chunk(text);
      expect(chunks.length, greaterThan(1));
      expect(chunks.every((c) => c.length <= 1000), isTrue);
    });
  });

  group('transcript parsing', () {
    test('parses SRT timestamps and text', () {
      const srt =
          '1\n00:00:01,000 --> 00:00:03,500\nHello there.\n\n'
          '2\n00:00:04,000 --> 00:00:06,000\nSecond line.\n';
      final segments = TranscriptionService.parseSrt(srt);
      expect(segments.length, 2);
      expect(segments.first.startMs, 1000);
      expect(segments.first.text, 'Hello there.');
      expect(segments.last.endMs, 6000);
    });

    test('emits valid WebVTT', () {
      final vtt = TranscriptionService.toVtt(const [
        TranscriptSegment(startMs: 1500, endMs: 2500, text: 'Hi'),
      ]);
      expect(vtt.startsWith('WEBVTT'), isTrue);
      expect(vtt.contains('00:00:01.500 --> 00:00:02.500'), isTrue);
    });
  });

  group('portable paths & SQLite persistence', () {
    test('creates the portable layout and persists courses, notes, and SM-2 cards', () async {
      final paths = testPaths();
      for (final dir in [
        paths.dataDir,
        paths.configDir,
        paths.modelsDir,
        paths.cacheDir,
      ]) {
        expect(Directory(dir).existsSync(), isTrue, reason: dir);
      }

      final store = await Store.open();
      final now = DateTime.now();

      // Schema v4: nested pages and schema node metadata must exist.
      final noteCols = await store.db.rawQuery('PRAGMA table_info(notes)');
      final noteColNames = noteCols.map((r) => r['name'] as String).toSet();
      expect(noteColNames.contains('parent_id'), isTrue);
      expect(noteColNames.contains('icon'), isTrue);
      expect(noteColNames.contains('cover'), isTrue);
      expect(noteColNames.contains('deleted_at'), isTrue);
      expect(noteColNames.contains('position'), isTrue);
      final nodeCols = await store.db.rawQuery('PRAGMA table_info(concept_nodes)');
      final nodeColNames = nodeCols.map((r) => r['name'] as String).toSet();
      expect(nodeColNames.contains('kind'), isTrue);
      expect(nodeColNames.contains('start_year'), isTrue);
      final course = Course(
        id: 'test-course-1',
        title: 'Cognitive Psychology of Learning',
        author: 'itsnilith',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveCourse(course);
      final loaded = await store.course('test-course-1');
      expect(loaded?.title, 'Cognitive Psychology of Learning');

      await store.saveExtract(StudyExtract(
        id: 'test-extract-1',
        kind: 'formula',
        content: r'Q = \Delta m c^2',
        description: 'Mass-energy equivalence in nuclear fission',
        courseId: 'test-course-1',
        page: 17,
        createdAt: now,
      ));
      final extracts = await store.extracts(courseId: 'test-course-1');
      expect(extracts.length, 1);
      expect(extracts.first.page, 17);

      final mapDoc = ConceptMapDoc(
        id: 'test-map-1',
        title: 'Nuclear Fission Schema',
        courseId: 'test-course-1',
        createdAt: now,
        updatedAt: now,
      );
      await store.saveConceptMap(mapDoc);
      await store.saveConceptNode(const ConceptNode(
        id: 'test-node-1',
        mapId: 'test-map-1',
        title: 'Uranium-235',
        body: 'Captures slow neutron',
      ));
      final bundle = await store.exportKnowledgeBundle(
        courseId: 'test-course-1',
        title: 'Fission Card',
      );
      expect(bundle['format'], 'klaro-knowledge-card-v1');
      expect((bundle['extracts'] as List).length, 1);
      expect((bundle['maps'] as List).length, 1);

      final card = Flashcard(
        id: 'test-card-1',
        deck: 'Cognitive Psychology',
        front: 'What is the testing effect?',
        back: 'Retrieving information from memory strengthens retention more than restudying.',
        dueAt: now,
        createdAt: now,
      );
      await store.saveCard(card);
      final reviewed = await store.reviewCard(card, 3); // Easy
      expect(reviewed.reps, 1);
      expect(reviewed.intervalDays, greaterThanOrEqualTo(4));

      await store.deleteExtract('test-extract-1');
      await store.deleteConceptMap('test-map-1');
      await store.deleteCard('test-card-1');
      await store.deleteCourse('test-course-1');
    });
  });

  group('sync envelope', () {
    test('seals and opens a payload with the same key', () async {
      final key = List<int>.generate(32, (i) => i);
      final sealed = await sealJson({'a': 1, 'text': 'ciao'}, key);
      final opened = await openJson(SyncSealed.decode(sealed.encode()), key);
      expect(opened['a'], 1);
      expect(opened['text'], 'ciao');
    });

    test('rejects a different key', () async {
      final sealed = await sealJson({'a': 1}, List<int>.generate(32, (i) => i));
      final other = List<int>.generate(32, (i) => i + 1);
      expect(
        () => openJson(SyncSealed.decode(sealed.encode()), other),
        throwsA(anything),
      );
    });
  });
}
