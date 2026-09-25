import 'dart:convert';
import 'dart:io';

import 'package:conduit/features/hermes/services/hermes_a2ui_layout_normalizer.dart';
import 'package:conduit/features/hermes/widgets/hermes_visual_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
// ignore: implementation_imports
import 'package:genui/src/primitives/embedded_schemas.g.dart'
    show commonTypesSchemaJson;
// ignore: depend_on_referenced_packages
import 'package:json_schema_builder/json_schema_builder.dart';

const _catalogId =
    'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';

void main() {
  final catalog = createHermesVisualCatalog();

  test('preflight schemas accept supported v0.9 message shapes', () {
    final registry = SchemaRegistry()
      ..addSchema(
        Uri.parse(commonTypesSchemaId),
        Schema.fromMap(
          Map<String, Object?>.from(jsonDecode(commonTypesSchemaJson) as Map),
        ),
      )
      ..addSchema(
        Uri.parse('https://a2ui.org/specification/v0_9/catalog.json'),
        catalog.fullSchema,
      );
    final createErrors = A2uiSchemas.createSurfaceSchema().validateSync({
      'surfaceId': 's',
      'catalogId': _catalogId,
    }, schemaRegistry: registry);
    final updateErrors = A2uiSchemas.updateComponentsSchema(catalog)
        .validateSync({
          'surfaceId': 's',
          'components': [
            {
              'id': 'root',
              'component': 'Row',
              'children': ['text', 'button'],
            },
            {'id': 'text', 'component': 'Text', 'text': 'Online'},
            {
              'id': 'button',
              'component': 'Button',
              'child': 'label',
              'action': {
                'event': {'name': 'service.details'},
              },
            },
            {'id': 'label', 'component': 'Text', 'text': 'Details'},
          ],
        }, schemaRegistry: registry);
    expect(createErrors, isEmpty, reason: createErrors.join('; '));
    expect(updateErrors, isEmpty, reason: updateErrors.join('; '));
  });

  test('stacks an unweighted Text and Button row without changing actions', () {
    const input =
        '''
{"version":"v0.9","createSurface":{"surfaceId":"saved-status","catalogId":"$_catalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"saved-status","components":[{"id":"root","component":"Row","children":["summary","action"]},{"id":"summary","component":"Text","text":"A long status that used to overflow the phone screen"},{"id":"action","component":"Button","child":"label","action":{"event":{"name":"service.immich_details"}}},{"id":"label","component":"Text","text":"Details"}]}}
''';

    final result = normalizeHermesA2uiPayload(input, catalog: catalog);

    expect(result.isReady, isTrue);
    expect(result.changed, isTrue);
    final update =
        jsonDecode(result.payload.split('\n').last) as Map<String, dynamic>;
    final components =
        ((update['updateComponents'] as Map<String, dynamic>)['components']
                as List)
            .cast<Map<String, dynamic>>();
    expect(components.first['component'], 'Column');
    expect(components.map((component) => component['id']), [
      'root',
      'summary',
      'action',
      'label',
    ]);
    expect((components[2]['action'] as Map<String, dynamic>)['event'], {
      'name': 'service.immich_details',
    });
  });

  test('keeps a weighted Text and Button row unchanged', () {
    const input =
        '''
{"version":"v0.9","createSurface":{"surfaceId":"weighted","catalogId":"$_catalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"weighted","components":[{"id":"root","component":"Row","children":["summary","action"]},{"id":"summary","component":"Text","text":"Connected","weight":1},{"id":"action","component":"Button","child":"label","action":{"event":{"name":"service.details"}}},{"id":"label","component":"Text","text":"Details"}]}}
''';

    final result = normalizeHermesA2uiPayload(input, catalog: catalog);

    expect(result.isReady, isTrue);
    expect(result.changed, isFalse);
    expect(result.payload, input);
  });

  test('weights an unweighted ranged metric row and is idempotent', () {
    final input = File(
      'test/fixtures/hermes/a2ui/metric-row-ranged-unweighted.jsonl',
    ).readAsStringSync();

    final result = normalizeHermesA2uiPayload(input, catalog: catalog);

    expect(result.isReady, isTrue);
    expect(result.changed, isTrue);
    final lines = result.payload.split('\n');
    final update = jsonDecode(lines.last) as Map<String, dynamic>;
    final components =
        ((update['updateComponents'] as Map<String, dynamic>)['components']
                as List)
            .cast<Map<String, dynamic>>();
    expect(components.first['id'], 'root');
    expect(components.first['component'], 'Row');
    expect(components.last, {
      'id': 'cpu',
      'component': 'MetricTile',
      'label': 'CPU use',
      'value': 65,
      'unit': '%',
      'min': 0,
      'max': 100,
      'state': 'ok',
      'source': 'Synthetic test data',
      'weight': 1,
    });

    final repeated = normalizeHermesA2uiPayload(
      result.payload,
      catalog: catalog,
    );
    expect(repeated.isReady, isTrue);
    expect(repeated.changed, isFalse);
    expect(repeated.payload, result.payload);
  });

  test('preserves explicit metric weights and already-safe rows', () {
    const input =
        '''
{"version":"v0.9","createSurface":{"surfaceId":"weighted-metrics","catalogId":"$_catalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"weighted-metrics","components":[{"id":"root","component":"Row","children":["cpu","memory"]},{"id":"cpu","component":"MetricTile","label":"CPU use","value":65,"unit":"%","min":0,"max":100,"weight":2},{"id":"memory","component":"MetricTile","label":"Memory","value":7,"unit":"GiB","min":0,"max":16,"weight":1}]}}
''';

    final result = normalizeHermesA2uiPayload(input, catalog: catalog);

    expect(result.isReady, isTrue);
    expect(result.changed, isFalse);
    expect(result.payload, input);
  });

  test('accepts the validated synthetic meal-plan form from device QA', () {
    final input = File('test/fixtures/hermes/a2ui/meal-plan-form.jsonl')
        .readAsStringSync();

    final result = normalizeHermesA2uiPayload(input, catalog: catalog);

    expect(result.isReady, isTrue);
    expect(result.changed, isFalse);
  });

  test('accepts bounded event context and rejects context function calls', () {
    const valid =
        '''
{"version":"v0.9","createSurface":{"surfaceId":"context","catalogId":"$_catalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"context","components":[{"id":"root","component":"Button","child":"label","action":{"event":{"name":"trip.view_details","context":{"trip":"montreal","day":2,"selected":{"path":"/pace"}}}}},{"id":"label","component":"Text","text":"View details"}]}}
''';

    expect(normalizeHermesA2uiPayload(valid, catalog: catalog).isReady, isTrue);

    final unsafe = valid.replaceFirst(
      '"selected":{"path":"/pace"}',
      '"selected":{"call":"openUrl","args":{"url":"https://invalid.example"}}',
    );
    expect(
      normalizeHermesA2uiPayload(unsafe, catalog: catalog).isReady,
      isFalse,
    );
  });

  test('repairs v0.9 spec-style Tabs for pinned GenUI', () {
    const input =
        '''
{"version":"v0.9","createSurface":{"surfaceId":"tabs","catalogId":"$_catalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"tabs","components":[{"id":"root","component":"Tabs","tabs":[{"title":"Plan","child":"plan"},{"title":"Notes","child":"notes"}]},{"id":"plan","component":"Text","text":"Saturday itinerary"},{"id":"notes","component":"Text","text":"Illustrative data"}]}}
''';

    final result = normalizeHermesA2uiPayload(input, catalog: catalog);

    expect(result.isReady, isTrue);
    expect(result.changed, isTrue);
    final update = jsonDecode(result.payload.split('\n').last);
    final root = update['updateComponents']['components'].first;
    expect(root['tabs'], [
      {'label': 'Plan', 'content': 'plan'},
      {'label': 'Notes', 'content': 'notes'},
    ]);
  });

  test('accepts varied travel, budget, and project surfaces', () {
    for (final fixture in const [
      'travel-itinerary.jsonl',
      'budget-planner.jsonl',
      'project-sprint.jsonl',
    ]) {
      final input = File('test/fixtures/hermes/a2ui/$fixture')
          .readAsStringSync();
      final result = normalizeHermesA2uiPayload(input, catalog: catalog);
      expect(result.isReady, isTrue, reason: fixture);
    }
  });

  test('stacks rows that mix charts or controls with other children', () {
    const input =
        '''
{"version":"v0.9","createSurface":{"surfaceId":"mixed","catalogId":"$_catalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"mixed","components":[{"id":"root","component":"Column","children":["chart-row","control-row","text-row"]},{"id":"chart-row","component":"Row","children":["chart","button"]},{"id":"chart","component":"MiniChart","label":"Trend","kind":"line","points":[{"label":"A","value":1},{"label":"B","value":2}]},{"id":"button","component":"Button","child":"button-label","action":{"event":{"name":"chart.details"}}},{"id":"button-label","component":"Text","text":"Chart details"},{"id":"control-row","component":"Row","children":["slider","hint"]},{"id":"slider","component":"Slider","label":"Level","min":0,"max":100,"value":{"path":"/level"}},{"id":"hint","component":"Text","text":"Choose a value"},{"id":"text-row","component":"Row","children":["verbose","short"]},{"id":"verbose","component":"Text","text":"This label is intentionally long and should not be placed beside another value on mobile"},{"id":"short","component":"Text","text":"Online"}]}}
''';

    final result = normalizeHermesA2uiPayload(input, catalog: catalog);

    expect(result.isReady, isTrue);
    final update = jsonDecode(
      result.payload.split('\n').where((line) => line.trim().isNotEmpty).last,
    ) as Map<String, dynamic>;
    final components =
        ((update['updateComponents'] as Map<String, dynamic>)['components']
                as List)
            .cast<Map<String, dynamic>>();
    expect(
      components
          .where(
            (component) =>
                component['id'] == 'chart-row' ||
                component['id'] == 'control-row' ||
                component['id'] == 'text-row',
          )
          .map((component) => component['component']),
      everyElement('Column'),
    );
    expect(components.map((component) => component['id']), [
      'root',
      'chart-row',
      'chart',
      'button',
      'button-label',
      'control-row',
      'slider',
      'hint',
      'text-row',
      'verbose',
      'short',
    ]);
    expect((components[3]['action'] as Map<String, dynamic>)['event'], {
      'name': 'chart.details',
    });
  });

  test('rejects invalid versions, foreign catalogs, malformed JSON and bad IDs', () {
    const header =
        '{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"$_catalogId"}}\n';
    const validUpdate =
        '{"version":"v0.9","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Text","text":"Status"}]}}';

    expect(
      normalizeHermesA2uiPayload('not-json', catalog: catalog).isReady,
      isFalse,
    );
    expect(
      normalizeHermesA2uiPayload(
        header.replaceFirst(
              _catalogId,
              'https://untrusted.invalid/catalog.json',
            ) +
            validUpdate,
        catalog: catalog,
      ).isReady,
      isFalse,
    );
    expect(
      normalizeHermesA2uiPayload(
        header + validUpdate.replaceFirst('"v0.9"', '"v1.0"'),
        catalog: catalog,
      ).isReady,
      isFalse,
    );
    expect(
      normalizeHermesA2uiPayload(
        header + validUpdate.replaceFirst('"root"', 'null'),
        catalog: catalog,
      ).isReady,
      isFalse,
    );
  });

  test('rejects payloads above the byte ceiling', () {
    final oversized = List.filled(hermesA2uiMaxPayloadBytes + 1, ' ').join();

    expect(
      normalizeHermesA2uiPayload(oversized, catalog: catalog).isReady,
      isFalse,
    );
  });

  test('limits unique components across the entire response', () {
    final components = List.generate(
      hermesA2uiMaxComponents + 1,
      (index) => {'id': 'component-$index', 'component': 'Text', 'text': 'x'},
    );
    final payload = [
      jsonEncode({
        'version': 'v0.9',
        'createSurface': {'surfaceId': 'many', 'catalogId': _catalogId},
      }),
      jsonEncode({
        'version': 'v0.9',
        'updateComponents': {'surfaceId': 'many', 'components': components},
      }),
    ].join('\n');

    expect(
      normalizeHermesA2uiPayload(payload, catalog: catalog).isReady,
      isFalse,
    );
  });
}
