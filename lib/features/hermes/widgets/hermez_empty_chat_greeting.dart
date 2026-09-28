import 'package:flutter/material.dart';

import 'hermez_bot_mark.dart';
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';
import 'hermez_technical_background.dart';

/// Empty Hermes chat. Decorative once messages exist; this only fills the void.
class HermezEmptyChatGreeting extends StatelessWidget {
  const HermezEmptyChatGreeting({
    super.key,
    required this.greeting,
    this.contextLabel,
    this.starters = const [],
    this.onStarter,
    this.botName,
  });

  final String greeting;
  final String? contextLabel;
  final List<String> starters;
  final ValueChanged<String>? onStarter;

  /// The chat's bot, so the greeting shows that bot's mark.
  final String? botName;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final visibleStarters = onStarter == null
        ? const <String>[]
        : starters.take(3).toList(growable: false);

    return Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: HermezTechnicalBackground(
              variant: HermezBackgroundVariant.editorial,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: palette.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'HERMEZ',
                          style: HermezType.technical(palette.muted),
                        ),
                        const Spacer(),
                        Text('01', style: HermezType.technical(palette.muted)),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            greeting,
                            style: HermezType.display(palette)
                                .copyWith(fontSize: 36),
                          ),
                        ),
                        HermezBotMark(
                          identity: hermezIdentityForName(botName),
                          size: 64,
                          label: botName,
                        ),
                      ],
                    ),
                    if (contextLabel != null && contextLabel!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          contextLabel!,
                          style: HermezType.meta(palette),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Container(width: 42, height: 3, color: palette.accent),
                    if (visibleStarters.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final starter in visibleStarters)
                            ActionChip(
                              label: Text(starter),
                              labelStyle: HermezType.meta(palette)
                                  .copyWith(color: palette.ink),
                              backgroundColor: palette.surface,
                              side: BorderSide.none,
                              onPressed: () => onStarter!(starter),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
