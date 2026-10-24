import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/persistence/persistence_keys.dart';
import '../../../core/persistence/preferences_store.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../shared/widgets/platform_ui/platform_ui.dart';
import '../../notifications/services/local_notification_service.dart';
import '../models/hermes_bot.dart' show hermesProfileDisplayName;
import '../models/hermes_job.dart';
import '../models/hermes_session.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_pending_decision_store.dart';
import 'hermes_session_tile.dart' show openHermesSession;
import 'hermez_bot_mark.dart';
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';

/// How long the app must have been out of use before Home summarizes what
/// happened meanwhile.
const hermesAwayThreshold = Duration(minutes: 10);

/// When the user left, if they were away long enough to catch up on. Set at
/// launch and on every return from the background; cleared when dismissed.
final hermesAwaySinceProvider = NotifierProvider<HermesAwaySince, DateTime?>(
  HermesAwaySince.new,
);

class HermesAwaySince extends Notifier<DateTime?> {
  @override
  DateTime? build() => _fromStore();

  /// The app came back to the foreground.
  void returned() => state = _fromStore();

  void dismiss() => state = null;

  static DateTime? _fromStore() {
    final raw = PreferencesStore.getString(PreferenceKeys.hermesLastActiveAt);
    final last = raw == null ? null : DateTime.tryParse(raw)?.toUtc();
    if (last == null) return null;
    final away = DateTime.now().toUtc().difference(last);
    return away >= hermesAwayThreshold ? last : null;
  }
}

/// Decisions Hermes is waiting on, across bots. Refreshes when one is
/// added or resolved.
final hermesHomePendingDecisionsProvider =
    FutureProvider.autoDispose<List<HermesPendingDesktopDecision>>((ref) async {
      ref.watch(_pendingChangesProvider);
      final service = ref.watch(hermesApiServiceProvider);
      return service is HermesDesktopApiService
          ? service.pendingDecisions()
          : const <HermesPendingDesktopDecision>[];
    });

final _pendingChangesProvider = StreamProvider<void>(
  (ref) => HermesPendingDecisionStore.changes,
);

/// "12m", "3h", "2d".
String hermesAwayLabel(Duration away) {
  if (away.inMinutes < 60) return '${away.inMinutes}m';
  if (away.inHours < 48) return '${away.inHours}h';
  return '${away.inDays}d';
}

/// What happened while the app was out of use, as one quiet line: "While you
/// were away · 2 chats updated · 1 routine failed". Conversations that moved
/// and scheduled agents that failed; requests waiting on the owner are
/// Needs you's, not repeated here. Tapping the line opens the details in
/// place. Only what really changed; hidden when nothing did.
class HermesAwayDigest extends ConsumerWidget {
  const HermesAwayDigest({super.key, required this.jobs});

  /// Home's scheduled jobs, each with its profile.
  final List<(String, HermesJob)>? jobs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final since = ref.watch(hermesAwaySinceProvider);
    final sessions = ref.watch(hermesSessionsProvider).asData?.value;
    final moved = since == null || sessions == null
        ? const <HermesSessionSummary>[]
        : ([
            // Your conversations, not the automated runs behind them.
            ...sessions.where(
              (session) =>
                  !session.isAutomated &&
                  (session.updatedAt?.toUtc().isAfter(since) ?? false),
            ),
          ]..sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!)));
    final ran = since == null
        ? const <(String, HermesJob)>[]
        : ([
            // A schedule that simply ran is not news; one that failed is.
            ...?jobs?.where(
              (item) =>
                  _AwayLine._failed(item.$2) &&
                  (item.$2.lastRun?.toUtc().isAfter(since) ?? false),
            ),
          ]..sort((a, b) => b.$2.lastRun!.compareTo(a.$2.lastRun!)));
    return HermezReveal(
      visible: since != null && (moved.isNotEmpty || ran.isNotEmpty),
      weight: HermezMotionWeight.medium,
      revealKey: const ValueKey('hermes-away-digest'),
      child: _AwayLine(moved: moved, ran: ran),
    );
  }
}

class _AwayLine extends ConsumerStatefulWidget {
  const _AwayLine({required this.moved, required this.ran});

  final List<HermesSessionSummary> moved;
  final List<(String, HermesJob)> ran;

  static bool _failed(HermesJob job) => job.isFailing;

  /// "2 chats updated · 1 routine failed".
  String get summary => [
    if (moved.isNotEmpty)
      '${moved.length} ${moved.length == 1 ? 'chat' : 'chats'} updated',
    if (ran.isNotEmpty)
      '${ran.length} ${ran.length == 1 ? 'routine' : 'routines'} failed',
  ].join(' · ');

  @override
  ConsumerState<_AwayLine> createState() => _AwayLineState();
}

class _AwayLineState extends ConsumerState<_AwayLine> {
  /// Screen-local: whether the details are open. Never opens by itself.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final summary = widget.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HermezMotionSurface(
          weight: HermezMotionWeight.medium,
          semanticLabel: 'While you were away: $summary',
          semanticsExpanded: _expanded,
          onTap: () => setState(() => _expanded = !_expanded),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'While you were away · $summary',
                    style: HermezType.meta(palette),
                  ),
                ),
                HermezIconSwap(
                  icon: _expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.chevron_right_rounded,
                  color: palette.muted,
                ),
              ],
            ),
          ),
        ),
        HermezReveal(
          visible: _expanded,
          weight: HermezMotionWeight.medium,
          revealKey: const ValueKey('hermes-away-details'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final session in widget.moved.take(3))
                _AwayRow(
                  leading: HermezBotMark(
                    identity: hermezIdentityForName(session.profile),
                    botName: session.profile,
                    size: 30,
                    label: session.profile,
                  ),
                  title: session.title.isEmpty ? 'Conversation' : session.title,
                  subtitle: [
                    if (session.profile case final profile?)
                      hermesProfileDisplayName(profile)
                    else
                      'Hermes',
                    'new activity',
                  ].join(' · '),
                  onTap: () => openHermesSession(context, ref, session),
                ),
              for (final (profile, job) in widget.ran.take(3))
                _AwayRow(
                  leading: Icon(
                    Icons.error_outline_rounded,
                    color: palette.accent,
                    size: 24,
                  ),
                  title: job.name ?? 'Scheduled agent',
                  subtitle: '${hermesProfileDisplayName(profile)} · run failed',
                  onTap: () => context.pushNamed(RouteNames.hermesJobs),
                ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () =>
                      ref.read(hermesAwaySinceProvider.notifier).dismiss(),
                  child: Text(
                    'Dismiss',
                    style: TextStyle(color: palette.muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AwayRow extends StatelessWidget {
  const _AwayRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezMotionSurface(
      weight: HermezMotionWeight.medium,
      semanticLabel: '$title. $subtitle',
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox.square(dimension: 32, child: Center(child: leading)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HermezType.section(palette).copyWith(fontSize: 15),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HermezType.meta(palette),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks, once, to let bots reach the user. Notifications are off by default
/// in this app, so without this a finished run or a waiting approval could
/// only be seen by opening the app.
class HermesNotifyPrompt extends ConsumerStatefulWidget {
  const HermesNotifyPrompt({super.key, this.asRow = false});

  /// A calm list row (for the Work hub) instead of the prompt card: Turn on
  /// is the row, and a small close dismisses it.
  final bool asRow;

  @override
  ConsumerState<HermesNotifyPrompt> createState() => _HermesNotifyPromptState();
}

class _HermesNotifyPromptState extends ConsumerState<HermesNotifyPrompt> {
  bool _dismissed =
      PreferencesStore.getBool(PreferenceKeys.hermesNotifyPromptDismissed) ??
      false;

  Future<void> _enable() async {
    await ref.read(appSettingsProvider.notifier).setNotificationsEnabled(true);
    final granted = await ref
        .read(localNotificationServiceProvider)
        .requestPermissions();
    if (!mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: granted
          ? 'Your bots can reach you now.'
          : 'Notifications are blocked for this app in system settings.',
      type: granted
          ? AdaptiveSnackBarType.success
          : AdaptiveSnackBarType.warning,
    );
  }

  void _dismiss() {
    setState(() => _dismissed = true);
    unawaited(
      PreferencesStore.put(PreferenceKeys.hermesNotifyPromptDismissed, true),
    );
  }

  Widget _row(HermezChatPalette palette) => Row(
    children: [
      Expanded(
        child: HermezMotionSurface(
          weight: HermezMotionWeight.medium,
          semanticLabel: 'Let your bots reach you. Turn on notifications',
          onTap: _enable,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 32,
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Let your bots reach you',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HermezType.section(
                          palette,
                        ).copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Notifications are off · Turn on',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HermezType.meta(palette),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: 'Not now',
        onPressed: _dismiss,
        icon: Icon(Icons.close_rounded, color: palette.muted, size: 20),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      appSettingsProvider.select((settings) => settings.notificationsEnabled),
    );
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezReveal(
      visible: !enabled && !_dismissed,
      weight: HermezMotionWeight.medium,
      revealKey: const ValueKey('hermes-notify-prompt'),
      child: widget.asRow
          ? _row(palette)
          : Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: palette.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            color: palette.accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Let your bots reach you',
                                  style: HermezType.section(palette)
                                      .copyWith(fontSize: 16),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Get a notification when a run finishes or a bot '
                                  'is waiting for your approval.',
                                  style: HermezType.meta(palette),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: _dismiss,
                              child: const Text('Not now'),
                            ),
                            TextButton(
                              onPressed: _enable,
                              child: const Text('Turn on'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
