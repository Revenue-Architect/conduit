import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../../chat/providers/chat_providers.dart' show sendMessageWithContainer;
import '../models/hermes_bot.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart' show HermesLiveSession;
import '../sheets/hermes_active_work_sheet.dart' show hermesSummaryForSession;
import '../widgets/hermes_home_composer.dart' show startHermesBotConversation;
import '../widgets/hermes_home_inbox.dart' show hermesChiefProfile;
import '../widgets/hermes_home_needs_you.dart';
import '../widgets/hermes_home_working.dart';
import '../widgets/hermes_session_tile.dart' show openHermesSession;
import '../widgets/hermes_tab_dock.dart' show hermesDockClearance;
import 'manga_pick_page.dart';
import 'manga_portrait.dart';
import 'manga_prefs.dart';
import 'manga_theme.dart';
import 'manga_widgets.dart';

/// Starts a new conversation with [bot], opens it, and sends [text] as its
/// first message. Runs on Today's ref, which outlives the Pick route.
Future<void> mangaSendTask(
  BuildContext context,
  WidgetRef ref,
  HermesBot bot,
  String text,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  ref.read(mangaLastBotProvider.notifier).set(bot.name);
  final id = await startHermesBotConversation(context, ref, bot);
  if (id == null) return;
  // Only into the chat that really opened.
  if (container.read(hermesActiveSessionProvider) != id) return;
  await sendMessageWithContainer(container, text, null);
}

/// A preview cleaned for a speech bubble: no protocol tags, no bracketed
/// notices, no slash commands. Null when nothing readable is left.
String? mangaSpeech(String? raw) {
  if (raw == null) return null;
  final text = raw
      .replaceAll(RegExp(r'<[^>]{1,80}>'), ' ')
      .replaceAll(RegExp(r'\[[^\]]{0,120}\]'), ' ')
      .replaceAll(RegExp(r'[*_`#>]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isEmpty || text.startsWith('/') || text.length < 3) return null;
  return text;
}

/// The bots in page order: working ones first, in Hermes' order, then by
/// last activity.
List<HermesBot> mangaPageOrder(
  List<HermesBot> bots,
  List<HermesWorkingAgent> working,
) {
  final rank = {for (var i = 0; i < working.length; i++) working[i].profile: i};
  final ordered = [...bots]
    ..sort((a, b) {
      final wa = rank[a.name], wb = rank[b.name];
      if (wa != null || wb != null) {
        if (wa == null) return 1;
        if (wb == null) return -1;
        return wa.compareTo(wb);
      }
      final la = a.lastActive, lb = b.lastActive;
      if (la == null && lb == null) return 0;
      if (la == null) return 1;
      if (lb == null) return -1;
      return lb.compareTo(la);
    });
  return ordered;
}

/// Today: the team's day as a manga page. The bot doing the most is the big
/// panel, two more report beside it, what needs you sits above the roster,
/// and the task box at the bottom sends to the last bot picked.
class MangaTodayPage extends ConsumerStatefulWidget {
  const MangaTodayPage({super.key});

  @override
  ConsumerState<MangaTodayPage> createState() => _MangaTodayPageState();
}

class _MangaTodayPageState extends ConsumerState<MangaTodayPage>
    with WidgetsBindingObserver {
  final _task = TextEditingController();
  final _focus = FocusNode();
  final _tileKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _task.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _task.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    invalidateHermesNeedsYou(ref);
    ref.invalidate(hermesSessionsProvider);
    ref.invalidate(hermesBotsProvider);
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(hermesBotsProvider)
      ..invalidate(hermesSessionsProvider);
    invalidateHermesNeedsYou(ref);
    try {
      await ref.read(hermesBotsProvider.future);
    } catch (_) {}
  }

  HermesBot? _taskBot(List<HermesBot> bots) {
    final last = ref.watch(mangaLastBotProvider);
    return bots.where((b) => b.name == last).firstOrNull ??
        bots.where((b) => b.name == hermesChiefProfile).firstOrNull ??
        bots.firstOrNull;
  }

  Future<void> _openPick(List<HermesBot> bots, HermesBot bot) async {
    final key = _tileKeys[bot.name];
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    _focus.unfocus();
    final result = await Navigator.of(context).push(
      MangaPickRoute(
        bots: bots,
        initial: bots.indexOf(bot),
        origin: origin,
        working: {
          for (final agent in watchWorkingSnapshot()) agent.profile: agent,
        },
      ),
    );
    if (!mounted || result == null) return;
    await mangaSendTask(context, ref, result.bot, result.text);
  }

  List<HermesWorkingAgent> watchWorkingSnapshot() =>
      // Read, not watched: the route takes a snapshot when it opens.
      _lastWorking;
  List<HermesWorkingAgent> _lastWorking = const [];

  Future<void> _send(HermesBot bot) async {
    final text = _task.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.mediumImpact();
    _task.clear();
    _focus.unfocus();
    await mangaSendTask(context, ref, bot, text);
  }

  void _openBot(
    HermesBot bot,
    HermesWorkingAgent? agent,
    List<HermesBot> bots,
  ) {
    final id = agent?.storedId ?? bot.chatSessionId;
    if (id == null) {
      _openPick(bots, bot);
      return;
    }
    openHermesSession(
      context,
      ref,
      hermesSummaryForSession(ref, id, bot.title),
      bot: bot,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    final bots = ref.watch(hermesBotsProvider).value;
    final working = watchHermesWorkingAgents(ref);
    _lastWorking = working;
    final live =
        ref.watch(hermesActiveWorkProvider).value ??
        const <HermesLiveSession>[];
    final sessions =
        ref.watch(hermesSessionsProvider).value ??
        const <HermesSessionSummary>[];
    final needs = watchHermesNeedsYou(ref);
    final now = DateTime.now();
    final runsToday = sessions.where((s) {
      final at = s.updatedAt?.toLocal();
      return at != null &&
          at.year == now.year &&
          at.month == now.month &&
          at.day == now.day;
    }).length;
    final byProfile = {for (final a in working) a.profile: a};
    final order = bots == null
        ? const <HermesBot>[]
        : mangaPageOrder(bots, working);
    final taskBot = bots == null ? null : _taskBot(bots);
    final clearance = hermesDockClearance(context);

    String? said(HermesBot bot) {
      final agent = byProfile[bot.name];
      if (agent != null) return agent.line;
      final latest = sessions
          .where((s) => s.profile == bot.name && (s.preview ?? '').isNotEmpty)
          .firstOrNull;
      for (final candidate in [latest?.preview, bot.preview, bot.description]) {
        final text = mangaSpeech(candidate);
        if (text != null) return text;
      }
      return null;
    }

    String? caption(HermesBot bot) {
      final agent = byProfile[bot.name];
      if (agent != null) {
        for (final session in live) {
          if (session.storedId == agent.storedId) return session.title;
        }
        return null;
      }
      final last = bot.lastActive;
      return last == null ? null : 'last ${mangaWhen(last, now: now)}';
    }

    Widget panelFor(HermesBot bot, {required bool hero}) {
      final agent = byProfile[bot.name];
      return MangaPress(
        semanticLabel: '${bot.title}. ${said(bot) ?? ''}',
        onTap: () => _openBot(bot, agent, bots!),
        scale: .985,
        child: hero
            ? _HeroPanel(
                bot: bot,
                working: agent != null,
                said: said(bot),
                caption: caption(bot),
              )
            : _SmallPanel(
                bot: bot,
                working: agent != null,
                said: said(bot),
                caption: caption(bot),
              ),
      );
    }

    return Material(
      color: ink.ground,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('Today', style: MangaType.display(ink.ink)),
                    ),
                  ),
                  Text(
                    '${_dateLine(now)}\n'
                    '$runsToday ${runsToday == 1 ? 'run' : 'runs'}',
                    textAlign: TextAlign.right,
                    style: MangaType.meta(ink.ink2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: ink.ink,
                child: LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: box.maxHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: order.isEmpty
                            ? _PageSkeleton(ink: ink)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: panelFor(order[0], hero: true),
                                  ),
                                  if (order.length > 1) ...[
                                    const SizedBox(height: 6),
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: panelFor(
                                              order[1],
                                              hero: false,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: order.length > 2
                                                ? panelFor(
                                                    order[2],
                                                    hero: false,
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(14, 24, 14, clearance + 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NeedsBand(items: needs),
                  if (bots != null && bots.isNotEmpty) ...[
                    _Roster(
                      bots: bots,
                      selected: taskBot?.name,
                      working: byProfile.keys.toSet(),
                      keyFor: (name) =>
                          _tileKeys.putIfAbsent(name, GlobalKey.new),
                      onTap: (bot) => _openPick(bots, bot),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (taskBot != null)
                    _TaskBox(
                      bot: taskBot,
                      controller: _task,
                      focus: _focus,
                      onAvatar: () => _openPick(bots!, taskBot),
                      onSend: () => _send(taskBot),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dateLine(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.bot,
    required this.working,
    required this.said,
    required this.caption,
  });

  final HermesBot bot;
  final bool working;
  final String? said;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    return MangaPanel(
      working: working,
      rayCentre: const Alignment(.5, .25),
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Positioned(
              right: 4,
              bottom: 0,
              width: box.maxWidth * .54,
              height: box.maxHeight * .9,
              child: MangaPortrait(botName: bot.name),
            ),
            if (said != null)
              Positioned(
                left: 12,
                top: 14,
                width: box.maxWidth * .56,
                child: MangaBubble(
                  child: Text(
                    said!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: MangaType.speech(ink.ink),
                  ),
                ),
              ),
            if (working)
              const Positioned(
                right: 10,
                top: 10,
                child: MangaStamp('On it', tilt: 4),
              ),
            Positioned(
              left: 14,
              bottom: 14,
              right: box.maxWidth * .4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    bot.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MangaType.hero(ink.ink),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MangaType.meta(ink.ink2),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallPanel extends StatelessWidget {
  const _SmallPanel({
    required this.bot,
    required this.working,
    required this.said,
    required this.caption,
  });

  final HermesBot bot;
  final bool working;
  final String? said;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    return MangaPanel(
      working: working,
      rayCentre: const Alignment(.7, .7),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            bottom: -6,
            width: 100,
            height: 104,
            child: MangaPortrait(botName: bot.name),
          ),
          Positioned(
            left: 10,
            top: 9,
            right: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bot.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MangaType.panel(ink.ink),
                ),
                const SizedBox(height: 4),
                if (said != null)
                  Text(
                    said!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: MangaType.line(ink.ink),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 10,
            bottom: 9,
            child: working
                ? const MangaStamp('On it')
                : Text(caption ?? '', style: MangaType.meta(ink.ink2)),
          ),
        ],
      ),
    );
  }
}

class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton({required this.ink});

  final MangaInk ink;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        flex: 3,
        child: MangaPanel(color: ink.raised, child: const SizedBox()),
      ),
      const SizedBox(height: 6),
      Expanded(
        flex: 2,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: MangaPanel(color: ink.raised, child: const SizedBox()),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: MangaPanel(color: ink.raised, child: const SizedBox()),
            ),
          ],
        ),
      ),
    ],
  );
}

/// What needs the owner: one black band, the count in orange, the first
/// item and how many more. Absent when nothing waits.
class _NeedsBand extends StatelessWidget {
  const _NeedsBand({required this.items});

  final List<HermesNeedsYouItem> items;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final first = items.firstOrNull;
    return AnimatedSize(
      duration: MangaMotion.enter,
      curve: MangaMotion.easeOut,
      alignment: Alignment.topCenter,
      child: first == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MangaPress(
                semanticLabel:
                    '${items.length} need you. ${first.title}. Open Needs you',
                onTap: () => context.pushNamed(RouteNames.hermesAttention),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ink.ink,
                    border: Border.all(color: ink.ink, width: ink.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                    child: Row(
                      children: [
                        Text(
                          '${items.length}',
                          style: MangaType.display(
                            // On the bone band of dark mode the light orange
                            // is too pale; the deeper one reads.
                            dark ? MangaInk.light.accentText : ink.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                first.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MangaType.title(ink.ground),
                              ),
                              Text(
                                items.length > 1
                                    ? '+${items.length - 1} more · ${first.source}'
                                    : first.source,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MangaType.meta(
                                  ink.ground.withValues(alpha: .8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: ink.ground),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// The six faces: who gets the task. A tap opens Pick from that tile.
class _Roster extends StatelessWidget {
  const _Roster({
    required this.bots,
    required this.selected,
    required this.working,
    required this.keyFor,
    required this.onTap,
  });

  final List<HermesBot> bots;
  final String? selected;
  final Set<String> working;
  final GlobalKey Function(String name) keyFor;
  final ValueChanged<HermesBot> onTap;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    final shown = bots.take(6).toList();
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: MangaPress(
                key: keyFor(shown[i].name),
                semanticLabel: 'Pick ${shown[i].title}',
                haptic: true,
                scale: .94,
                onTap: () => onTap(shown[i]),
                child: AnimatedContainer(
                  duration: MangaMotion.swap,
                  curve: MangaMotion.easeOut,
                  decoration: BoxDecoration(
                    color: shown[i].name == selected ? ink.ink : ink.raised,
                    border: Border.all(color: ink.ink, width: ink.border),
                  ),
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned(
                          left: -4,
                          right: -4,
                          top: 4,
                          bottom: -6,
                          child: MangaPortrait(
                            botName: shown[i].name,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                        if (working.contains(shown[i].name))
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: ink.accent,
                                shape: BoxShape.circle,
                                border: Border.all(color: ink.ground, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The fast path: type and send to the last bot picked, no extra screen.
/// The send button is ink at rest and turns orange once there is a task.
class _TaskBox extends StatelessWidget {
  const _TaskBox({
    required this.bot,
    required this.controller,
    required this.focus,
    required this.onAvatar,
    required this.onSend,
  });

  final HermesBot bot;
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onAvatar;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    final armed = controller.text.trim().isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ink.ground,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: ink.ink, width: ink.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
        child: Row(
          children: [
            MangaPress(
              semanticLabel: 'Choose who gets the task',
              onTap: onAvatar,
              scale: .92,
              child: Container(
                width: 40,
                height: 40,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: ink.raised,
                  shape: BoxShape.circle,
                ),
                // The face swaps with a short cross-fade when the bot does.
                child: AnimatedSwitcher(
                  duration: MangaMotion.swap,
                  switchInCurve: MangaMotion.easeOut,
                  child: MangaPortrait(
                    key: ValueKey(bot.name),
                    botName: bot.name,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: MangaType.body(ink.ink),
                cursorColor: ink.ink,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Tell ${bot.title} what to do',
                  hintStyle: MangaType.body(ink.ink3),
                ),
              ),
            ),
            const SizedBox(width: 6),
            MangaPress(
              semanticLabel: 'Send to ${bot.title}',
              onTap: armed ? onSend : null,
              scale: .92,
              child: AnimatedContainer(
                duration: MangaMotion.swap,
                curve: MangaMotion.easeOut,
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: armed ? ink.accent : ink.ink,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 22,
                  color: armed ? ink.onAccent : ink.ground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
