import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../feedback/hermez_feedback.dart';
import '../models/hermes_bot.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_providers.dart';
import 'hermes_home_avatar.dart';
import 'hermes_home_working.dart' show watchHermesWorkingAgents;
import 'hermez_bot_identity.dart';
import 'hermez_bot_mark.dart';
import '../manga/manga_prefs.dart';
import '../manga/manga_theme.dart';
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';

/// A small technical-caps heading over a group of Work rows. Groups are told
/// apart by space, not by lines.
class HermesWorkHeading extends StatelessWidget {
  const HermesWorkHeading(this.label, {super.key, this.first = false});

  final String label;

  /// The first heading sits closer to the page title.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    if (mangaLayoutOf(context)) {
      // The panel face over a thick ink rule, in sentence case.
      final ink = MangaInk.of(context);
      final text = label.isEmpty
          ? label
          : label[0] + label.substring(1).toLowerCase();
      return Padding(
        padding: EdgeInsets.only(top: first ? 8 : 28, bottom: 2),
        child: Semantics(
          header: true,
          child: Container(
            padding: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: ink.ink, width: ink.border),
              ),
            ),
            child: Text(text, style: MangaType.panel(ink.ink)),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: first ? 4 : 26, bottom: 4),
      child: Semantics(
        header: true,
        child: Text(label, style: HermezType.technical(palette.muted)),
      ),
    );
  }
}

/// One place in the Work hub: an icon, a title, one true line under it, and
/// a chevron. Opens its destination growing out of the row.
class HermesWorkRow extends StatelessWidget {
  const HermesWorkRow({
    super.key,
    required this.icon,
    required this.title,
    required this.meta,
    required this.onOpen,
    this.titleMorphId,
  });

  final IconData icon;
  final String title;

  /// What is true of it right now ("3 active · 5 total").
  final String meta;

  /// Lets the title travel to the destination's title.
  final String? titleMorphId;
  final ValueChanged<HermezMorphOrigin?> onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final manga = mangaLayoutOf(context);
    final ink = MangaInk.of(context);
    return HermezMotionSurface(
      weight: HermezMotionWeight.medium,
      semanticLabel: '$title. $meta',
      feedbackCue: HermezFeedbackCue.objectOpen,
      originRadius: 14,
      originColor: palette.canvas,
      onOpen: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              if (manga)
                // A square glyph tile with an ink border: the panel shape,
                // small.
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    border: Border.all(color: ink.ink, width: ink.border),
                  ),
                  child: Icon(icon, size: 22, color: ink.ink),
                )
              else
                SizedBox.square(
                  dimension: 32,
                  child: Icon(icon, size: 22, color: palette.ink),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HermezMorphText(
                      title,
                      id: titleMorphId,
                      style: manga
                          ? MangaType.panel(ink.ink)
                          : HermezType.section(palette).copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                    ),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: manga
                          ? MangaType.meta(ink.ink2)
                          : HermezType.meta(palette),
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

/// One bot of the roster, compact: its mark, its name, and when it was last
/// used. Opens the bot, whose mark and name travel to its page.
class HermesWorkTeamRow extends ConsumerWidget {
  const HermesWorkTeamRow({super.key, required this.bot});

  final HermesBot bot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final service = ref.watch(hermesApiServiceProvider);
    // Any of the bot's chats, not only its own chat: a new chat with Chief
    // runs in a session of its own.
    final working = watchHermesWorkingAgents(ref).any(
      (agent) =>
          hermesProfileDisplayName(agent.profile).toLowerCase() ==
          hermesProfileDisplayName(bot.name).toLowerCase(),
    );
    final running = working || hermezBotRunning(service, bot);
    final title = hermesBotDisplayTitle(bot);
    final status = hermezBotStatus(bot, running: running);
    final morphId = hermezBotMorphId(bot.name);
    return HermezMotionSurface(
      weight: HermezMotionWeight.medium,
      semanticLabel: '$title. $status',
      feedbackCue: HermezFeedbackCue.objectOpen,
      originRadius: 14,
      originColor: palette.canvas,
      onOpen: (origin) => context.pushNamed(
        RouteNames.hermesBotDetail,
        pathParameters: {'profile': bot.name},
        extra: origin,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 32,
                child: HermezMorph(
                  id: hermezMorphPart(morphId, 'mark'),
                  child: HermezBotMark(
                    identity: hermezIdentityForBot(bot),
                    botName: bot.name,
                    size: 32,
                    label: title,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HermezMorphText(
                      title,
                      id: hermezMorphPart(morphId, 'name'),
                      style: HermezType.section(palette)
                          .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Accent only while Hermes reports a live turn.
                      style: HermezType.meta(palette).copyWith(
                        color: running ? palette.accent : palette.muted,
                      ),
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
