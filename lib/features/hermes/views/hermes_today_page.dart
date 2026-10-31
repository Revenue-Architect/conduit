import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../kanban/hermes_kanban_page.dart' show showHermesKanbanCard;
import '../sheets/hermes_scheduled_card.dart';
import '../../../core/services/navigation_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../models/hermes_bot.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../sky/hermez_sky.dart';
import '../sky/hermez_weather.dart';
import '../widgets/hermes_home_composer.dart' show startHermesBotConversation;
import '../widgets/hermes_home_inbox.dart';
import '../widgets/hermes_home_lines.dart';
import '../widgets/hermes_home_needs_you.dart';
import '../widgets/hermes_home_presence.dart' show HermesAwayDigest;
import '../widgets/hermes_home_working.dart';
import '../widgets/hermes_session_tile.dart' show openHermesSession;
import '../widgets/hermes_tab_dock.dart';
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';
import '../motion/hermez_card_stack.dart';
import '../motion/hermez_card_route.dart';
import 'hermes_today_copy.dart';
import 'hermes_work_page.dart';

/// Today (docs/app-design-2026-10-30, screens 01, 07, 08): the view from the
/// window, with the team's day written on it. One sentence answers "what
/// happened, and what needs me?"; the team stays visible; asking the team is
/// one tap; the sheet holds what needs the owner, then what is running and
/// what happened.
class HermesTodayPage extends ConsumerStatefulWidget {
  const HermesTodayPage({super.key});

  @override
  ConsumerState<HermesTodayPage> createState() => _HermesTodayPageState();
}

class _HermesTodayPageState extends ConsumerState<HermesTodayPage>
    with WidgetsBindingObserver {
  /// Who "Ask the team" talks to; Chief unless the owner picks another bot.
  String? _recipient;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back is when what waits on the owner has most likely changed,
    // and when the sky may have moved on an hour.
    if (state != AppLifecycleState.resumed) return;
    invalidateHermesNeedsYou(ref);
    ref.invalidate(hermesSessionsProvider);
    ref.invalidate(hermezWeatherProvider);
  }

  Future<void> _refresh() async {
    refreshHermesHome(ref);
    ref.invalidate(hermezWeatherProvider);
    try {
      await ref.read(hermesSessionsProvider.future);
    } catch (_) {
      // The offline line says it; nothing more to wait for.
    }
  }

  HermesBot? _recipientBot(List<HermesBot> bots) {
    if (bots.isEmpty) return null;
    for (final bot in bots) {
      if (bot.name == _recipient) return bot;
    }
    for (final bot in bots) {
      if (bot.name.toLowerCase() == 'chief' ||
          bot.title.toLowerCase() == 'chief') {
        return bot;
      }
    }
    return bots.first;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final now = DateTime.now();
    final weather = ref.watch(hermezWeatherProvider).value;
    final sky = HermezSkyState(
      phase: hermezSkyPhaseAt(
        now,
        sunrise: weather?.sunrise,
        sunset: weather?.sunset,
        dark: dark,
      ),
      weather: weather?.sky ?? HermezSkyWeather.clear,
    );
    final bots = ref.watch(hermesBotsProvider).value ?? const <HermesBot>[];
    final sessions =
        ref.watch(hermesSessionsProvider).value ??
        const <HermesSessionSummary>[];
    final working = watchHermesWorkingAgents(ref);
    final needs = watchHermesNeedsYou(ref).where((i) => i.actionable).length;
    final stale = watchHermesHomeStale(ref);
    final since = hermesTodayDoneSince(now);
    final workingIds = {for (final w in working) w.storedId};
    final done = sessions
        .where(
          (s) =>
              s.updatedAt != null &&
              s.updatedAt!.isAfter(since) &&
              !workingIds.contains(s.id),
        )
        .length;
    final headline = hermesTodayHeadline(
      done: done,
      needs: needs,
      now: now,
      phase: sky.phase,
    );
    final jobs = ref.watch(hermesHomeProfileJobsProvider).value;
    final recipient = _recipientBot(bots);
    final media = MediaQuery.of(context);
    // The sky fills the top of the screen down to Ask the team; the sheet
    // starts right under it.
    final skyHeight = (media.size.height * 0.58).clamp(420.0, 560.0);
    // The sheet rests with "Ask the team" where the sky meets the city, and
    // springs up to cover the sky; the sky and its sentence stay put.
    final screen = media.size.height;
    final askTop = media.padding.top + skyHeight - 70;
    final resting = ((screen - askTop) / screen).clamp(0.3, 0.7);
    // Raised, Ask the team stops just under the status bar.
    final raised = ((screen - media.padding.top - 8) / screen).clamp(
      resting,
      1.0,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Material(
        color: hermezSkyGround(sky.phase),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: skyHeight + media.padding.top,
              child: CustomPaint(painter: HermezSkyPainter(sky)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, media.padding.top + 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopLine(now: now, weather: weather, phase: sky.phase),
                  const SizedBox(height: 30),
                  _Headline(done: headline.done, needs: headline.needs),
                  const SizedBox(height: 22),
                  _TeamStrip(
                    bots: bots,
                    working: working,
                    onOpenBot: (bot) =>
                        startHermesBotConversation(context, ref, bot),
                    onOpenWorking: (agent) => context.pushNamed(
                      RouteNames.hermesLiveRun,
                      pathParameters: {'sessionId': agent.storedId},
                      queryParameters: {'profile': agent.profile},
                    ),
                  ),
                  if (working.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _Caption(
                      agent: working.first,
                      bot: _botNamed(bots, working.first.profile),
                    ),
                  ],
                ],
              ),
            ),
            // A magnetic sheet: it snaps between resting and raised with a
            // spring instead of the whole page scrolling.
            DraggableScrollableSheet(
              initialChildSize: resting,
              minChildSize: resting,
              maxChildSize: raised,
              snap: true,
              snapSizes: [resting, raised],
              snapAnimationDuration: const Duration(milliseconds: 340),
              builder: (context, controller) => RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  controller: controller,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: _AskTheTeam(
                        recipient: recipient,
                        palette: palette,
                        onAsk: recipient == null
                            ? null
                            : () => startHermesBotConversation(
                                context,
                                ref,
                                recipient,
                              ),
                        onChooseRecipient: (chipContext) async {
                          final picked = await _chooseRecipient(
                            chipContext,
                            bots,
                          );
                          if (picked != null && mounted) {
                            setState(() => _recipient = picked.name);
                          }
                        },
                      ),
                    ),
                    _Sheet(
                      palette: palette,
                      clearance: hermesDockClearance(context) + 16,
                      minHeight: screen * raised - 70,
                      children: [
                        HermesHomeOfflineLine(visible: stale),
                        const HermesNeedsYouSection(),
                        if (working.isNotEmpty)
                          _Running(
                            working: working,
                            bots: bots,
                            sessions: sessions,
                            palette: palette,
                          ),
                        const HermesHomeInbox(),
                        HermesHomeLaterToday(
                          routines: hermesRoutinesLaterToday(
                            jobs ?? const [],
                            now,
                          ).length,
                        ),
                        HermesAwayDigest(jobs: jobs),
                        const SizedBox(height: 8),
                        _QuietLinks(palette: palette, routines: jobs?.length),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

HermesBot? _botNamed(List<HermesBot> bots, String name) {
  for (final bot in bots) {
    if (bot.name == name) return bot;
  }
  return null;
}

/// The recipient chip becomes its card (docs/app-design-2026-10-30, m01):
/// the chip's own surface grows into "Send to" and folds back into the chip,
/// which then shows the bot chosen. Choosing never starts a conversation.
Future<HermesBot?> _chooseRecipient(
  BuildContext chipContext,
  List<HermesBot> bots,
) {
  if (bots.isEmpty) return Future.value();
  final palette = HermezChatPalette.forBrightness(
    Theme.of(chipContext).brightness,
  );
  return pushHermezCard<HermesBot>(
    chipContext,
    from: chipContext,
    semanticLabel: 'Send to',
    builder: (panelContext) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: HermezCardStack(
        root: HermezCardView(
          title: 'Send to',
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final bot in bots)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  leading: ClipOval(
                    child: SizedBox.square(
                      dimension: 36,
                      child: HermezBotMark(
                        identity: hermezIdentityForBot(bot),
                        botName: bot.name,
                        size: 36,
                        label: bot.title,
                      ),
                    ),
                  ),
                  title: Text(
                    bot.title,
                    style: _geist(15, FontWeight.w500, palette.ink),
                  ),
                  subtitle: bot.description == null
                      ? null
                      : Text(
                          bot.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _geist(13, FontWeight.w400, palette.muted),
                        ),
                  onTap: () => Navigator.pop(panelContext, bot),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

TextStyle _geist(
  double size,
  FontWeight weight,
  Color color, {
  double? spacing,
  double? height,
}) => TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: spacing,
  height: height,
  fontFeatures: const [FontFeature.tabularFigures()],
);

class _TopLine extends StatelessWidget {
  const _TopLine({
    required this.now,
    required this.weather,
    required this.phase,
  });

  final DateTime now;
  final HermezWeather? weather;
  final HermezSkyPhase phase;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
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

  String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final w = weather;
    String? right;
    if (w != null) {
      final sun = now.isBefore(w.sunrise)
          ? 'sunrise ${_clock(w.sunrise)}'
          : now.isBefore(w.sunset)
          ? 'sunset ${_clock(w.sunset)}'
          : 'dark since ${_clock(w.sunset)}';
      right = '${w.temperatureC.round()}° ${w.words} · $sun';
    }
    final soft = _geist(
      13,
      FontWeight.w500,
      Colors.white.withValues(alpha: 0.86),
    );
    return Row(
      children: [
        Text(
          '${_days[now.weekday - 1]} ${now.day} ${_months[now.month - 1]}',
          style: _geist(13, FontWeight.w600, Colors.white),
        ),
        Text('  Toronto', style: soft),
        if (right != null)
          Expanded(
            child: Text(
              right,
              style: soft,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.done, required this.needs});

  final String done;
  final String needs;

  @override
  Widget build(BuildContext context) {
    final style = _geist(
      40,
      FontWeight.w600,
      Colors.white,
      spacing: -1.8,
      height: 1.04,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$done\n'),
          TextSpan(
            text: needs,
            style: style.copyWith(color: Colors.white.withValues(alpha: 0.62)),
          ),
        ],
      ),
      style: style,
    );
  }
}

/// The six faces, scrolling. A working bot widens into a live tile: what it
/// is doing in words and an amber frame; quiet bots sit dimmed.
class _TeamStrip extends StatelessWidget {
  const _TeamStrip({
    required this.bots,
    required this.working,
    required this.onOpenBot,
    required this.onOpenWorking,
  });

  final List<HermesBot> bots;
  final List<HermesWorkingAgent> working;
  final ValueChanged<HermesBot> onOpenBot;
  final ValueChanged<HermesWorkingAgent> onOpenWorking;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final byProfile = {for (final w in working) w.profile: w};
    final ordered = [
      ...bots.where((b) => byProfile.containsKey(b.name)),
      ...bots.where((b) => !byProfile.containsKey(b.name)),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: ordered.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final bot = ordered[i];
          final agent = byProfile[bot.name];
          final mark = HermezBotMark(
            identity: hermezIdentityForBot(bot),
            botName: bot.name,
            size: agent == null ? 52 : 28,
            label: bot.title,
          );
          if (agent == null) {
            return Semantics(
              button: true,
              label: 'Open ${bot.title}',
              child: GestureDetector(
                onTap: () => onOpenBot(bot),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.18),
                    child: Opacity(
                      opacity: working.isEmpty ? 1 : 0.6,
                      child: SizedBox.square(dimension: 52, child: mark),
                    ),
                  ),
                ),
              ),
            );
          }
          return Semantics(
            button: true,
            label:
                '${bot.title} is working: ${agent.line}. Open the live window',
            child: GestureDetector(
              onTap: () => onOpenWorking(agent),
              child: Container(
                width: 150,
                padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
                decoration: BoxDecoration(
                  color: palette.raised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.live, width: 2),
                ),
                child: Row(
                  children: [
                    ClipOval(
                      child: SizedBox.square(dimension: 28, child: mark),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            agent.line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _geist(12, FontWeight.w600, palette.ink),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: palette.live,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Working',
                                style: _geist(
                                  12,
                                  FontWeight.w600,
                                  palette.liveText,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.agent, required this.bot});

  final HermesWorkingAgent agent;
  final HermesBot? bot;

  @override
  Widget build(BuildContext context) {
    final name = bot?.title ?? agent.profile;
    final line = agent.line.isEmpty
        ? ''
        : agent.line[0].toLowerCase() + agent.line.substring(1);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: name,
            style: _geist(13, FontWeight.w600, Colors.white),
          ),
          TextSpan(
            text: ' is ${line.isEmpty ? 'working' : line}. Tap to watch.',
          ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: _geist(
        13,
        FontWeight.w400,
        Colors.white.withValues(alpha: 0.84),
        height: 1.3,
      ),
    );
  }
}

class _AskTheTeam extends StatelessWidget {
  const _AskTheTeam({
    required this.recipient,
    required this.palette,
    required this.onAsk,
    required this.onChooseRecipient,
  });

  final HermesBot? recipient;
  final HermezChatPalette palette;
  final VoidCallback? onAsk;
  final ValueChanged<BuildContext> onChooseRecipient;

  @override
  Widget build(BuildContext context) {
    final bot = recipient;
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(6, 0, 8, 0),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(999),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: palette.border)
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onAsk,
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 40,
                    child: Icon(Icons.add_rounded, color: palette.muted),
                  ),
                  Text(
                    'Ask the team',
                    style: _geist(16, FontWeight.w400, palette.muted),
                  ),
                ],
              ),
            ),
          ),
          if (bot != null)
            Semantics(
              button: true,
              label: 'Send to ${bot.title}. Change',
              child: Builder(
                builder: (chipContext) => GestureDetector(
                  onTap: () => onChooseRecipient(chipContext),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        ClipOval(
                          child: SizedBox.square(
                            dimension: 24,
                            child: HermezBotMark(
                              identity: hermezIdentityForBot(bot),
                              botName: bot.name,
                              size: 24,
                              label: bot.title,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          bot.title,
                          style: _geist(13, FontWeight.w600, palette.ink),
                        ),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: palette.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: 'Talk to the team',
            child: GestureDetector(
              onTap: onAsk,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.ink,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mic_none_rounded,
                  color: palette.raised,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The working sheet under the sky: raised, rounded on top, rows grouped by
/// space rather than boxes.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.palette,
    required this.clearance,
    required this.minHeight,
    required this.children,
  });

  final HermezChatPalette palette;
  final double clearance;
  final double minHeight;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        // On the evening sky the sheet needs an edge to read as a card.
        border: dark ? Border(top: BorderSide(color: palette.border)) : null,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 8, 20, clearance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Running extends ConsumerWidget {
  const _Running({
    required this.working,
    required this.bots,
    required this.sessions,
    required this.palette,
  });

  final List<HermesWorkingAgent> working;
  final List<HermesBot> bots;
  final List<HermesSessionSummary> sessions;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Running',
            style: _geist(15, FontWeight.w600, palette.ink, spacing: -0.3),
          ),
          const SizedBox(height: 4),
          for (final agent in working)
            InkWell(
              onTap: () {
                final session = sessions.firstWhere(
                  (s) => s.id == agent.storedId,
                  orElse: () => HermesSessionSummary(
                    id: agent.storedId,
                    title: agent.line,
                  ),
                );
                openHermesSession(
                  context,
                  ref,
                  session,
                  bot: _botNamed(bots, agent.profile),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.live, width: 2),
                      ),
                      child: ClipOval(
                        child: SizedBox.square(
                          dimension: 36,
                          child: _botNamed(bots, agent.profile) == null
                              ? ColoredBox(color: palette.surface)
                              : HermezBotMark(
                                  identity: hermezIdentityForBot(
                                    _botNamed(bots, agent.profile)!,
                                  ),
                                  botName: agent.profile,
                                  size: 36,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            agent.line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _geist(
                              15,
                              FontWeight.w600,
                              palette.ink,
                              spacing: -0.2,
                            ),
                          ),
                          Text(
                            _botNamed(bots, agent.profile)?.title ??
                                agent.profile,
                            style: _geist(13, FontWeight.w400, palette.muted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Working',
                      style: _geist(12, FontWeight.w600, palette.liveText),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Quiet links to the places Work used to hold: Scheduled, Kanban, and the
/// rest of the team's tools.
class _QuietLinks extends ConsumerWidget {
  const _QuietLinks({required this.palette, required this.routines});

  final HermezChatPalette palette;
  final int? routines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget link(String label, String? detail, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.border),
          ),
          child: Center(
            widthFactor: 1,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: label,
                    style: _geist(13, FontWeight.w600, palette.ink),
                  ),
                  if (detail != null) TextSpan(text: ' · $detail'),
                ],
              ),
              style: _geist(13, FontWeight.w500, palette.muted),
            ),
          ),
        ),
      ),
    );
    return Wrap(
      children: [
        link(
          'Scheduled',
          routines == null ? null : '$routines',
          // Scheduled is the routines card (m13).
          () => showHermesScheduledCard(context, ref),
        ),
        // Kanban is a card (owner, you-kanban.html k01).
        link('Kanban', null, () => showHermesKanbanCard(context)),
        link(
          'Team and tools',
          null,
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const HermesWorkPage()),
          ),
        ),
      ],
    );
  }
}
