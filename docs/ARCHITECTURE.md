# Architecture

## Shape

```
lib/
  main.dart              entry: paths, database, settings, window
  app.dart               MaterialApp, theme mode, custom title bar
  core/
    paths.dart           portable-first storage layout
    db.dart              SQLite schema, migrations, all queries
    models.dart          immutable domain models
    state.dart           persisted preferences + revision counter
  design/
    tokens.dart          colour, type, spacing, radii, theme
    widgets.dart         mark, buttons, cards, chips, empty states
  services/
    ai.dart              Ollama and OpenAI-compatible streaming, embeddings, pull
    rag.dart             chunking, indexing, hybrid retrieval, citations
    transcription.dart   OpenAI-compatible and whisper.cpp backends, SRT/VTT
    sync.dart            identity, pairing, AES-GCM envelopes, manifest merge
  features/
    shell.dart           navigation, command palette, import actions
    home/                dashboard
    courses/             course list, detail, lesson workspace
    library/             library and resource viewer
    notes/               split editor
    review/              SRS session and card generation
    tutor/               chat, context controls, citations
    settings/            settings, AI setup, sync
```

## Data

SQLite in WAL mode, one file in `userdata/klaro.db`. Tables: `courses`, `modules`,
`lessons`, `progress`, `resources`, `notes`, `note_blocks`, `note_versions`, `page_templates`,
`tags`, `taggables`, `cards`, `reviews`, `threads`, `messages`, `providers`, `devices`,
`transcripts`, `chunks`, `sync_log`, `meta`.

A page is a `notes` row; its content is a tree of `note_blocks` rows ordered by a base-36
fractional sibling key, so inserting or reordering a block touches one row. `notes.body` stays
authoritative as a markdown projection for search, export, preview and the AI context builder,
and is regenerated from the blocks on every save. Opening a page that has no blocks yet parses
its markdown into blocks once, then the tree is the source of truth.

Editing is snapshot-undoable: the editor keeps a bounded stack of block-row snapshots and
restores one on `Ctrl+Z`, so structural changes (split, merge, indent, delete, turn into,
colour, drag) are undoable together with typing. Image blocks store an absolute path in their
props, the same contract resources use, so the database never holds binary payloads.

`chunks` is mirrored into an FTS5 virtual table when the SQLite build supports it; the
retrieval layer falls back to `LIKE` when it does not. Embeddings are stored as raw
float32 blobs and compared with cosine similarity in Dart.

Files are never copied into the database. A resource stores an absolute path; the UI
reports a missing file instead of pretending it exists.

## State

`AppState` is a `ChangeNotifier` holding persisted preferences and a revision counter.
Screens listen to it and reload their own data after a mutation. There is no global
mutable domain state: the database is the source of truth.

## AI

`AiClient` speaks two protocols:

- Ollama native (`/api/chat`, `/api/tags`, `/api/embed`, `/api/pull`).
- OpenAI-compatible (`/chat/completions`, `/models`, `/embeddings`).

Streaming is parsed incrementally for both. A provider is a row in `providers`; the API
key is stored in the same local database and never leaves the machine except as an
`Authorization` header to that provider.

Retrieval is hybrid: FTS5/BM25 candidates plus cosine similarity over stored embeddings
when an embedding model is configured. The context builder numbers passages and returns
the citation list that the UI renders under the answer.

## Sync

Each installation has an X25519 identity in `userdata/identity.json`. Pairing:

1. The host opens an HTTP server and shows a six-digit code that rotates every five
   minutes.
2. The client fetches the host public key, derives a shared secret with its own private
   key, and sends the SHA-256 of the code plus its public key.
3. The host verifies the code hash, stores the client key, and both sides derive a
   per-device session key with HKDF-SHA256 over the X25519 secret.
4. Every manifest request and response is an AES-256-GCM envelope with a random 96-bit
   nonce and a 128-bit tag.

Merge is last-write-wins on `updated_at` for notes, courses and progress; cards are
upserted by id. The protocol is deliberately small and testable; it is not a CRDT.

## Why Flutter

The product is a desktop application with a dense, custom interface, a video surface, a
PDF surface and a lot of local state. Flutter gives one rendering model for all of it,
mature Windows packaging, and a testable widget layer. The native pieces that need more
than Dart (media decoding, PDF rasterisation, SQLite) are provided by focused plugins
rather than a second UI stack.

## Rust native engine (`native/klaro_engine`)

The Rust native engine (`klaro_engine.dll`) is compiled as a `cdylib` and accessed from
Dart through `dart:ffi` (`lib/core/native_engine.dart`). It implements:

- 64-bit FNV-1a and FIPS 180-4 SHA-256 content hashing (`klaro_fnv1a64`, `klaro_sha256_hex`)
- Paragraph and sentence-aware RAG text chunking with overlap (`klaro_chunk_text_json`)
- BM25 lexical scoring (`klaro_bm25_score`)
- Float32 cosine vector similarity (`klaro_cosine_f32`)

Every FFI entry point has a pure-Dart fallback in `NativeEngine` so the application
remains resilient even if the native library is absent on a non-Windows target.

