class Course {
  const Course({
    required this.id,
    required this.title,
    this.author,
    this.description,
    this.cover,
    this.category,
    this.objectives,
    this.folder,
    this.favorite = false,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
    this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String? author;
  final String? description;
  final String? cover;
  final String? category;
  final String? objectives;

  /// Folder on disk this course was imported from. Files are never moved or
  /// copied: the app only remembers where to look for them.
  final String? folder;
  final bool favorite;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;

  Course copyWith({
    String? title,
    String? author,
    String? description,
    String? cover,
    bool clearCover = false,
    String? category,
    String? objectives,
    String? folder,
    bool? favorite,
    bool? archived,
    DateTime? updatedAt,
    DateTime? lastOpenedAt,
  }) => Course(
    id: id,
    title: title ?? this.title,
    author: author ?? this.author,
    description: description ?? this.description,
    cover: clearCover ? null : (cover ?? this.cover),
    category: category ?? this.category,
    objectives: objectives ?? this.objectives,
    folder: folder ?? this.folder,
    favorite: favorite ?? this.favorite,
    archived: archived ?? this.archived,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'author': author,
    'description': description,
    'cover': cover,
    'category': category,
    'objectives': objectives,
    'folder': folder,
    'favorite': favorite ? 1 : 0,
    'archived': archived ? 1 : 0,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'last_opened_at': lastOpenedAt?.millisecondsSinceEpoch,
  };

  static Course fromMap(Map<String, Object?> m) => Course(
    id: m['id'] as String,
    title: m['title'] as String,
    author: m['author'] as String?,
    description: m['description'] as String?,
    cover: m['cover'] as String?,
    category: m['category'] as String?,
    objectives: m['objectives'] as String?,
    folder: m['folder'] as String?,
    favorite: (m['favorite'] as int? ?? 0) == 1,
    archived: (m['archived'] as int? ?? 0) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
    lastOpenedAt: m['last_opened_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['last_opened_at'] as int),
  );
}

class Module {
  const Module({
    required this.id,
    required this.courseId,
    required this.title,
    required this.position,
    this.cover,
  });

  final String id;
  final String courseId;
  final String title;
  final int position;
  final String? cover;

  Module copyWith({
    String? title,
    int? position,
    String? cover,
    bool clearCover = false,
  }) => Module(
    id: id,
    courseId: courseId,
    title: title ?? this.title,
    position: position ?? this.position,
    cover: clearCover ? null : (cover ?? this.cover),
  );

  static Module fromMap(Map<String, Object?> m) => Module(
    id: m['id'] as String,
    courseId: m['course_id'] as String,
    title: m['title'] as String,
    position: m['position'] as int? ?? 0,
    cover: m['cover'] as String?,
  );
}

class Lesson {
  const Lesson({
    required this.id,
    required this.courseId,
    this.moduleId,
    required this.title,
    this.path,
    this.kind = 'video',
    this.durationMs = 0,
    this.position = 0,
    this.transcriptId,
    this.description,
    this.createdAt,
  });

  final String id;
  final String courseId;
  final String? moduleId;
  final String title;
  final String? path;
  final String kind;
  final int durationMs;
  final int position;
  final String? transcriptId;

  /// Free-form description shown under the player and editable by the user.
  final String? description;
  final DateTime? createdAt;

  Lesson copyWith({
    String? title,
    String? description,
    bool clearDescription = false,
  }) => Lesson(
    id: id,
    courseId: courseId,
    moduleId: moduleId,
    title: title ?? this.title,
    path: path,
    kind: kind,
    durationMs: durationMs,
    position: position,
    transcriptId: transcriptId,
    description: clearDescription ? null : (description ?? this.description),
    createdAt: createdAt,
  );

  static Lesson fromMap(Map<String, Object?> m) => Lesson(
    id: m['id'] as String,
    courseId: m['course_id'] as String,
    moduleId: m['module_id'] as String?,
    title: m['title'] as String,
    path: m['path'] as String?,
    kind: m['kind'] as String? ?? 'video',
    durationMs: m['duration_ms'] as int? ?? 0,
    position: m['position'] as int? ?? 0,
    transcriptId: m['transcript_id'] as String?,
    description: m['description'] as String?,
    createdAt: m['created_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );
}

class Progress {
  const Progress({
    required this.lessonId,
    required this.positionMs,
    required this.watchedMs,
    required this.completed,
    required this.updatedAt,
  });
  final String lessonId;
  final int positionMs;
  final int watchedMs;
  final bool completed;
  final DateTime updatedAt;

  static Progress fromMap(Map<String, Object?> m) => Progress(
    lessonId: m['lesson_id'] as String,
    positionMs: m['position_ms'] as int? ?? 0,
    watchedMs: m['watched_ms'] as int? ?? 0,
    completed: (m['completed'] as int? ?? 0) == 1,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int? ?? 0),
  );
}

class LibraryResource {
  const LibraryResource({
    required this.id,
    required this.title,
    required this.path,
    required this.kind,
    this.size = 0,
    this.hash,
    this.courseId,
    this.favorite = false,
    required this.createdAt,
    this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String path;
  final String kind;
  final int size;
  final String? hash;
  final String? courseId;
  final bool favorite;
  final DateTime createdAt;
  final DateTime? lastOpenedAt;

  static LibraryResource fromMap(Map<String, Object?> m) => LibraryResource(
    id: m['id'] as String,
    title: m['title'] as String,
    path: m['path'] as String,
    kind: m['kind'] as String,
    size: m['size'] as int? ?? 0,
    hash: m['hash'] as String?,
    courseId: m['course_id'] as String?,
    favorite: (m['favorite'] as int? ?? 0) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    lastOpenedAt: m['last_opened_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['last_opened_at'] as int),
  );
}

class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    this.parentId,
    this.icon = '',
    this.cover = '',
    this.courseId,
    this.lessonId,
    this.resourceId,
    this.page,
    this.timestampMs,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
    this.position = 0,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String body;
  final String? parentId;
  final String icon;
  final String cover;
  final String? courseId;
  final String? lessonId;
  final String? resourceId;
  final int? page;
  final int? timestampMs;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pinned;
  final int position;
  final DateTime? deletedAt;

  bool get isTrashed => deletedAt != null;

  Note copyWith({
    String? title,
    String? body,
    String? parentId,
    bool clearParent = false,
    String? icon,
    String? cover,
    String? courseId,
    String? lessonId,
    String? resourceId,
    int? page,
    int? timestampMs,
    DateTime? updatedAt,
    bool? pinned,
    int? position,
    DateTime? deletedAt,
    bool clearDeleted = false,
  }) => Note(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    parentId: clearParent ? null : (parentId ?? this.parentId),
    icon: icon ?? this.icon,
    cover: cover ?? this.cover,
    courseId: courseId ?? this.courseId,
    lessonId: lessonId ?? this.lessonId,
    resourceId: resourceId ?? this.resourceId,
    page: page ?? this.page,
    timestampMs: timestampMs ?? this.timestampMs,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    pinned: pinned ?? this.pinned,
    position: position ?? this.position,
    deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'body': body,
    'parent_id': parentId,
    'icon': icon,
    'cover': cover,
    'course_id': courseId,
    'lesson_id': lessonId,
    'resource_id': resourceId,
    'page': page,
    'timestamp_ms': timestampMs,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'pinned': pinned ? 1 : 0,
    'position': position,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
  };

  static Note fromMap(Map<String, Object?> m) => Note(
    id: m['id'] as String,
    title: m['title'] as String,
    body: m['body'] as String? ?? '',
    parentId: m['parent_id'] as String?,
    icon: m['icon'] as String? ?? '',
    cover: m['cover'] as String? ?? '',
    courseId: m['course_id'] as String?,
    lessonId: m['lesson_id'] as String?,
    resourceId: m['resource_id'] as String?,
    page: m['page'] as int?,
    timestampMs: m['timestamp_ms'] as int?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
    pinned: (m['pinned'] as int? ?? 0) == 1,
    position: m['position'] as int? ?? 0,
    deletedAt: m['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['deleted_at'] as int),
  );
}

class Flashcard {
  const Flashcard({
    required this.id,
    required this.deck,
    required this.front,
    required this.back,
    this.courseId,
    this.lessonId,
    this.resourceId,
    this.page,
    required this.dueAt,
    this.intervalDays = 0,
    this.ease = 2.5,
    this.reps = 0,
    this.lapses = 0,
    this.state = 'new',
    required this.createdAt,
  });

  final String id;
  final String deck;
  final String front;
  final String back;
  final String? courseId;
  final String? lessonId;
  final String? resourceId;
  final int? page;
  final DateTime dueAt;
  final double intervalDays;
  final double ease;
  final int reps;
  final int lapses;
  final String state;
  final DateTime createdAt;

  static Flashcard fromMap(Map<String, Object?> m) => Flashcard(
    id: m['id'] as String,
    deck: m['deck'] as String,
    front: m['front'] as String,
    back: m['back'] as String,
    courseId: m['course_id'] as String?,
    lessonId: m['lesson_id'] as String?,
    resourceId: m['resource_id'] as String?,
    page: m['page'] as int?,
    dueAt: DateTime.fromMillisecondsSinceEpoch(m['due_at'] as int),
    intervalDays: (m['interval_days'] as num? ?? 0).toDouble(),
    ease: (m['ease'] as num? ?? 2.5).toDouble(),
    reps: m['reps'] as int? ?? 0,
    lapses: m['lapses'] as int? ?? 0,
    state: m['state'] as String? ?? 'new',
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );
}

class AiProvider {
  const AiProvider({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
    this.temperature = 0.4,
    this.contextWindow = 8192,
    this.isDefault = false,
    this.embeddingModel,
    this.capabilities = 'chat',
  });

  final String id;
  final String name;
  final String kind; // ollama | openai
  final String baseUrl;
  final String model;
  final String apiKey;
  final double temperature;
  final int contextWindow;
  final bool isDefault;
  final String? embeddingModel;
  final String capabilities;

  AiProvider copyWith({
    String? name,
    String? kind,
    String? baseUrl,
    String? model,
    String? apiKey,
    double? temperature,
    int? contextWindow,
    bool? isDefault,
    String? embeddingModel,
    String? capabilities,
  }) => AiProvider(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
    temperature: temperature ?? this.temperature,
    contextWindow: contextWindow ?? this.contextWindow,
    isDefault: isDefault ?? this.isDefault,
    embeddingModel: embeddingModel ?? this.embeddingModel,
    capabilities: capabilities ?? this.capabilities,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'kind': kind,
    'base_url': baseUrl,
    'model': model,
    'api_key': apiKey,
    'temperature': temperature,
    'context_window': contextWindow,
    'is_default': isDefault ? 1 : 0,
    'embedding_model': embeddingModel,
    'capabilities': capabilities,
  };

  static AiProvider fromMap(Map<String, Object?> m) => AiProvider(
    id: m['id'] as String,
    name: m['name'] as String,
    kind: m['kind'] as String,
    baseUrl: m['base_url'] as String,
    model: m['model'] as String,
    apiKey: m['api_key'] as String? ?? '',
    temperature: (m['temperature'] as num? ?? 0.4).toDouble(),
    contextWindow: m['context_window'] as int? ?? 8192,
    isDefault: (m['is_default'] as int? ?? 0) == 1,
    embeddingModel: m['embedding_model'] as String?,
    capabilities: m['capabilities'] as String? ?? 'chat',
  );
}

class Citation {
  const Citation({required this.label, required this.sourceType, required this.sourceId, this.locator});
  final String label;
  final String sourceType;
  final String sourceId;
  final String? locator;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.content,
    this.citations = const [],
    required this.createdAt,
  });
  final String id;
  final String threadId;
  final String role;
  final String content;
  final List<Citation> citations;
  final DateTime createdAt;

  static ChatMessage fromMap(Map<String, Object?> m) => ChatMessage(
    id: m['id'] as String,
    threadId: m['thread_id'] as String,
    role: m['role'] as String,
    content: m['content'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );
}

class TranscriptSegment {
  const TranscriptSegment({required this.startMs, required this.endMs, required this.text});
  final int startMs;
  final int endMs;
  final String text;
  Map<String, Object?> toJson() => {'start': startMs, 'end': endMs, 'text': text};
}

class StudyExtract {
  const StudyExtract({
    required this.id,
    required this.kind, // keyword | formula | quote
    required this.content,
    this.description,
    this.tags = '',
    this.courseId,
    this.lessonId,
    this.resourceId,
    this.page,
    this.timestampMs,
    required this.createdAt,
  });

  final String id;
  final String kind;
  final String content;
  final String? description;
  final String tags;
  final String? courseId;
  final String? lessonId;
  final String? resourceId;
  final int? page;
  final int? timestampMs;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'kind': kind,
    'content': content,
    'description': description,
    'tags': tags,
    'course_id': courseId,
    'lesson_id': lessonId,
    'resource_id': resourceId,
    'page': page,
    'timestamp_ms': timestampMs,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  static StudyExtract fromMap(Map<String, Object?> m) => StudyExtract(
    id: m['id'] as String,
    kind: m['kind'] as String? ?? 'keyword',
    content: m['content'] as String? ?? '',
    description: m['description'] as String?,
    tags: m['tags'] as String? ?? '',
    courseId: m['course_id'] as String?,
    lessonId: m['lesson_id'] as String?,
    resourceId: m['resource_id'] as String?,
    page: m['page'] as int?,
    timestampMs: m['timestamp_ms'] as int?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
  );
}

class ConceptNode {
  const ConceptNode({
    required this.id,
    required this.mapId,
    this.parentId,
    required this.title,
    this.body = '',
    this.x = 120,
    this.y = 120,
    this.sourceLabel,
    this.kind = 'normal', // normal | hint | floating
    this.color = '',
    this.startYear,
    this.endYear,
    this.lane = 0,
    this.linkedNodeId,
    this.linkLabel,
  });

  final String id;
  final String mapId;
  final String? parentId;
  final String title;
  final String body;
  final double x;
  final double y;
  final String? sourceLabel;
  final String kind;
  final String color;
  final double? startYear;
  final double? endYear;
  final int lane;
  final String? linkedNodeId;
  final String? linkLabel;

  bool get isHint => kind == 'hint';

  ConceptNode copyWith({
    String? parentId,
    String? title,
    String? body,
    double? x,
    double? y,
    String? sourceLabel,
    String? kind,
    String? color,
    double? startYear,
    double? endYear,
    int? lane,
    String? linkedNodeId,
    String? linkLabel,
  }) => ConceptNode(
    id: id,
    mapId: mapId,
    parentId: parentId ?? this.parentId,
    title: title ?? this.title,
    body: body ?? this.body,
    x: x ?? this.x,
    y: y ?? this.y,
    sourceLabel: sourceLabel ?? this.sourceLabel,
    kind: kind ?? this.kind,
    color: color ?? this.color,
    startYear: startYear ?? this.startYear,
    endYear: endYear ?? this.endYear,
    lane: lane ?? this.lane,
    linkedNodeId: linkedNodeId ?? this.linkedNodeId,
    linkLabel: linkLabel ?? this.linkLabel,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'map_id': mapId,
    'parent_id': parentId,
    'title': title,
    'body': body,
    'x': x,
    'y': y,
    'source_label': sourceLabel,
    'kind': kind,
    'color': color,
    'start_year': startYear,
    'end_year': endYear,
    'lane': lane,
    'linked_node_id': linkedNodeId,
    'link_label': linkLabel,
  };

  static ConceptNode fromMap(Map<String, Object?> m) => ConceptNode(
    id: m['id'] as String,
    mapId: m['map_id'] as String,
    parentId: m['parent_id'] as String?,
    title: m['title'] as String? ?? '',
    body: m['body'] as String? ?? '',
    x: (m['x'] as num? ?? 120).toDouble(),
    y: (m['y'] as num? ?? 120).toDouble(),
    sourceLabel: m['source_label'] as String?,
    kind: m['kind'] as String? ?? 'normal',
    color: m['color'] as String? ?? '',
    startYear: (m['start_year'] as num?)?.toDouble(),
    endYear: (m['end_year'] as num?)?.toDouble(),
    lane: m['lane'] as int? ?? 0,
    linkedNodeId: m['linked_node_id'] as String?,
    linkLabel: m['link_label'] as String?,
  );
}

class ConceptMapDoc {
  const ConceptMapDoc({
    required this.id,
    required this.title,
    this.kind = 'mindmap', // mindmap | linear | diagram | timeline
    this.courseId,
    this.resourceId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String kind;
  final String? courseId;
  final String? resourceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  ConceptMapDoc copyWith({
    String? title,
    String? kind,
    DateTime? updatedAt,
  }) => ConceptMapDoc(
    id: id,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    courseId: courseId,
    resourceId: resourceId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'kind': kind,
    'course_id': courseId,
    'resource_id': resourceId,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  static ConceptMapDoc fromMap(Map<String, Object?> m) => ConceptMapDoc(
    id: m['id'] as String,
    title: m['title'] as String? ?? 'Concept map',
    kind: m['kind'] as String? ?? 'mindmap',
    courseId: m['course_id'] as String?,
    resourceId: m['resource_id'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int? ?? 0),
  );
}

class Transcript {
  const Transcript({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.language,
    required this.source,
    required this.segments,
    required this.createdAt,
  });
  final String id;
  final String ownerType;
  final String ownerId;
  final String language;
  final String source;
  final List<TranscriptSegment> segments;
  final DateTime createdAt;
}
class TagModel {
  const TagModel({required this.id, required this.name, this.color});

  final String id;
  final String name;
  final String? color;

  static TagModel fromMap(Map<String, Object?> m) => TagModel(
        id: m['id'] as String,
        name: m['name'] as String,
        color: m['color'] as String?,
      );

  TagModel copyWith({String? name, String? color}) =>
      TagModel(id: id, name: name ?? this.name, color: color ?? this.color);
}