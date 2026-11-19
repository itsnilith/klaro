import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../features/notes/block_model.dart';
import 'models.dart';
import 'paths.dart';

const _uuid = Uuid();

const _tagPalette = <String>[
  '#2563EB',
  '#059669',
  '#D97706',
  '#DC2626',
  '#7C3AED',
  '#0891B2',
  '#DB2777',
  '#4B5563',
];

Map<String, Object?> _lessonMap(Lesson l) => {
  'id': l.id,
  'course_id': l.courseId,
  'module_id': l.moduleId,
  'title': l.title,
  'path': l.path,
  'kind': l.kind,
  'duration_ms': l.durationMs,
  'position': l.position,
  'transcript_id': l.transcriptId,
  'description': l.description,
  'created_at': (l.createdAt ?? DateTime.now()).millisecondsSinceEpoch,
};

Map<String, Object?> _cardMap(Flashcard c) => {
  'id': c.id,
  'deck': c.deck,
  'front': c.front,
  'back': c.back,
  'course_id': c.courseId,
  'lesson_id': c.lessonId,
  'resource_id': c.resourceId,
  'page': c.page,
  'created_at': c.createdAt.millisecondsSinceEpoch,
  'due_at': c.dueAt.millisecondsSinceEpoch,
  'interval_days': c.intervalDays,
  'ease': c.ease,
  'reps': c.reps,
  'lapses': c.lapses,
  'state': c.state,
};

class Store {
  Store._(this.db);

  final Database db;

  static Store? _instance;
  static Store get i => _instance!;

  static Future<Store> open() async {
    if (_instance != null) return _instance!;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = AppPaths.i.dbPath;
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 13,
        onConfigure: (db) async {
          await db.execute('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA synchronous=NORMAL');
          await db.execute('PRAGMA foreign_keys=ON');
          await db.execute('PRAGMA busy_timeout=5000');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
          await _createV2Schema(db);
          await _createV3Schema(db);
          await _createV4Schema(db);
          await _createV5Schema(db);
          await _createV6Schema(db);
          await _createV7Schema(db);
          await _createV8Schema(db);
          await _createV9Schema(db);
          await _createV10Schema(db);
          await _createV11Schema(db);
          await _createV12Schema(db);
          await _createV13Schema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createV2Schema(db);
          }
          if (oldVersion < 3) {
            await _createV3Schema(db);
          }
          if (oldVersion < 4) {
            await _createV4Schema(db);
          }
          if (oldVersion < 5) {
            await _createV5Schema(db);
          }
          if (oldVersion < 6) {
            await _createV6Schema(db);
          }
          if (oldVersion < 7) {
            await _createV7Schema(db);
          }
          if (oldVersion < 8) {
            await _createV8Schema(db);
          }
          if (oldVersion < 9) {
            await _createV9Schema(db);
          }
          if (oldVersion < 10) {
            await _createV10Schema(db);
          }
          if (oldVersion < 11) {
            await _createV11Schema(db);
          }
          if (oldVersion < 12) {
            await _createV12Schema(db);
          }
          if (oldVersion < 13) {
            await _createV13Schema(db);
          }
        },
      ),
    );
    _instance = Store._(db);
    return _instance!;
  }

  static Future<void> _createSchema(Database db) async {
    final b = db.batch();
    b.execute(
      '''CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)''',
    );
    b.execute('''CREATE TABLE courses (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT, description TEXT,
      cover TEXT, category TEXT, objectives TEXT, favorite INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL, last_opened_at INTEGER)''');
    b.execute('''CREATE TABLE modules (
      id TEXT PRIMARY KEY, course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
      title TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0)''');
    b.execute('''CREATE TABLE lessons (
      id TEXT PRIMARY KEY, course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
      module_id TEXT, title TEXT NOT NULL, path TEXT, kind TEXT NOT NULL DEFAULT 'video',
      duration_ms INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0,
      transcript_id TEXT, created_at INTEGER NOT NULL)''');
    b.execute('''CREATE TABLE progress (
      lesson_id TEXT PRIMARY KEY REFERENCES lessons(id) ON DELETE CASCADE,
      position_ms INTEGER NOT NULL DEFAULT 0, watched_ms INTEGER NOT NULL DEFAULT 0,
      completed INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)''');
    b.execute('''CREATE TABLE resources (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, path TEXT NOT NULL, kind TEXT NOT NULL,
      size INTEGER NOT NULL DEFAULT 0, hash TEXT, course_id TEXT, favorite INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL, last_opened_at INTEGER)''');
    b.execute(
      '''CREATE TABLE notes (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL DEFAULT '',
      course_id TEXT, lesson_id TEXT, resource_id TEXT, page INTEGER, timestamp_ms INTEGER,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, pinned INTEGER NOT NULL DEFAULT 0)''',
    );
    b.execute('''CREATE TABLE tags (
      id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, color TEXT)''');
    b.execute('''CREATE TABLE taggables (
      tag_id TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
      PRIMARY KEY (tag_id, entity_type, entity_id))''');
    b.execute('''CREATE TABLE cards (
      id TEXT PRIMARY KEY, deck TEXT NOT NULL, front TEXT NOT NULL, back TEXT NOT NULL,
      course_id TEXT, lesson_id TEXT, resource_id TEXT, page INTEGER,
      created_at INTEGER NOT NULL, due_at INTEGER NOT NULL, interval_days REAL NOT NULL DEFAULT 0,
      ease REAL NOT NULL DEFAULT 2.5, reps INTEGER NOT NULL DEFAULT 0,
      lapses INTEGER NOT NULL DEFAULT 0, state TEXT NOT NULL DEFAULT 'new')''');
    b.execute('''CREATE TABLE reviews (
      id TEXT PRIMARY KEY, card_id TEXT NOT NULL, rating INTEGER NOT NULL,
      reviewed_at INTEGER NOT NULL, duration_ms INTEGER NOT NULL DEFAULT 0)''');
    b.execute(
      '''CREATE TABLE threads (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, mode TEXT NOT NULL,
      course_id TEXT, lesson_id TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    );
    b.execute('''CREATE TABLE messages (
      id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, role TEXT NOT NULL,
      content TEXT NOT NULL, citations TEXT, created_at INTEGER NOT NULL)''');
    b.execute('''CREATE TABLE providers (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, base_url TEXT NOT NULL,
      model TEXT NOT NULL, api_key TEXT NOT NULL DEFAULT '', temperature REAL NOT NULL DEFAULT 0.4,
      context_window INTEGER NOT NULL DEFAULT 8192, is_default INTEGER NOT NULL DEFAULT 0,
      embedding_model TEXT, capabilities TEXT NOT NULL DEFAULT 'chat')''');
    b.execute(
      '''CREATE TABLE devices (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, public_key TEXT NOT NULL,
      paired_at INTEGER NOT NULL, last_sync_at INTEGER, revoked INTEGER NOT NULL DEFAULT 0)''',
    );
    b.execute(
      '''CREATE TABLE transcripts (
      id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL,
      language TEXT NOT NULL, source TEXT NOT NULL, segments TEXT NOT NULL, created_at INTEGER NOT NULL)''',
    );
    b.execute(
      '''CREATE TABLE chunks (
      id TEXT PRIMARY KEY, source_type TEXT NOT NULL, source_id TEXT NOT NULL,
      label TEXT NOT NULL, text TEXT NOT NULL, locator TEXT, embedding BLOB, updated_at INTEGER NOT NULL)''',
    );
    b.execute(
      '''CREATE TABLE sync_log (
      id TEXT PRIMARY KEY, device_id TEXT, at INTEGER NOT NULL, direction TEXT,
      items INTEGER NOT NULL DEFAULT 0, bytes INTEGER NOT NULL DEFAULT 0, note TEXT)''',
    );
    b.execute('CREATE INDEX idx_lessons_course ON lessons(course_id)');
    b.execute('CREATE INDEX idx_resources_course ON resources(course_id)');
    b.execute('CREATE INDEX idx_notes_lesson ON notes(lesson_id)');
    b.execute('CREATE INDEX idx_cards_due ON cards(due_at)');
    b.execute(
      'CREATE INDEX idx_chunks_source ON chunks(source_type, source_id)',
    );
    b.execute('CREATE INDEX idx_messages_thread ON messages(thread_id)');
    await b.commit();

    try {
      await db.execute(
        "CREATE VIRTUAL TABLE chunks_fts USING fts5(text, content='chunks', content_rowid='rowid')",
      );
      await db.execute(
        '''CREATE TRIGGER chunks_ai AFTER INSERT ON chunks BEGIN
        INSERT INTO chunks_fts(rowid, text) VALUES (new.rowid, new.text); END''',
      );
      await db.execute(
        '''CREATE TRIGGER chunks_ad AFTER DELETE ON chunks BEGIN
        INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.rowid, old.text); END''',
      );
      await db.execute(
        '''CREATE TRIGGER chunks_au AFTER UPDATE ON chunks BEGIN
        INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.rowid, old.text);
        INSERT INTO chunks_fts(rowid, text) VALUES (new.rowid, new.text); END''',
      );
    } catch (_) {
      // FTS5 is optional; retrieval falls back to LIKE.
    }
  }

  static Future<void> _createV2Schema(Database db) async {
    final b = db.batch();
    b.execute('''CREATE TABLE IF NOT EXISTS extracts (
      id TEXT PRIMARY KEY, kind TEXT NOT NULL, content TEXT NOT NULL,
      description TEXT, tags TEXT NOT NULL DEFAULT '',
      course_id TEXT, lesson_id TEXT, resource_id TEXT, page INTEGER, timestamp_ms INTEGER,
      created_at INTEGER NOT NULL)''');
    b.execute('''CREATE TABLE IF NOT EXISTS concept_maps (
      id TEXT PRIMARY KEY, title TEXT NOT NULL,
      course_id TEXT, resource_id TEXT,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
    b.execute(
      '''CREATE TABLE IF NOT EXISTS concept_nodes (
      id TEXT PRIMARY KEY, map_id TEXT NOT NULL REFERENCES concept_maps(id) ON DELETE CASCADE,
      parent_id TEXT, title TEXT NOT NULL, body TEXT NOT NULL DEFAULT '',
      x REAL NOT NULL DEFAULT 120, y REAL NOT NULL DEFAULT 120, source_label TEXT)''',
    );
    b.execute(
      'CREATE INDEX IF NOT EXISTS idx_extracts_resource ON extracts(resource_id)',
    );
    b.execute(
      'CREATE INDEX IF NOT EXISTS idx_extracts_course ON extracts(course_id)',
    );
    b.execute(
      'CREATE INDEX IF NOT EXISTS idx_concept_nodes_map ON concept_nodes(map_id)',
    );
    await b.commit();
  }

  static Future<void> _createV3Schema(Database db) async {
    for (final stmt in [
      "ALTER TABLE concept_maps ADD COLUMN kind TEXT NOT NULL DEFAULT 'mindmap'",
      "ALTER TABLE concept_nodes ADD COLUMN kind TEXT NOT NULL DEFAULT 'normal'",
      "ALTER TABLE concept_nodes ADD COLUMN color TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE concept_nodes ADD COLUMN start_year REAL",
      "ALTER TABLE concept_nodes ADD COLUMN end_year REAL",
      "ALTER TABLE concept_nodes ADD COLUMN lane INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE concept_nodes ADD COLUMN linked_node_id TEXT",
      "ALTER TABLE concept_nodes ADD COLUMN link_label TEXT",
    ]) {
      try {
        await db.execute(stmt);
      } catch (_) {}
    }
  }

  static Future<void> _createV4Schema(Database db) async {
    for (final stmt in [
      "ALTER TABLE notes ADD COLUMN parent_id TEXT",
      "ALTER TABLE notes ADD COLUMN icon TEXT NOT NULL DEFAULT ''",
    ]) {
      try {
        await db.execute(stmt);
      } catch (_) {}
    }
  }

  /// v13: a free-form description per lesson, editable under the player.
  static Future<void> _createV13Schema(Database db) async {
    try {
      await db.execute('ALTER TABLE lessons ADD COLUMN description TEXT');
    } catch (_) {}
  }

  /// v12: per-module cover image path for the module gallery view.
  static Future<void> _createV12Schema(Database db) async {
    try {
      await db.execute('ALTER TABLE modules ADD COLUMN cover TEXT');
    } catch (_) {}
  }

  /// v11: remember the folder a course was imported from. Purely metadata, so
  /// "Open folder" keeps working even after the list hides the course.
  static Future<void> _createV11Schema(Database db) async {
    try {
      await db.execute('ALTER TABLE courses ADD COLUMN folder TEXT');
    } catch (_) {}
  }

  static Future<void> _createV10Schema(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS bookmarks (
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (entity_type, entity_id))''');
  }

  static Future<void> _createV9Schema(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS page_templates (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      snapshot TEXT NOT NULL,
      created_at INTEGER NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_page_templates ON page_templates(created_at DESC)',
    );
  }

  static Future<void> _createV8Schema(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS note_versions (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      snapshot TEXT NOT NULL,
      label TEXT,
      created_at INTEGER NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_note_versions ON note_versions(note_id, created_at DESC)',
    );
  }

  static Future<void> _createV7Schema(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS note_blocks (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      parent_id TEXT,
      sort_key TEXT NOT NULL,
      type TEXT NOT NULL,
      text TEXT NOT NULL DEFAULT '',
      props TEXT NOT NULL DEFAULT '{}',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_note_blocks_note ON note_blocks(note_id, parent_id, sort_key)',
    );
  }

  static Future<void> _createV6Schema(Database db) async {
    for (final stmt in [
      'ALTER TABLE notes ADD COLUMN position INTEGER NOT NULL DEFAULT 0',
      'CREATE INDEX IF NOT EXISTS idx_notes_position ON notes(parent_id, position)',
    ]) {
      try {
        await db.execute(stmt);
      } catch (_) {}
    }
  }

  static Future<void> _createV5Schema(Database db) async {
    for (final stmt in [
      "ALTER TABLE notes ADD COLUMN cover TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE notes ADD COLUMN deleted_at INTEGER",
      'CREATE INDEX IF NOT EXISTS idx_notes_parent ON notes(parent_id)',
      'CREATE INDEX IF NOT EXISTS idx_notes_deleted ON notes(deleted_at)',
    ]) {
      try {
        await db.execute(stmt);
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------- meta

  Future<String?> metaGet(String key) async {
    final rows = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> metaSet(String key, String value) async {
    await db.insert('meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> metaAll() async {
    final rows = await db.query('meta');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  // ---------------------------------------------------------------- courses

  Future<List<Course>> courses({bool includeArchived = false}) async {
    final rows = await db.query(
      'courses',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'COALESCE(last_opened_at, updated_at) DESC',
    );
    return rows.map(Course.fromMap).toList();
  }

  Future<Course?> course(String id) async {
    final rows = await db.query(
      'courses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Course.fromMap(rows.first);
  }

  Future<void> saveCourse(Course c) async {
    await db.insert(
      'courses',
      c.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteCourse(String id) async {
    await db.transaction((txn) async {
      final lessonRows = await txn.query(
        'lessons',
        columns: ['id'],
        where: 'course_id = ?',
        whereArgs: [id],
      );
      for (final r in lessonRows) {
        final lid = r['id'] as String;
        await txn.delete(
          'chunks',
          where: 'source_type = ? AND source_id = ?',
          whereArgs: ['lesson', lid],
        );
        await txn.delete(
          'transcripts',
          where: 'owner_type = ? AND owner_id = ?',
          whereArgs: ['lesson', lid],
        );
        await txn.delete(
          'taggables',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: ['lesson', lid],
        );
        await txn.delete(
          'bookmarks',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: ['lesson', lid],
        );
      }
      await txn.delete(
        'taggables',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['course', id],
      );
      await txn.delete(
        'bookmarks',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['course', id],
      );
      await txn.delete('courses', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Hides or restores a course in the list. The row stays in the database and
  /// no file on disk is touched.
  Future<void> setCourseArchived(String id, bool archived) async {
    await db.update(
      'courses',
      {
        'archived': archived ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setCourseCover(String id, String? cover) async {
    await db.update(
      'courses',
      {'cover': cover, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> touchCourse(String id) async {
    await db.update(
      'courses',
      {'last_opened_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------- modules / lessons

  Future<List<Module>> modules(String courseId) async {
    final rows = await db.query(
      'modules',
      where: 'course_id = ?',
      whereArgs: [courseId],
      orderBy: 'position',
    );
    return rows.map(Module.fromMap).toList();
  }

  Future<void> saveModule(Module m) async {
    await db.insert('modules', {
      'id': m.id,
      'course_id': m.courseId,
      'title': m.title,
      'position': m.position,
      'cover': m.cover,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Inserts imported modules, lessons and resources in a single transaction.
  Future<void> saveCourseImportBatch({
    required String courseId,
    required List<Module> modules,
    required List<Lesson> lessons,
    required List<({String title, String path, String kind, int size})>
    resources,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final m in modules) {
        batch.insert('modules', {
          'id': m.id,
          'course_id': m.courseId,
          'title': m.title,
          'position': m.position,
          'cover': m.cover,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final l in lessons) {
        batch.insert(
          'lessons',
          _lessonMap(l),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final r in resources) {
        batch.insert('resources', {
          'id': _uuid.v4(),
          'title': r.title,
          'path': r.path,
          'kind': r.kind,
          'size': r.size,
          'course_id': courseId,
          'created_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> setModuleCover(String id, String? cover) async {
    await db.update(
      'modules',
      {'cover': cover},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Rewrites lesson positions in one transaction. Order is the display order
  /// the user arranged: modules first, then lessons inside each module.
  Future<void> reorderLessons(List<String> orderedIds) async {
    await db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.update(
          'lessons',
          {'position': i},
          where: 'id = ?',
          whereArgs: [orderedIds[i]],
        );
      }
    });
  }

  Future<void> reorderModules(List<String> orderedIds) async {
    await db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.update(
          'modules',
          {'position': i},
          where: 'id = ?',
          whereArgs: [orderedIds[i]],
        );
      }
    });
  }

  Future<void> renameModule(String id, String title) async {
    await db.update(
      'modules',
      {'title': title},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Lesson>> lessons(String courseId) async {
    final rows = await db.query(
      'lessons',
      where: 'course_id = ?',
      whereArgs: [courseId],
      orderBy: 'position, created_at',
    );
    return rows.map(Lesson.fromMap).toList();
  }

  Future<Lesson?> lesson(String id) async {
    final rows = await db.query(
      'lessons',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Lesson.fromMap(rows.first);
  }

  Future<void> saveLesson(Lesson l) async {
    await db.insert(
      'lessons',
      _lessonMap(l),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Creates the module item and all its questions together: a failed write
  /// never leaves a quiz with only part of its questions.
  Future<void> createQuiz(Lesson lesson, List<Flashcard> questions) async {
    if (lesson.kind != 'quiz') {
      throw ArgumentError.value(lesson.kind, 'lesson.kind', 'must be quiz');
    }
    if (questions.isEmpty) {
      throw ArgumentError.value(questions, 'questions', 'must not be empty');
    }
    await db.transaction((txn) async {
      await txn.insert('lessons', _lessonMap(lesson));
      for (final question in questions) {
        await txn.insert('cards', _cardMap(question));
      }
    });
  }

  Future<List<Flashcard>> cardsForLesson(String lessonId) async {
    final rows = await db.query(
      'cards',
      where: 'lesson_id = ?',
      whereArgs: [lessonId],
      orderBy: 'created_at, id',
    );
    return rows.map(Flashcard.fromMap).toList();
  }

  Future<void> setLessonDescription(String id, String? description) async {
    await db.update(
      'lessons',
      {'description': description},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> renameLesson(String id, String title) async {
    await db.update(
      'lessons',
      {'title': title},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteLesson(String id) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'lessons',
        columns: ['kind'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty && rows.first['kind'] == 'quiz') {
        // Only a quiz owns its questions. Cards attached to ordinary lessons
        // may have been created independently and retain their prior behavior.
        await txn.delete('cards', where: 'lesson_id = ?', whereArgs: [id]);
      }
      await txn.delete(
        'chunks',
        where: 'source_type = ? AND source_id = ?',
        whereArgs: ['lesson', id],
      );
      await txn.delete(
        'transcripts',
        where: 'owner_type = ? AND owner_id = ?',
        whereArgs: ['lesson', id],
      );
      await txn.delete(
        'taggables',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['lesson', id],
      );
      await txn.delete(
        'bookmarks',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['lesson', id],
      );
      await txn.delete('lessons', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> setLessonDuration(String id, int ms) async {
    await db.update(
      'lessons',
      {'duration_ms': ms},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------- progress

  Future<Progress?> progress(String lessonId) async {
    final rows = await db.query(
      'progress',
      where: 'lesson_id = ?',
      whereArgs: [lessonId],
      limit: 1,
    );
    return rows.isEmpty ? null : Progress.fromMap(rows.first);
  }

  Future<void> saveProgress(
    String lessonId,
    int positionMs,
    int watchedMs,
    bool completed,
  ) async {
    await db.insert('progress', {
      'lesson_id': lessonId,
      'position_ms': positionMs,
      'watched_ms': watchedMs,
      'completed': completed ? 1 : 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Marks a single lesson completed or incomplete while preserving any saved
  /// playback position and watched time.
  Future<void> toggleLessonCompleted(String lessonId, bool completed) async {
    final existing = await progress(lessonId);
    await saveProgress(
      lessonId,
      existing?.positionMs ?? 0,
      existing?.watchedMs ?? 0,
      completed,
    );
  }

  /// Marks every lesson in a module (or the ungrouped lessons when [moduleId]
  /// is null) completed or incomplete in one transaction.
  Future<void> setModuleCompleted(
    String courseId,
    String? moduleId,
    bool completed,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'lessons',
      columns: ['id'],
      where: moduleId == null
          ? 'course_id = ? AND module_id IS NULL'
          : 'course_id = ? AND module_id = ?',
      whereArgs: moduleId == null ? [courseId] : [courseId, moduleId],
    );
    await db.transaction((txn) async {
      for (final r in rows) {
        final id = r['id'] as String;
        final existing = await txn.query(
          'progress',
          where: 'lesson_id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final pos = existing.isEmpty
            ? 0
            : (existing.first['position_ms'] as int? ?? 0);
        final watched = existing.isEmpty
            ? 0
            : (existing.first['watched_ms'] as int? ?? 0);
        await txn.insert('progress', {
          'lesson_id': id,
          'position_ms': pos,
          'watched_ms': watched,
          'completed': completed ? 1 : 0,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Loads all progress rows for a course in a single query.
  Future<Map<String, Progress>> courseProgressMap(String courseId) async {
    final rows = await db.rawQuery(
      '''
      SELECT p.*
      FROM progress p
      JOIN lessons l ON l.id = p.lesson_id
      WHERE l.course_id = ?''',
      [courseId],
    );
    return {
      for (final r in rows) (r['lesson_id'] as String): Progress.fromMap(r),
    };
  }

  Future<Map<String, int>> courseProgress(String courseId) async {
    final rows = await db.rawQuery(
      '''
      SELECT l.id, COALESCE(p.watched_ms, 0) AS watched, l.duration_ms, COALESCE(p.completed, 0) AS done
      FROM lessons l LEFT JOIN progress p ON p.lesson_id = l.id
      WHERE l.course_id = ?''',
      [courseId],
    );
    var done = 0;
    for (final r in rows) {
      if ((r['done'] as int? ?? 0) == 1) done++;
    }
    return {'total': rows.length, 'done': done};
  }

  Future<List<Map<String, Object?>>> continueWatching({int limit = 4}) async {
    return db.rawQuery(
      '''
      SELECT l.*, c.title AS course_title, p.position_ms, p.watched_ms, p.updated_at AS progress_at
      FROM progress p
      JOIN lessons l ON l.id = p.lesson_id
      JOIN courses c ON c.id = l.course_id
      WHERE p.completed = 0 AND p.position_ms > 5000
      ORDER BY p.updated_at DESC LIMIT ?''',
      [limit],
    );
  }

  // ---------------------------------------------------------------- resources

  Future<List<LibraryResource>> resources({
    String? kind,
    String? courseId,
    bool standaloneOnly = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    if (courseId != null) {
      where.add('course_id = ?');
      args.add(courseId);
    }
    // The Library holds what the reader added directly; course attachments stay
    // with their course.
    if (standaloneOnly) where.add('course_id IS NULL');
    final rows = await db.query(
      'resources',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'COALESCE(last_opened_at, created_at) DESC',
    );
    return rows.map(LibraryResource.fromMap).toList();
  }

  Future<LibraryResource?> resource(String id) async {
    final rows = await db.query(
      'resources',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : LibraryResource.fromMap(rows.first);
  }

  Future<String> addResource({
    required String title,
    required String path,
    required String kind,
    int size = 0,
    String? courseId,
  }) async {
    final id = _uuid.v4();
    await db.insert('resources', {
      'id': id,
      'title': title,
      'path': path,
      'kind': kind,
      'size': size,
      'course_id': courseId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return id;
  }

  /// Removes only the catalogue entry (and its tags). The file on disk is
  /// never touched: klaro. references files where they already live.
  Future<void> deleteResource(String id) async {
    await db.transaction((txn) async {
      await txn.delete(
        'taggables',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['resource', id],
      );
      await txn.delete(
        'bookmarks',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['resource', id],
      );
      await txn.delete(
        'chunks',
        where: 'source_type = ? AND source_id = ?',
        whereArgs: ['resource', id],
      );
      await txn.delete('resources', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> touchResource(String id) async {
    await db.update(
      'resources',
      {'last_opened_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------- tags

  Future<List<TagModel>> tags() async {
    final rows = await db.query('tags', orderBy: 'name COLLATE NOCASE');
    return rows.map(TagModel.fromMap).toList();
  }

  Future<TagModel> createTag(String name, {String? color}) async {
    final clean = name.trim();
    final existing = await db.query(
      'tags',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [clean],
      limit: 1,
    );
    if (existing.isNotEmpty) return TagModel.fromMap(existing.first);
    final tag = TagModel(
      id: _uuid.v4(),
      name: clean,
      color:
          color ?? _tagPalette[DateTime.now().microsecond % _tagPalette.length],
    );
    await db.insert('tags', {
      'id': tag.id,
      'name': tag.name,
      'color': tag.color,
    });
    return tag;
  }

  Future<void> renameTag(String id, String name) async {
    await db.update(
      'tags',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> recolorTag(String id, String color) async {
    await db.update('tags', {'color': color}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTag(String id) async {
    await db.transaction((txn) async {
      await txn.delete('taggables', where: 'tag_id = ?', whereArgs: [id]);
      await txn.delete('tags', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> tagUsage(String tagId) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM taggables WHERE tag_id = ?',
      [tagId],
    );
    return rows.first['n'] as int? ?? 0;
  }

  Future<List<TagModel>> tagsFor(String entityType, String entityId) async {
    final rows = await db.rawQuery(
      '''
      SELECT t.* FROM tags t
      JOIN taggables g ON g.tag_id = t.id
      WHERE g.entity_type = ? AND g.entity_id = ?
      ORDER BY t.name COLLATE NOCASE''',
      [entityType, entityId],
    );
    return rows.map(TagModel.fromMap).toList();
  }

  Future<Set<String>> tagIdsFor(String entityType, String entityId) async {
    final rows = await db.query(
      'taggables',
      columns: ['tag_id'],
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
    );
    return rows.map((r) => r['tag_id'] as String).toSet();
  }

  Future<void> setTagIdsFor(
    String entityType,
    String entityId,
    Set<String> tagIds,
  ) async {
    await db.transaction((txn) async {
      await txn.delete(
        'taggables',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityType, entityId],
      );
      for (final id in tagIds) {
        await txn.insert('taggables', {
          'tag_id': id,
          'entity_type': entityType,
          'entity_id': entityId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> toggleTag(
    String entityType,
    String entityId,
    String tagId,
  ) async {
    final current = await tagIdsFor(entityType, entityId);
    if (current.contains(tagId)) {
      current.remove(tagId);
    } else {
      current.add(tagId);
    }
    await setTagIdsFor(entityType, entityId, current);
  }

  // ---------------------------------------------------------------- notes

  Future<List<Note>> notes({
    String? lessonId,
    String? courseId,
    String? query,
    bool trashed = false,
  }) async {
    final where = <String>[
      trashed ? 'deleted_at IS NOT NULL' : 'deleted_at IS NULL',
    ];
    final args = <Object?>[];
    if (lessonId != null) {
      where.add('lesson_id = ?');
      args.add(lessonId);
    }
    if (courseId != null) {
      where.add('course_id = ?');
      args.add(courseId);
    }
    if (query != null && query.trim().isNotEmpty) {
      where.add('(title LIKE ? OR body LIKE ?)');
      args
        ..add('%$query%')
        ..add('%$query%');
    }
    final rows = await db.query(
      'notes',
      where: where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: trashed
          ? 'deleted_at DESC'
          : 'pinned DESC, position ASC, updated_at DESC',
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<Note?> note(String id) async {
    final rows = await db.query(
      'notes',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Note.fromMap(rows.first);
  }

  Future<ConceptMapDoc?> conceptMap(String id) async {
    final rows = await db.query(
      'concept_maps',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ConceptMapDoc.fromMap(rows.first);
  }

  Future<void> saveNote(Note n) async {
    await db.insert(
      'notes',
      n.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ------------------------------------------------------------ note blocks

  /// Blocks of one note, unordered; the editor rebuilds the tree by parent_id
  /// and sort_key.
  Future<List<NoteBlock>> blocksFor(String noteId) async {
    final rows = await db.query(
      'note_blocks',
      where: 'note_id = ?',
      whereArgs: [noteId],
    );
    return rows.map(NoteBlock.fromMap).toList();
  }

  /// Replaces the whole block set of a note in one transaction. Notes are
  /// small (hundreds of blocks), so a replace is simpler and safer than a diff.
  Future<void> replaceBlocks(String noteId, List<NoteBlock> blocks) async {
    await db.transaction((txn) async {
      await txn.delete(
        'note_blocks',
        where: 'note_id = ?',
        whereArgs: [noteId],
      );
      if (blocks.isEmpty) return;
      final batch = txn.batch();
      for (final b in blocks) {
        batch.insert(
          'note_blocks',
          b.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> deleteBlocks(String noteId) async {
    await db.delete('note_blocks', where: 'note_id = ?', whereArgs: [noteId]);
  }

  // -------------------------------------------------------------- templates

  Future<Set<String>> bookmarkIdsFor(String entityType) async {
    final rows = await db.query(
      'bookmarks',
      columns: ['entity_id'],
      where: 'entity_type = ?',
      whereArgs: [entityType],
    );
    return rows.map((r) => r['entity_id'] as String).toSet();
  }

  Future<bool> isBookmarked(String entityType, String entityId) async {
    final rows = await db.query(
      'bookmarks',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> toggleBookmark(String entityType, String entityId) async {
    final exists = await isBookmarked(entityType, entityId);
    if (exists) {
      await db.delete(
        'bookmarks',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityType, entityId],
      );
      return false;
    } else {
      await db.insert('bookmarks', {
        'entity_type': entityType,
        'entity_id': entityId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    }
  }

  Future<List<Lesson>> allLessons() async {
    final rows = await db.query(
      'lessons',
      orderBy: 'position ASC, created_at ASC',
    );
    return rows.map(Lesson.fromMap).toList();
  }

  Future<void> saveTemplate(String name, String snapshot) async {
    await db.insert('page_templates', {
      'id': _uuid.v4(),
      'name': name,
      'snapshot': snapshot,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, Object?>>> templates() {
    return db.query('page_templates', orderBy: 'created_at DESC');
  }

  Future<void> deleteTemplate(String id) async {
    await db.delete('page_templates', where: 'id = ?', whereArgs: [id]);
  }

  // --------------------------------------------------------- note versions

  Future<void> saveVersion(
    String noteId,
    String snapshot, {
    String? label,
  }) async {
    await db.insert('note_versions', {
      'id': _uuid.v4(),
      'note_id': noteId,
      'snapshot': snapshot,
      'label': label,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, Object?>>> versions(String noteId, {int limit = 50}) {
    return db.query(
      'note_versions',
      columns: ['id', 'label', 'created_at', 'snapshot'],
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'created_at DESC, rowid DESC',
      limit: limit,
    );
  }

  Future<Map<String, Object?>?> version(String id) async {
    final rows = await db.query(
      'note_versions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Keeps the newest [keep] versions for a note.
  Future<void> trimVersions(String noteId, {int keep = 40}) async {
    final rows = await db.query(
      'note_versions',
      columns: ['id'],
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'created_at DESC, rowid DESC',
    );
    if (rows.length <= keep) return;
    final stale = rows.skip(keep).map((r) => r['id'] as String).toList();
    for (final id in stale) {
      await db.delete('note_versions', where: 'id = ?', whereArgs: [id]);
    }
  }

  /// Moves a page (and its subtree by virtue of parent_id) to the trash.
  Future<void> trashNote(String id) async {
    await db.update(
      'notes',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> trashSubtree(String id) async {
    final children = await db.query(
      'notes',
      where: 'parent_id = ?',
      whereArgs: [id],
    );
    for (final child in children) {
      await trashSubtree(child['id'] as String);
    }
    await trashNote(id);
  }

  Future<void> restoreNote(String id) async {
    await db.update(
      'notes',
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
    final row = await db.query(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final parentId = row.isEmpty ? null : row.first['parent_id'] as String?;
    if (parentId != null) {
      final parent = await db.query(
        'notes',
        where: 'id = ?',
        whereArgs: [parentId],
        limit: 1,
      );
      if (parent.isNotEmpty && parent.first['deleted_at'] != null) {
        await db.update(
          'notes',
          {'parent_id': null},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  Future<void> restoreSubtree(String id) async {
    await restoreNote(id);
    final children = await db.query(
      'notes',
      where: 'parent_id = ?',
      whereArgs: [id],
    );
    for (final child in children) {
      await restoreSubtree(child['id'] as String);
    }
  }

  Future<void> purgeNote(String id) async {
    final children = await db.query(
      'notes',
      where: 'parent_id = ?',
      whereArgs: [id],
    );
    for (final child in children) {
      await purgeNote(child['id'] as String);
    }
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> moveNote(String id, String? parentId) async {
    await db.update(
      'notes',
      {'parent_id': parentId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setNotePosition(String id, int position) async {
    await db.update(
      'notes',
      {'position': position},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteNote(String id) async {
    await purgeNote(id);
  }

  // ---------------------------------------------------------------- cards

  Future<List<Flashcard>> dueCards({int limit = 40}) async {
    final rows = await db.query(
      'cards',
      where: 'due_at <= ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
      orderBy: 'due_at ASC',
      limit: limit,
    );
    return rows.map(Flashcard.fromMap).toList();
  }

  Future<int> dueCount() async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM cards WHERE due_at <= ?',
      [DateTime.now().millisecondsSinceEpoch],
    );
    return (r.first['n'] as int?) ?? 0;
  }

  Future<int> cardCount() async {
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM cards');
    return (r.first['n'] as int?) ?? 0;
  }

  Future<void> saveCard(Flashcard c) async {
    await db.insert(
      'cards',
      _cardMap(c),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteCard(String id) async {
    await db.delete('cards', where: 'id = ?', whereArgs: [id]);
  }

  /// SM-2 with four grades. Rating: 0 again, 1 hard, 2 good, 3 easy.
  Future<Flashcard> reviewCard(Flashcard card, int rating) async {
    var ease = card.ease;
    var interval = card.intervalDays;
    var reps = card.reps;
    var lapses = card.lapses;
    var state = 'review';
    switch (rating) {
      case 0:
        lapses += 1;
        reps = 0;
        ease = (ease - 0.2).clamp(1.3, 2.8);
        interval = 10 / (60 * 24); // ten minutes
        state = 'relearning';
      case 1:
        reps += 1;
        ease = (ease - 0.15).clamp(1.3, 2.8);
        interval = interval <= 0 ? 1 : interval * 1.2;
        state = 'review';
      case 2:
        reps += 1;
        interval = interval <= 0 ? 1 : interval * ease;
        state = interval >= 21 ? 'mastered' : 'review';
      default:
        reps += 1;
        ease = (ease + 0.15).clamp(1.3, 3.2);
        interval = interval <= 0 ? 4 : interval * ease * 1.25;
        state = interval >= 21 ? 'mastered' : 'review';
    }
    interval = interval.clamp(0.0069, 365.0);
    final due = DateTime.now().add(
      Duration(minutes: (interval * 24 * 60).round()),
    );
    final updated = Flashcard(
      id: card.id,
      deck: card.deck,
      front: card.front,
      back: card.back,
      courseId: card.courseId,
      lessonId: card.lessonId,
      resourceId: card.resourceId,
      page: card.page,
      dueAt: due,
      intervalDays: interval,
      ease: ease,
      reps: reps,
      lapses: lapses,
      state: state,
      createdAt: card.createdAt,
    );
    await saveCard(updated);
    await db.insert('reviews', {
      'id': _uuid.v4(),
      'card_id': card.id,
      'rating': rating,
      'reviewed_at': DateTime.now().millisecondsSinceEpoch,
    });
    return updated;
  }

  Future<Map<String, Object?>> reviewStats() async {
    final now = DateTime.now();
    final since = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    final rows = await db.rawQuery(
      'SELECT rating, COUNT(*) AS n FROM reviews WHERE reviewed_at >= ? GROUP BY rating',
      [since],
    );
    final total = rows.fold<int>(0, (s, r) => s + (r['n'] as int));
    final good = rows
        .where((r) => (r['rating'] as int) >= 2)
        .fold<int>(0, (s, r) => s + (r['n'] as int));
    final days = await db.rawQuery(
      '''
      SELECT DATE(reviewed_at / 1000, 'unixepoch', 'localtime') AS d, COUNT(*) AS n
      FROM reviews WHERE reviewed_at >= ? GROUP BY d ORDER BY d''',
      [since],
    );
    return {
      'total30': total,
      'retention': total == 0 ? null : good / total,
      'days': days,
    };
  }

  // ---------------------------------------------------------------- threads / messages

  Future<List<Map<String, Object?>>> threads() async {
    return db.query('threads', orderBy: 'updated_at DESC');
  }

  Future<String> createThread({
    required String title,
    required String mode,
    String? courseId,
    String? lessonId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('threads', {
      'id': id,
      'title': title,
      'mode': mode,
      'course_id': courseId,
      'lesson_id': lessonId,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  Future<void> touchThread(String id) async {
    await db.update(
      'threads',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<ChatMessage>> messages(String threadId) async {
    final rows = await db.query(
      'messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at',
    );
    return rows.map((r) {
      final citations = <Citation>[];
      final raw = r['citations'] as String?;
      if (raw != null && raw.isNotEmpty) {
        try {
          for (final c in jsonDecode(raw) as List) {
            citations.add(
              Citation(
                label: c['label'] as String,
                sourceType: c['type'] as String,
                sourceId: c['id'] as String,
                locator: c['locator'] as String?,
              ),
            );
          }
        } catch (_) {}
      }
      final m = ChatMessage.fromMap(r);
      return ChatMessage(
        id: m.id,
        threadId: m.threadId,
        role: m.role,
        content: m.content,
        citations: citations,
        createdAt: m.createdAt,
      );
    }).toList();
  }

  Future<ChatMessage> addMessage({
    required String threadId,
    required String role,
    required String content,
    List<Citation> citations = const [],
  }) async {
    final msg = ChatMessage(
      id: _uuid.v4(),
      threadId: threadId,
      role: role,
      content: content,
      citations: citations,
      createdAt: DateTime.now(),
    );
    await db.insert('messages', {
      'id': msg.id,
      'thread_id': threadId,
      'role': role,
      'content': content,
      'citations': jsonEncode(
        citations
            .map(
              (c) => {
                'label': c.label,
                'type': c.sourceType,
                'id': c.sourceId,
                'locator': c.locator,
              },
            )
            .toList(),
      ),
      'created_at': msg.createdAt.millisecondsSinceEpoch,
    });
    return msg;
  }

  // ---------------------------------------------------------------- providers

  Future<List<AiProvider>> providers() async {
    final rows = await db.query('providers', orderBy: 'is_default DESC, name');
    return rows.map(AiProvider.fromMap).toList();
  }

  Future<AiProvider?> defaultProvider() async {
    final rows = await db.query('providers', where: 'is_default = 1', limit: 1);
    if (rows.isEmpty) return null;
    return AiProvider.fromMap(rows.first);
  }

  Future<void> saveProvider(AiProvider p) async {
    if (p.isDefault) {
      await db.update('providers', {'is_default': 0});
    }
    await db.insert(
      'providers',
      p.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteProvider(String id) async {
    await db.delete('providers', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------- transcripts

  Future<Transcript?> transcriptFor(String ownerType, String ownerId) async {
    final rows = await db.query(
      'transcripts',
      where: 'owner_type = ? AND owner_id = ?',
      whereArgs: [ownerType, ownerId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final segs = <TranscriptSegment>[];
    try {
      for (final s in jsonDecode(r['segments'] as String) as List) {
        segs.add(
          TranscriptSegment(
            startMs: (s['start'] as num).toInt(),
            endMs: (s['end'] as num).toInt(),
            text: s['text'] as String,
          ),
        );
      }
    } catch (_) {}
    return Transcript(
      id: r['id'] as String,
      ownerType: ownerType,
      ownerId: ownerId,
      language: r['language'] as String,
      source: r['source'] as String,
      segments: segs,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    );
  }

  Future<Transcript> saveTranscript({
    required String ownerType,
    required String ownerId,
    required String language,
    required String source,
    required List<TranscriptSegment> segments,
  }) async {
    final t = Transcript(
      id: _uuid.v4(),
      ownerType: ownerType,
      ownerId: ownerId,
      language: language,
      source: source,
      segments: segments,
      createdAt: DateTime.now(),
    );
    await db.insert('transcripts', {
      'id': t.id,
      'owner_type': ownerType,
      'owner_id': ownerId,
      'language': language,
      'source': source,
      'created_at': t.createdAt.millisecondsSinceEpoch,
      'segments': jsonEncode(segments.map((s) => s.toJson()).toList()),
    });
    if (ownerType == 'lesson') {
      await db.update(
        'lessons',
        {'transcript_id': t.id},
        where: 'id = ?',
        whereArgs: [ownerId],
      );
    }
    return t;
  }

  // ---------------------------------------------------------------- RAG chunks

  Future<void> replaceChunks(
    String sourceType,
    String sourceId,
    List<Map<String, Object?>> chunks,
  ) async {
    await db.delete(
      'chunks',
      where: 'source_type = ? AND source_id = ?',
      whereArgs: [sourceType, sourceId],
    );
    final batch = db.batch();
    for (final c in chunks) {
      batch.insert('chunks', {
        'id': _uuid.v4(),
        'source_type': sourceType,
        'source_id': sourceId,
        'label': c['label'],
        'text': c['text'],
        'locator': c['locator'],
        'embedding': c['embedding'],
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> searchChunks(
    String query, {
    int limit = 6,
  }) async {
    final terms = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .take(6)
        .toList();
    if (terms.isEmpty) return [];
    try {
      final match = terms.map((t) => '"$t"').join(' OR ');
      final rows = await db.rawQuery(
        '''
        SELECT c.*, bm25(chunks_fts) AS rank FROM chunks_fts
        JOIN chunks c ON c.rowid = chunks_fts.rowid
        WHERE chunks_fts MATCH ? ORDER BY rank LIMIT ?''',
        [match, limit],
      );
      if (rows.isNotEmpty) return rows;
    } catch (_) {}
    final like = '%${terms.first}%';
    return db.query(
      'chunks',
      where: 'text LIKE ?',
      whereArgs: [like],
      limit: limit,
    );
  }

  // ---------------------------------------------------------------- devices

  Future<List<Map<String, Object?>>> devices() async {
    return db.query('devices', orderBy: 'paired_at DESC');
  }

  Future<void> saveDevice({
    required String id,
    required String name,
    required String publicKey,
  }) async {
    await db.insert('devices', {
      'id': id,
      'name': name,
      'public_key': publicKey,
      'paired_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> revokeDevice(String id) async {
    await db.update(
      'devices',
      {'revoked': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> logSync(
    String deviceId,
    String direction,
    int items,
    int bytes,
    String note,
  ) async {
    await db.insert('sync_log', {
      'id': _uuid.v4(),
      'device_id': deviceId,
      'at': DateTime.now().millisecondsSinceEpoch,
      'direction': direction,
      'items': items,
      'bytes': bytes,
      'note': note,
    });
  }

  // ---------------------------------------------------------------- stats

  Future<Map<String, Object?>> dashboardStats() async {
    final since30 = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;

    final (
      watch,
      reviewTime,
      courses,
      lessons,
      completedLessons,
      notes,
      notes30,
      resources,
      extractsCount,
    ) = await (
      db.rawQuery(
        '''
        SELECT COALESCE(SUM(watched_ms), 0) AS ms FROM progress
        WHERE updated_at >= ?''',
        [since30],
      ),
      db.rawQuery(
        '''
        SELECT COALESCE(SUM(duration_ms), 0) AS ms, COUNT(*) AS n,
               COALESCE(SUM(CASE WHEN rating >= 3 THEN 1 ELSE 0 END), 0) AS good
        FROM reviews WHERE reviewed_at >= ?''',
        [since30],
      ),
      db.rawQuery('SELECT COUNT(*) AS n FROM courses WHERE archived = 0'),
      db.rawQuery('SELECT COUNT(*) AS n FROM lessons'),
      db.rawQuery('SELECT COUNT(*) AS n FROM progress WHERE completed = 1'),
      db.rawQuery('SELECT COUNT(*) AS n FROM notes WHERE deleted_at IS NULL'),
      db.rawQuery(
        'SELECT COUNT(*) AS n FROM notes WHERE deleted_at IS NULL AND updated_at >= ?',
        [since30],
      ),
      db.rawQuery('SELECT COUNT(*) AS n FROM resources'),
      db.rawQuery('SELECT COUNT(*) AS n FROM extracts'),
    ).wait;

    final (
      mapsCount,
      cardsCount,
      recentResources,
      due,
      reviewsToday,
      streakRows,
      recent,
      dailySeries,
    ) = await (
      db.rawQuery('SELECT COUNT(*) AS n FROM concept_maps'),
      cardCount(),
      db.query(
        'resources',
        orderBy: 'COALESCE(last_opened_at, created_at) DESC',
        limit: 6,
      ),
      dueCount(),
      db.rawQuery('SELECT COUNT(*) AS n FROM reviews WHERE reviewed_at >= ?', [
        DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      ]),
      db.rawQuery('''
        SELECT DISTINCT d FROM (
          SELECT DATE(reviewed_at / 1000, 'unixepoch', 'localtime') AS d FROM reviews
          UNION ALL
          SELECT DATE(updated_at / 1000, 'unixepoch', 'localtime') AS d FROM progress WHERE completed = 1
          UNION ALL
          SELECT DATE(updated_at / 1000, 'unixepoch', 'localtime') AS d FROM notes WHERE deleted_at IS NULL
        ) ORDER BY d DESC LIMIT 60'''),
      db.rawQuery(
        '''
        SELECT c.*,
          (SELECT COUNT(*) FROM lessons l WHERE l.course_id = c.id) AS lesson_count,
          (SELECT COALESCE(SUM(l.duration_ms), 0) FROM lessons l WHERE l.course_id = c.id) AS total_duration_ms,
          (SELECT COUNT(*) FROM lessons l JOIN progress p ON p.lesson_id = l.id WHERE l.course_id = c.id AND p.completed = 1) AS completed_count
        FROM courses c WHERE c.archived = 0 ORDER BY COALESCE(c.last_opened_at, c.updated_at) DESC LIMIT 6''',
      ),
      db.rawQuery(
        '''
        SELECT d, SUM(ms) AS ms, SUM(actions) AS actions FROM (
          SELECT DATE(updated_at / 1000, 'unixepoch', 'localtime') AS d,
                 COALESCE(watched_ms, 0) AS ms, 0 AS actions
          FROM progress WHERE updated_at >= ?
          UNION ALL
          SELECT DATE(reviewed_at / 1000, 'unixepoch', 'localtime') AS d,
                 COALESCE(duration_ms, 0) AS ms, 1 AS actions
          FROM reviews WHERE reviewed_at >= ?
          UNION ALL
          SELECT DATE(updated_at / 1000, 'unixepoch', 'localtime') AS d,
                 0 AS ms, 1 AS actions
          FROM notes WHERE deleted_at IS NULL AND updated_at >= ?
          UNION ALL
          SELECT DATE(created_at / 1000, 'unixepoch', 'localtime') AS d,
                 0 AS ms, 1 AS actions
          FROM extracts WHERE created_at >= ?
          UNION ALL
          SELECT DATE(updated_at / 1000, 'unixepoch', 'localtime') AS d,
                 0 AS ms, 1 AS actions
          FROM concept_maps WHERE updated_at >= ?
        ) GROUP BY d ORDER BY d ASC''',
        [since30, since30, since30, since30, since30],
      ),
    ).wait;

    final watchedMs = watch.first['ms'] as int? ?? 0;
    final reviewMs = reviewTime.first['ms'] as int? ?? 0;
    final reviews30 = reviewTime.first['n'] as int? ?? 0;
    final goodReviews = reviewTime.first['good'] as int? ?? 0;
    final totalLessonsCount = lessons.first['n'] as int? ?? 0;
    final completedCount = completedLessons.first['n'] as int? ?? 0;
    final avgProgress = totalLessonsCount == 0
        ? 0.0
        : (completedCount / totalLessonsCount).clamp(0.0, 1.0);

    var streak = 0;
    var cursor = DateTime.now();
    for (final r in streakRows) {
      final d = DateTime.parse(r['d'] as String);
      final diff = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
      ).difference(DateTime(d.year, d.month, d.day)).inDays;
      if (diff <= 1) {
        streak++;
        cursor = d;
      } else {
        break;
      }
    }

    final activeDays = dailySeries
        .where((r) => ((r['actions'] as num?) ?? 0) > 0)
        .length;
    final actions30 = dailySeries.fold<int>(
      0,
      (sum, r) => sum + ((r['actions'] as num?) ?? 0).toInt(),
    );
    final retention = reviews30 == 0
        ? 0.0
        : (goodReviews / reviews30).clamp(0.0, 1.0);

    return {
      'watched_7d_ms': watchedMs,
      'review_ms_30d': reviewMs,
      'actions_30d': actions30,
      'active_days_30d': activeDays,
      'reviews_30d': reviews30,
      'retention': retention,
      'lessons_completed': completedCount,
      'notes_30d': notes30.first['n'] as int? ?? 0,
      'courses': courses.first['n'] as int? ?? 0,
      'resources': resources.first['n'] as int? ?? 0,
      'extracts': extractsCount.first['n'] as int? ?? 0,
      'maps': mapsCount.first['n'] as int? ?? 0,
      'cards': cardsCount,
      'lessons': totalLessonsCount,
      'avg_progress': avgProgress,
      'notes': notes.first['n'] as int? ?? 0,
      'due': due,
      'reviews_today': reviewsToday.first['n'] as int? ?? 0,
      'streak': streak,
      'recent_courses': recent,
      'recent_resources': recentResources,
      'daily_series': dailySeries,
    };
  }
  // ---------------------------------------------------------------- extracts (keywords, formulas, quotes)

  Future<List<StudyExtract>> extracts({
    String? resourceId,
    String? courseId,
    String? lessonId,
    String? kind,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (resourceId != null) {
      where.add('resource_id = ?');
      args.add(resourceId);
    }
    if (courseId != null) {
      where.add('course_id = ?');
      args.add(courseId);
    }
    if (lessonId != null) {
      where.add('lesson_id = ?');
      args.add(lessonId);
    }
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    final rows = await db.query(
      'extracts',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(StudyExtract.fromMap).toList();
  }

  Future<void> saveExtract(StudyExtract e) async {
    await db.insert(
      'extracts',
      e.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteExtract(String id) async {
    await db.delete('extracts', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------- concept maps

  Future<List<ConceptMapDoc>> conceptMaps({
    String? courseId,
    String? resourceId,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (courseId != null) {
      where.add('course_id = ?');
      args.add(courseId);
    }
    if (resourceId != null) {
      where.add('resource_id = ?');
      args.add(resourceId);
    }
    final rows = await db.query(
      'concept_maps',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_at DESC',
    );
    return rows.map(ConceptMapDoc.fromMap).toList();
  }

  Future<void> saveConceptMap(ConceptMapDoc m) async {
    await db.insert(
      'concept_maps',
      m.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteConceptMap(String id) async {
    await db.delete('concept_maps', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ConceptNode>> conceptNodes(String mapId) async {
    final rows = await db.query(
      'concept_nodes',
      where: 'map_id = ?',
      whereArgs: [mapId],
    );
    return rows.map(ConceptNode.fromMap).toList();
  }

  Future<void> saveConceptNode(ConceptNode n) async {
    await db.insert(
      'concept_nodes',
      n.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.update(
      'concept_maps',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [n.mapId],
    );
  }

  Future<void> deleteConceptNode(String id) async {
    await db.delete('concept_nodes', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------- shareable knowledge cards (.klaro.json)

  Future<Map<String, Object?>> exportKnowledgeBundle({
    String? courseId,
    String? resourceId,
    required String title,
  }) async {
    final notesList = await notes(courseId: courseId);
    final filteredNotes = resourceId == null
        ? notesList
        : notesList.where((n) => n.resourceId == resourceId).toList();
    final extractsList = await extracts(
      courseId: courseId,
      resourceId: resourceId,
    );
    final allCards = (await db.query('cards'))
        .map(Flashcard.fromMap)
        .where((c) {
          if (resourceId != null) return c.resourceId == resourceId;
          if (courseId != null) return c.courseId == courseId;
          return true;
        })
        .toList();
    final mapsList = await conceptMaps(
      courseId: courseId,
      resourceId: resourceId,
    );
    final nodesByMap = <String, List<Map<String, Object?>>>{};
    for (final m in mapsList) {
      final nodes = await conceptNodes(m.id);
      nodesByMap[m.id] = nodes.map((n) => n.toMap()).toList();
    }
    return {
      'format': 'klaro-knowledge-card-v1',
      'title': title,
      'exported_at': DateTime.now().toIso8601String(),
      'notes': filteredNotes.map((n) => n.toMap()).toList(),
      'extracts': extractsList.map((e) => e.toMap()).toList(),
      'cards': allCards
          .map(
            (c) => {
              'id': c.id,
              'deck': c.deck,
              'front': c.front,
              'back': c.back,
              'page': c.page,
              'created_at': c.createdAt.millisecondsSinceEpoch,
              'due_at': c.dueAt.millisecondsSinceEpoch,
            },
          )
          .toList(),
      'maps': mapsList.map((m) => m.toMap()).toList(),
      'map_nodes': nodesByMap,
    };
  }

  Future<Map<String, int>> importKnowledgeBundle(
    Map<String, Object?> bundle,
  ) async {
    var notesImported = 0,
        extractsImported = 0,
        cardsImported = 0,
        mapsImported = 0;
    for (final raw in (bundle['notes'] as List? ?? [])) {
      final m = Map<String, Object?>.from(raw as Map);
      await db.insert('notes', m, conflictAlgorithm: ConflictAlgorithm.replace);
      notesImported++;
    }
    for (final raw in (bundle['extracts'] as List? ?? [])) {
      final m = Map<String, Object?>.from(raw as Map);
      await db.insert(
        'extracts',
        m,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      extractsImported++;
    }
    for (final raw in (bundle['cards'] as List? ?? [])) {
      final m = Map<String, Object?>.from(raw as Map);
      await saveCard(
        Flashcard(
          id: m['id'] as String? ?? _uuid.v4(),
          deck:
              m['deck'] as String? ??
              (bundle['title'] as String? ?? 'Imported'),
          front: m['front'] as String? ?? '',
          back: m['back'] as String? ?? '',
          page: m['page'] as int?,
          dueAt: DateTime.now(),
          createdAt: DateTime.now(),
        ),
      );
      cardsImported++;
    }
    final nodesByMap = (bundle['map_nodes'] as Map?) ?? const {};
    for (final raw in (bundle['maps'] as List? ?? [])) {
      final m = Map<String, Object?>.from(raw as Map);
      await db.insert(
        'concept_maps',
        m,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      mapsImported++;
      final mapId = m['id'] as String;
      for (final nRaw in (nodesByMap[mapId] as List? ?? [])) {
        final nm = Map<String, Object?>.from(nRaw as Map);
        await db.insert(
          'concept_nodes',
          nm,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    return {
      'notes': notesImported,
      'extracts': extractsImported,
      'cards': cardsImported,
      'maps': mapsImported,
    };
  }
}
