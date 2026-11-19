import 'package:flutter/material.dart';

import 'core/i18n.dart';
import 'core/state.dart';
import 'design/tokens.dart';
import 'features/shell.dart';

class KlaroApp extends StatelessWidget {
  const KlaroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.i,
      builder: (context, _) {
        final s = AppState.i;
        L.current = languageFromCode(s.language);
        return MaterialApp(
          title: 'klaro.',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: s.themeMode,
          locale: languageFromCode(s.language).locale,
          supportedLocales: AppLanguage.values.map((l) => l.locale).toList(),
          home: const Shell(),
        );
      },
    );
  }
}
