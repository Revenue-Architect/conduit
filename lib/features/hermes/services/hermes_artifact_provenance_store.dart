import 'dart:convert';

import '../../../core/persistence/persistence_keys.dart';
import '../../../core/persistence/preferences_store.dart';
import 'hermes_identifier.dart';

final class HermesArtifactProvenance {
  const HermesArtifactProvenance({
    required this.connectionIdentity,
    required this.path,
    required this.sessionId,
    required this.observedAt,
  });

  final String connectionIdentity;
  final String path;
  final String sessionId;
  final DateTime observedAt;

  Map<String, String> toJson() => {
    'identity': connectionIdentity,
    'path': path,
    'session': sessionId,
    'observed_at': observedAt.toUtc().toIso8601String(),
  };

  static HermesArtifactProvenance? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final identity = raw['identity'];
    final path = raw['path'];
    final session = validateHermesOpaqueIdentifier(raw['session']);
    final observedAt = DateTime.tryParse(raw['observed_at']?.toString() ?? '');
    if (identity is! String ||
        identity.isEmpty ||
        identity.length > 512 ||
        path is! String ||
        path.length > 2048 ||
        !path.startsWith('/') ||
        session == null ||
        observedAt == null)
      return null;
    return HermesArtifactProvenance(
      connectionIdentity: identity,
      path: path,
      sessionId: session,
      observedAt: observedAt.toUtc(),
    );
  }
}

/// Bounded metadata only. Auth credentials and artifact bytes never enter this
/// store. Identity includes the active Hermes endpoint/principal so an old
/// account's provenance is not shown under a new connection.
final class HermesArtifactProvenanceStore {
  static const maxRecords = 128;
  static Future<void> _writes = Future<void>.value();

  static List<HermesArtifactProvenance> allFor(String identity) =>
      _read().where((row) => row.connectionIdentity == identity).toList();

  static HermesArtifactProvenance? find(String identity, String path) {
    for (final row in _read().reversed) {
      if (row.connectionIdentity == identity && row.path == path) return row;
    }
    return null;
  }

  static Future<void> record({
    required String connectionIdentity,
    required String path,
    required String sessionId,
  }) {
    final session = validateHermesOpaqueIdentifier(sessionId);
    if (!PreferencesStore.isReady ||
        connectionIdentity.isEmpty ||
        connectionIdentity.length > 512 ||
        path.length > 2048 ||
        !path.startsWith('/') ||
        session == null)
      return Future<void>.value();
    final write = _writes.then((_) async {
      final existing = _read();
      if (existing.any(
        (row) =>
            row.connectionIdentity == connectionIdentity &&
            row.path == path &&
            row.sessionId == session,
      ))
        return;
      existing.removeWhere(
        (row) =>
            row.connectionIdentity == connectionIdentity && row.path == path,
      );
      existing.add(
        HermesArtifactProvenance(
          connectionIdentity: connectionIdentity,
          path: path,
          sessionId: session,
          observedAt: DateTime.now().toUtc(),
        ),
      );
      final bounded = existing.length <= maxRecords
          ? existing
          : existing.sublist(existing.length - maxRecords);
      await PreferencesStore.putChecked(
        PreferenceKeys.hermesArtifactProvenance,
        bounded.map((row) => jsonEncode(row.toJson())).toList(growable: false),
      );
    });
    _writes = write.catchError((_) {});
    return write;
  }

  static List<HermesArtifactProvenance> _read() {
    if (!PreferencesStore.isReady) return [];
    final values =
        PreferencesStore.getStringList(
          PreferenceKeys.hermesArtifactProvenance,
        ) ??
        const <String>[];
    return [
      for (final source in values)
        if (source.length <= 4096)
          if (HermesArtifactProvenance.fromJson(_decode(source))
              case final row?)
            row,
    ];
  }

  static Object? _decode(String source) {
    try {
      return jsonDecode(source);
    } catch (_) {
      return null;
    }
  }
}
