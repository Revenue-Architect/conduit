import 'package:flutter/material.dart';

import 'hermez_chat_palette.dart';

/// A typographic restyle of ChatPage's existing empty state, not a new screen.
class HermezEmptyChatGreeting extends StatelessWidget {
  const HermezEmptyChatGreeting({super.key, required this.greeting});

  final String greeting;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final headline = Theme.of(context).textTheme.displaySmall;

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'HERMEZ',
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                greeting,
                style: headline?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.1,
                ),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 20),
              Container(
                width: 46,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
