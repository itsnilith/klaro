import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/db.dart';
import 'core/paths.dart';
import 'core/state.dart';
import 'core/window_style.dart';
import 'services/sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  AppPaths.init();
  await Store.open();
  await AppState.i.load();
  if (AppState.i.syncActive) {
    try {
      await SyncHost.start(port: AppState.i.syncPort);
    } catch (_) {}
  }

  await windowManager.ensureInitialized();
  // Fit the window to the work area instead of assuming a large monitor.
  final display = await screenRetriever.getPrimaryDisplay();
  final visible = display.visibleSize ?? display.size;
  final width = (visible.width * 0.94).clamp(880.0, 1680.0);
  final height = (visible.height * 0.92).clamp(560.0, 1040.0);
  final options = WindowOptions(
    size: Size(width, height),
    minimumSize: const Size(560, 480),
    center: true,
    title: 'klaro.',
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
    WindowStyle.applyRoundedCorners();
  });
  runApp(const KlaroApp());
}
