import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import 'hermes_admin_client.dart';
import 'hermes_admin_models.dart';

/// The admin client for the current Hermes connection, or null when the
/// connection is not a Desktop Gateway (the settings surfaces need one).
///
/// It follows [hermesApiServiceProvider], so a reconnect or a token refresh
/// hands the settings screens a client over the new service.
final hermesAdminClientProvider = Provider<HermesAdminClient?>((ref) {
  final service = ref.watch(hermesApiServiceProvider);
  if (service is! HermesDesktopApiService) return null;
  return HermesAdminClient.fromService(service);
});

/// Every bot (profile) with the fields the settings screens list.
///
/// Empty when there is no admin client. An unavailable `profiles.list` is
/// an error the screen shows as "not supported on this Hermes".
final hermesAdminProfilesProvider =
    FutureProvider.autoDispose<List<HermesAdminProfile>>((ref) async {
      final client = ref.watch(hermesAdminClientProvider);
      if (client == null) return const [];
      return client.listProfiles();
    });
