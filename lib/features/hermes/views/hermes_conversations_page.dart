import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../manga/manga_portrait.dart';
import '../manga/manga_prefs.dart';
import '../manga/manga_theme.dart';
import '../manga/manga_widgets.dart';
import '../models/hermes_bot.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../providers/hermes_session_totals_provider.dart';
import '../widgets/hermes_session_tile.dart';
import '../widgets/hermes_tab_dock.dart' show hermesDockClearance;
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
    final manga = !ref.watch(mangaClassicLayoutProvider);
    final all = totals?.values.fold<int>(0, (sum, n) => sum + n);
    return HermesPageChrome(
      title: manga ? 'Chats' : 'Conversations',
      subtitle: manga
          ? (all == null ? '' : '$all chats')
          : 'Every chat, organized by bot.',
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            manga ? 14 : 18,
            0,
            manga ? 14 : 18,
            manga ? 36 + hermesDockClearance(context) : 36,
          ),
          children: [
            if (bots.isNotEmpty) ...[
              manga
                  ? _FaceFilter(
                      bots: bots,
                      selected: bot,
                      onSelected: (name) => setState(() => _bot = name),
                    )
                  : _BotFilter(
                      bots: bots,
                      selected: bot,
                      onSelected: (name) => setState(() => _bot = name),
                    ),
              SizedBox(height: manga ? 4 : 16),
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

/// The manga layout's filter: "All", then each bot's face. A tap narrows
/// the list; the chosen chip fills with ink.
class _FaceFilter extends StatelessWidget {
  const _FaceFilter({
    required this.bots,
    required this.selected,
    required this.onSelected,
  });

  final List<HermesBot> bots;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    Widget chip({
      required bool on,
      required String label,
      required VoidCallback onTap,
      Widget? face,
    }) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: MangaPress(
        semanticLabel: label,
        haptic: true,
        scale: .94,
        onTap: onTap,
        child: AnimatedContainer(
          duration: MangaMotion.swap,
          curve: MangaMotion.easeOut,
          height: 48,
          width: face == null ? null : 44,
          padding: face == null
              ? const EdgeInsets.symmetric(horizontal: 16)
              : EdgeInsets.zero,
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: on ? ink.ink : ink.raised,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: ink.ink, width: ink.border),
          ),
          child:
              face ??
              Text(label, style: MangaType.title(on ? ink.ground : ink.ink)),
        ),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(
            on: selected == null,
            label: 'All',
            onTap: () => onSelected(null),
          ),
          for (final bot in bots)
            chip(
              on: selected == bot.name,
              label: bot.title,
              onTap: () => onSelected(bot.name),
              face: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MangaPortrait(
                  botName: bot.name,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
        ],
      ),
    );
  }
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
    if (mangaLayoutOf(context)) {
      final ink = MangaInk.of(context);
      // The manga group: the bot's face breaks over a thick ink rule, its
      // name in the panel face, then plain rows on the paper.
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: ink.ink, width: ink.border),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (bot != null)
                    SizedBox(
                      width: 56,
                      height: 52,
                      child: OverflowBox(
                        maxHeight: 62,
                        alignment: Alignment.topCenter,
                        child: Transform.translate(
                          offset: const Offset(0, 8),
                          child: MangaPortrait(
                            botName: bot.name,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: title,
                              style: MangaType.panel(ink.ink),
                            ),
                            TextSpan(
                              text: '  $count',
                              style: MangaType.meta(ink.ink3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (more)
                    MangaPress(
                      semanticLabel: 'See all of $title',
                      onTap: onSeeAll,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 0, 6),
                        child: Text('See all', style: MangaType.line(ink.ink)),
                      ),
                    ),
                ],
              ),
            ),
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: ink.rule),
              HermesSessionTile(session: shown[i], compact: true),
            ],
          ],
        ),
      );
    }
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
                  botName: bot.name,
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
