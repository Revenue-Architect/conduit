import 'package:conduit/core/services/navigation_service.dart';
import 'package:conduit/features/notifications/providers/notification_socket_listener.dart';
import 'package:conduit/features/notifications/services/active_view_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

const _view = ActiveView(
  chatId: 'chat-1',
  hermesSessionId: 'session-1',
  channelId: 'channel-1',
);

void main() {
  test('the chat counts as viewed only while its page is on screen', () {
    final onChat = visibleActiveView(
      _view,
      location: Routes.chat,
      drawerShowing: false,
    );
    expect(onChat.isViewingHermesSession('session-1'), isTrue);
    expect(onChat.isViewingChat('chat-1'), isTrue);
  });

  test('a page pushed over the chat (Kanban) is not viewing the chat', () {
    final onKanban = visibleActiveView(
      _view,
      location: Routes.hermesKanban,
      drawerShowing: false,
    );
    expect(onKanban.isViewingHermesSession('session-1'), isFalse);
    expect(onKanban.isViewingChat('chat-1'), isFalse);
  });

  test('the phone drawer (Hermes Home) over the chat is not viewing it', () {
    final onHome = visibleActiveView(
      _view,
      location: Routes.chat,
      drawerShowing: true,
    );
    expect(onHome.isViewingHermesSession('session-1'), isFalse);
  });

  test('a channel counts only on a channel route', () {
    expect(
      visibleActiveView(
        _view,
        location: '/channel/channel-1',
        drawerShowing: false,
      ).isViewingChannel('channel-1'),
      isTrue,
    );
    expect(
      visibleActiveView(
        _view,
        location: Routes.chat,
        drawerShowing: false,
      ).isViewingChannel('channel-1'),
      isFalse,
    );
  });

  test('before the router is attached, nothing is hidden', () {
    expect(
      visibleActiveView(
        _view,
        location: null,
        drawerShowing: false,
      ).isViewingHermesSession('session-1'),
      isTrue,
    );
  });
}
