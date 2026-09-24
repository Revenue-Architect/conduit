import 'dart:convert';

import 'package:conduit/features/hermes/services/hermes_a2ui_layout_normalizer.dart';
import 'package:conduit/features/hermes/widgets/hermes_visual_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
// ignore: implementation_imports
import 'package:genui/src/primitives/embedded_schemas.g.dart'
    show commonTypesSchemaJson;
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
