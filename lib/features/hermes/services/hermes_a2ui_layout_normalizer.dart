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
const _basicCatalogId =
    'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';
const _catalogSchemaId = 'https://a2ui.org/specification/v0_9/catalog.json';
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
/// Only a Row with both an unweighted Text child and a Button child becomes a
/// Column. Component IDs, order, properties, and event actions are preserved.
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
            ) ||
            !_validBySchema(A2uiSchemas.updateComponentsSchema(catalog), {
              'surfaceId': surfaceId,
              'components': rawComponents,
            }, schemaRegistry)) {
          return const HermesA2uiNormalizationResult.invalid();
        }

        final components = componentsBySurface.putIfAbsent(
          surfaceId,
          () => <String, Map<String, dynamic>>{},
        );
        final idsInUpdate = <String>{};
        for (final rawComponent in rawComponents) {
          final component = Map<String, dynamic>.from(
            rawComponent as Map<String, dynamic>,
          );
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
        }
        if (components.length > hermesA2uiMaxComponents) {
          return const HermesA2uiNormalizationResult.invalid();
        }
        updatedSurfaceIds.add(surfaceId);
        message['updateComponents'] = {
          ...update,
          'components': rawComponents
              .map((component) => Map<String, dynamic>.from(component as Map))
              .toList(growable: false),
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
      for (final childId in childIds.cast<String>()) {
        final child = componentsById[childId];
        if (child == null) continue;
        if (child['component'] == 'Button') hasButton = true;
        if (child['component'] == 'Text') {
          final weight = child['weight'];
          if (weight is! int || weight < 1) unweightedText = child;
        }
      }

      if (hasButton && unweightedText != null) {
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
  return event.length == 1 &&
      name is String &&
      name.length <= 80 &&
      _actionNamePattern.hasMatch(name);
}

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
