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

final _homePendingDecisionsProvider =
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

/// Home's first card after time away: requests waiting, conversations that
/// moved, and scheduled agents that ran. Only what really changed; hidden
/// when nothing did.
class HermesAwayDigest extends ConsumerWidget {
  const HermesAwayDigest({super.key, required this.jobs});

  /// Home's scheduled jobs, each with its profile.
  final List<(String, HermesJob)>? jobs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final since = ref.watch(hermesAwaySinceProvider);
    final sessions = ref.watch(hermesSessionsProvider).asData?.value;
    final pending =
        ref.watch(_homePendingDecisionsProvider).asData?.value ?? const [];
    final moved = since == null || sessions == null
        ? const <HermesSessionSummary>[]
        : ([
            ...sessions.where(
              (session) => session.updatedAt?.toUtc().isAfter(since) ?? false,
            ),
          ]..sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!)));
    final ran = since == null
        ? const <(String, HermesJob)>[]
        : ([
            ...?jobs?.where(
              (item) => item.$2.lastRun?.toUtc().isAfter(since) ?? false,
            ),
          ]..sort((a, b) => b.$2.lastRun!.compareTo(a.$2.lastRun!)));
    final visible =
        since != null &&
        (pending.isNotEmpty || moved.isNotEmpty || ran.isNotEmpty);
    return HermezReveal(
      visible: visible,
      weight: HermezMotionWeight.medium,
      revealKey: const ValueKey('hermes-away-digest'),
      child: since == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _AwayCard(
                away: DateTime.now().toUtc().difference(since),
                pending: pending.length,
                moved: moved.take(3).toList(growable: false),
                ran: ran.take(3).toList(growable: false),
              ),
            ),
    );
  }
}

class _AwayCard extends ConsumerWidget {
  const _AwayCard({
    required this.away,
    required this.pending,
    required this.moved,
    required this.ran,
  });

  final Duration away;
  final int pending;
  final List<HermesSessionSummary> moved;
  final List<(String, HermesJob)> ran;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'SINCE YOU WERE AWAY · ${hermesAwayLabel(away)}',
                    style: HermezType.technical(palette.muted),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: () =>
                      ref.read(hermesAwaySinceProvider.notifier).dismiss(),
                  icon: Icon(Icons.close_rounded, color: palette.muted),
                ),
              ],
            ),
            if (pending > 0)
              _AwayRow(
                leading: Icon(
                  Icons.priority_high_rounded,
                  color: palette.accent,
                  size: 22,
                ),
                title: pending == 1
                    ? '1 request is waiting for you'
                    : '$pending requests are waiting for you',
                subtitle: 'Approvals and questions from your bots',
                onTap: () => context.pushNamed(RouteNames.hermesAttention),
              ),
            for (final session in moved)
              _AwayRow(
                leading: HermezBotMark(
                  identity: hermezIdentityForName(session.profile),
                  size: 26,
                  label: session.profile,
                ),
                title: session.title.isEmpty ? 'Conversation' : session.title,
                subtitle: [
                  session.profile ?? 'Hermes',
                  'new activity',
                ].join(' · '),
                onTap: () => openHermesSession(context, ref, session),
              ),
            for (final (profile, job) in ran)
              _AwayRow(
                leading: Icon(
                  _failed(job)
                      ? Icons.error_outline_rounded
                      : Icons.schedule_rounded,
                  color: _failed(job) ? palette.accent : palette.ink,
                  size: 22,
                ),
                title: job.name ?? 'Scheduled agent',
                subtitle: [
                  profile,
                  _failed(job) ? 'run failed' : 'ran',
                ].join(' · '),
                onTap: () => context.pushNamed(RouteNames.hermesJobs),
              ),
          ],
        ),
      ),
    );
  }

  static bool _failed(HermesJob job) =>
      (job.lastError?.isNotEmpty ?? false) ||
      (job.lastStatus?.toLowerCase().contains('fail') ?? false) ||
      (job.lastStatus?.toLowerCase().contains('error') ?? false);
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
      weight: HermezMotionWeight.light,
      semanticLabel: title,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
        child: Row(
          children: [
            SizedBox.square(dimension: 30, child: Center(child: leading)),
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
    );
  }
}

/// Asks, once, to let bots reach the user. Notifications are off by default
/// in this app, so without this a finished run or a waiting approval could
/// only be seen by opening the app.
class HermesNotifyPrompt extends ConsumerStatefulWidget {
  const HermesNotifyPrompt({super.key});

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
      child: Padding(
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
