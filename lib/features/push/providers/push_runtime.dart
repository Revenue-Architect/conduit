import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../../notifications/providers/notification_center.dart';
import '../platform/conduit_push_api.g.dart';
import '../services/push_dispatcher.dart';
import 'push_providers.dart';

/// Connects native push events to the app: foreground pushes go through the
/// shared notification router, native changes refresh the health card and
/// pending approvals, and registration is re-asserted once per app start.
/// Read once from app startup (`ref.read(pushRuntimeProvider)`).
final pushRuntimeProvider = Provider<PushDispatcher>((ref) {
  final dispatcher = PushDispatcher(
    route: (notification) async {
      await ref.read(notificationRouterProvider).route(notification);
    },
    onStatusChange: () {
      unawaited(ref.read(pushStatusProvider.notifier).refreshLocal());
    },
    onApprovalActivity: (_) {
      ref.invalidate(approvalsPendingProvider);
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
  }

  final lifecycle = AppLifecycleListener(
    onResume: () => unawaited(reconcile()),
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
