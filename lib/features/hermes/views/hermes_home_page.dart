import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../feedback/hermez_feedback.dart';
import '../models/hermes_bot.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_providers.dart';
import '../sheets/hermez_modal_sheet.dart';
import '../widgets/hermes_home_composer.dart' show startHermesBotConversation;
import '../widgets/hermes_home_inbox.dart';
import '../widgets/hermes_home_lines.dart';
import '../widgets/hermes_home_needs_you.dart';
import '../widgets/hermes_home_presence.dart';
import '../widgets/hermes_home_working.dart';
import '../widgets/hermes_tab_dock.dart';
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_surfaces.dart';
import '../widgets/hermez_visual_theme.dart';
import 'hermes_page_chrome.dart';

/// What needs the owner, then the conversations and what is coming up. One
/// scroll with no card round any section. On a phone this is the dock's Work
/// tab; Home there is the hub (team, schedules, board, teams, files,
/// decisions, settings). On a tablet it is still the first page.
class HermesHomePage extends ConsumerStatefulWidget {
  const HermesHomePage({super.key});

  @override
  ConsumerState<HermesHomePage> createState() => _HermesHomePageState();
}

class _HermesHomePageState extends ConsumerState<HermesHomePage>
    with WidgetsBindingObserver {
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
    // Coming back to the app is when what waits on the owner has most likely
    // changed: ask the sources again once, rather than on a timer.
    if (state != AppLifecycleState.resumed) return;
    invalidateHermesNeedsYou(ref);
    ref.invalidate(hermesSessionsProvider);
  }

  Future<void> _refresh() async {
    refreshHermesHome(ref);
    try {
      await ref.read(hermesSessionsProvider.future);
    } catch (_) {
      // The page says it is not connected; there is nothing more to wait for.
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final jobs = ref.watch(hermesHomeProfileJobsProvider).value;
    final stale = watchHermesHomeStale(ref);
    final laterToday = hermesRoutinesLaterToday(
      jobs ?? const [],
      DateTime.now(),
    );
    // On a phone this is the dock's Work tab: Home (the hub) owns the
    // masthead and the + for a new chat. Without a dock (a tablet's
    // persistent sidebar) it is the app's first page and keeps both.
    final docked = HermesDockScope.maybeOf(context) != null;
    return HermesPageChrome(
      title: docked ? 'Work' : 'Conduit',
      subtitle: docked ? 'What needs you and what is running' : '',
      actions: [
        const HermesWorkingStack(),
        if (!docked) ...[
          HermesNewChatButton(palette: palette),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => context.pushNamed(RouteNames.profile),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ] else
          const SizedBox(width: 8),
      ],
      // One bottom element: the dock. Chief is the first conversation, so
      // talking to Chief is one tap without a second bar above the dock.
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: Builder(
          builder: (listContext) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              hermesDockClearance(listContext) + 16,
            ),
            children: [
              HermesHomeOfflineLine(visible: stale),
              const HermesNeedsYouSection(),
              const HermesHomeInbox(),
              HermesHomeLaterToday(routines: laterToday.length),
              HermesAwayDigest(jobs: jobs),
            ],
          ),
        ),
      ),
    );
  }
}

/// The + for a new conversation: it turns into the bot menu it opens.
class HermesNewChatButton extends ConsumerWidget {
  const HermesNewChatButton({super.key, required this.palette});

  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    key: const ValueKey('hermes-new-chat'),
    tooltip: 'New Hermes chat',
    onPressed: () => chooseHermesNewChat(
      context,
      ref,
      HermezMorphOrigin.of(context, radius: 24, color: palette.canvas),
    ),
    icon: const Icon(Icons.add_rounded),
  );
}

Future<void> chooseHermesNewChat(
  BuildContext context,
  WidgetRef ref, [
  HermezMorphOrigin? origin,
]) async {
  final bots = ref.read(hermesBotsProvider).value ?? const <HermesBot>[];
  if (bots.isEmpty) return;
  // The + turns into the bot menu, the same plus-to-menu morph as New task:
  // the button's own surface grows from its corner into the menu and folds
  // back into it. A sheet that rises from the bottom edge does not read as
  // coming out of a small control at the top of the screen.
  final palette = HermezChatPalette.forBrightness(Theme.of(context).brightness);
  final HermesBot? bot;
  if (origin == null) {
    bot = await pushHermezSheetRoute<HermesBot>(
      context,
      heightFactor: 0.8,
      builder: (sheetContext) => HermezModalSheet(
        eyebrow: 'New conversation',
        title: 'Choose a bot',
        body: _BotChoices(
          bots: bots,
          onChoose: (choice) => Navigator.pop(sheetContext, choice),
        ),
      ),
    );
  } else {
    bot = await pushHermezPanel<HermesBot>(
      context,
      origin: origin,
      surfaceColor: palette.surface,
      maxWidth: 380,
      semanticLabel: 'Choose a bot',
      theme: hermezVisualTheme(Theme.of(context)),
      faceBuilder: (faceContext, turn) => SizedBox.expand(
        child: Center(
          child: Transform.rotate(
            angle: turn * HermezPanelMotion.rotate,
            child: Icon(Icons.add_rounded, color: palette.ink),
          ),
        ),
      ),
      builder: (panelContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 48, 12),
              child: Text(
                'NEW CONVERSATION',
                style: HermezType.technical(palette.muted),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: _BotChoices(
                  bots: bots,
                  onChoose: (choice) => Navigator.pop(panelContext, choice),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  if (bot == null || !context.mounted) return;
  await startHermesBotConversation(context, ref, bot);
}

/// The bots a new conversation can start with.
class _BotChoices extends StatelessWidget {
  const _BotChoices({required this.bots, required this.onChoose});

  final List<HermesBot> bots;
  final ValueChanged<HermesBot> onChoose;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final candidate in bots)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _BotChoice(bot: candidate, onTap: () => onChoose(candidate)),
        ),
    ],
  );
}

class _BotChoice extends StatelessWidget {
  const _BotChoice({required this.bot, required this.onTap});

  final HermesBot bot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezSurface(
      kind: HermezSurfaceKind.utility,
      border: Border.all(color: palette.border.withValues(alpha: 0.8)),
      semanticLabel: 'Start a conversation with ${bot.title}',
      feedbackCue: HermezFeedbackCue.objectOpen,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          HermezBotMark(
            identity: hermezIdentityForBot(bot),
            botName: bot.name,
            size: 40,
            label: bot.title,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bot.title, style: HermezType.section(palette)),
                Text(
                  bot.description ?? bot.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HermezType.meta(palette),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: palette.muted),
        ],
      ),
    );
  }
}
