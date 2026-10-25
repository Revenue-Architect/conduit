import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/providers/chat_providers.dart' show sendMessageWithContainer;
import '../models/hermes_bot.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart'
    show HermesDesktopApiService;
import '../widgets/hermes_home_composer.dart' show startHermesBotConversation;
import '../widgets/hermes_home_inbox.dart' show hermesChiefProfile;
import 'manga_pick_page.dart';

/// Opens Pick, the character selector, over the app's home: the landing
/// screen of a cold start. Chief is the first fighter. A task given there
/// starts a new conversation with that bot and is sent as its first message;
/// the opener's ref runs the send, because it outlives the Pick route.
Future<void> openMangaPick(
  BuildContext context,
  WidgetRef ref, {
  bool instant = false,
}) async {
  final bots = mangaPickOrder(
    ref.read(hermesBotsProvider).value ?? const <HermesBot>[],
  );
  if (bots.isEmpty) return;
  final chief = bots.indexWhere((b) => b.name == hermesChiefProfile);
  final result = await Navigator.of(context).push(
    MangaPickRoute(
      bots: bots,
      initial: chief < 0 ? 0 : chief,
      origin: null,
      instant: instant,
    ),
  );
  if (result == null || !context.mounted) return;
  await mangaSendTask(context, ref, result.bot, result.text);
}

/// The selector's order: Chief first, then the rest by name. Fixed, so bots
/// do not trade places as they are used (Hermes lists the most recently
/// active first).
List<HermesBot> mangaPickOrder(List<HermesBot> bots) => [...bots]
  ..sort((a, b) {
    if (a.name == hermesChiefProfile) return -1;
    if (b.name == hermesChiefProfile) return 1;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });

/// Starts a new conversation with [bot], opens it, and sends [text] as its
/// first message.
Future<void> mangaSendTask(
  BuildContext context,
  WidgetRef ref,
  HermesBot bot,
  String text,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final id = await startHermesBotConversation(context, ref, bot);
  if (id == null) return;
  // Only into the chat that really opened.
  if (container.read(hermesActiveSessionProvider) != id) return;
  await sendMessageWithContainer(container, text, null);
}

/// A reply cleaned for a speech bubble: no protocol tags, no bracketed
/// notices, no markdown marks, no slash commands, no code. Null when nothing
/// readable is left.
String? mangaSpeech(String? raw) {
  if (raw == null) return null;
  final text = raw
      .replaceAll(RegExp(r'<[^>]{1,80}>'), ' ')
      .replaceAll(RegExp(r'\[[^\]]{0,120}\]'), ' ')
      .replaceAll(RegExp(r'[*_`#>]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // A short reply ("OK", "Done.") is still something the bot said.
  // A system notice cut off before its closing bracket is not speech.
  if (text.isEmpty || text.startsWith('/') || text.startsWith('[')) {
    return null;
  }
  // Code is not speech: an OpenUI tree, a JSON blob, a call.
  if (RegExp(r'[=(){}\[\]]').allMatches(text).length >= 3) return null;
  return text;
}

/// Standing instructions read as orders, not as something a bot said.
bool _instructions(String text) => RegExp(
  r"^(do not|don't|use |you are|run |always |never |follow |check |the receiving)",
  caseSensitive: false,
).hasMatch(text);

/// What [profile] last said to the owner: the newest reply that reads as
/// speech in its most recent chats a person started (scheduled runs talk to
/// no one), else the newest message of its own chat.
final mangaLastWordsProvider = FutureProvider.family<String?, String>((
  ref,
  profile,
) async {
  final bots = ref.watch(hermesBotsProvider).value ?? const <HermesBot>[];
  final bot = bots.where((b) => b.name == profile).firstOrNull;
  final service = ref.watch(hermesApiServiceProvider);
  if (service is HermesDesktopApiService) {
    final sessions = ref.watch(hermesSessionsProvider).value ?? const [];
    final ids = [
      for (final s in sessions)
        if (s.profile == profile && s.source != 'cron') s.id,
      ?bot?.chatSessionId,
    ];
    for (final id in ids.take(3)) {
      try {
        for (final reply in await service.latestAssistantTexts(id)) {
          final text = mangaSpeech(reply);
          if (text != null && !_instructions(text)) return text;
        }
      } catch (_) {
        // One unreadable chat does not stop the next.
      }
    }
  }
  final text = mangaSpeech(bot?.preview);
  return text != null && !_instructions(text) ? text : null;
});

/// The Chats tab: the character selector, always one tap away. Chief comes
/// first; a task given here starts a new conversation with that bot.
class MangaPickTab extends ConsumerWidget {
  const MangaPickTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bots = ref.watch(hermesBotsProvider).value ?? const <HermesBot>[];
    if (bots.isEmpty) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final ordered = mangaPickOrder(bots);
    final chief = ordered.indexWhere((b) => b.name == hermesChiefProfile);
    return MangaPickPage(
      // A new roster starts a fresh pager.
      key: ValueKey(ordered.map((b) => b.name).join(',')),
      bots: ordered,
      initial: chief < 0 ? 0 : chief,
      entrance: kAlwaysCompleteAnimation,
      onSend: (bot, text) => mangaSendTask(context, ref, bot, text),
    );
  }
}
