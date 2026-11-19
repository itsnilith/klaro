# klaro.

**Learning, remembered.**

klaro. is a local-first desktop learning workspace for Windows. It brings your video
courses, documents, notes, spaced repetition and an AI tutor into one place, and keeps
everything on your own computer unless you explicitly connect something else.

Created by **itsnilith**. Licensed under **GNU AGPL-3.0**.

---

## What it does

- **Courses and lessons** — import an existing folder of videos without moving a single
  file, or build a course by hand. Modules, ordering, progress and resume are tracked per
  lesson.
- **A real player** — play/pause, seek, speed, volume, skip, keyboard shortcuts, fullscreen
  stage, subtitle tracks generated from transcripts, and a floating player so you can read
  notes while the video keeps playing.
- **Library** — PDFs, documents, slides, code, images and media, referenced in place.
  PDFs open in an integrated viewer with page-aware notes.
- **Notes** — block editor and Markdown, saved automatically, linked to the course, lesson,
  timestamp or PDF page they came from.
- **Concept maps & outlines** — mind maps, hierarchical outlines, flowcharts and timelines,
  with guided AI prompts that help you think through missing links without writing the map
  for you.
- **Review** — flashcards with an SM-2 scheduler (Again / Hard / Good / Easy), retention
  statistics, free-recall and plain-language practice, and card generation from your own
  notes or transcripts.
- **Tutor** — chat with a local Ollama model or any OpenAI-compatible endpoint. The tutor
  receives only the context you enable, retrieves passages from your indexed material, and
  cites the source of every claim.
- **Transcription** — any OpenAI-compatible `/audio/transcriptions` endpoint, or a
  whisper.cpp executable you already have. Transcripts become searchable, timestamped
  subtitles and retrieval sources.
- **Device sync** — direct LAN pairing with a six-digit code, X25519 key agreement and
  AES-256-GCM payloads. No account and no relay.
- **Portable or installed** — run from a self-contained portable folder, or use the
  per-user Windows installer.

## What it deliberately does not do

- No account, no telemetry, no analytics endpoint.
- No silent uploads. A provider only sees a request when you send one.
- No bundled AI model. Models are large; you choose and install one.
- No fake data. Every number on the dashboard comes from your own activity.

## Requirements

- Windows 10/11, 64-bit.
- No administrator rights to run.
- For the tutor: [Ollama](https://ollama.com) (recommended) or an OpenAI-compatible API.
- For local transcription: a whisper.cpp build, or any local server exposing an
  OpenAI-compatible transcription endpoint.

## Build from source

See [docs/BUILD.md](docs/BUILD.md). In short:

```powershell
flutter pub get
flutter build windows --release
```

The portable layout is produced by `tool/package.ps1`.

## Portable layout

```
Klaro/
  klaro.exe
  userdata/    SQLite database, identity, media cache
  config/      reserved for exported configuration
  models/      optional local models
  cache/       generated subtitles and thumbnails
  logs/        klaro.log
  backups/     database snapshots
  docs/        this documentation
```

If the application folder is read-only, klaro. falls back to
`%LOCALAPPDATA%\Klaro` and says so in Settings → Storage.

## Privacy

Read [docs/PRIVACY.md](docs/PRIVACY.md). The short version: your files stay where they
are, the database is local, and network access happens only when you configure a provider
and send a message.

## Known limitations in 1.0

- Device sync transfers notes, courses, cards and progress; media files are not
  transferred yet.
- Pairing uses a short numeric code as the authenticator. It is rate-limited by a
  five-minute rotation, but it is not a PAKE; do not pair on an untrusted network.
- Picture-in-picture is an in-app floating player, not an OS-level PiP window.
- PDF text extraction depends on the PDF having a text layer; scanned documents are not
  OCR'd.

## License

GNU Affero General Public License v3.0. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
