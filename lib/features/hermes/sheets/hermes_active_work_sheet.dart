import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hermes_session.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../widgets/hermes_session_tile.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_live.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermez_modal_sheet.dart';
import '../widgets/hermez_skeleton.dart';

/// "2 working · 1 needs you".
String hermesActiveWorkSummary(List<HermesLiveSession> sessions) {
  final needs = sessions.where((session) => session.needsYou).length;
  final working = sessions.where((session) => session.working).length;
  return [
    if (working > 0) '$working working',
    if (needs > 0) '$needs ${needs == 1 ? 'needs' : 'need'} you',
  ].join(' · ');
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
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: HermezSkeleton.rows(count: 3),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (needs.isEmpty && working.isEmpty)
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
