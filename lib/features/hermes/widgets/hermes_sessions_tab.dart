import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/services/navigation_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/platform_scroll_physics.dart';
import '../../../shared/widgets/conduit_loading.dart';
import '../../../shared/widgets/sidebar_layout_contract.dart';
import '../../navigation/providers/sidebar_tab_scroll_registry.dart';
import '../../navigation/models/sidebar_navigation_model.dart';
import '../../navigation/widgets/chats_drawer.dart'
    show sidebarSectionDisclosureIcon;
import '../../navigation/widgets/drawer_section_notifiers.dart';
import '../kanban/hermes_kanban_summary_provider.dart';
import '../models/hermes_bot.dart';
import '../models/hermes_config.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../providers/hermes_session_totals_provider.dart';
import 'hermes_bot_tile.dart';
import 'hermes_bot_avatar.dart';
import 'hermez_bot_mark.dart';
import 'hermes_session_tile.dart';

/// Sidebar tab listing the user's Hermes server-side conversations, with one
/// compact entry point for scheduled agents when the server exposes jobs.
class HermesSessionsTab extends ConsumerStatefulWidget {
  const HermesSessionsTab({
    super.key,
    this.showBottomNavigationBar = true,
    this.standalone = false,
  });

  final bool showBottomNavigationBar;
  final bool standalone;

  @override
  ConsumerState<HermesSessionsTab> createState() => _HermesSessionsTabState();
}

class _HermesSessionsTabState extends ConsumerState<HermesSessionsTab>
    with SidebarTabScrollRegistration<HermesSessionsTab> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _expandedBots = <String>{};
  final Map<String, int> _visibleBotSessions = <String, int>{};

  @override
  SidebarTabId get sidebarTabId => SidebarTabId.hermes;

  @override
  bool get registerSidebarScrollController => !widget.standalone;

  @override
  ScrollController get sidebarScrollController => _scrollController;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(hermesCapabilitiesProvider).asData?.value;
    final showJobs = caps?.jobs ?? true;
    final sessionsAsync = ref.watch(hermesSessionsProvider);
    final profileTotals = ref.watch(hermesSessionTotalsProvider).asData?.value;

    // The sidebar tab host has no Material ancestor; provide a transparent one
    // so InkWell / IconButton / CustomizationTile work inside this tab.
    // Top/bottom insets + the refresh edge offset mirror the Chats tab so the
    // content clears the native sidebar chrome and bottom tab bar.
    final scroll = CustomScrollView(
      controller: _scrollController,
      primary: false,
      physics: platformAlwaysScrollablePhysics(context),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: widget.standalone
                ? 0
                : sidebarTabContentTopPadding(context),
          ),
        ),
        const SliverToBoxAdapter(child: _HermesHomeEntry()),
        ..._botSlivers(
          context,
          ref.watch(hermesBotsProvider).asData?.value,
          sessionsAsync.asData?.value ?? const [],
          profileTotals,
        ),
        if (ref.watch(hermesConfigProvider).mode ==
            HermesBackendMode.desktopGateway)
          const SliverToBoxAdapter(child: _KanbanEntry()),
        if (showJobs) const SliverToBoxAdapter(child: _ScheduledAgentsTile()),
        ..._sessionSlivers(context, sessionsAsync),
        SliverToBoxAdapter(
          child: SizedBox(
            height: sidebarTabContentBottomPadding(
              context,
              includeNativeBottomBar: widget.showBottomNavigationBar,
            ),
          ),
        ),
      ],
    );
    final refreshable = ConduitRefreshIndicator(
      edgeOffset: sidebarRefreshIndicatorEdgeOffset(context),
      onRefresh: () async {
        if (showJobs) ref.invalidate(hermesJobsProvider);
        ref.invalidate(hermesBotsProvider);
        ref.invalidate(hermesSessionsProvider);
        for (final profile in _expandedBots) {
          ref.invalidate(hermesBotSessionsProvider(profile));
        }
        ref.invalidate(hermesKanbanSummaryProvider);
        ref.invalidate(hermesSessionTotalsProvider);
        try {
          await ref.read(hermesSessionsProvider.future);
        } catch (_) {
          // Keep the list on screen. A failed refresh is not a new error page.
        }
      },
      child: scroll,
    );
    final primary = PrimaryScrollController(
      controller: _scrollController,
      child: refreshable,
    );
    return Material(
      type: MaterialType.transparency,
      child: context.usesCupertinoChrome
          ? CupertinoScrollbar(controller: _scrollController, child: primary)
          : Scrollbar(controller: _scrollController, child: primary),
    );
  }

  /// The Bot Mode roster, above everything else. Absent entirely on gateways
  /// without Bot Mode, which report no bots.
  List<Widget> _botSlivers(
    BuildContext context,
    List<HermesBot>? bots,
    List<HermesSessionSummary> sessions,
    Map<String, int>? profileTotals,
  ) {
    if (bots == null || bots.isEmpty) return const [];
    final expanded = ref.watch(hermesShowBotsProvider);
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.sm,
          Spacing.xs,
          Spacing.sm,
          Spacing.sm,
        ),
        sliver: SliverToBoxAdapter(
          child: Container(
            decoration: widget.standalone
                ? null
                : BoxDecoration(
                    color: context.conduitTheme.surfaceBackground,
                    borderRadius: BorderRadius.circular(16),
                  ),
            child: Column(
              children: [
                _SectionHeader(
                  title: AppLocalizations.of(context)!.hermesBotsTitle,
                  count: bots.length,
                  expanded: expanded,
                  onToggle: () {
                    ConduitHaptics.selectionClick();
                    ref.read(hermesShowBotsProvider.notifier).toggle();
                  },
                ),
                if (expanded)
                  for (var index = 0; index < bots.length; index++) ...[
                    if (index > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    _botGroup(bots[index], sessions, profileTotals),
                  ],
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _botGroup(
    HermesBot bot,
    List<HermesSessionSummary> sessions,
    Map<String, int>? profileTotals,
  ) {
    final theme = context.conduitTheme;
    final expanded = _expandedBots.contains(bot.name);
    final recentOwned = sessions
        .where((session) => session.profile == bot.name)
        .toList(growable: false);
    final scoped = expanded
        ? ref.watch(hermesBotSessionsProvider(bot.name))
        : null;
    final scopedOwned = scoped?.asData?.value;
    final owned = scopedOwned == null ||
            (scopedOwned.isEmpty && recentOwned.isNotEmpty)
        ? recentOwned
        : scopedOwned;
    final conversationCount = profileTotals?[bot.name] ?? owned.length;
    final visibleCount = _visibleBotSessions[bot.name] ?? 8;
    final avatar = bot.hasAvatar
        ? ref.watch(hermesBotAvatarProvider(bot.name)).asData?.value
        : null;
    return Column(
      children: [
        InkWell(
          key: ValueKey('hermes-bot-disclosure-${bot.name}'),
          onTap: () {
            ConduitHaptics.selectionClick();
            setState(() {
              if (!_expandedBots.add(bot.name)) _expandedBots.remove(bot.name);
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                bot.avatarImageKind == 'photo' && avatar != null
                    ? HermesBotAvatar(
                        size: 36,
                        imageUrl: avatar,
                        label: bot.title,
                        shape: bot.avatarShape,
                        color: bot.avatarColor,
                        imageKind: bot.avatarImageKind,
                      )
                    : HermezBotMark(
                        identity: hermezIdentityForBot(bot),
                        size: 36,
                        label: bot.title,
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bot.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMediumStyle.copyWith(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (conversationCount > 0)
                        Text(
                          '$conversationCount chats',
                          style: AppTypography.bodySmallStyle.copyWith(
                            color: theme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  sidebarSectionDisclosureIcon(expanded),
                  color: theme.iconSecondary,
                  size: IconSize.listItem,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 12, 10),
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: theme.cardBorder)),
              ),
              child: Column(
                children: [
                  // This action always starts a new profile-bound session.
                  HermesBotTile(bot: bot, nested: true),
                  if (scoped?.isLoading == true)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: LinearProgressIndicator(),
                    ),
                  if (scoped?.hasError == true && owned.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Could not refresh chats for this bot. Pull to retry.',
                      ),
                    ),
                  for (final session in owned.take(visibleCount))
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 3),
                      child: HermesSessionTile(session: session, nested: true),
                    ),
                  if (owned.length > visibleCount)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: ValueKey('hermes-bot-more-${bot.name}'),
                        onPressed: () => setState(() {
                          _visibleBotSessions[bot.name] = visibleCount + 12;
                        }),
                        child: Text(
                          'Show more conversations (${owned.length - visibleCount} left)',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _sessionSlivers(
    BuildContext context,
    AsyncValue<List<HermesSessionSummary>> sessionsAsync,
  ) {
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    return sessionsAsync.when(
      data: (sessions) {
        if (sessions.isEmpty) {
          return [
            SliverToBoxAdapter(
              child: _message(
                theme,
                Icons.smart_toy_outlined,
                l10n.hermesNoConversationsMessage,
                theme.textSecondary,
              ),
            ),
          ];
        }
        return [
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: l10n.hermesConversationsTitle,
              count: sessions.length,
            ),
          ),
          SliverPadding(
            // The shared conversation tile supplies the 4.0.3 Hermes 8pt row
            // gutter. Keep list padding vertical to avoid doubling that inset
            // only in this tab.
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            sliver: SliverList.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.sm,
                  0,
                  Spacing.sm,
                  Spacing.xs,
                ),
                child: widget.standalone
                    ? HermesSessionTile(
                        session: sessions[index],
                        compact: true,
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.surfaceBackground,
                          borderRadius: BorderRadius.circular(
                            AppBorderRadius.card,
                          ),
                        ),
                        child: HermesSessionTile(session: sessions[index]),
                      ),
              ),
            ),
          ),
        ];
      },
      loading: () => const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 64),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
      error: (_, _) => [
        SliverToBoxAdapter(
          child: _message(
            theme,
            Icons.chat_bubble_outline,
            'Recent conversations are unavailable right now.',
            theme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _message(
    ConduitThemeExtension theme,
    IconData icon,
    String text,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 80, left: 24, right: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: Spacing.md),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmallStyle.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _HermesHomeEntry extends StatelessWidget {
  const _HermesHomeEntry();

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.xs,
        Spacing.sm,
        Spacing.xs,
      ),
      child: Material(
        color: theme.surfaceBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ListTile(
          key: const ValueKey('hermes-home-entry'),
          leading: Icon(Icons.home_outlined, color: theme.buttonPrimary),
          title: const Text(
            'Hermes Home',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text('Bots, work, and what needs you'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.pushNamed(RouteNames.hermesHome),
        ),
      ),
    );
  }
}

class _KanbanEntry extends ConsumerWidget {
  const _KanbanEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.conduitTheme;
    final count = ref.watch(hermesKanbanSummaryProvider).asData?.value?.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.sm,
        Spacing.sm,
        Spacing.xs,
      ),
      child: Material(
        color: theme.surfaceBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.card),
        ),
        child: ListTile(
          key: const ValueKey<String>('hermes-kanban-entry'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 9,
          ),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.buttonPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppBorderRadius.button),
            ),
            child: Icon(
              Icons.view_kanban_outlined,
              color: theme.buttonPrimary,
              size: 27,
            ),
          ),
          title: Text(
            'Kanban',
            style: AppTypography.bodyMediumStyle.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: theme.textPrimary,
            ),
          ),
          subtitle: const Text('Boards and tasks'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (count != null) ...[
                Text(
                  '$count',
                  style: AppTypography.bodySmallStyle.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          onTap: () => context.pushNamed(RouteNames.hermesKanban),
        ),
      ),
    );
  }
}

class _ScheduledAgentsTile extends ConsumerWidget {
  const _ScheduledAgentsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(hermesJobsProvider);
    final jobs = jobsAsync.value;
    final count = jobs?.length;
    final activeCount = jobs?.where((job) => job.enabled).length;
    final theme = context.conduitTheme;
    final l10n = AppLocalizations.of(context)!;
    final subtitle = switch ((count, activeCount, jobsAsync)) {
      (null, _, AsyncLoading()) => l10n.hermesSchedulesLoading,
      (null, _, AsyncError()) => l10n.hermesSchedulesUnavailable,
      (0, _, _) => l10n.hermesNoSchedulesYet,
      (final int total, final int active, _) => l10n.hermesSchedulesSummary(
        active,
        total,
      ),
      _ => l10n.hermesReviewSchedules,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: InkWell(
        key: const ValueKey<String>('hermes-scheduled-agents-tile'),
        onTap: () => context.pushNamed(RouteNames.hermesJobs),
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: 16,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.buttonPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppBorderRadius.button),
                ),
                child: Icon(
                  Icons.event_repeat_rounded,
                  size: IconSize.listItem,
                  color: theme.buttonPrimary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.hermesScheduledAgentsTitle,
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: Spacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.buttonPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppBorderRadius.pill),
                  ),
                  child: Text(
                    '$count',
                    style: AppTypography.labelMediumStyle.copyWith(
                      color: theme.buttonPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSize.listItem,
                color: theme.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section header with an optional count badge.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.count,
    this.expanded,
    this.onToggle,
  });

  final String title;
  final int? count;

  /// Disclosure state; null renders a plain, non-collapsible header.
  final bool? expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final titleStyle = AppTypography.labelStyle.copyWith(
      color: theme.textPrimary,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (expanded != null) ...[
                  Icon(
                    sidebarSectionDisclosureIcon(expanded!),
                    color: theme.iconSecondary,
                    size: IconSize.listItem,
                  ),
                  const SizedBox(width: Spacing.xxs),
                ],
                Text(title, style: titleStyle),
                if (count != null) ...[
                  const SizedBox(width: Spacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppBorderRadius.pill),
                    ),
                    child: Text(
                      '$count',
                      style: AppTypography.labelMediumStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onToggle == null) return header;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: header,
    );
  }
}
