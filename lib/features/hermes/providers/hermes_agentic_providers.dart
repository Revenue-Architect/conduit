import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hermes_config.dart';
import '../services/hermes_agentic_state.dart';
import '../services/hermes_backend_service.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_identifier.dart';
import '../services/hermes_live_activity.dart';
import 'hermes_providers.dart';

/// One session's plan, delegated workers and live model, as Hermes reports
/// them. Empty for anything that is not a Desktop session.
final hermesAgenticStateProvider = StreamProvider.autoDispose
    .family<HermesAgenticSnapshot, String>((ref, storedId) {
      final service = ref.watch(hermesApiServiceProvider);
      if (service is! HermesDesktopApiService ||
          validateHermesOpaqueIdentifier(storedId) == null) {
        return Stream.value(HermesAgenticSnapshot.empty);
      }
      // A chat on screen gets its plan back even when Hermes sent none.
      service.restorePlanIfMissing(storedId);
      return service.agenticStateFor(storedId);
    });

/// One session's live activity history on this connection.
final hermesSessionActivityProvider = StreamProvider.autoDispose
    .family<List<HermesLiveActivityEvent>, String>((ref, storedId) {
      final service = ref.watch(hermesApiServiceProvider);
      if (service is! HermesDesktopApiService ||
          validateHermesOpaqueIdentifier(storedId) == null) {
        return Stream.value(const []);
      }
      return service.activityFor(storedId);
    });

/// Whether a session's turn is running, reconnecting, or idle.
final hermesSessionTurnStateProvider = StreamProvider.autoDispose
    .family<HermesDesktopTurnState, String>((ref, storedId) {
      final service = ref.watch(hermesApiServiceProvider);
      if (service is! HermesDesktopApiService ||
          validateHermesOpaqueIdentifier(storedId) == null) {
        return Stream.value(HermesDesktopTurnState.idle);
      }
      return service.turnStatesFor(storedId);
    });

typedef HermesModelCatalogKey = ({String? storedId, String? profile});

/// What a chat can switch to. Kept for a minute after the picker closes so
/// reopening it is instant; the list itself is the profile's connected
/// providers as Hermes reports them.
final hermesModelCatalogProvider = FutureProvider.autoDispose
    .family<HermesModelCatalog, HermesModelCatalogKey>((ref, key) async {
      final service = ref.watch(hermesApiServiceProvider);
      if (service is! HermesDesktopApiService) {
        return const HermesModelCatalog(options: []);
      }
      final link = ref.keepAlive();
      Timer? release;
      ref.onCancel(
        () => release = Timer(const Duration(minutes: 1), link.close),
      );
      ref.onResume(() => release?.cancel());
      ref.onDispose(() => release?.cancel());
      return service.modelCatalog(storedId: key.storedId, profile: key.profile);
    });

/// A model or effort picked in a new chat before it has a Hermes session;
/// the session is created with it.
final hermesDraftModelChoiceProvider =
    NotifierProvider<HermesDraftModelChoice, HermesSessionModelChoice?>(
      HermesDraftModelChoice.new,
    );

class HermesDraftModelChoice extends Notifier<HermesSessionModelChoice?> {
  @override
  HermesSessionModelChoice? build() => null;

  void set(HermesSessionModelChoice? choice) => state = choice;
}

/// Live sessions on this Hermes, polled while something shows them (and
/// the app is in front). Needs-you and working first.
final hermesActiveWorkProvider =
    StreamProvider.autoDispose<List<HermesLiveSession>>((ref) {
      final service = ref.watch(hermesApiServiceProvider);
      if (service is! HermesDesktopApiService) return Stream.value(const []);
      final controller = StreamController<List<HermesLiveSession>>();
      Timer? timer;
      var closed = false;
      Future<void> poll() async {
        if (closed) return;
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        final active =
            lifecycle == null || lifecycle == AppLifecycleState.resumed;
        if (active) {
          try {
            final sessions = await service.activeSessions();
            if (!closed) controller.add(sessions);
          } catch (error, stack) {
            if (!closed) controller.addError(error, stack);
          }
        }
        if (closed) return;
        final busy = controller.hasListener;
        timer = Timer(Duration(seconds: busy ? 4 : 10), poll);
      }

      unawaited(poll());
      ref.onDispose(() {
        closed = true;
        timer?.cancel();
        unawaited(controller.close());
      });
      return controller.stream;
    });
