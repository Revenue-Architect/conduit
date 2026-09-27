import 'package:conduit/core/persistence/preferences_store.dart';
import 'package:conduit/features/hermes/services/hermes_artifact_provenance_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PreferencesStore.debugOverride(await SharedPreferences.getInstance());
  });
  tearDown(PreferencesStore.debugReset);

  test(
    'records metadata only and scopes lookup to connection identity',
    () async {
      await HermesArtifactProvenanceStore.record(
        connectionIdentity: 'https://one.example|principal',
        path: '/opt/data/artifacts/test.png',
        sessionId: 'session-1',
      );
      final row = HermesArtifactProvenanceStore.find(
        'https://one.example|principal',
        '/opt/data/artifacts/test.png',
      );
      expect(row?.sessionId, 'session-1');
      expect(
        HermesArtifactProvenanceStore.find(
          'https://two.example|principal',
          '/opt/data/artifacts/test.png',
        ),
        isNull,
      );
    },
  );

  test('rejects arbitrary relative paths and invalid session IDs', () async {
    await HermesArtifactProvenanceStore.record(
      connectionIdentity: 'origin|principal',
      path: '../secret',
      sessionId: 'session-1',
    );
    await HermesArtifactProvenanceStore.record(
      connectionIdentity: 'origin|principal',
      path: '/opt/data/artifacts/report.pdf',
      sessionId: '',
    );
    expect(HermesArtifactProvenanceStore.allFor('origin|principal'), isEmpty);
  });
}
