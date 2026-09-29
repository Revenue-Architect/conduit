import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers/app_providers.dart';
import '../../channels/providers/channel_providers.dart';

part 'active_view_tracker.g.dart';

/// The chat / channel the user is currently looking at.
///
/// Derived from the existing [activeConversationProvider] and
/// [activeChannelProvider], which are set synchronously when their pages load.
/// This is the source of truth for notification foreground-suppression — a
/// `NavigatorObserver` cannot recover these ids (the chat route carries no path
/// parameter), whereas these providers already track them reactively.
class ActiveView {
  const ActiveView({this.chatId, this.channelId, this.hermesSessionId});

  final String? chatId;
  final String? channelId;

  /// The Hermes stored session behind the open chat, if it is a Hermes chat.
  final String? hermesSessionId;

  bool isViewingChat(String id) => chatId != null && chatId == id;

  bool isViewingHermesSession(String id) =>
      hermesSessionId != null && hermesSessionId == id;

  bool isViewingChannel(String id) => channelId != null && channelId == id;
}

@Riverpod(keepAlive: true)
ActiveView activeView(Ref ref) {
  final conversation = ref.watch(activeConversationProvider);
  final channel = ref.watch(activeChannelProvider);
  final hermesSessionId = conversation?.metadata['hermesSessionId'];
  return ActiveView(
    chatId: conversation?.id,
    channelId: channel?.id,
    hermesSessionId: hermesSessionId is String ? hermesSessionId : null,
  );
}
