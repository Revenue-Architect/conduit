import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../hermes/models/hermes_bot.dart';
import '../../hermes/models/hermes_session.dart';
import '../../hermes/providers/hermes_providers.dart';
import '../../hermes/services/hermes_desktop_api_service.dart';
import '../../hermes/services/hermes_desktop_transport.dart';
import '../../hermes/widgets/hermes_session_tile.dart';
import '../models/spaces_models.dart';
import '../providers/spaces_providers.dart';
import 'hermes_spaces_client.dart';

/// Why "Ask" could not open the Page's conversation.
class PageChatUnavailable implements Exception {
  const PageChatUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Bots in the order the picker offers them: the ones that already have a
/// conversation for this Page (most recent first), then kai, then the rest.
List<HermesBot> orderPageChatBots(
  List<HermesBot> bots,
  List<PageChatBinding> chats,
) {
  final recent = [for (final chat in chats) chat.profile];
  int rank(HermesBot bot) {
    final index = recent.indexOf(bot.name);
    if (index >= 0) return index;
    if (bot.name == spacesDefaultProfile) return recent.length;
    return recent.length + 1;
  }

  final ordered = [...bots];
  ordered.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0
        ? byRank
        : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return ordered;
}

/// Opens the Page's own conversation with [bot], creating and binding one
/// the first time (or when the bound one no longer exists). Each Hermes
/// profile has its own conversation per Page. It is a normal Hermes
/// session; the server tells the agent which Page it belongs to.
Future<void> openPageChat(
  BuildContext context,
  WidgetRef ref, {
  required HermesPage page,
  required HermesBot bot,
}) async {
  final client = ref.read(hermesSpacesClientProvider);
  final service = ref.read(hermesApiServiceProvider);
  if (client == null || service is! HermesDesktopApiService) {
    throw const PageChatUnavailable('Connect to Hermes to ask about a Page.');
  }

  var sessionId = (await client.pageChat(page.id, bot.name))?.sessionId;
  if (sessionId != null && !await _sessionUsable(service, sessionId, bot)) {
    sessionId = null;
  }
  if (sessionId == null) {
    sessionId = await service.createBotConversation(bot);
    try {
      await client.bindPageChat(page.id, bot.name, sessionId);
    } on SpacesApiException catch (error) {
      throw PageChatUnavailable(error.message);
    }
  }
  if (!context.mounted) return;
  await openHermesSession(
    context,
    ref,
    HermesSessionSummary(id: sessionId, title: page.title, profile: bot.name),
    bot: bot,
  );
}

/// Whether a bound conversation can still be opened. A conversation that
/// was created but never sent anything is not kept by Hermes; the gateway
/// refuses it, and a fresh one replaces it. Transport failures are not
/// "gone": those are surfaced instead of silently starting over.
Future<bool> _sessionUsable(
  HermesDesktopApiService service,
  String sessionId,
  HermesBot bot,
) async {
  service.bindSessionProfile(sessionId, bot.name);
  try {
    await service.getSessionMessages(sessionId);
    return true;
  } on HermesDesktopRpcException catch (error) {
    if (error.deliveryAmbiguous) {
      throw const PageChatUnavailable(
        'Could not reach Hermes. Check your connection and retry.',
      );
    }
    return false;
  }
}
