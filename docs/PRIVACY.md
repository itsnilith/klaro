# Privacy

Klaro is built so that the default configuration cannot send your material anywhere.

## What is stored, and where

| Data | Location | Notes |
| --- | --- | --- |
| Courses, lessons, progress | `userdata/klaro.db` | Paths to your files, not copies |
| Notes, cards, reviews | `userdata/klaro.db` | Plain SQLite |
| AI provider settings and API keys | `userdata/klaro.db` | Local file; protect the folder |
| Sync identity (X25519 private key) | `userdata/identity.json` | Local file |
| Generated subtitles | `cache/subtitles/` | Regenerable |
| Logs | `logs/klaro.log` | No prompts, no keys |

If the application folder is read-only, the same layout is created under
`%LOCALAPPDATA%\Klaro`.

## Network access

Klaro makes a network request only when:

1. You use an AI feature with a configured provider, including generating embeddings when indexing with an embedding model.
2. You start or join a device pairing session.
3. You ask to download a model through Ollama or download a Whisper model.
4. You open an external link.

There is no telemetry, no crash reporting, no update check and no analytics endpoint in
this build.

## What a provider receives

When you send a message, the request contains:

- the system instruction,
- the selected course and lesson metadata,
- the transcript excerpt for the selected lesson,
- retrieved passages from notes and library files, if those toggles are on,
- the recent conversation,
- your message.

The Tutor screen states which provider is active and what will be sent. Turning off
"Search my notes" or "Search library files" removes those passages from the request.

Passage AI in the resource viewer sends the text you paste or type, the selected
action's instructions, and your global AI instructions if set. It does not send the
rest of the resource or look through other notes. When indexing with an embedding
model, the provider receives extracted text chunks from the resource being indexed.

Ollama on `127.0.0.1` keeps the request on the machine. A cloud endpoint receives it.

## Keys

API keys are stored in the local SQLite database in plain text. This is a deliberate
trade-off for a portable, account-free application: anyone who can read the data folder
can read the keys. Use a dedicated key with a spending limit, and keep the folder on a
disk you control.

## Sync

Pairing uses X25519 for key agreement and AES-256-GCM for every payload. The six-digit
code authenticates the pairing exchange and rotates every five minutes. It is not a PAKE,
so a determined attacker on the same network could attempt an offline guess during the
window; pair on a network you trust.

## Deleting data

Delete the `userdata` folder to remove the database, identity and cached media. Your original
course files are untouched. Backups in `backups/` are separate files and must be deleted
separately.

