import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/conversation.dart';
import '../../../core/providers/app_providers.dart' show conversationsProvider;
import '../../../core/services/navigation_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../navigation/providers/conversation_selection_provider.dart';
import '../models/hermes_bot.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../providers/hermes_unread_providers.dart';
import '../widgets/hermes_home_composer.dart' show startHermesBotConversation;
import '../widgets/hermes_home_working.dart';
import '../widgets/hermes_tab_dock.dart';
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';
import 'hermes_home_page.dart' show chooseHermesNewChat;

/// Chats (docs/app-design-2026-10-30, screen 05): one list of every
/// conversation, the team first with the working bot visible, then Open
/// WebUI and direct chats. Search covers both.
class HermesChatsPage extends ConsumerStatefulWidget {
  const HermesChatsPage({super.key});

  @override
  ConsumerState<HermesChatsPage> createState() => _HermesChatsPageState();
}

/// Rows a search query keeps: a bot row matches its name, title or last
/// message; a conversation matches its title or model.
bool hermesChatsMatches(String query, Iterable<String?> fields) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return fields.any((f) => f != null && f.toLowerCase().contains(q));
}

TextStyle _geist(double size, FontWeight weight, Color color) => TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
  fontFeatures: const [FontFeature.tabularFigures()],
);

String _when(DateTime? at, DateTime now) {
  if (at == null) return '';
  final local = at.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) {
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '$h:${local.minute.toString().padLeft(2, '0')}';
  }
  final age = today.difference(day).inDays;
  if (age < 7) {
    return const [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ][local.weekday - 1];
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${local.day} ${months[local.month - 1]}';
}

class _HermesChatsPageState extends ConsumerState<HermesChatsPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final now = DateTime.now();
    final query = _search.text;
    final bots = ref.watch(hermesBotsProvider).value ?? const <HermesBot>[];
    final sessions =
        ref.watch(hermesSessionsProvider).value ??
        const <HermesSessionSummary>[];
    final unreadIds = ref.watch(hermesUnreadSessionIdsProvider);
    final working = {
      for (final w in watchHermesWorkingAgents(ref)) w.profile: w,
    };
    final conversations =
        ref.watch(conversationsProvider).value ?? const <Conversation>[];

    // The latest session and unread count per bot.
    final latest = <String, HermesSessionSummary>{};
    final unread = <String, int>{};
    for (final s in sessions) {
      final p = s.profile;
      if (p == null) continue;
      final seen = latest[p];
      if (seen == null ||
          (s.updatedAt ?? DateTime(0)).isAfter(seen.updatedAt ?? DateTime(0))) {
        latest[p] = s;
      }
      if (unreadIds.contains(s.id)) unread[p] = (unread[p] ?? 0) + 1;
    }
    final team = [...bots]
      ..sort((a, b) {
        final ua = unread[a.name] ?? 0, ub = unread[b.name] ?? 0;
        if ((ua > 0) != (ub > 0)) return ua > 0 ? -1 : 1;
        final ta = latest[a.name]?.updatedAt ?? DateTime(0);
        final tb = latest[b.name]?.updatedAt ?? DateTime(0);
        return tb.compareTo(ta);
      });
    final teamShown = team
        .where(
          (b) => hermesChatsMatches(query, [
            b.name,
            b.title,
            latest[b.name]?.preview,
            latest[b.name]?.title,
          ]),
        )
        .toList();
    final others = conversations
        .where((c) => hermesChatsMatches(query, [c.title, c.model]))
        .take(30)
        .toList();
    final totalUnread = unread.values.fold<int>(0, (a, b) => a + b);
    final top = MediaQuery.of(context).padding.top;

    return Material(
      color: palette.canvas,
      child: ListView(
        padding: EdgeInsets.only(bottom: hermesDockClearance(context) + 24),
        children: [
          _Band(
            top: top,
            title: 'Chats',
            subtitle:
                '${bots.length} bots${totalUnread > 0 ? ' · $totalUnread unread' : ''}',
            onNewChat: () => chooseHermesNewChat(context, ref),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: _geist(15, FontWeight.w400, palette.ink),
              decoration: InputDecoration(
                hintText: 'Search chats',
                hintStyle: _geist(15, FontWeight.w400, palette.faint),
                prefixIcon: Icon(Icons.search_rounded, color: palette.muted),
                filled: true,
                fillColor: palette.raised,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: palette.border),
                ),
              ),
            ),
          ),
          if (teamShown.isNotEmpty) _Heading('Your team', palette),
          for (final bot in teamShown)
            _Row(
              palette: palette,
              leading: _Face(
                bot: bot,
                live: working.containsKey(bot.name),
                palette: palette,
              ),
              title: bot.title,
              subtitle:
                  working[bot.name]?.line ??
                  latest[bot.name]?.preview ??
                  latest[bot.name]?.title ??
                  bot.description ??
                  '',
              unread: unread[bot.name] ?? 0,
              trailing: working.containsKey(bot.name)
                  ? 'Working'
                  : _when(latest[bot.name]?.updatedAt, now),
              live: working.containsKey(bot.name),
              onTap: () => startHermesBotConversation(context, ref, bot),
            ),
          if (others.isNotEmpty) _Heading('Open WebUI and direct', palette),
          for (final c in others)
            _Row(
              palette: palette,
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: palette.surface,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: ClipOval(
                  child: Image.asset(
                    'assets/icons/open_webui.png',
                    width: 24,
                    height: 24,
                  ),
                ),
              ),
              title: c.title,
              subtitle: c.model ?? 'Open WebUI',
              unread: 0,
              trailing: _when(c.updatedAt, now),
              live: false,
              onTap: () async {
                final result = await ref
                    .read(conversationSelectionProvider.notifier)
                    .select(c);
                if (result.disposition ==
                    ConversationSelectionDisposition.committed) {
                  NavigationService.router.go(Routes.chat);
                }
              },
            ),
          if (teamShown.isEmpty && others.isEmpty && query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
              child: Text(
                'No chats match "$query".',
                style: _geist(15, FontWeight.w400, palette.muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// The page's sky band: the dawn gradient and the skyline's base, with the
/// title, the count and the new-chat pencil.
class _Band extends StatelessWidget {
  const _Band({
    required this.top,
    required this.title,
    required this.subtitle,
    required this.onNewChat,
  });

  final double top;
  final String title;
  final String subtitle;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 14, 8, 34),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D2141), Color(0xFF2C4F80), Color(0xFF7E9DC2)],
        ),
        border: Border(bottom: BorderSide(color: palette.canvas, width: 0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _geist(
                    30,
                    FontWeight.w600,
                    Colors.white,
                  ).copyWith(letterSpacing: -1.2),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: _geist(
                    15,
                    FontWeight.w400,
                    Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: onNewChat,
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, this.palette);

  final String text;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
    child: Text(
      text,
      style: _geist(
        15,
        FontWeight.w600,
        palette.ink,
      ).copyWith(letterSpacing: -0.3),
    ),
  );
}

class _Face extends StatelessWidget {
  const _Face({required this.bot, required this.live, required this.palette});

  final HermesBot bot;
  final bool live;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) {
    final mark = ClipOval(
      child: SizedBox.square(
        dimension: 42,
        child: HermezBotMark(
          identity: hermezIdentityForBot(bot),
          botName: bot.name,
          size: 42,
          label: bot.title,
        ),
      ),
    );
    if (!live) return mark;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.live, width: 2),
      ),
      child: SizedBox.square(dimension: 38, child: mark),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.palette,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.unread,
    required this.trailing,
    required this.live,
    required this.onTap,
  });

  final HermezChatPalette palette;
  final Widget leading;
  final String title;
  final String subtitle;
  final int unread;
  final String trailing;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bold = unread > 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Align(alignment: Alignment.centerLeft, child: leading),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _geist(
                      15,
                      bold ? FontWeight.w600 : FontWeight.w500,
                      palette.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _geist(13, FontWeight.w400, palette.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  trailing,
                  style: _geist(
                    12,
                    live || bold ? FontWeight.w600 : FontWeight.w500,
                    live
                        ? palette.liveText
                        : (bold ? palette.ink : palette.faint),
                  ),
                ),
                const SizedBox(height: 6),
                if (unread > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: palette.ink,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$unread',
                      style: _geist(11, FontWeight.w700, palette.raised),
                    ),
                  )
                else
                  const SizedBox(height: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
