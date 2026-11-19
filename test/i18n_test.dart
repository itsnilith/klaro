import 'package:flutter_test/flutter_test.dart';

import 'package:klaro/core/i18n.dart';
import 'package:klaro/services/whisper_models.dart';

void main() {
  test('every supported language translates the app chrome', () {
    const keys = ['home', 'courses', 'settings', 'files', 'markComplete'];
    for (final language in AppLanguage.values) {
      L.current = language;
      for (final key in keys) {
        final value = L.tr(key);
        expect(value, isNotEmpty, reason: '${language.code} $key');
        if (language != AppLanguage.en) {
          expect(value, isNot(key), reason: '${language.code} $key is untranslated');
        }
      }
    }
    L.current = AppLanguage.en;
  });

  test('a missing key falls back to the key itself', () {
    L.current = AppLanguage.it;
    expect(L.tr('key-that-does-not-exist'), 'key-that-does-not-exist');
    L.current = AppLanguage.en;
  });

  test('whisper offers every v3 model except large, with turbo instead', () {
    final ids = whisperModels.map((m) => m.id).toList();
    expect(ids, containsAll(['tiny', 'base', 'small', 'medium']));
    expect(ids, contains('large-v3-turbo'));
    expect(ids, isNot(contains('large')));
    expect(ids, isNot(contains('large-v3')));
    expect(whisperModelFileName('base'), 'ggml-base.bin');
  });
}
