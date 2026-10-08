import 'dart:convert';
import 'dart:io';

import 'package:conduit/features/hermes/widgets/hermes_a2ui_surface.dart';
import 'package:conduit/features/hermes/widgets/hermes_visual_extensions.dart';
import 'package:conduit/features/hermes/widgets/hermes_visual_catalog.dart';
import 'package:conduit/features/hermes/services/hermes_a2ui_layout_normalizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:conduit/features/hermes/widgets/hermes_a2ui_media_scope.dart';
import 'package:conduit/features/hermes/widgets/hermes_artifact_view.dart';
import 'package:conduit/features/hermes/services/hermes_media_parser.dart';

String fixture(String kind) =>
    File('test/fixtures/hermes/a2ui/extensions/$kind.jsonl').readAsStringSync();
Map<String, dynamic> data(String kind) =>
    Map<String, dynamic>.from(
        (jsonDecode(
                      fixture(kind).trim().split('\n').last,
                    )['updateComponents']['components']
                    as List)
                .single
            as Map,
      )
      ..remove('id')
      ..remove('component');
Future<void> pump(
  WidgetTester tester,
  String payload,
  List<String> turns,
) async {
  await tester.binding.setSurfaceSize(const Size(320, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 1400),
          textScaler: TextScaler.linear(1.5),
        ),
        child: ColoredBox(
          color: Colors.white,
          child: SingleChildScrollView(
            child: HermesA2uiSurface(
              payload: payload,
              onInteraction: turns.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test(
    'image previews require an exact declared MEDIA image, not just a path',
    () {
      final images = {
        for (final a in parseHermesMedia(
          'MEDIA:/opt/data/artifacts/before.png',
        ).artifacts)
          a.path: a,
      };
      expect(
        hermesDeclaredImagePreview(
          '/opt/data/artifacts/before.png',
          declaredImages: images,
        ),
        isA<HermesArtifactView>(),
      );
      for (final path in [
        'https://example.test/image.png',
        '/opt/data/.env',
        '/opt/data/artifacts/after.png',
      ]) {
        expect(
          hermesDeclaredImagePreview(path, declaredImages: images),
          isA<Text>(),
        );
      }
      images['/opt/data/artifacts/report.pdf'] = const HermesMediaArtifact(
        path: '/opt/data/artifacts/report.pdf',
        filename: 'report.pdf',
        kind: HermesMediaKind.file,
      );
      expect(
        hermesDeclaredImagePreview(
          '/opt/data/artifacts/report.pdf',
          declaredImages: images,
        ),
        isA<Text>(),
      );
    },
  );
  testWidgets(
    'before/after image preview uses the supplied preview callback locally',
    (tester) async {
      var image = '';
      final messages = fixture('BeforeAfterViewer')
          .trim()
          .split('\n')
          .map(jsonDecode)
          .toList();
      final component = messages[1]['updateComponents']['components'][0];
      component['beforeMedia'] = '/opt/data/artifacts/before.png';
      component['afterMedia'] = '/opt/data/artifacts/after.png';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HermesA2uiSurface(
              payload: messages.map(jsonEncode).join('\n'),
              mediaPreview: (path) {
                image = path;
                return Text(path);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(image, '/opt/data/artifacts/before.png');
      await tester.tap(find.widgetWithText(ChoiceChip, 'After'));
      await tester.pumpAndSettle();
      expect(image, '/opt/data/artifacts/after.png');
      expect(tester.takeException(), isNull);
    },
  );

  for (final name in hermesVisualExtensionSchemas.keys) {
    testWidgets('$name renders at 320px and 1.5x through actual surface', (
      tester,
    ) async {
      final turns = <String>[];
      await pump(tester, fixture(name), turns);
      expect(find.text(name), findsOneWidget);
      expect(find.textContaining('Visual unavailable'), findsNothing);
      expect(find.byType(ExtensionVisual), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(turns, isEmpty);
    });
    test('$name rejects oversized title at schema boundary', () {
      final payload = fixture(name)
          .replaceFirst('"title": "$name"', '"title": "${'x' * 121}"');
      expect(
        normalizeHermesA2uiPayload(
          payload,
          catalog: createHermesVisualCatalog(),
        ).isReady,
        isFalse,
      );
    });
  }
  testWidgets('local selection controls never send a turn', (tester) async {
    final turns = <String>[];
    await pump(tester, fixture('BeforeAfterViewer'), turns);
    await tester.tap(find.widgetWithText(ChoiceChip, 'After'));
    await tester.pumpAndSettle();
    expect(find.text('Revised description'), findsOneWidget);
    expect(turns, isEmpty);
    await pump(tester, fixture('DecisionTree'), turns);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Explore'));
    await tester.pumpAndSettle();
    expect(find.text('Selected route'), findsOneWidget);
    expect(turns, isEmpty);
    await tester.tap(find.text('Reset choices'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a route'), findsOneWidget);
    await pump(tester, fixture('ScenarioSlider'), turns);
    await tester.drag(find.byType(Slider), const Offset(70, 0));
    await tester.pumpAndSettle();
    expect(turns, isEmpty);
    expect(find.text('Estimate: 45.00 USD'), findsNothing);
  });
  testWidgets('schedule and map selections stay local', (tester) async {
    final turns = <String>[];
    for (final kind in ['Agenda', 'CalendarGrid']) {
      await pump(tester, fixture(kind), turns);
      await tester.tap(find.widgetWithText(ChoiceChip, '2026-10-09'));
      await tester.pumpAndSettle();
      expect(find.text('10:00 · Review'), findsOneWidget);
    }
    await pump(tester, fixture('RelationshipMap'), turns);
    await tester.tap(find.widgetWithText(ChoiceChip, '2. Client'));
    await tester.pumpAndSettle();
    expect(find.text('Provided client context'), findsOneWidget);
    await pump(tester, fixture('RoomMap'), turns);
    await tester.tap(find.widgetWithText(ChoiceChip, '2. Office'));
    await tester.pumpAndSettle();
    expect(find.text('No further finding supplied.'), findsOneWidget);
    expect(turns, isEmpty);
  });
  test('new rich widgets stack in Rows even when weighted', () {
    final messages = fixture('DataTable')
        .trim()
        .split('\n')
        .map(jsonDecode)
        .toList();
    final data = messages[1]['updateComponents']['components'][0] as Map;
    data['id'] = 'data';
    data['weight'] = 1;
    messages[1]['updateComponents']['components'] = [
      {
        'id': 'root',
        'component': 'Row',
        'children': ['data'],
      },
      data,
    ];
    final result = normalizeHermesA2uiPayload(
      messages.map(jsonEncode).join('\n'),
      catalog: createHermesVisualCatalog(),
    );
    expect(result.isReady, isTrue);
    expect(result.changed, isTrue);
    final normalized = jsonDecode(result.payload.split('\n').last);
    expect(
      normalized['updateComponents']['components'][0]['component'],
      'Column',
    );
  });
  test('semantic validation rejects mismatched columns, chart points, invalid dates and cycles', () {
    final table = data('DataTable');
    table['rows'] = [
      ['one'],
    ];
    expect(validExtensionSemantics('DataTable', table), isFalse);
    final chart = data('MultiSeriesChart');
    chart['labels'] = ['one'];
    expect(validExtensionSemantics('MultiSeriesChart', chart), isFalse);
    final agenda = data('Agenda');
    agenda['events'][0]['date'] = '2026-02-31';
    expect(validExtensionSemantics('Agenda', agenda), isFalse);
    final tree = data('DecisionTree');
    tree['nodes'][1]['options'] = [
      {'label': 'Cycle', 'target': 'a'},
    ];
    expect(validExtensionSemantics('DecisionTree', tree), isFalse);
    final room = data('RoomMap');
    room['rooms'][0]['width'] = 1;
    room['rooms'][0]['x'] = .5;
    expect(validExtensionSemantics('RoomMap', room), isFalse);
    final slider = data('ScenarioSlider');
    slider['min'] = 10;
    expect(validExtensionSemantics('ScenarioSlider', slider), isFalse);
  });
  test('Dart schema and generation schema stay identical', () {
    final file = jsonDecode(
      File('docs/hermes-a2ui-mobile/references/extension-schemas.json')
          .readAsStringSync(),
    );
    expect(hermesVisualExtensionSchemas, file);
  });
}
