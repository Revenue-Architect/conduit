import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hermes_bot.dart';
import '../models/hermes_session.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../sheets/hermes_active_work_sheet.dart' show showHermesActiveWorkSheet;
import 'hermes_home_lines.dart';
import 'hermez_bot_mark.dart';
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';

/// The line shown for a session that is working but has not said anything
/// yet.
String hermesWorkingFallbackLine(HermesLiveSession session) =>
    session.status == 'starting' ? 'Starting…' : 'Working…';

/// What Hermes says a working session is doing right now: the reply as it is
/// being written, else the plain state.
String hermesWorkingLine(HermesLiveSession session) {
  final preview = session.preview?.replaceAll(RegExp(r'\s+'), ' ').trim();
  return preview == null || preview.isEmpty
      ? hermesWorkingFallbackLine(session)
      : preview;
}

/// One agent that is working now.
@immutable
class HermesWorkingAgent {
  const HermesWorkingAgent({
    required this.profile,
    required this.storedId,
    required this.line,
  });

  final String profile;

  /// The session it is working in.
  final String storedId;

  /// What it is doing, from Hermes.
  final String line;
}

/// The agents really working now, one per bot, in Hermes' order (the most
/// recently active first). A session counts only while Hermes reports it
/// `working` or `starting`; one waiting for the owner is not working, and
/// [stale] data (a failed refresh) counts as nothing, because activity Home
/// cannot see is not claimed.
///
/// [profileOf] names the bot a session belongs to; a session it cannot place
/// is left out.
List<HermesWorkingAgent> hermesWorkingAgents(
  Iterable<HermesLiveSession> live, {
  required String? Function(String storedId) profileOf,
  bool stale = false,
}) {
  if (stale) return const [];
  final seen = <String>{};
  final agents = <HermesWorkingAgent>[];
  for (final session in live) {
    if (!session.working) continue;
    final profile = profileOf(session.storedId);
    if (profile == null || !seen.add(profile)) continue;
    agents.add(
      HermesWorkingAgent(
        profile: profile,
        storedId: session.storedId,
        line: hermesWorkingLine(session),
      ),
    );
  }
  return agents;
}

/// The bot a live session belongs to, as far as Home knows: its row in the
/// session list, else the bot whose chat it is, else the profile the
/// connection opened it under.
String? hermesProfileOfSession(
  String storedId, {
  required List<HermesSessionSummary> sessions,
  required List<HermesBot> bots,
  HermesDesktopApiService? service,
}) {
  for (final session in sessions) {
    if (session.id == storedId && session.profile != null) {
      return session.profile;
    }
  }
  for (final bot in bots) {
    if (bot.chatSessionId == storedId) return bot.name;
  }
  return service?.profileForSession(storedId);
}

/// The agents working now, each placed by the bot its session belongs to.
List<HermesWorkingAgent> watchHermesWorkingAgents(WidgetRef ref) {
  final service = ref.watch(hermesApiServiceProvider);
  final work = ref.watch(hermesActiveWorkProvider);
  final sessions =
      ref.watch(hermesSessionsProvider).value ?? const <HermesSessionSummary>[];
  final bots = ref.watch(hermesBotsProvider).value ?? const <HermesBot>[];
  return hermesWorkingAgents(
    work.value ?? const <HermesLiveSession>[],
    stale: watchHermesHomeStale(ref),
    profileOf: (id) => hermesProfileOfSession(
      id,
      sessions: sessions,
      bots: bots,
      service: service is HermesDesktopApiService ? service : null,
    ),
  );
}

/// Small overlapping avatars of the agents working now, for Home's header.
/// Nothing when everything is idle. Tapping opens Active Work: each working
/// agent and what it is saying, and each opens its conversation.
class HermesWorkingStack extends ConsumerWidget {
  const HermesWorkingStack({super.key});

  static const double _avatar = 22;
  static const double _step = 14;
  static const int _maxShown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final agents = watchHermesWorkingAgents(ref);
    final shown = agents.take(_maxShown).toList(growable: false);
    final extra = agents.length - shown.length;
    final names = [
      for (final agent in agents) hermesProfileDisplayName(agent.profile),
    ];
    return HermezSize(
      weight: HermezMotionWeight.light,
      alignment: Alignment.centerRight,
      child: agents.isEmpty
          ? const SizedBox(height: 48)
          : HermezMotionSurface(
              weight: HermezMotionWeight.light,
              semanticLabel:
                  '${agents.length == 1 ? '1 agent' : '${agents.length} agents'} '
                  'working: ${names.join(', ')}. Opens active work',
              originRadius: 20,
              originColor: palette.surface,
              onOpen: (origin) =>
                  showHermesActiveWorkSheet(context, ref, origin: origin),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: _avatar + 4,
                        width: _avatar + 4 + _step * (shown.length - 1),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Drawn right to left so the first agent sits on
                            // top, as in a messenger's group avatar.
                            for (var i = shown.length - 1; i >= 0; i--)
                              Positioned(
                                left: _step * i,
                                top: 0,
                                // The canvas-coloured margin cuts each avatar
                                // out of the one beneath it.
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: palette.canvas,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: HermezBotMark(
                                      identity: hermezIdentityForName(
                                        shown[i].profile,
                                      ),
                                      botName: shown[i].profile,
                                      size: _avatar,
                                      label: hermesProfileDisplayName(
                                        shown[i].profile,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (extra > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '+$extra',
                          style: HermezType.meta(palette)
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
