import 'dart:async';

import 'package:conduit/features/hermes/widgets/hermes_a2ui_surface.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart' show Surface;

void main() {
  testWidgets('renders an A2UI v0.9 card through the GenUI surface', (
    tester,
  ) async {
    const payload = '''
{"version":"v0.9","createSurface":{"surfaceId":"status","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"status","components":[{"id":"root","component":"Card","child":"column"},{"id":"column","component":"Column","children":["heading","button"]},{"id":"heading","component":"Text","text":"Hermes status"},{"id":"button","component":"Button","child":"button-label","action":{"event":{"name":"open_hermes"}}},{"id":"button-label","component":"Text","text":"Open Hermes"}]}}
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HermesA2uiSurface(payload: payload)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Surface), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('Hermes status'), findsOneWidget);
    expect(find.text('Open Hermes'), findsOneWidget);
  });

  testWidgets('weighted status text leaves room for a button on a phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const payload = '''
{"version":"v0.9","createSurface":{"surfaceId":"mobile","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"mobile","components":[{"id":"root","component":"Card","child":"row"},{"id":"row","component":"Row","children":["status","button"]},{"id":"status","component":"Text","text":"Immich is online and its API responded to the current health check","weight":1},{"id":"button","component":"Button","child":"label","action":{"event":{"name":"immich.check_status"}}},{"id":"label","component":"Text","text":"Details"}]}}
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HermesA2uiSurface(payload: payload)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Details'), findsOneWidget);
    expect(tester.getTopRight(find.text('Details')).dx, lessThan(360));
  });

  for (final width in <double>[320, 360, 412]) {
    for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'saved rows keep distinct action targets at ${width.toInt()} px, ${themeMode.name}, 200% text',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 760));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          const payload = '''
{"version":"v0.9","createSurface":{"surfaceId":"saved","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"saved","components":[{"id":"root","component":"Column","children":["row-hermes","row-immich"]},{"id":"row-hermes","component":"Row","children":["hermes-status","hermes-button"]},{"id":"hermes-status","component":"Text","text":"Hermes gateway is connected with queue depth zero"},{"id":"hermes-button","component":"Button","child":"hermes-label","action":{"event":{"name":"service.hermes_details"}}},{"id":"hermes-label","component":"Text","text":"Hermes details"},{"id":"row-immich","component":"Row","children":["immich-status","immich-button"]},{"id":"immich-status","component":"Text","text":"Immich API is online and ready to receive requests"},{"id":"immich-button","component":"Button","child":"immich-label","action":{"event":{"name":"service.immich_details"}}},{"id":"immich-label","component":"Text","text":"Immich details"}]}}
''';
          final sentPrompts = <String>[];

          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(useMaterial3: true),
              darkTheme: ThemeData.dark(useMaterial3: true),
              themeMode: themeMode,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 760),
                    textScaler: const TextScaler.linear(2),
                  ),
                  child: SingleChildScrollView(
                    child: HermesA2uiSurface(
                      payload: payload,
                      onInteraction: sentPrompts.add,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(tester.takeException(), isNull);
          final hermesButton = find.ancestor(
            of: find.text('Hermes details'),
            matching: find.byType(ElevatedButton),
          );
          final immichButton = find.ancestor(
            of: find.text('Immich details'),
            matching: find.byType(ElevatedButton),
          );
          expect(hermesButton, findsOneWidget);
          expect(immichButton, findsOneWidget);
          final hermesRect = tester.getRect(hermesButton);
          final immichRect = tester.getRect(immichButton);
          for (final rect in <Rect>[hermesRect, immichRect]) {
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
          }
          expect(hermesRect.overlaps(immichRect), isFalse);
          await tester.ensureVisible(immichButton);
          await tester.tap(immichButton);
          await tester.pump();

          expect(sentPrompts, hasLength(1));
          final interaction = jsonDecode(
            sentPrompts.single.substring('[A2UI_INTERACTION]\n'.length),
          ) as Map<String, dynamic>;
          expect(
            (interaction['action'] as Map<String, dynamic>)['name'],
            'service.immich_details',
          );
        },
      );
    }
  }

  testWidgets('does not submit repeated actions while a turn is in flight', (
    tester,
  ) async {
    final sentPrompts = <String>[];
    final releaseSubmission = Completer<void>();
    const payload = '''
{"version":"v0.9","createSurface":{"surfaceId":"busy","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"busy","components":[{"id":"root","component":"Button","child":"label","action":{"event":{"name":"open_hermes"}}},{"id":"label","component":"Text","text":"Open Hermes"}]}}
''';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HermesA2uiSurface(
            payload: payload,
            onInteraction: (prompt) {
              sentPrompts.add(prompt);
              return releaseSubmission.future;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Open Hermes'));
    await tester.pump();
    await tester.tap(find.text('Open Hermes'), warnIfMissed: false);
    await tester.pump();

    expect(sentPrompts, hasLength(1));
    releaseSubmission.complete();
    await tester.pump();
  });

  testWidgets('sends A2UI actions as normal Hermes interaction prompts', (
    tester,
  ) async {
    const payload = '''
{"version":"v0.9","createSurface":{"surfaceId":"status","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"status","components":[{"id":"root","component":"Button","child":"label","action":{"event":{"name":"open_hermes"}}},{"id":"label","component":"Text","text":"Open Hermes"}]}}
''';
    final sentPrompts = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HermesA2uiSurface(
            payload: payload,
            onInteraction: sentPrompts.add,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Open Hermes'));
    await tester.pump();

    expect(sentPrompts, hasLength(1));
    expect(sentPrompts.single, startsWith('[A2UI_INTERACTION]\n'));
    final interaction = jsonDecode(
      sentPrompts.single.substring('[A2UI_INTERACTION]\n'.length),
    ) as Map<String, dynamic>;
    expect(interaction['version'], 'v0.9');
    expect(
      (interaction['action'] as Map<String, dynamic>)['name'],
      'open_hermes',
    );
  });

  testWidgets('does not load agent-supplied network media', (tester) async {
    const payload = '''
{"version":"v0.9","createSurface":{"surfaceId":"media","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"media","components":[{"id":"root","component":"Image","url":"https://tracking.invalid/pixel.png"}]}}
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HermesA2uiSurface(payload: payload)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows a safe fallback for an empty or malformed surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HermesA2uiSurface(payload: 'not-json')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(
        'This A2UI card could not be displayed safely. Ask Hermes to regenerate it.',
      ),
      findsOneWidget,
    );
    expect(find.text('not-json'), findsNothing);
  });
}
