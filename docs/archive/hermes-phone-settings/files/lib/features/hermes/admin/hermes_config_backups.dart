/// On-device backups of Hermes configs, kept before each advanced-editor save
/// (KTD9). The last [kHermesConfigBackupLimit] per scope, newest first. They
/// are stored masked: every secret is a placeholder, so restoring one brings
/// back the structure and never a key.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/persistence_keys.dart';
import '../../../core/persistence/preferences_store.dart';
import 'hermes_config_document.dart';

/// How many backups each scope keeps.
const int kHermesConfigBackupLimit = 10;

/// Largest backup stored; a Hermes config is a few KB.
const int _kMaxBackupChars = 256 * 1024;

/// One kept version of a config. [yaml] is masked.
final class HermesConfigBackup {
  const HermesConfigBackup({required this.savedAt, required this.yaml});

  final DateTime savedAt;
  final String yaml;

  /// Identifies a backup within its scope.
  int get id => savedAt.millisecondsSinceEpoch;
}

/// Where backups live. The scope is a bot name, or null for the server's own
/// (root) config.
abstract interface class HermesConfigBackupStore {
  /// The scope's backups, newest first.
  List<HermesConfigBackup> list(String? scope);

  /// Keeps [yaml] (masked again here, whatever the caller passed) as the
  /// scope's newest backup and drops the oldest beyond the limit. Throws when
  /// it cannot be stored: a save must not go ahead without its backup.
  Future<void> add(String? scope, String yaml, {DateTime? now});
}

/// [HermesConfigBackupStore] over the app's preferences, one key per scope.
final class HermesPreferencesConfigBackupStore
    implements HermesConfigBackupStore {
  const HermesPreferencesConfigBackupStore();

  /// Bot names are `[a-z0-9_-]`, so `~root` cannot collide with one.
  static String _key(String? scope) =>
      '${PreferenceKeys.hermesConfigBackups}:${scope ?? '~root'}';

  @override
  List<HermesConfigBackup> list(String? scope) {
    final source = PreferencesStore.getString(_key(scope));
    if (source == null) return const [];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return const [];
      final backups = <HermesConfigBackup>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final time = item['t'];
        final yaml = item['y'];
        if (time is! int || yaml is! String) continue;
        backups.add(
          HermesConfigBackup(
            savedAt: DateTime.fromMillisecondsSinceEpoch(time),
            yaml: yaml,
          ),
        );
      }
      return backups.take(kHermesConfigBackupLimit).toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> add(String? scope, String yaml, {DateTime? now}) async {
    final masked = HermesConfigDocument.mask(yaml).text;
    if (masked.length > _kMaxBackupChars) {
      throw StateError('The config is too large to back up.');
    }
    final kept = list(scope);
    var stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    // Two saves in one millisecond must still be two backups.
    if (kept.isNotEmpty && kept.first.id >= stamp) stamp = kept.first.id + 1;
    final next = <HermesConfigBackup>[
      HermesConfigBackup(
        savedAt: DateTime.fromMillisecondsSinceEpoch(stamp),
        yaml: masked,
      ),
      ...kept,
    ].take(kHermesConfigBackupLimit);
    await PreferencesStore.putChecked(
      _key(scope),
      jsonEncode([
        for (final backup in next) {'t': backup.id, 'y': backup.yaml},
      ]),
    );
  }
}

/// The backups the advanced config editor uses. Tests override it.
final hermesConfigBackupStoreProvider = Provider<HermesConfigBackupStore>(
  (ref) => const HermesPreferencesConfigBackupStore(),
);
