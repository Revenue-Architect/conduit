import 'package:flutter/material.dart';

import '../models/hermes_bot.dart';
import 'hermez_bot_mark.dart';
import 'hermez_chat_palette.dart';

/// The name to show for [bot]: its own title, except that the default profile
/// reads as Chief even when its stored title is still "Default".
String hermesBotDisplayTitle(HermesBot bot) =>
    bot.name == 'default' && bot.title.trim().toLowerCase() == 'default'
    ? hermesProfileDisplayName(bot.name)
    : bot.title;

/// A bot's circular mark for Home's lists: no fill, no frame.
///
/// [working] draws one still accent ring round it (never a spinner), and
/// [needsYou] a small accent dot at its corner. The ring and dot sit in a
/// fixed margin around the mark, so a row's layout never shifts when either
/// one arrives.
class HermesHomeAvatar extends StatelessWidget {
  const HermesHomeAvatar({
    super.key,
    required this.profile,
    this.size = 36,
    this.working = false,
    this.needsYou = false,
  });

  /// The bot's profile id; null draws the neutral mark.
  final String? profile;
  final double size;
  final bool working;
  final bool needsYou;

  /// Margin that holds the ring and the dot.
  static const double margin = 3;

  /// Room the avatar takes in a row.
  static double extent(double size) => size + margin * 2;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final name = profile;
    return SizedBox.square(
      dimension: extent(size),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(margin),
              child: HermezBotMark(
                identity: hermezIdentityForName(name),
                botName: name,
                size: size,
                label: name == null ? 'Hermes' : hermesProfileDisplayName(name),
              ),
            ),
          ),
          if (working)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.accent, width: 1.5),
                  ),
                ),
              ),
            ),
          if (needsYou)
            Positioned(
              right: -1,
              top: -1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.accent,
                  shape: BoxShape.circle,
                  // Cuts the dot out of the mark with the canvas.
                  border: Border.all(color: palette.canvas, width: 2),
                ),
                child: const SizedBox.square(dimension: 12),
              ),
            ),
        ],
      ),
    );
  }
}
