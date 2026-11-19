import 'package:flutter_test/flutter_test.dart';
import 'package:klaro/core/db.dart';
import 'package:klaro/core/state.dart';

import 'test_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Store store;
  setUpAll(() async {
    testPaths();
    store = await Store.open();
  });
  setUp(() => store.db.delete('meta'));

  test('v3 uses the current default when the prompt was never saved', () async {
    await AppState.i.load();

    expect(AppState.i.aiGlobalInstructions, AppState.defaultGlobalAiPrompt);
    expect(await store.metaAll(), {'ai_prompt_version': '3'});
  });

  test(
    'v3 preserves exact custom instructions and unrelated settings',
    () async {
      const prompt = '  Use my examples.\nKeep my formatting.  ';
      await store.metaSet('ai_prompt_version', '2');
      await store.metaSet('ai_global_instructions', prompt);
      await store.metaSet('playback_speed', '1.5');
      await store.metaSet('device_name', 'My offline workspace');

      await AppState.i.load();
      await AppState.i.load();

      expect(AppState.i.aiGlobalInstructions, prompt);
      expect(AppState.i.playbackSpeed, 1.5);
      expect(await store.metaAll(), {
        'ai_prompt_version': '3',
        'ai_global_instructions': prompt,
        'playback_speed': '1.5',
        'device_name': 'My offline workspace',
      });
    },
  );

  test('v3 preserves a deliberately empty prompt', () async {
    await store.metaSet('ai_global_instructions', '');
    await AppState.i.load();

    expect(AppState.i.aiGlobalInstructions, isEmpty);
    expect(await store.metaAll(), {
      'ai_prompt_version': '3',
      'ai_global_instructions': '',
    });
  });

  test('an older build does not downgrade a future prompt marker', () async {
    await store.metaSet('ai_prompt_version', '4');
    await store.metaSet('ai_global_instructions', 'A future default');
    await AppState.i.load();

    expect(AppState.i.aiGlobalInstructions, 'A future default');
    expect((await store.metaAll())['ai_prompt_version'], '4');
  });
}
