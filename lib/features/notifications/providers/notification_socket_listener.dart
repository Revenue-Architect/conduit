import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/utils/debug_logger.dart';
import '../../channels/providers/channel_providers.dart';
import '../models/app_notification.dart';
import '../services/notification_event_classifier.dart';
import '../services/notification_router.dart';
import 'notification_center.dart';

export 'notification_center.dart'
    show notificationRouterProvider, visibleActiveView;

part 'notification_socket_listener.g.dart';

const _classifier = NotificationEventClassifier();

/// Single global subscriber that turns Open WebUI socket events into
/// notifications. Everything that is not Open WebUI (the router, the local
/// plugin, taps, the in-app banner) lives in [NotificationCenter].
///
/// Mirrors `ActiveChatsSync._bindSocket`: one chat handler + one channel
/// handler, both `requireFocus:false`, re-bound on socket change and on
/// reconnect. The [NotificationRouter] (not this class) owns all gating, so the
/// listener can run unconditionally — when notifications are disabled the router
/// simply drops everything.
@Riverpod(keepAlive: true)
class NotificationSocketListener extends _$NotificationSocketListener {
  SocketEventSubscription? _chatSub;
  SocketEventSubscription? _channelSub;
  StreamSubscription<void>? _reconnectSub;
  SocketService? _boundSocket;

  @override
  void build() {
    ref.onDispose(() {
      _chatSub?.dispose();
      _channelSub?.dispose();
      _reconnectSub?.cancel();
    });

    _bindSocket(ref.read(socketServiceProvider));
    ref.listen<SocketService?>(socketServiceProvider, (_, next) {
      _bindSocket(next);
    });
  }

  void _bindSocket(SocketService? socket) {
    if (identical(socket, _boundSocket)) return;
    _boundSocket = socket;
    _chatSub?.dispose();
    _chatSub = null;
    _channelSub?.dispose();
    _channelSub = null;
    _reconnectSub?.cancel();
    _reconnectSub = null;
    if (socket == null) return;

    // Wildcard handlers (all selectors null) so we see every chat/channel event.
    _chatSub = socket.addChatEventHandler(
      requireFocus: false,
      handler: (event, _) => _onChatEvent(event),
    );
    _channelSub = socket.addChannelEventHandler(
      requireFocus: false,
      handler: (event, _) => _onChannelEvent(event),
    );

    // Unread counts can drift while disconnected; reconcile from the server.
    _reconnectSub = socket.onReconnect.listen((_) {
      unawaited(ref.read(channelsListProvider.notifier).refresh());
      // Socket.IO does not replay channel history. Drop every keepAlive family
      // instance so an open thread and a channel reopened later both fetch an
      // authoritative page instead of retaining the pre-disconnect snapshot.
      ref.invalidate(channelMessagesProvider);
      ref.invalidate(threadMessagesProvider);
    });
  }

  String get _currentUserId => ref.read(currentUserProvider).value?.id ?? '';

  void _onChatEvent(Map<String, dynamic> event) {
    final notification = _classifier.classifyChatEvent(
      event,
      currentUserId: _currentUserId,
    );
    if (notification != null) _route(notification);
  }

  void _onChannelEvent(Map<String, dynamic> event) {
    final userId = _currentUserId;
    // Until the current user resolves we can't run the self-author filter, so
    // skip rather than risk notifying the user for their own messages.
    if (userId.isEmpty) return;
    final notification = _classifier.classifyChannelEvent(
      event,
      currentUserId: userId,
    );
    if (notification != null) _route(notification);
  }

  void _route(AppNotification notification) {
    unawaited(
      ref.read(notificationRouterProvider).route(notification).catchError((
        Object e,
        StackTrace st,
      ) {
        DebugLogger.error(
          'notification routing failed',
          error: e,
          stackTrace: st,
          scope: 'notifications/center',
        );
        return NotificationSurface.suppressed;
      }),
    );
  }
}
