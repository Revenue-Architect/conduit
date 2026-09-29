import 'package:flutter/material.dart';

import '../models/hermes_bot.dart';

/// Visual identity only. Derived from the profile name, not from capabilities.
enum HermezBotIdentity { neutral, kai, local, autopilot, fast, strong }

HermezBotIdentity hermezIdentityForBot(HermesBot bot) =>
    hermezIdentityForName(bot.name);

HermezBotIdentity hermezIdentityForName(String? name) {
  final key = (name ?? '').toLowerCase();
  if (key.contains('kai')) return HermezBotIdentity.kai;
  if (key.contains('local')) return HermezBotIdentity.local;
  if (key.contains('autopilot')) return HermezBotIdentity.autopilot;
  if (key.contains('fast')) return HermezBotIdentity.fast;
  if (key.contains('strong')) return HermezBotIdentity.strong;
  return HermezBotIdentity.neutral;
}

/// The artwork for each bot identity (`assets/icons`).
const Map<HermezBotIdentity, String> hermezBotMarkAssets = {
  HermezBotIdentity.neutral: 'assets/icons/Defaultbot.png',
  HermezBotIdentity.kai: 'assets/icons/KaiBot.png',
  HermezBotIdentity.local: 'assets/icons/locabot.png',
  HermezBotIdentity.autopilot: 'assets/icons/autopilotbot.png',
  HermezBotIdentity.fast: 'assets/icons/fast bot.png',
  HermezBotIdentity.strong: 'assets/icons/StrongBot.png',
};

/// A bot's mark: its artwork, fitted inside a [size] square.
class HermezBotMark extends StatelessWidget {
  const HermezBotMark({
    super.key,
    required this.identity,
    this.size = 44,
    this.label,
  });

  final HermezBotIdentity identity;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    // Decode at the size it is drawn, not the source resolution.
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Semantics(
      label: label == null ? 'Bot' : 'Bot $label',
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(
          hermezBotMarkAssets[identity]!,
          fit: BoxFit.contain,
          cacheWidth: pixels > 0 ? pixels : null,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
