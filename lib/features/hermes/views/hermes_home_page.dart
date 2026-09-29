import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../../../shared/widgets/sidebar_layout_contract.dart';
import '../feedback/hermez_feedback.dart';
import '../kanban/hermes_kanban_summary_provider.dart';
import '../models/hermes_bot.dart';
import '../models/hermes_config.dart';
import '../models/hermes_job.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../providers/hermes_session_totals_provider.dart';
import '../services/hermes_desktop_api_service.dart';
import '../sheets/hermes_scheduled_agent_sheet.dart';
import '../widgets/hermes_session_tile.dart';
import '../widgets/hermez_bot_identity.dart';
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_relative_time.dart';
import '../motion/hermez_motion.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermes_page_chrome.dart';
import '../widgets/hermes_home_presence.dart';
import 'hermes_teams_page.dart' show HermesTeamsSection;

final hermesHomeProfileJobsProvider =
    FutureProvider.autoDispose<List<(String, HermesJob)>>((ref) async {
      final service = ref.watch(hermesApiServiceProvider);
      if (service is! HermesDesktopApiService) return const [];
      final bots = await ref.watch(hermesBotsProvider.future);
      final profiles = {
        service.config.desktopProfile,
        ...bots.map((bot) => bot.name),
      };
      final groups = await Future.wait(
        profiles.map((profile) async {
          try {
            final rows = await service.listJobsForProfile(profile);
            return [
              for (final job
                  in rows.map(HermesJob.fromJson).whereType<HermesJob>())
                (profile, job),
            ];
          } catch (_) {
            return <(String, HermesJob)>[];
          }
        }),
      );
      return [for (final group in groups) ...group];
    });

class HermesHomePage extends ConsumerWidget {
  const HermesHomePage({super.key});

  Future<void> _openJob(
    BuildContext context,
    WidgetRef ref,
    HermesJob job,
    String profile, [
    HermezMorphOrigin? origin,
  ]) async {
    final run = await showHermesScheduledAgentSheet(
      context,
      job: job,
      profile: profile,
      origin: origin,
    );
    if (run != null && context.mounted) {
      await openHermesSession(context, ref, run);
    }
  }

  Future<void> _chooseNewChat(BuildContext context, WidgetRef ref) async {
    final bots =
        ref.read(hermesBotsProvider).asData?.value ?? const <HermesBot>[];
    if (bots.isEmpty) return;
    final bot = await showModalBottomSheet<HermesBot>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Start a new conversation')),
            for (final candidate in bots)
              ListTile(
                title: Text(candidate.title),
                subtitle: Text(candidate.description ?? candidate.name),
                onTap: () => Navigator.pop(sheetContext, candidate),
              ),
          ],
        ),
      ),
    );
    if (bot == null || !context.mounted) return;
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    try {
      final id = await service.createBotConversation(bot);
      if (!context.mounted ||
          !identical(ref.read(hermesApiServiceProvider), service)) {
        return;
      }
      ref.invalidate(hermesBotSessionsProvider(bot.name));
      ref.invalidate(hermesSessionsProvider);
      ref.invalidate(hermesSessionTotalsProvider);
      await openHermesSession(
        context,
        ref,
        HermesSessionSummary(
          id: id,
          title: 'New conversation',
          profile: bot.name,
        ),
        bot: bot,
        botAvatar: ref.read(hermesBotAvatarProvider(bot.name)).asData?.value,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start a bot conversation.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final bots = ref.watch(hermesBotsProvider).asData?.value;
    final jobs = ref.watch(hermesHomeProfileJobsProvider).asData?.value;
    final sessionsAsync = ref.watch(hermesSessionsProvider);
    final sessions = sessionsAsync.asData?.value;
    final kanban = ref.watch(hermesKanbanSummaryProvider).asData?.value;
    final now = DateTime.now();
    final todayJobs = (jobs ?? const <(String, HermesJob)>[])
        .where((item) {
          final next = item.$2.nextRun?.toLocal();
          return item.$2.enabled &&
              next != null &&
              next.year == now.year &&
              next.month == now.month &&
              next.day == now.day;
        })
        .toList(growable: false);
    final activeJobs = (jobs ?? const <(String, HermesJob)>[])
        .where((item) => item.$2.enabled)
        .toList();
    final running = kanban?.snapshot.lanes['running'] ?? const [];
    // On phones Home sits in its own side navigation (see the route); the
    // button slides Home aside to reveal it. Tablets show no button.
    final navigation = SidebarDrawerControllerScope.maybeOf(context);
    return HermesPageChrome(
      title: 'Hermes',
      subtitle: 'Y O U R  T H I N K I N G  P A R T N E R',
      leading: navigation == null || usesPersistentTabletSidebar(context)
          ? null
          : IconButton(
              key: const ValueKey('hermes-home-navigation-toggle'),
              tooltip: 'Navigation',
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                navigation.toggle();
              },
              icon: const Icon(Icons.menu_rounded),
            ),
      actions: [
        IconButton(
          tooltip: 'New Hermes chat',
          onPressed: () => _chooseNewChat(context, ref),
          icon: const Icon(Icons.add_rounded),
        ),
        IconButton(
          tooltip: 'Profile',
          onPressed: () => context.pushNamed(RouteNames.profile),
          icon: const Icon(Icons.account_circle_outlined),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(hermesBotsProvider);
          ref.invalidate(hermesJobsProvider);
          ref.invalidate(hermesHomeProfileJobsProvider);
          ref.invalidate(hermesSessionsProvider);
          ref.invalidate(hermesKanbanSummaryProvider);
          await ref.read(hermesBotsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 36),
          children: [
            // After time away, what happened meanwhile comes first. It is
            // hidden when nothing did.
            HermesAwayDigest(jobs: jobs),
            HermezSectionBar(
              label: 'BOTS  ${bots?.length ?? '—'}',
              actionLabel: 'All chats',
              onAction: () => context.pushNamed(RouteNames.hermesConversations),
            ),
            const SizedBox(height: 8),
            if (bots == null)
              const LinearProgressIndicator()
            else if (bots.isEmpty)
              Text(
                'No Hermes bot profiles available.',
                style: HermezType.meta(palette),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  final columns = constraints.maxWidth >= 300 && scale <= 1.35
                      ? 2
                      : 1;
                  const gap = 10.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final bot in bots.take(6))
                        SizedBox(
                          width: width,
                          child: _BotCard(bot: bot),
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 22),
            Text('TODAY', style: HermezType.technical(palette.muted)),
            const SizedBox(height: 8),
            HermezSurface(
              kind: HermezSurfaceKind.hero,
              motif: HermezMotif.crop,
              indexLabel: '02',
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What is actually on today',
                          style: HermezType.section(palette),
                        ),
                        const SizedBox(height: 8),
                        if (todayJobs.isEmpty && running.isEmpty)
                          Text(
                            'No scheduled runs or running Kanban work today.',
                            style: HermezType.meta(palette),
                          ),
                        for (final (profile, job) in todayJobs.take(4))
                          _TodayRow(
                            title: job.displayName,
                            titleMorphId: hermezMorphPart(
                              hermezJobMorphId(profile, job.id),
                              'title',
                            ),
                            detail:
                                'Scheduled · ${hermezRelativeLabel(job.nextRun!)}',
                            onOpen: (origin) =>
                                _openJob(context, ref, job, profile, origin),
                          ),
                        for (final task in running.take(3))
                          _TodayRow(
                            title: task.title,
                            detail:
                                'Running${task.assignee == null ? '' : ' · ${task.assignee}'}',
                            onOpen: (_) =>
                                context.pushNamed(RouteNames.hermesKanban),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 72,
                    child: Column(
                      children: [
                        Text(
                          '${todayJobs.length + running.length}',
                          style: HermezType.numeric(palette.ink),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ITEMS',
                          style: HermezType.technical(palette.accent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _ActiveWorkCard(
              sessions: sessions ?? const [],
              bots: bots ?? const [],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: HermezSurface(
                    kind: HermezSurfaceKind.utility,
                    motif: HermezMotif.slash,
                    motifMorphId: hermezMorphPart(
                      hermezScheduleMorphId,
                      'motif',
                    ),
                    semanticLabel: 'Scheduled agents',
                    feedbackCue: HermezFeedbackCue.objectOpen,
                    onOpen: (origin) =>
                        context.pushNamed(RouteNames.hermesJobs, extra: origin),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SCHEDULE',
                          style: HermezType.technical(palette.accent),
                        ),
                        const SizedBox(height: 8),
                        HermezMorphText(
                          'Scheduled agents',
                          id: hermezMorphPart(hermezScheduleMorphId, 'title'),
                          style: HermezType.section(palette),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          jobs == null
                              ? 'Loading…'
                              : '${activeJobs.length} active · ${jobs.length} total',
                          style: HermezType.meta(palette),
                        ),
                        if (activeJobs.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            activeJobs.first.$2.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HermezType.body(palette),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: HermezSurface(
                    kind: HermezSurfaceKind.utility,
                    motif: HermezMotif.arc,
                    motifMorphId: hermezMorphPart(hermezBoardMorphId, 'motif'),
                    semanticLabel: 'Kanban',
                    feedbackCue: HermezFeedbackCue.objectOpen,
                    onOpen: (origin) => context.pushNamed(
                      RouteNames.hermesKanban,
                      extra: origin,
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BOARD',
                          style: HermezType.technical(palette.muted),
                        ),
                        const SizedBox(height: 8),
                        HermezMorphText(
                          'Kanban',
                          id: hermezMorphPart(hermezBoardMorphId, 'title'),
                          style: HermezType.section(palette),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          kanban == null
                              ? 'Unavailable'
                              : '${kanban.total} tasks · ${kanban.board.name}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: HermezType.meta(palette),
                        ),
                        if (kanban != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${kanban.count('todo')} todo · ${kanban.count('running')} running · ${kanban.count('done')} done',
                            style: HermezType.meta(palette),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            HermezSectionBar(
              label: 'RECENT',
              onAction: () => context.pushNamed(RouteNames.hermesConversations),
            ),
            HermezSurface(
              kind: HermezSurfaceKind.list,
              padding: EdgeInsets.zero,
              child: sessions == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: sessionsAsync.hasError
                          ? Text(
                              'Recent conversations are unavailable right now.',
                              style: HermezType.meta(palette),
                            )
                          : const LinearProgressIndicator(),
                    )
                  : sessions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No recent conversations.',
                        style: HermezType.meta(palette),
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < sessions.take(4).length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              color: palette.border.withValues(alpha: 0.7),
                            ),
                          HermesSessionTile(
                            session: sessions[i],
                            compact: true,
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 22),
            // Bots working together: group conversations, after the one-to-one
            // ones. The latest teams, or a way to start one.
            const HermesTeamsSection(),
            // Asks once to let bots reach the user, beside Attention and
            // below everything else so it never pushes content down.
            const HermesNotifyPrompt(),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () =>
                        context.pushNamed(RouteNames.hermesAttention),
                    icon: const Icon(Icons.notifications_none_rounded),
                    label: const Text('Attention'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () =>
                        context.pushNamed(RouteNames.hermesArtifacts),
                    icon: const Icon(Icons.folder_outlined),
                    label: const Text('Artifacts'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveWorkCard extends ConsumerWidget {
  const _ActiveWorkCard({required this.sessions, required this.bots});
  final List<HermesSessionSummary> sessions;
  final List<HermesBot> bots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return const SizedBox.shrink();
    return StreamBuilder<HermesDesktopTurnState>(
      stream: service.turnStates,
      builder: (context, _) {
        final candidates = <HermesSessionSummary>[
          ...sessions,
          for (final bot in bots)
            if (bot.chatSessionId != null &&
                !sessions.any((session) => session.id == bot.chatSessionId))
              HermesSessionSummary(
                id: bot.chatSessionId!,
                title: bot.title,
                profile: bot.name,
              ),
        ];
        HermesSessionSummary? active;
        for (final candidate in candidates) {
          if (service.turnStateFor(candidate.id) ==
              HermesDesktopTurnState.running) {
            active = candidate;
            break;
          }
        }
        if (active == null) return const SizedBox.shrink();
        final palette = HermezChatPalette.forBrightness(
          Theme.of(context).brightness,
        );
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: HermezSurface(
            kind: HermezSurfaceKind.technical,
            motif: HermezMotif.arc,
            // Live work belongs to the conversation's inline activity panel.
            onTap: () => openHermesSession(context, ref, active!),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LIVE WORK',
                        style: HermezType.technical(const Color(0xFFFF5A26)),
                      ),
                      Text(
                        active.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF6F5F2),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFF6F5F2),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({
    required this.title,
    required this.detail,
    required this.onOpen,
    this.titleMorphId,
  });

  final String title;
  final String detail;
  final ValueChanged<HermezMorphOrigin?> onOpen;
  final String? titleMorphId;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezMotionSurface(
      weight: HermezMotionWeight.light,
      semanticLabel: title,
      originRadius: 12,
      originColor: palette.surface,
      onOpen: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: palette.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HermezMorphText(
                    title,
                    id: titleMorphId,
                    style: HermezType.body(palette),
                  ),
                  Text(detail, style: HermezType.meta(palette)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotCard extends ConsumerWidget {
  const _BotCard({required this.bot});
  final HermesBot bot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final service = ref.watch(hermesApiServiceProvider);
    final running = hermezBotRunning(service, bot);
    final status = hermezBotStatus(bot, running: running);
    final description = bot.description?.trim();
    final morphId = hermezBotMorphId(bot.name);
    return HermezSurface(
      kind: HermezSurfaceKind.utility,
      motif: HermezMotif.etched,
      motifMorphId: hermezMorphPart(morphId, 'motif'),
      border: Border.all(color: palette.border.withValues(alpha: 0.8)),
      semanticLabel: bot.title,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
      feedbackCue: HermezFeedbackCue.objectOpen,
      onOpen: (origin) => context.pushNamed(
        RouteNames.hermesBotDetail,
        pathParameters: {'profile': bot.name},
        extra: origin,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 116),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HermezMorph(
                  id: hermezMorphPart(morphId, 'mark'),
                  child: HermezBotMark(
                    identity: hermezIdentityForBot(bot),
                    size: 46,
                    label: bot.title,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HermezMorphText(
                        'BOT',
                        id: hermezMorphPart(morphId, 'kind'),
                        style: HermezBotStyles.kind(palette),
                      ),
                      const SizedBox(height: 2),
                      HermezMorphText(
                        bot.title,
                        id: hermezMorphPart(morphId, 'name'),
                        style: HermezBotStyles.cardName(palette),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            HermezMorphText(
              description == null || description.isEmpty
                  ? 'Hermes profile'
                  : description,
              id: hermezMorphPart(morphId, 'about'),
              maxLines: 2,
              style: HermezBotStyles.cardAbout(palette),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                HermezMorph(
                  id: hermezMorphPart(morphId, 'dot'),
                  child: HermezStatusDot(running: running),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: HermezMorphText(
                    status,
                    id: hermezMorphPart(morphId, 'status'),
                    style: HermezType.meta(palette),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
