import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../models/hermes_job.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import 'hermes_home_needs_you.dart' show invalidateHermesNeedsYou;
import 'hermes_home_presence.dart' show hermesHomePendingDecisionsProvider;
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';

/// True when something Home shows failed its last refresh. Home then says it
/// is not connected and drops live "working" state, because activity it
/// cannot see is not claimed.
bool watchHermesHomeStale(WidgetRef ref) =>
    // Only whether each failed: Home does not rebuild on every poll.
    ref.watch(hermesSessionsProvider.select((value) => value.hasError)) ||
    ref.watch(hermesBotsProvider.select((value) => value.hasError)) ||
    ref.watch(hermesActiveWorkProvider.select((value) => value.hasError)) ||
    ref.watch(
      hermesHomePendingDecisionsProvider.select((value) => value.hasError),
    );

/// Asks every source Home reads again: pull to refresh and Retry.
void refreshHermesHome(WidgetRef ref) {
  ref
    ..invalidate(hermesBotsProvider)
    ..invalidate(hermesJobsProvider)
    ..invalidate(hermesHomeProfileJobsProvider)
    ..invalidate(hermesSessionsProvider)
    ..invalidate(hermesActiveWorkProvider);
  invalidateHermesNeedsYou(ref);
}

/// The enabled scheduled agents whose next run is still to come today.
List<(String, HermesJob)> hermesRoutinesLaterToday(
  Iterable<(String, HermesJob)> jobs,
  DateTime now,
) => [
  for (final item in jobs)
    if (item.$2.enabled)
      if (item.$2.nextRun?.toLocal() case final next?
          when next.year == now.year &&
              next.month == now.month &&
              next.day == now.day &&
              next.isAfter(now))
        item,
];

/// "Later today · 2 routines".
String hermesLaterTodayLabel(int routines) =>
    'Later today · $routines ${routines == 1 ? 'routine' : 'routines'}';

/// One quiet line: scheduled agents still to run today. Gone when none are.
class HermesHomeLaterToday extends StatelessWidget {
  const HermesHomeLaterToday({super.key, required this.routines});

  final int routines;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezReveal(
      visible: routines > 0,
      revealKey: const ValueKey('hermes-later-today'),
      child: HermezMotionSurface(
        weight: HermezMotionWeight.medium,
        semanticLabel: hermesLaterTodayLabel(routines),
        originRadius: 14,
        originColor: palette.canvas,
        onOpen: (origin) =>
            context.pushNamed(RouteNames.hermesJobs, extra: origin),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hermesLaterTodayLabel(routines),
                  style: HermezType.meta(palette),
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

/// "Not connected · Retry": shown while Hermes cannot be reached. Retry asks
/// every source again.
class HermesHomeOfflineLine extends ConsumerWidget {
  const HermesHomeOfflineLine({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezReveal(
      visible: visible,
      weight: HermezMotionWeight.medium,
      revealKey: const ValueKey('hermes-offline'),
      child: HermezMotionSurface(
        weight: HermezMotionWeight.light,
        semanticLabel: 'Not connected. Retry',
        onTap: () => refreshHermesHome(ref),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text.rich(
              TextSpan(
                style: HermezType.meta(palette),
                children: [
                  const TextSpan(text: 'Not connected · '),
                  TextSpan(
                    text: 'Retry',
                    style: TextStyle(
                      color: palette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
