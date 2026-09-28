import 'package:flutter/material.dart';

import '../models/hermes_bot.dart';
import '../models/hermes_config.dart';
import '../services/hermes_desktop_api_service.dart';
import 'hermez_chat_palette.dart';
import 'hermez_relative_time.dart';
import 'hermez_surfaces.dart';

/// Text styles shared by a bot's Home card and its detail header, so each
/// part can travel between the two and keep being text.
abstract final class HermezBotStyles {
  static TextStyle kind(HermezChatPalette palette) =>
      HermezType.technical(palette.muted).copyWith(fontSize: 9, height: 1.1);

  static TextStyle detailKind(HermezChatPalette palette) =>
      HermezType.technical(palette.muted).copyWith(fontSize: 11, height: 1.1);

  static TextStyle cardName(HermezChatPalette palette) =>
      HermezType.section(palette).copyWith(fontSize: 15, height: 1.15);

  static TextStyle detailName(HermezChatPalette palette) =>
      HermezType.display(palette).copyWith(fontSize: 34, height: 1.02);

  static TextStyle cardAbout(HermezChatPalette palette) =>
      HermezType.meta(palette);

  static TextStyle detailAbout(HermezChatPalette palette) =>
      HermezType.body(palette).copyWith(color: palette.muted);
}

/// Whether Hermes reports a live turn in this bot's own chat session.
bool hermezBotRunning(Object? service, HermesBot bot) {
  final session = bot.chatSessionId;
  return service is HermesDesktopApiService &&
      session != null &&
      service.turnStateFor(session) == HermesDesktopTurnState.running;
}

/// The one-line status a bot shows on Home and in its detail header. Only
/// what Hermes reported: a live turn, or the last activity time.
String hermezBotStatus(HermesBot bot, {required bool running}) {
  if (running) return 'Running';
  final last = bot.lastActive;
  if (last == null) return 'No recent activity';
  return 'Used ${hermezRelativeLabel(last).split(',').first.toLowerCase()}';
}

/// The small status light beside a bot's status line: accent while Hermes
/// reports a live turn, muted otherwise.
class HermezStatusDot extends StatelessWidget {
  const HermezStatusDot({super.key, required this.running, this.size = 6});

  final bool running;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: running ? palette.accent : palette.muted,
        shape: BoxShape.circle,
      ),
    );
  }
}
