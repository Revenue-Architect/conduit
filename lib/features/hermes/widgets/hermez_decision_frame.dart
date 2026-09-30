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
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: palette.accent.withValues(alpha: 0.55),
            width: 1.5,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
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
        color: palette.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border.withValues(alpha: 0.8)),
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
    final edge = destructive
        ? danger.withValues(alpha: 0.6)
        : selected
        ? palette.accent
        : palette.border;
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
                  ? palette.accent.withValues(alpha: 0.08)
                  : palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: edge, width: selected ? 1.5 : 1),
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
