import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../../../core/providers/app_providers.dart' show activeConversationProvider;
import '../../hermes/providers/hermes_providers.dart';
import '../../hermes/services/hermes_desktop_api_service.dart';
import '../../notifications/providers/notification_center.dart';
import '../platform/conduit_push_api.g.dart';
import '../services/push_dispatcher.dart';
import 'push_providers.dart';

/// Connects native push events to the app: foreground pushes go through the
/// shared notification router, native changes refresh the health card and
/// pending approvals, and registration is re-asserted once per app start.
/// Read once from app startup (`ref.read(pushRuntimeProvider)`).
final pushRuntimeProvider = Provider<PushDispatcher>((ref) {
  // Server-side additions to a chat (an initiative card, a digest entry) never
  // arrive on the live event stream. A push or a return to the app is the
  // moment they may have landed, so let the open Hermes chat re-read its stored
  // transcript (the live runtime's history does not include such writes).
  void refreshOpenHermesChat() {
    final service = ref.read(hermesApiServiceProvider);
    // The open chat's own binding is what its transcript refresh checks.
    final active = ref.read(activeConversationProvider);
    final sessionId =
        (active?.metadata['hermesSessionId'] as String?) ??
        ref.read(hermesActiveSessionProvider);
    if (service is HermesDesktopApiService && sessionId != null) {
      service.requestTranscriptRefresh(sessionId);
    }
  }

  final dispatcher = PushDispatcher(
    route: (notification) async {
      await ref.read(notificationRouterProvider).route(notification);
      refreshOpenHermesChat();
    },
    onStatusChange: () {
      unawaited(ref.read(pushStatusProvider.notifier).refreshLocal());
    },
    onApprovalActivity: (_) {
      ref.invalidate(approvalsPendingProvider);
      ref.invalidate(approvalDetailProvider);
    },
  );
  ConduitPushFlutterApi.setUp(dispatcher);
  var disposed = false;
  Future<void> reconcile() async {
    await ref.read(pushRegistrationServiceProvider).startup();
    if (disposed) return;
    ref.invalidate(pushPairingProvider);
    unawaited(ref.read(pushStatusProvider.notifier).refresh());
    ref.invalidate(approvalsPendingProvider);
    ref.invalidate(approvalDetailProvider);
  }

  final lifecycle = AppLifecycleListener(
    onResume: () {
      unawaited(reconcile());
      refreshOpenHermesChat();
    },
  );
  final timer = Timer(const Duration(seconds: 2), () => unawaited(reconcile()));
  ref.onDispose(() {
    disposed = true;
    timer.cancel();
    lifecycle.dispose();
    ConduitPushFlutterApi.setUp(null);
  });
  // Registration and endpoint upload: after startup, never during first frame.
  return dispatcher;
});
