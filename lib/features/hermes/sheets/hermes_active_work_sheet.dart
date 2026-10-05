import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hermes_session.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../widgets/hermes_session_tile.dart';
import '../widgets/hermez_relative_time.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_live.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermez_modal_sheet.dart';

/// "2 working · 1 needs you".
String hermesActiveWorkSummary(List<HermesLiveSession> sessions) {
  final needs = sessions.where((session) => session.needsYou).length;
  final working = sessions.where((session) => session.working).length;
  return [
    if (working > 0) '$working working',
    if (needs > 0) '$needs ${needs == 1 ? 'needs' : 'need'} you',
  ].join(' · ');
}

/// Runs on this connection that ended recently and are not running again,
/// newest first. Hermes lists open idle sessions as active too, so only a
/// working or waiting session means a run is not done.
List<({String storedId, DateTime at, bool failed})> hermesFinishedWork(
  HermesDesktopApiService service,
  List<HermesLiveSession> sessions,
) {
  final running = {
    for (final session in sessions)
      if (session.working || session.needsYou) session.storedId,
  };
  return [
    for (final done in service.recentlyFinished())
      if (!running.contains(done.storedId)) done,
  ];
}

/// Finds the chat a live session belongs to, so it opens in its own
/// profile with its own name.
HermesSessionSummary hermesSummaryForSession(
  WidgetRef ref,
  String storedId,
  String title,
) {
  final sessions = ref.read(hermesSessionsProvider).value ?? const [];
  final known = sessions.where((session) => session.id == storedId).firstOrNull;
  if (known != null) return known;
  final bots = ref.read(hermesBotsProvider).value ?? const [];
  final bot = bots.where((bot) => bot.chatSessionId == storedId).firstOrNull;
  final service = ref.read(hermesApiServiceProvider);
  return HermesSessionSummary(
    id: storedId,
    title: title,
    profile:
        bot?.name ??
        (service is HermesDesktopApiService
            ? service.profileForSession(storedId)
            : null),
  );
}

/// Everything Hermes is doing right now, across chats, bots, devices and
/// schedules; what needs you comes first. A row closes the sheet and opens
/// its chat from [context] (the sheet's own context is gone by then).
Future<void> showHermesActiveWorkSheet(
  BuildContext context,
  WidgetRef ref, {
  HermezMorphOrigin? origin,
}) async {
  final chosen = await pushHermezSheetRoute<HermesSessionSummary>(
    context,
    origin: origin,
    heightFactor: 0.82,
    builder: (_) => const _HermesActiveWorkSheet(),
  );
  if (chosen != null && context.mounted) {
    await openHermesSession(context, ref, chosen);
  }
}

class _HermesActiveWorkSheet extends ConsumerWidget {
  const _HermesActiveWorkSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final work = ref.watch(hermesActiveWorkProvider);
    final sessions = work.value ?? const <HermesLiveSession>[];
    final needs = sessions.where((session) => session.needsYou).toList();
    final working = sessions.where((session) => session.working).toList();
    final service = ref.watch(hermesApiServiceProvider);
    final known = ref.watch(hermesSessionsProvider).value ?? const [];
    final finished = service is HermesDesktopApiService
        ? hermesFinishedWork(service, sessions)
        : const <({String storedId, DateTime at, bool failed})>[];
    String titleFor(String id) =>
        known.where((session) => session.id == id).firstOrNull?.title ?? 'Chat';

    void open(String storedId, String title) =>
        Navigator.of(context)
            .pop(hermesSummaryForSession(ref, storedId, title));

    final summary = hermesActiveWorkSummary(sessions);
    return HermezModalSheet(
      eyebrow: summary.isEmpty ? 'ACTIVE WORK' : summary.toUpperCase(),
      title: 'Active work',
      subtitle: Text(
        'What Hermes is doing now, on every chat and bot.',
        style: HermezType.meta(palette),
      ),
      body: work.isLoading && work.value == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (needs.isEmpty && working.isEmpty && finished.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Nothing is running right now.',
                      style: HermezType.body(palette)
                          .copyWith(color: palette.muted),
                    ),
                  ),
                if (needs.isNotEmpty) ...[
                  _Label('NEEDS YOU', accent: true),
                  for (final session in needs)
                    _WorkRow(
                      key: ValueKey('needs-${session.storedId}'),
                      state: HermezLiveState.attention,
                      title: session.title,
                      detail: session.preview ?? 'Waiting for your answer',
                      live: false,
                      onTap: () => open(session.storedId, session.title),
                    ),
                ],
                if (working.isNotEmpty) ...[
                  _Label('WORKING'),
                  for (final session in working)
                    _WorkRow(
                      key: ValueKey('working-${session.storedId}'),
                      state: HermezLiveState.working,
                      title: session.title,
                      detail:
                          session.preview ??
                          (session.status == 'starting'
                              ? 'Starting…'
                              : 'Working…'),
                      meta: session.model,
                      live: true,
                      onTap: () => open(session.storedId, session.title),
                    ),
                ],
                if (finished.isNotEmpty) ...[
                  _Label('FINISHED RECENTLY'),
                  for (final done in finished.take(6))
                    _WorkRow(
                      key: ValueKey('done-${done.storedId}'),
                      state: done.failed
                          ? HermezLiveState.failed
                          : HermezLiveState.done,
                      title: titleFor(done.storedId),
                      detail: done.failed ? 'Run failed' : 'Done',
                      meta: hermezRelativeLabel(done.at),
                      live: false,
                      onTap: () => open(done.storedId, titleFor(done.storedId)),
                    ),
                ],
              ],
            ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.accent = false});
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
      child: Text(
        text,
        style: HermezType.technical(accent ? palette.accent : palette.muted),
      ),
    );
  }
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({
    super.key,
    required this.state,
    required this.title,
    required this.detail,
    required this.live,
    required this.onTap,
    this.meta,
  });

  final HermezLiveState state;
  final String title;
  final String detail;
  final String? meta;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HermezSurface(
        kind: HermezSurfaceKind.list,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        semanticLabel: '$title. $detail',
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HermezLiveDot(state: state, size: 8),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HermezType.body(palette)
                        .copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  HermezLiveText(
                    detail,
                    live: live,
                    maxLines: 2,
                    style: HermezType.meta(palette)
                        .copyWith(color: live ? palette.ink : palette.muted),
                  ),
                  if (meta != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HermezType.meta(palette).copyWith(fontSize: 11),
                    ),
                  ],
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
