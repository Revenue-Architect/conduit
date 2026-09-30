import 'dart:async';

import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/local_conversation_loader.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/current_localizations.dart';
import '../../../core/utils/debug_logger.dart';
import '../../channels/providers/channel_providers.dart';
import '../../chat/providers/chat_providers.dart';
import '../../hermes/services/hermes_identifier.dart';
import '../../navigation/widgets/responsive_drawer_layout.dart';
import '../models/app_notification.dart';
import '../services/active_view_tracker.dart';
import '../services/local_notification_service.dart';
import '../services/notification_router.dart';
import '../services/notification_sound_service.dart';
import '../views/in_app_banner.dart';

part 'notification_center.g.dart';

/// Builds the [NotificationRouter], wiring it to live app state. keepAlive so
/// its dedup memory persists across socket re-binds.
@Riverpod(keepAlive: true)
NotificationRouter notificationRouter(Ref ref) {
  return NotificationRouter(
    readSettings: () => ref.read(appSettingsProvider),
    readActiveView: () => visibleActiveView(
      ref.read(activeViewProvider),
      location: NavigationService.currentRoute,
      drawerShowing: ResponsiveDrawerLayoutState.mobileDrawerShowing.value,
    ),
    isAppForeground: _isAppForeground,
    localNotifications: ref.read(localNotificationServiceProvider),
    sound: ref.read(notificationSoundServiceProvider),
    showInAppBanner: (n) => _showInAppBanner(ref, n),
    onChannelUnread: (n) => _bumpChannelUnread(ref, n),
  );
}

/// The conversation the user is actually looking at. The active chat stays
/// set while other pages (Kanban, Settings) are pushed over it or the phone
/// drawer (Hermes Home) covers it; a run finishing there must still raise a
/// banner, so the chat only counts while its page is the one on screen.
@visibleForTesting
ActiveView visibleActiveView(
  ActiveView view, {
  required String? location,
  required bool drawerShowing,
}) {
  final path = location == null ? null : Uri.tryParse(location)?.path;
  final onChat = path == null || path == Routes.chat;
  final onChannel = path == null || path.startsWith('/channel');
  return ActiveView(
    chatId: onChat && !drawerShowing ? view.chatId : null,
    hermesSessionId: onChat && !drawerShowing ? view.hermesSessionId : null,
    channelId: onChannel && !drawerShowing ? view.channelId : null,
  );
}

bool _isAppForeground() {
  final state = WidgetsBinding.instance.lifecycleState;
  // Null very early in startup — treat as foreground so banners work.
  return state == null || state == AppLifecycleState.resumed;
}

void _showInAppBanner(Ref ref, AppNotification notification) {
  final context = NavigationService.navigatorKey.currentContext;
  if (context == null) return;
  // Hermes runs finish while the user is on any page (Kanban, Home, a bot):
  // draw above all of them instead of on whichever Scaffold a snackbar
  // reaches.
  final overlay = NavigationService.navigatorKey.currentState?.overlay;
  if (overlay != null &&
      (notification.kind == NotificationKind.hermesRun ||
          notification.kind == NotificationKind.hermesAttention)) {
    HermezInAppBanner.show(
      overlay,
      title: notification.title,
      body: notification.body,
      onOpen: () => unawaited(
        _handleTap(
          ref,
          NotificationTap(
            kind: notification.kind,
            sourceId: notification.sourceId,
          ),
        ),
      ),
    );
    return;
  }
  final l10n = currentAppLocalizations();
  final message = notification.title.isNotEmpty
      ? '${notification.title}: ${notification.body}'
      : notification.body;
  AdaptiveSnackBar.show(
    context,
    message: message,
    type: AdaptiveSnackBarType.info,
    action: l10n.notificationViewAction,
    onActionPressed: () => _handleTap(
      ref,
      NotificationTap(kind: notification.kind, sourceId: notification.sourceId),
    ),
  );
}

void _bumpChannelUnread(Ref ref, AppNotification notification) {
  final list = ref.read(channelsListProvider).value;
  if (list == null) return;
  for (final channel in list) {
    if (channel.id == notification.sourceId) {
      ref
          .read(channelsListProvider.notifier)
          .updateChannel(
            channel.copyWith(unreadCount: channel.unreadCount + 1),
          );
      return;
    }
  }
}

Future<void> _handleTap(Ref ref, NotificationTap tap) async {
  // Fire-and-forget from tap streams / cold launch — never let a navigation
  // failure surface as an uncaught async error.
  try {
    switch (tap.kind) {
      // A bot waiting on the user opens its live page, where the request is
      // reviewed. A finished run goes on to its conversation, to read the
      // answer; the live page shows while the transcript loads.
      case NotificationKind.hermesAttention:
      case NotificationKind.hermesRun:
        final sessionId = validateHermesOpaqueIdentifier(tap.sourceId);
        if (sessionId == null) return;
        await NavigationService.router.pushNamed<void>(
          RouteNames.hermesLiveRun,
          pathParameters: {'sessionId': sessionId},
          queryParameters: tap.kind == NotificationKind.hermesRun
              ? const {'open': 'chat'}
              : const <String, String>{},
        );
      case NotificationKind.channelMessage:
        NavigationService.navigateToChannel(tap.sourceId);
      case NotificationKind.chatCompletion:
        final ownership = captureOpenWebUiConversationRead(ref);
        if (ownership == null) return;
        final outgoing = ref.read(activeConversationProvider);
        if (outgoing == null ||
            !conversationMatchesScopedId(outgoing, tap.sourceId)) {
          clearSelectedFiltersForConversationBoundary(ref);
        }
        // DB-first open, mirroring the conversation-list selection flow.
        await NavigationService.navigateToChat();
        if (!openWebUiConversationReadIsCurrent(ref, ownership)) return;
        final local = await loadLocalConversation(
          ref,
          tap.sourceId,
          ownership: ownership,
        );
        if (!openWebUiConversationReadIsCurrent(ref, ownership)) return;
        if (local != null) {
          ref.read(activeConversationProvider.notifier).set(local);
        }
        schedulePullChatNow(ref, tap.sourceId, ownership: ownership);
    }
  } catch (e, st) {
    DebugLogger.error(
      'notification deep-link failed',
      error: e,
      stackTrace: st,
      scope: 'notifications/center',
    );
  }
}

/// The app's notification plumbing that does not depend on any backend:
/// the local plugin, taps on system notifications (foreground and cold
/// launch) and their deep links. Hermes runs and Open WebUI events both
/// route through [notificationRouterProvider]; neither owns this.
@Riverpod(keepAlive: true)
class NotificationCenter extends _$NotificationCenter {
  StreamSubscription<NotificationTap>? _tapSub;
  bool _launchHandled = false;

  @override
  void build() {
    ref.onDispose(() => _tapSub?.cancel());
    final local = ref.read(localNotificationServiceProvider);
    // Initialize the plugin (channel + tap handler) without requesting
    // permission — permission is requested on master-toggle opt-in.
    unawaited(local.initialize());
    // System-notification taps (foreground) route to the target.
    _tapSub = local.taps.listen((tap) => unawaited(_handleTap(ref, tap)));
  }

  /// Handles a notification that cold-launched the app from a killed state.
  /// Called once after the router is ready.
  Future<void> handleLaunchTap() async {
    // Both the app shell and the Open WebUI post-sign-in startup call this;
    // the launch intent is opened once.
    if (_launchHandled) return;
    _launchHandled = true;
    final local = ref.read(localNotificationServiceProvider);
    // Ensure the plugin finished native init before querying the launch intent:
    // on Android getNotificationAppLaunchDetails() returns null until then, so
    // racing it would silently drop the deep link. initialize() is idempotent
    // and shares the in-flight future started in build().
    await local.initialize();
    final tap = await local.launchTap();
    if (tap != null) {
      await _handleTap(ref, tap);
    }
  }
}
