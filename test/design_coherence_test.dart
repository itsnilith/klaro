import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klaro/design/tokens.dart';
import 'package:klaro/design/widgets.dart';

void main() {
  Future<void> pumpControls(WidgetTester tester, Brightness brightness) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(brightness),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      MButton(
                        key: Key('primary-button'),
                        label: 'Primary',
                        kind: MButtonKind.primary,
                        onPressed: () {},
                      ),
                      SizedBox(width: 12),
                      MButton(
                        key: Key('secondary-button'),
                        label: 'Secondary',
                        onPressed: () {},
                      ),
                      SizedBox(width: 12),
                      MButton(
                        key: Key('danger-button'),
                        label: 'Delete',
                        kind: MButtonKind.danger,
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  MSegmented(
                    items: const [('Lessons', null), ('Notes', null)],
                    index: 0,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BoxDecoration buttonDecoration(WidgetTester tester, Key key) {
    final container = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byKey(key),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    return container.decoration! as BoxDecoration;
  }

  for (final kind in MButtonKind.values.where((k) => k != MButtonKind.ghost)) {
    testWidgets('$kind keeps a raised light-to-dark gradient in dark mode', (
      tester,
    ) async {
      await pumpControls(tester, Brightness.dark);
      final key = switch (kind) {
        MButtonKind.primary => const Key('primary-button'),
        MButtonKind.secondary => const Key('secondary-button'),
        MButtonKind.danger => const Key('danger-button'),
        MButtonKind.ghost => throw StateError('unreachable'),
      };
      final decoration = buttonDecoration(tester, key);
      final gradient = decoration.gradient! as LinearGradient;

      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      expect(
        gradient.colors.first.computeLuminance(),
        greaterThan(gradient.colors.last.computeLuminance()),
      );
      expect(decoration.boxShadow, hasLength(1));
      expect(
        decoration.boxShadow!.single.color,
        MColors.dark.shadow.withValues(alpha: 0.30),
      );
      expect(
        decoration.boxShadow!.single.color.computeLuminance(),
        lessThan(0.01),
        reason: 'Dark buttons must not use an external white highlight.',
      );
    });
  }

  testWidgets('light button shading and highlights remain calibrated', (
    tester,
  ) async {
    await pumpControls(tester, Brightness.light);
    final primary = buttonDecoration(tester, const Key('primary-button'));
    final secondary = buttonDecoration(tester, const Key('secondary-button'));
    final danger = buttonDecoration(tester, const Key('danger-button'));

    expect((primary.gradient! as LinearGradient).colors, [
      Color.alphaBlend(
        Colors.white.withValues(alpha: 0.10),
        MColors.light.accent,
      ),
      MColors.light.accent,
    ]);
    expect((secondary.gradient! as LinearGradient).colors, [
      MColors.light.surface,
      Color.alphaBlend(
        MColors.light.ink.withValues(alpha: 0.025),
        MColors.light.surface,
      ),
    ]);
    expect((danger.gradient! as LinearGradient).colors, [
      MColors.light.dangerSoft,
      Color.alphaBlend(
        MColors.light.danger.withValues(alpha: 0.05),
        MColors.light.dangerSoft,
      ),
    ]);
    expect(secondary.boxShadow, hasLength(2));
    expect(
      secondary.boxShadow!.last.color,
      Colors.white.withValues(alpha: 0.55),
    );
    expect(
      secondary.boxShadow!.first.color,
      MColors.light.shadow.withValues(alpha: 0.09),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('segmented thumb is raised above the track in $brightness', (
      tester,
    ) async {
      await pumpControls(tester, brightness);
      final containers = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(MSegmented),
              matching: find.byType(Container),
            ),
          )
          .toList();
      expect(containers, hasLength(2));
      final track = containers[0].decoration! as BoxDecoration;
      final thumb = containers[1].decoration! as BoxDecoration;
      expect(
        thumb.color!.computeLuminance(),
        greaterThan(track.color!.computeLuminance()),
      );
      expect(thumb.boxShadow, hasLength(1));
      expect(
        thumb.boxShadow!.single.color,
        brightness == Brightness.dark
            ? MColors.dark.shadow.withValues(alpha: 0.34)
            : MColors.light.shadow.withValues(alpha: 0.12),
      );
      if (brightness == Brightness.light) {
        expect(track.color, MColors.light.surfaceAlt);
        expect(thumb.color, MColors.light.surface);
      } else {
        expect(track.color, MColors.dark.surfaceSunken);
      }
    });
  }

  testWidgets('clip applies consistently to static and interactive cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Column(
            children: [
              MCard(
                key: const Key('static-card'),
                clip: true,
                padding: EdgeInsets.zero,
                child: Container(
                  key: const Key('card-content'),
                  width: 100,
                  height: 60,
                  color: MColors.dark.accentSoft,
                ),
              ),
              MCard(
                key: const Key('interactive-card'),
                clip: true,
                onTap: () {},
                child: const SizedBox(width: 100, height: 60),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('static-card')),
        matching: find.byType(ClipRRect),
      ),
      findsOneWidget,
    );
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byKey(const Key('interactive-card')),
        matching: find.byType(Material),
      ),
    );
    expect(material.clipBehavior, Clip.antiAlias);
  });

  test('semantic danger foreground has accessible contrast in both themes', () {
    for (final brightness in Brightness.values) {
      final theme = buildTheme(brightness);
      final foreground = theme.colorScheme.onError;
      final background = theme.colorScheme.error;
      final lighter =
          foreground.computeLuminance() > background.computeLuminance()
          ? foreground
          : background;
      final darker = identical(lighter, foreground) ? background : foreground;
      final contrast =
          (lighter.computeLuminance() + 0.05) /
          (darker.computeLuminance() + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5), reason: '$brightness');
    }
  });
}
