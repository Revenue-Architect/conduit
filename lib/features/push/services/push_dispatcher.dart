import 'dart:async';

import '../../../core/utils/debug_logger.dart';
import '../../notifications/models/app_notification.dart';
import '../models/push_envelope.dart';
import '../platform/conduit_push_api.g.dart';

/// Maps a push category to the notification kind the router gates on.
NotificationKind notificationKindForPush(PushCategory category) =>
    switch (category) {
      PushCategory.approvals => NotificationKind.pushApproval,
      PushCategory.critical || PushCategory.alerts => NotificationKind.pushAlert,
      PushCategory.proactive => NotificationKind.pushProactive,
      PushCategory.briefs => NotificationKind.pushBrief,
      PushCategory.agent => NotificationKind.pushAgent,
      PushCategory.watch => NotificationKind.pushWatch,
      PushCategory.status => NotificationKind.pushStatus,
    };

/// Where a tap on a push banner goes when the envelope names no destination.
String defaultPushRoute(PushCategory category) =>
    category == PushCategory.approvals
    ? '/profile/hermes/approvals'
    : '/profile/hermes/home';

/// Turns a decrypted, foreground envelope into an [AppNotification], or null
/// when it is not something to show (probe, verify, malformed, dismiss).
AppNotification? notificationFromEnvelope(PushEnvelope envelope) {
  if (envelope.type != 'notify') return null;
  final title = envelope.shadow ? '[shadow] ${envelope.title}' : envelope.title;
  return AppNotification(
    kind: notificationKindForPush(envelope.category),
    title: title,
    body: envelope.body,
    sourceId: envelope.route ?? defaultPushRoute(envelope.category),
    dedupKey: 'push:${envelope.dedupKey}',
  );
}

/// Receives pushes the native side forwarded because the app is on screen, and
/// native state changes. It owns no UI: the router decides how to show them.
class PushDispatcher implements ConduitPushFlutterApi {
  PushDispatcher({
    required Future<void> Function(AppNotification) route,
    required void Function() onStatusChange,
    required void Function(PushEnvelope) onApprovalActivity,
  }) : _route = route,
       _onStatusChange = onStatusChange,
       _onApprovalActivity = onApprovalActivity;

  final Future<void> Function(AppNotification) _route;
  final void Function() _onStatusChange;
  final void Function(PushEnvelope) _onApprovalActivity;

  @override
  void onForegroundEnvelope(String json) {
    final envelope = PushEnvelope.tryParse(json);
    if (envelope == null) {
      DebugLogger.warning('unparseable-envelope', scope: 'push/dispatcher');
      return;
    }
    if (envelope.category == PushCategory.approvals) {
      _onApprovalActivity(envelope);
    }
    final notification = notificationFromEnvelope(envelope);
    if (notification == null) return;
    unawaited(_route(notification));
  }

  @override
  void onStatusChanged() => _onStatusChange();

  @override
  void onEndpoint(String url, String pubKey, String authSecret, int generation) =>
      _onStatusChange();

  @override
  void onRegistrationFailed(String reason) {
    DebugLogger.warning(
      'registration-failed',
      scope: 'push/dispatcher',
      data: {'reason': reason},
    );
    _onStatusChange();
  }

  @override
  void onUnregistered() => _onStatusChange();
}
