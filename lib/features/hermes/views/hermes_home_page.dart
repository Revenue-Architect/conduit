import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../kanban/hermes_kanban_summary_provider.dart';
import '../models/hermes_bot.dart';
import '../models/hermes_config.dart';
import '../models/hermes_job.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../providers/hermes_session_totals_provider.dart';
import '../services/hermes_desktop_api_service.dart';
import '../sheets/hermes_scheduled_agent_sheet.dart';
import '../widgets/hermes_bot_avatar.dart';
import '../widgets/hermes_session_tile.dart';
import '../widgets/hermez_chat_palette.dart';
import 'hermes_page_chrome.dart';

final _homeProfileJobsProvider =
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
    String profile,
  ) async {
    final run = await showHermesScheduledAgentSheet(
      context,
      job: job,
      profile: profile,
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
          !identical(ref.read(hermesApiServiceProvider), service))
        return;
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
    final jobs = ref.watch(_homeProfileJobsProvider).asData?.value;
    final sessions = ref.watch(hermesSessionsProvider).asData?.value;
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
    return HermesPageChrome(
      title: 'Hermes',
      subtitle: 'Y O U R  T H I N K I N G  P A R T N E R',
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
          ref.invalidate(_homeProfileJobsProvider);
          ref.invalidate(hermesSessionsProvider);
          ref.invalidate(hermesKanbanSummaryProvider);
          await ref.read(hermesBotsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 36),
          children: [
            Text(
              'An intelligent personal agent to help you think clearer, make progress, and build a more intentional life.',
              style: TextStyle(color: palette.muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 22),
            HermesSectionTitle(
              'Bots',
              trailing: TextButton(
                onPressed: () =>
                    context.pushNamed(RouteNames.hermesConversations),
                child: Text('${bots?.length ?? '—'}  See all →'),
              ),
            ),
            const SizedBox(height: 8),
            if (bots == null)
              const HermesPanel(child: LinearProgressIndicator())
            else if (bots.isEmpty)
              const HermesPanel(
                child: Text('No Hermes bot profiles available.'),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final tileWidth = (constraints.maxWidth - 8) / 2;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final bot in bots.take(6))
                        SizedBox(
                          width: tileWidth,
                          child: _BotCard(bot: bot),
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 18),
            HermesSectionTitle(
              'Today',
              trailing: Text(
                '${now.day}/${now.month}',
                style: TextStyle(color: palette.muted, fontSize: 11),
              ),
            ),
            const SizedBox(height: 8),
            HermesPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Make progress on what matters.',
                          style: TextStyle(color: palette.muted, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.accent, width: 4),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${todayJobs.length + running.length}',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                            const Text(
                              'ITEMS',
                              style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (todayJobs.isEmpty && running.isEmpty)
                    const Text(
                      'No scheduled runs or running Kanban work today.',
                    ),
                  for (final (profile, job) in todayJobs.take(4))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        Icons.circle,
                        color: palette.accent,
                        size: 12,
                      ),
                      title: Text(
                        job.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${job.nextRun!.toLocal().hour.toString().padLeft(2, '0')}:${job.nextRun!.toLocal().minute.toString().padLeft(2, '0')} · Scheduled agent',
                      ),
                      onTap: () => _openJob(context, ref, job, profile),
                    ),
                  for (final task in running.take(3))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(
                        Icons.radio_button_checked,
                        color: Color(0xFF2776D2),
                        size: 17,
                      ),
                      title: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Running${task.assignee == null ? '' : ' · ${task.assignee}'}',
                      ),
                      onTap: () => context.pushNamed(RouteNames.hermesKanban),
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
              children: [
                Expanded(
                  child: HermesPanel(
                    onTap: activeJobs.isEmpty
                        ? () => context.pushNamed(RouteNames.hermesJobs)
                        : () => _openJob(
                            context,
                            ref,
                            activeJobs.first.$2,
                            activeJobs.first.$1,
                          ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.event_repeat_rounded, color: palette.accent),
                        const SizedBox(height: 9),
                        const Text(
                          'Scheduled agents',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          jobs == null
                              ? 'Loading…'
                              : '${activeJobs.length} active · ${jobs.length} total',
                          style: TextStyle(color: palette.muted, fontSize: 11),
                        ),
                        if (activeJobs.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            activeJobs.first.$2.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: HermesPanel(
                    onTap: () => context.pushNamed(RouteNames.hermesKanban),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.view_kanban_outlined, color: palette.accent),
                        const SizedBox(height: 9),
                        const Text(
                          'Kanban',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          kanban == null
                              ? 'Unavailable'
                              : '${kanban.total} tasks · ${kanban.board.name}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: palette.muted, fontSize: 11),
                        ),
                        if (kanban != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${kanban.count('todo')} Todo  ·  ${kanban.count('running')} Running  ·  ${kanban.count('done')} Done',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            HermesSectionTitle(
              'Recent conversations',
              trailing: TextButton(
                onPressed: () =>
                    context.pushNamed(RouteNames.hermesConversations),
                child: const Text('See all →'),
              ),
            ),
            const SizedBox(height: 8),
            HermesPanel(
              child: sessions == null
                  ? const LinearProgressIndicator()
                  : sessions.isEmpty
                  ? const Text('No recent conversations.')
                  : Column(
                      children: [
                        for (final session in sessions.take(3))
                          HermesSessionTile(session: session),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            HermesPanel(
              onTap: sessions?.isNotEmpty == true
                  ? () => context.pushNamed(
                      RouteNames.hermesLiveRun,
                      pathParameters: {'sessionId': sessions!.first.id},
                    )
                  : null,
              child: Row(
                children: [
                  Icon(
                    Icons.radio_button_checked_rounded,
                    color: palette.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      sessions?.isNotEmpty == true
                          ? 'Live activity · ${sessions!.first.title}'
                          : 'Live activity · No conversations yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.pushNamed(RouteNames.hermesAttention),
                    icon: const Icon(Icons.notifications_none_rounded),
                    label: const Text('Attention'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
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
          child: HermesPanel(
            onTap: () => context.pushNamed(
              RouteNames.hermesLiveRun,
              pathParameters: {'sessionId': active!.id},
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LIVE WORK',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        active.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        );
      },
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
    final avatar = ref.watch(hermesBotAvatarProvider(bot.name)).asData?.value;
    final service = ref.watch(hermesApiServiceProvider);
    final state =
        service is HermesDesktopApiService && bot.chatSessionId != null
        ? service.turnStateFor(bot.chatSessionId!)
        : HermesDesktopTurnState.idle;
    final running = state == HermesDesktopTurnState.running;
    return HermesPanel(
      onTap: () => context.pushNamed(
        RouteNames.hermesBotDetail,
        pathParameters: {'profile': bot.name},
      ),
      padding: const EdgeInsets.all(11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HermesBotAvatar(
                size: 42,
                label: bot.title,
                shape: bot.avatarShape,
                color: bot.avatarColor,
                imageKind: bot.avatarImageKind,
                imageUrl: avatar,
              ),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            bot.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            bot.description ?? 'Hermes profile',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: palette.muted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                radius: 3,
                backgroundColor: running
                    ? const Color(0xFF17A46A)
                    : const Color(0xFF2776D2),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  running
                      ? 'Running'
                      : bot.lastActive == null
                      ? 'Available'
                      : 'Last active ${bot.lastActive!.toLocal().hour}:${bot.lastActive!.toLocal().minute.toString().padLeft(2, '0')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: palette.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
