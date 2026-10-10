import 'package:flutter/material.dart';

import '../motion/hermez_motion.dart';
import '../views/hermes_live_run_page.dart';
import 'hermes_run_actions.dart';
import 'hermez_chat_palette.dart';
import 'hermez_visual_theme.dart';

/// The same button-to-panel route as Kanban's New task. The live page remains
/// the single detail implementation; this only changes how chat opens it.
class HermesRunDetailsButton extends StatefulWidget {
  const HermesRunDetailsButton({
    super.key,
    required this.sessionId,
    this.compact = false,
    this.detailsBuilder,
  });
  final String sessionId;
  final bool compact;
  final WidgetBuilder? detailsBuilder;
  @override
  State<HermesRunDetailsButton> createState() => _HermesRunDetailsButtonState();
}

class _HermesRunDetailsButtonState extends State<HermesRunDetailsButton> {
  bool _open = false;

  Widget _face(BuildContext context, ValueChanged<HermezMorphOrigin?> onOpen) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    if (!widget.compact) {
      return HermezRunPill(
        label: 'Run details',
        icon: Icons.timeline_rounded,
        onOpen: onOpen,
      );
    }
    return Tooltip(
      message: 'Run details',
      child: HermezMotionSurface(
        semanticLabel: 'Run details',
        weight: HermezMotionWeight.light,
        originRadius: 24,
        originColor: palette.surface,
        originBorderColor: palette.border,
        onOpen: onOpen,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.border),
          ),
          child: Icon(Icons.timeline_rounded, color: palette.ink, size: 22),
        ),
      ),
    );
  }

  Future<void> _show(HermezMorphOrigin? origin) async {
    if (_open || origin == null) return;
    final sessionId = widget.sessionId;
    final detailsBuilder = widget.detailsBuilder;
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final fixed = HermezMorphOrigin.rect(
      origin.resolve(),
      radius: origin.radius,
      color: origin.color,
      borderColor: origin.borderColor,
    );
    setState(() => _open = true);
    try {
      await pushHermezPanel<void>(
        context,
        origin: fixed,
        semanticLabel: 'Run details',
        surfaceColor: palette.surface,
        theme: hermezVisualTheme(Theme.of(context)),
        faceBuilder: (context, frame) => _face(context, (_) {}),
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child:
              detailsBuilder?.call(context) ??
              HermesLiveRunPage(
                key: ValueKey(sessionId),
                sessionId: sessionId,
                embedded: true,
              ),
        ),
      );
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: _open,
    child: ExcludeSemantics(
      excluding: _open,
      child: Opacity(opacity: _open ? 0 : 1, child: _face(context, _show)),
    ),
  );
}
