import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_identifier.dart';
import '../services/hermes_pending_decision_store.dart';
import 'hermes_providers.dart';

final _pendingDecisionChangesProvider = StreamProvider<void>(
  (ref) => HermesPendingDecisionStore.changes,
);

/// Restart-safe requests for one exact stored Hermes session. Invalidate on
/// waiting-for-input, foreground recovery, or a successful resolution; never
/// poll all profiles or substitute the current/default session.
final hermesPendingSessionDecisionsProvider = FutureProvider.autoDispose
    .family<List<HermesPendingDesktopDecision>, String>((ref, storedId) async {
      ref.watch(_pendingDecisionChangesProvider);
      final service = ref.watch(hermesApiServiceProvider);
      if (service is! HermesDesktopApiService ||
          validateHermesOpaqueIdentifier(storedId) == null) {
        return const [];
      }
      return service.pendingStoredDecisionsForSession(storedId);
    });
