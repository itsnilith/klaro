import 'dart:io';

import 'package:path/path.dart' as p;

/// Portable-first storage.
///
/// Layout next to the executable:
///   Klaro.exe
///   data/  config/  models/  cache/  logs/  backups/
///
/// If the installation directory is read-only (Program Files, removable media
/// with write protection) we fall back to %LOCALAPPDATA%\Klaro, and every
/// path is reported in Settings so the user always knows where data lives.
class AppPaths {
  AppPaths._(this.root, this.portable);

  final String root;
  final bool portable;

  static AppPaths? _instance;
  static AppPaths get i => _instance ?? (throw StateError('AppPaths not initialised'));

  static AppPaths init() {
    if (_instance != null) return _instance!;
    final exeDir = p.dirname(Platform.resolvedExecutable);
    var root = exeDir;
    var portable = true;
    try {
      final probe = File(p.join(exeDir, '.write-probe'));
      probe.writeAsStringSync('ok');
      probe.deleteSync();
    } catch (_) {
      portable = false;
      final local = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
      root = p.join(local, 'Klaro');
    }
    return initAt(root, portable: portable);
  }

  /// Uses an explicit root instead of the executable folder.
  ///
  /// Tests call this so every test file gets its own database and folders:
  /// parallel runs never share a SQLite file, and no test sees another's rows.
  static AppPaths initAt(String root, {bool portable = true}) {
    if (_instance != null) return _instance!;
    for (final sub in ['userdata', 'config', 'models', 'cache', 'logs', 'backups']) {
      Directory(p.join(root, sub)).createSync(recursive: true);
    }
    _migrateLegacyData(root);
    _instance = AppPaths._(root, portable);
    return _instance!;
  }

  /// Carries a pre-rename installation forward: the database was stored as
  /// mnemora.db before the rebrand, so the first launch copies it once.
  static void _migrateLegacyData(String root) {
    final target = File(p.join(root, 'userdata', 'klaro.db'));
    if (target.existsSync()) return;
    for (final suffix in ['', '-wal', '-shm']) {
      final legacy = File(p.join(root, 'userdata', 'mnemora.db$suffix'));
      if (legacy.existsSync()) {
        legacy.copySync(target.path + suffix);
      }
    }
  }

  String get dataDir => p.join(root, 'userdata');
  String get configDir => p.join(root, 'config');
  String get modelsDir => p.join(root, 'models');
  String get cacheDir => p.join(root, 'cache');
  String get logsDir => p.join(root, 'logs');
  String get backupsDir => p.join(root, 'backups');
  String get dbPath => p.join(dataDir, 'klaro.db');
  String get mediaDir {
    final d = p.join(dataDir, 'media');
    Directory(d).createSync(recursive: true);
    return d;
  }

  String get appVersion => const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

  Future<void> writeLog(String line) async {
    try {
      final f = File(p.join(logsDir, 'klaro.log'));
      await f.writeAsString(
        '${DateTime.now().toIso8601String()}  $line\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (_) {}
  }
}