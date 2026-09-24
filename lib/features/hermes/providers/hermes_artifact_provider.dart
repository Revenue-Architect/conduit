import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_artifact_client.dart';
import 'hermes_providers.dart';

final hermesArtifactClientProvider = Provider<HermesArtifactClient>((ref) {
  final config = ref.watch(hermesConfigProvider);
  final service = ref.watch(hermesApiServiceProvider);
  final client = HermesArtifactClient(
    config: config,
    nativeAuthorizationReader: service is HermesDesktopApiService
        ? service.artifactAuthorizationHeaders
        : null,
  );
  ref.onDispose(client.close);
  return client;
});
