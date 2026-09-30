import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hermes_bot.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../providers/hermes_session_totals_provider.dart';
import '../widgets/hermes_session_tile.dart';
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermes_page_chrome.dart';

/// Every Hermes conversation, organized by bot.
///
/// A destination of its own, grown out of Home's Recent block: a bot filter,
/// then conversations grouped under each bot. It reuses the session
/// providers and the shared conversation row (which opens a conversation the
/// usual way) and carries none of the side navigation's entries.
class HermesConversationsPage extends ConsumerStatefulWidget {
  const HermesConversationsPage({super.key});

  @override
  ConsumerState<HermesConversationsPage> createState() =>
      _HermesConversationsPageState();
}

class _HermesConversationsPageState
    extends ConsumerState<HermesConversationsPage> {
  /// The bot the list is narrowed to; null for all bots.
  String? _bot;

  Future<void> _refresh() async {
    ref.invalidate(hermesBotsProvider);
    ref.invalidate(hermesSessionsProvider);
    ref.invalidate(hermesSessionTotalsProvider);
    final bot = _bot;
    if (bot != null) ref.invalidate(hermesBotSessionsProvider(bot));
    await ref.read(hermesSessionsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final bots = ref.watch(hermesBotsProvider).asData?.value ?? const [];
    final recent = ref.watch(hermesSessionsProvider);
    final totals = ref.watch(hermesSessionTotalsProvider).asData?.value;
    final bot = _bot;
    return HermesPageChrome(
      title: 'Conversations',
      subtitle: 'Every chat, organized by bot.',
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 36),
          children: [
            if (bots.isNotEmpty) ...[
              _BotFilter(
                bots: bots,
                selected: bot,
                onSelected: (name) => setState(() => _bot = name),
              ),
              const SizedBox(height: 16),
            ],
            if (bot == null)
              ..._allBots(context, palette, bots, recent, totals)
            else
              ..._oneBot(context, palette, bots, bot, totals),
          ],
        ),
      ),
    );
  }

  /// Recent conversations grouped under their bots, bots in recency order.
  List<Widget> _allBots(
    BuildContext context,
    HermezChatPalette palette,
    List<HermesBot> bots,
    AsyncValue<List<HermesSessionSummary>> recent,
    Map<String, int>? totals,
  ) {
    final sessions = recent.asData?.value;
    if (sessions == null) {
      return [
        recent.hasError
            ? _Note('Conversations are unavailable right now.')
            : const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: LinearProgressIndicator(),
              ),
      ];
    }
    if (sessions.isEmpty) return [_Note('No conversations yet.')];
    final groups = <String, List<HermesSessionSummary>>{};
    for (final session in sessions) {
      groups.putIfAbsent(session.profile ?? '', () => []).add(session);
    }
    final order = [
      for (final bot in bots)
        if (groups.containsKey(bot.name)) bot.name,
      for (final profile in groups.keys)
        if (!bots.any((bot) => bot.name == profile)) profile,
    ];
    return [
      for (final profile in order)
        _BotGroup(
          bot: _botNamed(bots, profile),
          profile: profile,
          sessions: groups[profile]!,
          total: totals?[profile],
          onSeeAll: _botNamed(bots, profile) == null
              ? null
              : () => setState(() => _bot = profile),
        ),
    ];
  }

  /// Every conversation of one bot.
  List<Widget> _oneBot(
    BuildContext context,
    HermezChatPalette palette,
    List<HermesBot> bots,
    String profile,
    Map<String, int>? totals,
  ) {
    final scoped = ref.watch(hermesBotSessionsProvider(profile));
    final sessions = scoped.asData?.value;
    if (sessions == null) {
      return [
        scoped.hasError
            ? _Note('This bot\'s conversations are unavailable right now.')
            : const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: LinearProgressIndicator(),
              ),
      ];
    }
    if (sessions.isEmpty) return [_Note('No conversations with this bot yet.')];
    return [
      _BotGroup(
        bot: _botNamed(bots, profile),
        profile: profile,
        sessions: sessions,
        total: totals?[profile] ?? sessions.length,
        limit: null,
      ),
    ];
  }

  static HermesBot? _botNamed(List<HermesBot> bots, String profile) {
    for (final bot in bots) {
      if (bot.name == profile) return bot;
    }
    return null;
  }
}

/// All bots, then each bot, as a single-choice row.
class _BotFilter extends StatelessWidget {
  const _BotFilter({
    required this.bots,
    required this.selected,
    required this.onSelected,
  });

  final List<HermesBot> bots;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _chip('All bots', selected == null, () => onSelected(null)),
        for (final bot in bots)
          _chip(bot.title, selected == bot.name, () => onSelected(bot.name)),
      ],
    ),
  );

  Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: on,
      onSelected: (_) => onTap(),
    ),
  );
}

/// One bot's heading and its conversations.
class _BotGroup extends StatelessWidget {
  const _BotGroup({
    required this.bot,
    required this.profile,
    required this.sessions,
    this.total,
    this.onSeeAll,
    this.limit = 5,
  });

  final HermesBot? bot;
  final String profile;
  final List<HermesSessionSummary> sessions;
  final int? total;

  /// Narrows the list to this bot; null when there is nothing more to show.
  final VoidCallback? onSeeAll;

  /// How many rows to show; null for all.
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final bot = this.bot;
    final title = bot?.title ?? (profile.isEmpty ? 'Other' : profile);
    final shown = limit == null
        ? sessions
        : sessions.take(limit!).toList(growable: false);
    final count = total ?? sessions.length;
    final more = onSeeAll != null && count > shown.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (bot != null) ...[
                HermezBotMark(
                  identity: hermezIdentityForBot(bot),
                  size: 24,
                  label: bot.title,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  '${title.toUpperCase()}  $count',
                  style: HermezType.technical(palette.muted),
                ),
              ),
              if (more)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onSeeAll,
                  child: const Text('See all'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          HermezSurface(
            kind: HermezSurfaceKind.list,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: palette.border.withValues(alpha: 0.7),
                    ),
                  HermesSessionTile(session: shown[i], compact: true),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(
      text,
      style: HermezType.meta(
        HermezChatPalette.forBrightness(Theme.of(context).brightness),
      ),
    ),
  );
}
