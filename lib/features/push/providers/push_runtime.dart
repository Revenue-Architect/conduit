import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  ref.onDispose(() => ConduitPushFlutterApi.setUp(null));
  // Registration and endpoint upload: after startup, never during first frame.
  unawaited(
    Future<void>.delayed(const Duration(seconds: 2), () {
      return ref.read(pushRegistrationServiceProvider).startup();
    }),
  );
  return dispatcher;
});
