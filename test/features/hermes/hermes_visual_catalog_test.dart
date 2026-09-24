import 'package:conduit/features/hermes/widgets/hermes_a2ui_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _catalogId =
    'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';

void main() {
  testWidgets('renders status, metric, and chart components at phone width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const payload =
        '''
{"version":"v0.9","createSurface":{"surfaceId":"visual","catalogId":"$_catalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"visual","components":[{"id":"root","component":"Column","children":["heading","hermes","disk","trend"]},{"id":"heading","component":"Text","text":"System overview","variant":"h4"},{"id":"hermes","component":"StatusBadge","label":"Hermes","state":"ok","detail":"Gateway connected"},{"id":"disk","component":"MetricTile","label":"Storage used","value":86,"unit":"%","min":0,"max":100,"state":"warning","asOf":"2026-09-24T18:04:00Z","source":"Filesystem check"},{"id":"trend","component":"MiniChart","label":"Storage trend","kind":"line","unit":"%","points":[{"label":"Sep 22","value":80},{"label":"Sep 23","value":83},{"label":"Sep 24","value":86}],"asOf":"2026-09-24T18:04:00Z","source":"Daily filesystem samples"}]}}
''';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const SingleChildScrollView(
              child: HermesA2uiSurface(payload: payload),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Hermes'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Storage used'), findsOneWidget);
    expect(find.text('86 %'), findsOneWidget);
    expect(find.text('Storage trend'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('hermes-mini-chart')),
      findsOneWidget,
    );
  });

  testWidgets('shows an honest empty-chart state and no progress fiction', (
    tester,
  ) async {
    const payload =
        '''
{"version":"v0.9","createSurface":{"surfaceId":"empty-chart","catalogId":"$_catalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"empty-chart","components":[{"id":"root","component":"MiniChart","label":"Storage trend","kind":"line","points":[]}]}}
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HermesA2uiSurface(payload: payload)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('No observations yet.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('renders one sample as a value instead of inventing a trend', (
    tester,
  ) async {
    const payload =
        '''
{"version":"v0.9","createSurface":{"surfaceId":"one-point","catalogId":"$_catalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"one-point","components":[{"id":"root","component":"MiniChart","label":"Storage trend","kind":"line","unit":"%","points":[{"label":"Today","value":86}]}]}}
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HermesA2uiSurface(payload: payload)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('One sample: 86 %'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('hermes-mini-chart')),
      findsNothing,
    );
  });

  testWidgets(
    'keeps four states, a value-only metric, and seven samples readable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const payload =
          '''
{"version":"v0.9","createSurface":{"surfaceId":"all-states","catalogId":"$_catalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"all-states","components":[{"id":"root","component":"Column","children":["ok","warning","error","unknown","metric","chart"]},{"id":"ok","component":"StatusBadge","label":"Hermes","state":"ok"},{"id":"warning","component":"StatusBadge","label":"NVR","state":"warning"},{"id":"error","component":"StatusBadge","label":"Immich","state":"error"},{"id":"unknown","component":"StatusBadge","label":"Jellyfin","state":"unknown"},{"id":"metric","component":"MetricTile","label":"Storage used","value":248.6,"unit":"GiB"},{"id":"chart","component":"MiniChart","label":"Bridge uptime","kind":"line","unit":"h","points":[{"label":"Mon","value":1},{"label":"Tue","value":2},{"label":"Wed","value":3},{"label":"Thu","value":4},{"label":"Fri","value":5},{"label":"Sat","value":6},{"label":"Sun","value":7}]}]}}
''';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          darkTheme: ThemeData.dark(useMaterial3: true),
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const SingleChildScrollView(
                child: HermesA2uiSurface(payload: payload),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      for (final state in <String>['OK', 'Warning', 'Error', 'Unknown']) {
        expect(find.text(state), findsOneWidget);
      }
      expect(find.text('248.6 GiB'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('7 samples'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('hermes-mini-chart')),
        findsOneWidget,
      );
    },
  );

  testWidgets('keeps extreme but finite chart values inside a narrow card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const payload =
        '''
{"version":"v0.9","createSurface":{"surfaceId":"extreme","catalogId":"$_catalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"extreme","components":[{"id":"root","component":"MiniChart","label":"Extremes","kind":"line","points":[{"label":"Before","value":-1e308},{"label":"After","value":1e308}]}]}}
''';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: HermesA2uiSurface(payload: payload),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('hermes-mini-chart')),
      findsOneWidget,
    );
  });

  testWidgets('rejects a chart with more than 60 samples', (tester) async {
    final points = List<String>.generate(
      61,
      (index) => '{"label":"$index","value":$index}',
    ).join(',');
    final payload =
        '''
{"version":"v0.9","createSurface":{"surfaceId":"too-many","catalogId":"$_catalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"too-many","components":[{"id":"root","component":"MiniChart","label":"Too many","kind":"bar","points":[$points]}]}}
''';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HermesA2uiSurface(payload: payload)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('hermes-mini-chart')),
      findsNothing,
    );
    expect(
      find.textContaining('could not be displayed safely'),
      findsOneWidget,
    );
  });
}
