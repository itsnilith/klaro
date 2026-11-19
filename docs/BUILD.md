# Build and package

## Toolchain

- Flutter 3.47.6 (stable), Dart 3.13.5
- Rust 1.99.1 (`x86_64-pc-windows-msvc`) for `native/klaro_engine`
- Visual Studio 2022 Build Tools with the C++ desktop workload and Windows 10/11 SDK
- CMake 3.31 or newer

## Build

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

The executable is written to `build\windows\x64\runner\Release\klaro.exe`.

## Package the portable folder

```powershell
powershell -ExecutionPolicy Bypass -File tool\package.ps1
```

This rebuilds `Klaro-Portable\` from the release bundle, creates the empty data folders
and copies the documentation and license files. Existing `userdata\`, `backups\`,
`config\` and `models\` folders are moved aside and restored, so repackaging never
deletes local data. The same run writes `Klaro-Windows-Portable.zip` and the
`Start-Klaro.bat` launcher. The result can be moved between computers; no installer and
no registry entries are involved.

## Notes for this machine

The build host used to keep a Visual Studio 2022 Build Tools copy at
`C:\Temp\vs-buildtools` and a patched Flutter tool pointing at it. That folder no longer
exists (November 2026), so `flutter build windows` stops at *Unable to find suitable
Visual Studio toolchain* and no C++ source can be rebuilt until the Build Tools with the
desktop C++ workload are installed again. The runner and the plugin DLLs already built
in `build\windows\x64\runner\Release` stay valid.

A Dart-only change does not need MSBuild: the AOT snapshot and asset bundle come from the
same step CMake runs, and can be produced directly.

```powershell
$root = "C:\Projects\Mnemora"
C:\Users\Alessandro\AppData\Local\Programs\CMake\bin\cmake.exe -E env `
  FLUTTER_ROOT=C:\dev\flutter PROJECT_DIR=$root FLUTTER_TARGET=lib\main.dart `
  PACKAGE_CONFIG=$root\.dart_tool\package_config.json `
  C:\dev\flutter\packages\flutter_tools\bin\tool_backend.bat windows-x64 Release

Copy-Item $root\build\windows\app.so "$root\build\windows\x64\runner\Release\data\app.so" -Force
Copy-Item $root\build\flutter_assets\* "$root\build\windows\x64\runner\Release\data\flutter_assets\" -Recurse -Force
```

Then run `tool\package.ps1` as usual.

## Verification performed

- `flutter analyze` — no errors.
- `flutter test` — 7 tests: chunking, SRT parsing, WebVTT output, portable paths, AES-GCM
  envelope round-trip, wrong-key rejection.
- `flutter build windows --debug` and `--release` — both produce a runnable executable.
- The application launches, renders the home screen, and navigates between sections
  without framework exceptions.
