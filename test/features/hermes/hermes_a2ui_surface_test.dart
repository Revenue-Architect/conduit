import 'dart:async';
import 'dart:io';

import 'package:conduit/features/hermes/widgets/hermes_a2ui_surface.dart';
import 'package:conduit/features/hermes/widgets/hermes_visual_catalog.dart';
import 'package:conduit/features/hermes/widgets/hermez_chat_palette.dart';
import 'package:conduit/features/hermes/widgets/hermez_visual_theme.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart'
    show
        Catalog,
        CatalogItem,
        CatalogItemContext,
        DataContext,
        DataPath,
        InMemoryDataModel,
        Surface;

Widget _catalogItemInUnboundedRow({
  required CatalogItem item,
  required Catalog catalog,
  required DataContext dataContext,
  required Map<String, Object?> data,
}) {
  CatalogItem? getCatalogItem(String type) {
    for (final candidate in catalog.items) {
      if (candidate.name == type) return candidate;
    }
    return null;
  }

  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Row(
          children: [
            item.widgetBuilder(
              CatalogItemContext(
                data: data,
                id: 'unbounded-visual',
                type: item.name,
                buildChild: (id, [dataContext]) => const SizedBox.shrink(),
                dispatchEvent: (_) {},
                buildContext: context,
                dataContext: dataContext,
                getComponent: (_) => null,
                getCatalogItem: getCatalogItem,
                surfaceId: 'unbounded-test',
                reportError: (_, _) {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('stock A2UI Card and Button use Hermez $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final payload = File('test/fixtures/hermes/a2ui/meal-plan-form.jsonl')
          .readAsStringSync();
      final palette = HermezChatPalette.forBrightness(brightness);

      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: hermezVisualTheme(ThemeData(brightness: brightness)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: HermesA2uiSurface(payload: payload),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final card = tester.widget<Card>(find.byType(Card).first);
      expect((card.child! as Padding).padding, const EdgeInsets.all(16));
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton).first,
      );
      expect(button.style?.backgroundColor?.resolve({}), palette.accent);
      expect(button.style?.foregroundColor?.resolve({}), palette.onAccent);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renders a saved ranged metric row without infinite width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payload = File(
      'test/fixtures/hermes/a2ui/metric-row-ranged-unweighted.jsonl',
    ).readAsStringSync();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HermesA2uiSurface(payload: payload),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byType(Surface), findsOneWidget);
    expect(find.text('CPU use'), findsOneWidget);
    expect(find.text('65 %'), findsOneWidget);
    expect(find.text('Synthetic test data'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('renders a native meal-plan form with varied controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payload = File('test/fixtures/hermes/a2ui/meal-plan-form.jsonl')
        .readAsStringSync();
    final interactions = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HermesA2uiSurface(
              payload: payload,
              onInteraction: interactions.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byType(Surface), findsOneWidget);
    expect(find.text('One-day meal plan'), findsOneWidget);
    expect(find.text('Meal name'), findsOneWidget);
    expect(find.text('Vegetarian'), findsOneWidget);
    expect(find.text('Servings'), findsOneWidget);
    expect(find.text('Preview plan'), findsOneWidget);
    await tester.ensureVisible(find.text('Preview plan'));
    await tester.tap(find.text('Preview plan'));
    await tester.pump();

    expect(interactions, hasLength(1));
    final interaction = jsonDecode(
      interactions.single.substring('[A2UI_INTERACTION]\n'.length),
    ) as Map<String, dynamic>;
    expect(
      (interaction['action'] as Map<String, dynamic>)['name'],
      'meal.preview_plan',
    );
    expect((interaction['action'] as Map<String, dynamic>)['context'], {
      'surface': 'meal-plan-form-01',
    });
  });

  for (final scenario in const [
    (
      fixture: 'travel-itinerary.jsonl',
      expected: ['Fictional Montreal weekend', 'Pace', 'View details'],
    ),
    (
      fixture: 'budget-planner.jsonl',
      expected: ['Synthetic monthly budget', 'Weekly spend', 'Review plan'],
    ),
    (
      fixture: 'project-sprint.jsonl',
      expected: ['Synthetic sprint plan', 'QA complete', 'Show summary'],
    ),
  ]) {
    testWidgets('renders ${scenario.fixture} at narrow width and large text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final payload = File('test/fixtures/hermes/a2ui/${scenario.fixture}')
          .readAsStringSync();

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: HermesA2uiSurface(payload: payload),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull, reason: scenario.fixture);
      expect(find.byType(Surface), findsOneWidget, reason: scenario.fixture);
      for (final text in scenario.expected) {
        expect(find.text(text), findsOneWidget, reason: scenario.fixture);
      }
    });
  }

  testWidgets(
    'visuals have readable fallbacks under unbounded row constraints',
    (tester) async {
      final catalog = createHermesVisualCatalog();
      final dataModel = InMemoryDataModel();
      addTearDown(dataModel.dispose);
      final dataContext = DataContext(dataModel, DataPath.root);
      CatalogItem item(String name) =>
          catalog.items.singleWhere((candidate) => candidate.name == name);

      await tester.pumpWidget(
        _catalogItemInUnboundedRow(
          item: item('MetricTile'),
          catalog: catalog,
          dataContext: dataContext,
          data: {
            'label': 'CPU use',
            'value': 65,
            'unit': '%',
            'min': 0,
            'max': 100,
            'source': 'Synthetic source',
          },
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('65 %'), findsOneWidget);
      expect(find.text('0 – 100 %'), findsOneWidget);
      expect(find.textContaining('Synthetic s'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.pumpWidget(
        _catalogItemInUnboundedRow(
          item: item('MiniChart'),
          catalog: catalog,
          dataContext: dataContext,
          data: {
            'label': 'Network traffic',
            'kind': 'line',
            'unit': 'MiB/s',
            'points': [
              {'label': '09:00', 'value': 18},
              {'label': '10:00', 'value': 22},
            ],
            'source': 'Synthetic samples',
          },
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Network traffic'), findsOneWidget);
      expect(find.textContaining('2 samples'), findsOneWidget);
      expect(find.textContaining('Source: Synthetic s'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('hermes-mini-chart')),
        findsNothing,
      );

      await tester.pumpWidget(
        _catalogItemInUnboundedRow(
          item: item('StatusBadge'),
          catalog: catalog,
          dataContext: dataContext,
          data: {
            'label': 'Hermes',
            'state': 'ok',
            'detail': 'Synthetic connection state',
          },
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Hermes'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.textContaining('Synthetic connectio'), findsOneWidget);
    },
  );

  for (final width in <double>[320, 360, 412]) {
    for (final textScale in <double>[1, 2]) {
      for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
        testWidgets(
          'renders synthetic 22-component dashboard at ${width.toInt()} px, ${textScale}x, ${themeMode.name}',
          (tester) async {
            await tester.binding.setSurfaceSize(Size(width, 900));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final payload = File(
              'test/fixtures/hermes/a2ui/synthetic-22-component-dashboard.jsonl',
            ).readAsStringSync();

            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(useMaterial3: true),
                darkTheme: ThemeData.dark(useMaterial3: true),
                themeMode: themeMode,
                home: Scaffold(
                  body: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 900),
                      textScaler: TextScaler.linear(textScale),
                    ),
                    child: SingleChildScrollView(
                      child: HermesA2uiSurface(payload: payload),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));

            expect(tester.takeException(), isNull);
            expect(find.byType(Surface), findsOneWidget);
            expect(find.text('Synthetic system overview'), findsOneWidget);
            expect(find.text('65 %'), findsOneWidget);
            expect(find.text('Synthetic telemetry'), findsWidgets);
            expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
            expect(find.text('Refresh'), findsOneWidget);
          },
        );
      }
    }
  }

  testWidgets('repaired dashboard action routes one turn with its target', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payload = File(
      'test/fixtures/hermes/a2ui/synthetic-22-component-dashboard.jsonl',
    ).readAsStringSync();
    final interactions = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HermesA2uiSurface(
              payload: payload,
              onInteraction: interactions.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Refresh'));
    await tester.tap(find.text('Refresh'));
    await tester.pump();

    expect(interactions, hasLength(1));
    expect(interactions.single, startsWith('[A2UI_INTERACTION]\n'));
    final interaction = jsonDecode(
      interactions.single.substring('[A2UI_INTERACTION]\n'.length),
    ) as Map<String, dynamic>;
    expect(
      (interaction['action'] as Map<String, dynamic>)['name'],
      'dashboard.refresh',
    );
  });

  testWidgets('surface reconstructs after scrolling away and back', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final payload = File(
      'test/fixtures/hermes/a2ui/metric-row-ranged-unweighted.jsonl',
    ).readAsStringSync();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: scrollController,
            itemCount: 36,
            itemBuilder: (context, index) => index == 1
                ? SizedBox(
                    key: const ValueKey('saved-a2ui-surface'),
                    height: 220,
                    child: HermesA2uiSurface(payload: payload),
                  )
                : SizedBox(height: 160, child: Text('List item $index')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CPU use'), findsOneWidget);

    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pump();
    scrollController.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byType(Surface), findsOneWidget);
    expect(find.text('CPU use'), findsOneWidget);
    expect(find.text('65 %'), findsOneWidget);
  });

  testWidgets('surface reconstructs after background-style subtree resume', (
    tester,
  ) async {
    final payload = File(
      'test/fixtures/hermes/a2ui/metric-row-ranged-unweighted.jsonl',
    ).readAsStringSync();
    Widget surface() => MaterialApp(
      home: Scaffold(body: HermesA2uiSurface(payload: payload)),
    );

    await tester.pumpWidget(surface());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Surface), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    await tester.pumpWidget(surface());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byType(Surface), findsOneWidget);
    expect(find.text('65 %'), findsOneWidget);
  });

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
