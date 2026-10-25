import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../../push/providers/push_providers.dart' show approvalsPendingProvider;
import '../kanban/hermes_kanban_summary_provider.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_providers.dart';
import '../widgets/hermes_home_needs_you.dart';
import '../widgets/hermes_home_presence.dart' show HermesNotifyPrompt;
import '../widgets/hermes_home_working.dart' show HermesWorkingStack;
import '../widgets/hermes_tab_dock.dart';
import '../widgets/hermes_work_rows.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_skeleton.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermes_home_page.dart' show HermesNewChatButton;
import 'hermes_page_chrome.dart';
import 'hermes_teams_page.dart' show hermesTeamsProvider;

/// "2 active · 3 total".
String hermesWorkScheduleMeta(int active, int total) =>
    '$active active · $total total';

/// "12 tasks · 2 running · 4 done".
String hermesWorkBoardMeta(HermesKanbanSummary board) =>
    '${board.total} ${board.total == 1 ? 'task' : 'tasks'} · '
    '${board.count('running')} running · ${board.count('done')} done';

/// Work: every place that is not a conversation. A calm list of rows grouped
/// by space: the team, the work Hermes does, what needs a decision, and
/// Hermes itself. Each row says one true thing about where it leads.
class HermesWorkPage extends ConsumerWidget {
  const HermesWorkPage({super.key, this.title});

  /// Overrides the docked "Conduit" masthead: the manga layout names this
  /// tab Work, because Today is home there.
  final String? title;

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(hermesBotsProvider)
      ..invalidate(hermesHomeProfileJobsProvider)
      ..invalidate(hermesKanbanSummaryProvider)
      ..invalidate(hermesTeamsProvider);
    invalidateHermesNeedsYou(ref);
    try {
      await ref.read(hermesBotsProvider.future);
    } catch (_) {
      // Each row reports what it could not load.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final botsAsync = ref.watch(hermesBotsProvider);
    final bots = botsAsync.value;
    final jobs = ref.watch(hermesHomeProfileJobsProvider).value;
    final kanban = ref.watch(hermesKanbanSummaryProvider);
    final teams = ref.watch(hermesTeamsProvider);
    final approvals = ref.watch(approvalsPendingProvider).value;
    final needsYou = watchHermesNeedsYou(ref);
    final activeJobs = jobs?.where((item) => item.$2.enabled).length ?? 0;

    // In the phone dock this hub is Home: the Conduit masthead, with what is
    // running and the + for a new chat at its right.
    final docked = HermesDockScope.maybeOf(context) != null;
    return HermesPageChrome(
      title: title ?? (docked ? 'Conduit' : 'Work'),
      subtitle: 'Schedules, board, teams and files',
      brandHeader: docked && title == null,
      actions: docked
          ? [
              const HermesWorkingStack(),
              HermesNewChatButton(palette: palette),
              const SizedBox(width: 6),
            ]
          : const [],
      child: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: Builder(
          // Below the page's own safe area, so the dock's clearance is what
          // is measured here.
          builder: (listContext) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              hermesDockClearance(listContext) + 16,
            ),
            children: [
              HermesWorkHeading(
                bots == null ? 'TEAM' : 'TEAM · ${bots.length}',
                first: true,
              ),
              HermezPresence(
                presenceKey: ValueKey(
                  bots == null
                      ? 'team-loading'
                      : bots.isEmpty
                      ? 'team-empty'
                      : 'team',
                ),
                weight: HermezMotionWeight.medium,
                child: bots == null
                    ? (botsAsync.hasError
                          ? const SizedBox.shrink()
                          : HermezSkeleton.rows(count: 3))
                    : bots.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No Hermes bot profiles available.',
                          style: HermezType.meta(palette),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final bot in bots)
                            HermesWorkTeamRow(
                              key: ValueKey('team-${bot.name}'),
                              bot: bot,
                            ),
                        ],
                      ),
              ),
              const HermesWorkHeading('WORK'),
              HermesWorkRow(
                icon: Icons.schedule_rounded,
                title: 'Scheduled agents',
                titleMorphId: hermezMorphPart(hermezScheduleMorphId, 'title'),
                meta: jobs == null
                    ? 'Loading…'
                    : hermesWorkScheduleMeta(activeJobs, jobs.length),
                onOpen: (origin) =>
                    context.pushNamed(RouteNames.hermesJobs, extra: origin),
              ),
              HermesWorkRow(
                icon: Icons.view_kanban_outlined,
                title: 'Kanban',
                titleMorphId: hermezMorphPart(hermezBoardMorphId, 'title'),
                meta: switch (kanban.value) {
                  final board? => hermesWorkBoardMeta(board),
                  null when kanban.isLoading => 'Loading…',
                  null => 'Unavailable',
                },
                onOpen: (origin) =>
                    context.pushNamed(RouteNames.hermesKanban, extra: origin),
              ),
              // Group Chat is optional on a Hermes server: no row without it.
              if (!teams.hasError)
                HermesWorkRow(
                  icon: Icons.groups_outlined,
                  title: 'Teams',
                  meta: switch (teams.value) {
                    null => 'Loading…',
                    final list when list.isEmpty => 'Start a team',
                    final list =>
                      '${list.length} ${list.length == 1 ? 'team' : 'teams'}',
                  },
                  onOpen: (origin) =>
                      context.pushNamed(RouteNames.hermesTeams, extra: origin),
                ),
              HermesWorkRow(
                icon: Icons.article_outlined,
                title: 'Spaces',
                meta: 'Pages you and Hermes work on',
                onOpen: (origin) =>
                    context.pushNamed(RouteNames.spaces, extra: origin),
              ),
              HermesWorkRow(
                icon: Icons.folder_outlined,
                title: 'Artifacts',
                meta: 'Files Hermes made',
                onOpen: (origin) => context.pushNamed(
                  RouteNames.hermesArtifacts,
                  extra: origin,
                ),
              ),
              const HermesWorkHeading('DECISIONS'),
              HermesWorkRow(
                icon: Icons.notifications_none_rounded,
                title: 'Needs you',
                meta: needsYou.isEmpty
                    ? 'Questions, prepared work and failed runs'
                    : '${needsYou.length} waiting',
                onOpen: (origin) => context.pushNamed(
                  RouteNames.hermesAttention,
                  extra: origin,
                ),
              ),
              HermesWorkRow(
                icon: Icons.verified_user_outlined,
                title: 'Approvals',
                meta: approvals == null || approvals.isEmpty
                    ? 'Decide what agents may do'
                    : '${approvals.length} pending',
                onOpen: (origin) => context.pushNamed(
                  RouteNames.hermesApprovals,
                  extra: origin,
                ),
              ),
              const HermesWorkHeading('HERMES'),
              // Only while notifications are off and not waved away.
              const HermesNotifyPrompt(asRow: true),
              HermesWorkRow(
                icon: Icons.tune_rounded,
                title: 'Hermes settings',
                meta: 'Connection and preferences',
                onOpen: (origin) =>
                    context.pushNamed(RouteNames.hermesSettings, extra: origin),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
