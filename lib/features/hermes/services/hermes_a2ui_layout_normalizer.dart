import 'dart:convert';

import 'package:genui/genui.dart';
// GenUI 0.10.3's public component schemas reference this bundled common-types
// schema. Register the bundled copy so preflight validation never fetches a
// schema from the network. genui is pinned to 0.10.3 in pubspec.yaml.
// ignore: implementation_imports
import 'package:genui/src/primitives/embedded_schemas.g.dart'
    show commonTypesSchemaJson;
// GenUI 0.10.3 exposes Schema validation in its API but does not re-export the
// schema builder. Keep the documented single direct dependency on GenUI; the
// exact transitive builder version is pinned in pubspec.lock.
// ignore: depend_on_referenced_packages
import 'package:json_schema_builder/json_schema_builder.dart';

const hermesA2uiMaxPayloadBytes = 256 * 1024;
const hermesA2uiMaxComponents = 100;
const hermesA2uiMaxComponentDepth = 12;
// Longer or data-bound Text in an unweighted Row is too unpredictable to
// compare side by side on a phone; stack it instead.
const _maxShortUnweightedRowTextLength = 36;
const _basicCatalogId =
    'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';
const _catalogSchemaId = 'https://a2ui.org/specification/v0_9/catalog.json';

// Unweighted direct children of these supported types are stacked: MiniChart,
// StatusBadge, Slider, TextField, ChoicePicker, DateTimeInput, Card, Column,
// Row, List, and Tabs. They either contain their own flex layout or need the
// full row width to remain legible. Asset components (Image, AudioPlayer, and
// Video) are unavailable in the no-asset catalog. MetricTile is intentionally
// excluded: rows made only of comparable metric tiles stay side-by-side and
// each unweighted tile receives a flex weight instead.
const _stackInRowComponentTypes = {
  'MiniChart',
  'StatusBadge',
  'Slider',
  'TextField',
  'ChoicePicker',
  'DateTimeInput',
  'Card',
  'Column',
  'Row',
  'List',
  'Tabs',
};
final _actionNamePattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*)*$',
);

SchemaRegistry _createSchemaRegistry(Catalog catalog) {
  final registry = SchemaRegistry();
  final schema = jsonDecode(commonTypesSchemaJson);
  registry.addSchema(
    Uri.parse(commonTypesSchemaId),
    Schema.fromMap(Map<String, Object?>.from(schema as Map)),
  );
  registry.addSchema(Uri.parse(_catalogSchemaId), catalog.fullSchema);
  return registry;
}

enum HermesA2uiPayloadStatus { ready, invalid }

/// A bounded, read-time normalization result for one completed Hermes A2UI
/// fence. The source message is never modified or persisted by this service.
class HermesA2uiNormalizationResult {
  const HermesA2uiNormalizationResult._({
    required this.status,
    required this.payload,
    required this.changed,
  });

  const HermesA2uiNormalizationResult.invalid()
    : this._(
        status: HermesA2uiPayloadStatus.invalid,
        payload: '',
        changed: false,
      );

  final HermesA2uiPayloadStatus status;
  final String payload;
  final bool changed;

  bool get isReady => status == HermesA2uiPayloadStatus.ready;
}

/// Validates and repairs a completed A2UI v0.9 block before GenUI receives it.
/// Unweighted MetricTile-only rows receive flex weights for comparison. Rows
/// containing charts, badges, width-dependent built-in controls/media, mixed
/// metric content, or an unweighted Text beside a Button become Columns.
/// Existing positive weights, component IDs, order, values, and actions remain
/// unchanged.
///
/// The block is limited to the registered catalog, bounded in size, checked
/// against GenUI's component schemas without network access, and checked for a
/// rooted acyclic component graph. Unsupported data fails closed to the
/// renderer's regeneration fallback.
HermesA2uiNormalizationResult normalizeHermesA2uiPayload(
  String payload, {
  required Catalog catalog,
}) {
  if (utf8.encode(payload).length > hermesA2uiMaxPayloadBytes) {
    return const HermesA2uiNormalizationResult.invalid();
  }
  final schemaRegistry = _createSchemaRegistry(catalog);

  final messages = <Map<String, dynamic>>[];
  final createdSurfaceIds = <String>{};
  final updatedSurfaceIds = <String>{};
  final otherTargetSurfaceIds = <String>{};
  final componentsBySurface = <String, Map<String, Map<String, dynamic>>>{};
  var changed = false;

  for (final sourceLine in payload.split('\n')) {
    if (sourceLine.trim().isEmpty) continue;

    final Object? decoded;
    try {
      decoded = jsonDecode(sourceLine);
    } on FormatException {
      return const HermesA2uiNormalizationResult.invalid();
    }
    if (decoded is! Map<String, dynamic> || decoded['version'] != 'v0.9') {
      return const HermesA2uiNormalizationResult.invalid();
    }

    final message = Map<String, dynamic>.from(decoded);
    final controlKeys = const [
      'createSurface',
      'updateComponents',
      'updateDataModel',
      'deleteSurface',
    ].where(message.containsKey).toList(growable: false);
    if (controlKeys.length != 1) {
      return const HermesA2uiNormalizationResult.invalid();
    }

    switch (controlKeys.single) {
      case 'createSurface':
        final createSurface = message['createSurface'];
        if (createSurface is! Map<String, dynamic> ||
            createSurface['catalogId'] != _basicCatalogId ||
            // Theme icon URLs could initiate a device network request.
            createSurface.containsKey('theme') ||
            !_validBySchema(
              A2uiSchemas.createSurfaceSchema(),
              createSurface,
              schemaRegistry,
            )) {
          return const HermesA2uiNormalizationResult.invalid();
        }
        final surfaceId = createSurface['surfaceId'];
        if (surfaceId is! String ||
            surfaceId.isEmpty ||
            surfaceId.length > 128 ||
            !createdSurfaceIds.add(surfaceId)) {
          return const HermesA2uiNormalizationResult.invalid();
        }

      case 'updateComponents':
        final update = message['updateComponents'];
        if (update is! Map<String, dynamic> || update['components'] is! List) {
          return const HermesA2uiNormalizationResult.invalid();
        }
        final surfaceId = update['surfaceId'];
        final rawComponents = update['components'] as List;
        if (surfaceId is! String ||
            surfaceId.isEmpty ||
            surfaceId.length > 128 ||
            rawComponents.isEmpty ||
            rawComponents.length > hermesA2uiMaxComponents ||
            rawComponents.any(
              (component) => component is! Map<String, dynamic>,
            )) {
          return const HermesA2uiNormalizationResult.invalid();
        }

        final schemaComponents = <Map<String, dynamic>>[];
        for (final rawComponent in rawComponents) {
          final component = Map<String, dynamic>.from(
            rawComponent as Map<String, dynamic>,
          );
          if (component['component'] == 'Tabs' && component['tabs'] is List) {
            final normalizedTabs = <Map<String, dynamic>>[];
            for (final rawTab in component['tabs'] as List) {
              if (rawTab is! Map<String, dynamic>) {
                return const HermesA2uiNormalizationResult.invalid();
              }
              final tab = Map<String, dynamic>.from(rawTab);
              final usesSpecNames =
                  tab.containsKey('title') || tab.containsKey('child');
              if (usesSpecNames) {
                // The published v0.9 catalog uses title/child, while pinned
                // Flutter GenUI 0.10.3 consumes label/content. Repair the
                // standard spelling at read time so saved replies survive.
                if (tab.containsKey('label') || tab.containsKey('content')) {
                  return const HermesA2uiNormalizationResult.invalid();
                }
                final title = tab.remove('title');
                final child = tab.remove('child');
                if (title is! String || child is! String) {
                  return const HermesA2uiNormalizationResult.invalid();
                }
                tab['label'] = title;
                tab['content'] = child;
                changed = true;
              }
              normalizedTabs.add(tab);
            }
            component['tabs'] = normalizedTabs;
          }
          schemaComponents.add(component);
        }

        if (!_validBySchema(A2uiSchemas.updateComponentsSchema(catalog), {
          'surfaceId': surfaceId,
          'components': schemaComponents,
        }, schemaRegistry)) {
          return const HermesA2uiNormalizationResult.invalid();
        }

        final components = componentsBySurface.putIfAbsent(
          surfaceId,
          () => <String, Map<String, dynamic>>{},
        );
        final normalizedComponents = <Map<String, dynamic>>[];
        final idsInUpdate = <String>{};
        for (final rawComponent in schemaComponents) {
          final component = Map<String, dynamic>.from(rawComponent);
          final id = component['id'];
          final type = component['component'];
          if (id is! String ||
              id.isEmpty ||
              id.length > 128 ||
              type is! String ||
              !idsInUpdate.add(id)) {
            return const HermesA2uiNormalizationResult.invalid();
          }
          if (type == 'Button' && !_hasHermesEventAction(component['action'])) {
            // Conduit forwards button events to the Hermes chat. GenUI client
            // function calls are not part of this integration.
            return const HermesA2uiNormalizationResult.invalid();
          }
          components[id] = component;
          normalizedComponents.add(component);
        }
        if (components.length > hermesA2uiMaxComponents) {
          return const HermesA2uiNormalizationResult.invalid();
        }
        updatedSurfaceIds.add(surfaceId);
        message['updateComponents'] = {
          ...update,
          'components': normalizedComponents,
        };

      case 'updateDataModel':
        final update = message['updateDataModel'];
        if (update is! Map<String, dynamic> ||
            !_validBySchema(
              A2uiSchemas.updateDataModelSchema(),
              update,
              schemaRegistry,
            )) {
          return const HermesA2uiNormalizationResult.invalid();
        }
        final surfaceId = update['surfaceId'];
        if (surfaceId is! String ||
            surfaceId.isEmpty ||
            surfaceId.length > 128) {
          return const HermesA2uiNormalizationResult.invalid();
        }
        otherTargetSurfaceIds.add(surfaceId);

      case 'deleteSurface':
        final deleteSurface = message['deleteSurface'];
        if (deleteSurface is! Map<String, dynamic> ||
            !_validBySchema(
              A2uiSchemas.deleteSurfaceSchema(),
              deleteSurface,
              schemaRegistry,
            )) {
          return const HermesA2uiNormalizationResult.invalid();
        }
        final surfaceId = deleteSurface['surfaceId'];
        if (surfaceId is! String ||
            surfaceId.isEmpty ||
            surfaceId.length > 128) {
          return const HermesA2uiNormalizationResult.invalid();
        }
        otherTargetSurfaceIds.add(surfaceId);
    }
    messages.add(message);
  }

  if (messages.isEmpty ||
      createdSurfaceIds.isEmpty ||
      updatedSurfaceIds.isEmpty ||
      !createdSurfaceIds.containsAll(updatedSurfaceIds) ||
      !updatedSurfaceIds.containsAll(createdSurfaceIds) ||
      !createdSurfaceIds.containsAll(otherTargetSurfaceIds)) {
    return const HermesA2uiNormalizationResult.invalid();
  }

  for (final surfaceId in updatedSurfaceIds) {
    final components = componentsBySurface[surfaceId];
    if (components == null ||
        !components.containsKey('root') ||
        !_hasSafeComponentGraph(components)) {
      return const HermesA2uiNormalizationResult.invalid();
    }
  }

  for (final message in messages) {
    final update = message['updateComponents'];
    if (update is! Map<String, dynamic>) continue;
    final surfaceId = update['surfaceId'] as String;
    final components = update['components'] as List;
    final componentsById = componentsBySurface[surfaceId]!;
    for (final rawComponent in components) {
      final component = rawComponent as Map<String, dynamic>;
      if (component['component'] != 'Row') continue;
      final childIds = component['children'];
      // A data-bound template has runtime-generated children, so its hit
      // targets cannot be classified here. Fail closed instead of risking an
      // overflowing interactive row.
      if (childIds is Map) {
        return const HermesA2uiNormalizationResult.invalid();
      }
      if (childIds is! List || childIds.any((id) => id is! String)) continue;

      var hasButton = false;
      Map<String, dynamic>? unweightedText;
      final children = <Map<String, dynamic>>[];
      for (final childId in childIds.cast<String>()) {
        final child = componentsById[childId];
        if (child == null) continue;
        children.add(child);
        if (child['component'] == 'Button') hasButton = true;
        if (child['component'] == 'Text') {
          final weight = child['weight'];
          if (weight is! int || weight < 1) unweightedText = child;
        }
      }

      final childTypes = children
          .map((child) => child['component'])
          .whereType<String>()
          .toSet();
      final allMetricTiles =
          children.isNotEmpty &&
          children.every((child) => child['component'] == 'MetricTile');
      if (allMetricTiles) {
        for (final child in children) {
          // An explicitly weighted tile is already safe and may encode a
          // deliberate unequal comparison. Never rewrite it.
          if (child.containsKey('weight')) continue;
          child['weight'] = 1;
          changed = true;
        }
        continue;
      }

      final hasUnweightedWidthDependentChild = children.any(
        (child) =>
            _stackInRowComponentTypes.contains(child['component']) &&
            !_hasPositiveWeight(child),
      );
      final hasUnweightedMetricTile = children.any(
        (child) =>
            child['component'] == 'MetricTile' && !_hasPositiveWeight(child),
      );
      final hasLongUnweightedText = children.any((child) {
        if (child['component'] != 'Text' || _hasPositiveWeight(child)) {
          return false;
        }
        final text = child['text'];
        return text is! String ||
            text.trim().length > _maxShortUnweightedRowTextLength;
      });
      final mixedMetricRow =
          childTypes.contains('MetricTile') && hasUnweightedMetricTile;
      final mustStack =
          (hasButton && unweightedText != null) ||
          hasUnweightedWidthDependentChild ||
          hasLongUnweightedText ||
          mixedMetricRow;

      if (mustStack && component['component'] == 'Row') {
        component['component'] = 'Column';
        // Keep the surface-wide component graph in sync with the message map.
        componentsById[component['id'] as String] = component;
        changed = true;
      }
    }
  }

  final normalizedPayload = changed
      ? messages.map(jsonEncode).join('\n')
      : payload;
  return HermesA2uiNormalizationResult._(
    status: HermesA2uiPayloadStatus.ready,
    payload: normalizedPayload,
    changed: changed,
  );
}

bool _validBySchema(Schema schema, Object data, SchemaRegistry schemaRegistry) {
  try {
    return schema.validateSync(data, schemaRegistry: schemaRegistry).isEmpty;
  } on SchemaResolutionRequiredException {
    return false;
  } catch (_) {
    return false;
  }
}

bool _hasHermesEventAction(Object? action) {
  if (action is! Map<String, dynamic>) return false;
  if (action.length != 1 || action['event'] is! Map<String, dynamic>) {
    return false;
  }
  final event = action['event'] as Map<String, dynamic>;
  final name = event['name'];
  if (event.keys.any((key) => key != 'name' && key != 'context') ||
      name is! String ||
      name.length > 80 ||
      !_actionNamePattern.hasMatch(name)) {
    return false;
  }

  if (!event.containsKey('context')) return true;
  final context = event['context'];
  if (context is! Map<String, dynamic> || context.length > 16) return false;
  return context.entries.every(
    (entry) =>
        entry.key.isNotEmpty &&
        entry.key.length <= 80 &&
        _isSafeHermesEventContextValue(entry.value, depth: 0),
  );
}

bool _isSafeHermesEventContextValue(Object? value, {required int depth}) {
  if (depth > 3) return false;
  if (value is bool) return true;
  if (value is num) return value.isFinite;
  if (value is String) return value.length <= 2048;
  if (value is List) {
    return value.length <= 32 &&
        value.every(
          (item) => _isSafeHermesEventContextValue(item, depth: depth + 1),
        );
  }
  if (value is Map<String, dynamic>) {
    // A2UI context values may bind to the surface data model. Keep that
    // useful declarative form, but reject function-call objects and arbitrary
    // nested maps at this client safety boundary.
    return value.length == 1 &&
        value['path'] is String &&
        (value['path'] as String).length <= 256;
  }
  return false;
}

bool _hasPositiveWeight(Map<String, dynamic> component) =>
    component['weight'] is int && (component['weight'] as int) > 0;

bool _hasSafeComponentGraph(Map<String, Map<String, dynamic>> components) {
  final visiting = <String>{};
  final visited = <String>{};

  bool visit(String id, int depth) {
    if (depth > hermesA2uiMaxComponentDepth || visiting.contains(id)) {
      return false;
    }
    if (visited.contains(id)) return true;
    final component = components[id];
    if (component == null) return false;
    visiting.add(id);
    final references = <String>[];

    for (final key in const ['child', 'content', 'trigger']) {
      final reference = component[key];
      if (reference == null) continue;
      if (reference is! String) return false;
      references.add(reference);
    }

    final children = component['children'];
    if (children is List) {
      if (children.any((child) => child is! String)) return false;
      references.addAll(children.cast<String>());
    } else if (children is Map) {
      final componentId = children['componentId'];
      final path = children['path'];
      if (componentId is! String || path is! String) return false;
      references.add(componentId);
    } else if (children != null) {
      return false;
    }

    final tabs = component['tabs'];
    if (tabs is List) {
      for (final tab in tabs) {
        if (tab is! Map || tab['content'] is! String) return false;
        references.add(tab['content'] as String);
      }
    }

    for (final reference in references) {
      if (!visit(reference, depth + 1)) return false;
    }
    visiting.remove(id);
    visited.add(id);
    return true;
  }

  return visit('root', 1);
}
