import 'package:flutter/material.dart';

import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';

/// The Hermez frame for an inline decision Hermes is waiting on: approval,
/// clarification, sudo, secret, MCP setup. A technical eyebrow and a status
/// word, then the question and the answers.
class HermezDecisionFrame extends StatelessWidget {
  const HermezDecisionFrame({
    super.key,
    required this.eyebrow,
    required this.status,
    required this.children,
    this.semanticsLabel,
    this.busy = false,
  });

  final String eyebrow;

  /// A short status word: WAIT, SENDING, SENT, APPROVED, DENIED.
  final String status;
  final List<Widget> children;
  final String? semanticsLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    // Part of the conversation, not a box over it: the accent dot and label
    // head a thin neutral rail, and the question and answers hang under it,
    // the same branch shape as delegated work and run steps.
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 28,
                child: Row(
                  children: [
                    SizedBox(
                      width: 10,
                      child: Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: palette.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        eyebrow.toUpperCase(),
                        style: HermezType.technical(palette.ink),
                      ),
                    ),
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ),
                    Text(status, style: HermezType.technical(palette.accent)),
                  ],
                ),
              ),
              CustomPaint(
                painter: _DecisionRail(palette.accent.withValues(alpha: 0.45)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 0, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecisionRail extends CustomPainter {
  const _DecisionRail(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawLine(
    const Offset(5, 0),
    Offset(5, size.height),
    Paint()
      ..color = color
      ..strokeWidth = 1,
  );

  @override
  bool shouldRepaint(_DecisionRail oldDelegate) => oldDelegate.color != color;
}

/// The action or command a decision is about, as a terminal line.
class HermezCommandBlock extends StatelessWidget {
  const HermezCommandBlock({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '> $text',
        style: TextStyle(
          color: palette.ink,
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }
}

/// One answer as a physical option: a titled row that compresses under the
/// finger. [selected] shows a choice held before sending; [marker] draws a
/// radio or check mark for choice lists.
class HermezDecisionOption extends StatelessWidget {
  const HermezDecisionOption({
    super.key,
    required this.title,
    required this.onTap,
    this.detail,
    this.enabled = true,
    this.destructive = false,
    this.selected = false,
    this.marker,
  });

  final String title;
  final String? detail;
  final VoidCallback onTap;
  final bool enabled;
  final bool destructive;
  final bool selected;

  /// A leading radio or checkbox glyph, for choice lists.
  final IconData? marker;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final danger = Theme.of(context).colorScheme.error;
    // A quiet fill, outlined only when held as the choice.
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: HermezMotionSurface(
        weight: HermezMotionWeight.light,
        enabled: enabled,
        semanticLabel: detail == null ? title : '$title. $detail',
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: selected
                  ? palette.accent.withValues(alpha: 0.10)
                  : palette.surface,
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? Border.all(color: palette.accent, width: 1.5)
                  : null,
            ),
            child: Row(
              children: [
                if (marker != null) ...[
                  Icon(
                    marker,
                    size: 20,
                    color: selected ? palette.accent : palette.muted,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: destructive ? danger : palette.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail!,
                          style: TextStyle(color: palette.muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
