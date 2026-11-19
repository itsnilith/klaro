# Third-party notices

Klaro is distributed under the GNU Affero General Public License v3.0. It uses the
following third-party components. Versions are those resolved in `pubspec.lock` at the
time of the 1.0.0 build.

## Fonts

| Component | License | Use |
| --- | --- | --- |
| Inter (Rasmus Andersson) | SIL Open Font License 1.1 | Interface type |
| Fraunces (Undercase Type) | SIL Open Font License 1.1 | Display type |

Full license texts are in `assets/fonts/OFL-Inter.txt` and `assets/fonts/OFL-Fraunces.txt`.

## Flutter and Dart packages

| Package | License | Use |
| --- | --- | --- |
| flutter, flutter_test | BSD-3-Clause | Application framework |
| sqflite_common_ffi, sqflite_common | BSD-2-Clause | SQLite access |
| sqlite3 | MIT | SQLite bindings and native build |
| http | BSD-3-Clause | Provider and sync HTTP |
| path, path_provider | BSD-3-Clause | Paths |
| file_picker | MIT | File and folder selection |
| window_manager | MIT | Window chrome |
| screen_retriever | MIT | Display metrics |
| media_kit, media_kit_video, media_kit_libs_windows_video | MIT (package); libmpv/FFmpeg components under LGPL-2.1+/GPL-2.0+ as distributed | Video and audio playback |
| pdfrx, pdfrx_engine | BSD-3-Clause (package); PDFium under BSD-3-Clause | PDF rendering and text extraction |
| flutter_markdown, markdown | BSD-3-Clause | Markdown rendering |
| cryptography | Apache-2.0 | X25519, HKDF, AES-GCM |
| crypto | BSD-3-Clause | SHA-256 |
| qr_flutter | BSD-3-Clause | Pairing QR |
| uuid | MIT | Identifiers |
| intl | BSD-3-Clause | Dates |
| url_launcher | BSD-3-Clause | Opening folders and links |
| collection | BSD-3-Clause | Collection helpers |
| ffi | BSD-3-Clause | Native interop |
| web_socket_channel | BSD-3-Clause | Reserved for future transports |
| archive | MIT | Reserved for backup export |

## Native components

- **SQLite** — public domain.
- **libmpv / FFmpeg** — shipped by `media_kit_libs_windows_video`. Their licenses and
  notices are included in the package's own distribution; redistributors must preserve
  them. Klaro does not modify these binaries.
- **PDFium** — BSD-3-Clause, shipped by `pdfrx`.

## Notes on redistribution

If you redistribute a build of Klaro, keep this file, the `LICENSE`, the font license
texts, and the license files that the media and PDF packages place next to their binaries.
The AGPL requires that users who interact with the program over a network are offered the
corresponding source.
