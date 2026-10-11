import 'package:flutter/material.dart';

import '../motion/hermez_motion.dart';
import '../views/hermes_live_run_page.dart';
import '../sheets/hermez_modal_sheet.dart' show pushHermezSheetRoute;
import 'hermes_run_actions.dart';
import 'hermez_chat_palette.dart';
import 'hermez_visual_theme.dart';
import '../../../core/models/chat_message.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/conduit_localizations.dart';

/// Shared measured-source launch into the existing detail implementation.
/// The unified orb uses the critically damped sheet; legacy pills retain the
/// Kanban-style panel route. Neither adds a second run or activity store.
class HermesRunDetailsButton extends StatefulWidget {
  const HermesRunDetailsButton({
    super.key,
    required this.sessionId,
    this.compact = false,
    this.detailsBuilder,
    this.faceBuilder,
    this.answerMessages,
    this.currentAnswer = false,
  });
  final String sessionId;
  final bool compact;
  final WidgetBuilder? detailsBuilder;
  final Widget Function(BuildContext, ValueChanged<HermezMorphOrigin?>)?
  faceBuilder;
  final List<ChatMessage>? answerMessages;
  final bool currentAnswer;
  @override
  State<HermesRunDetailsButton> createState() => _HermesRunDetailsButtonState();
}

class _HermesRunDetailsButtonState extends State<HermesRunDetailsButton> {
  bool _open = false;

  Widget _face(BuildContext context, ValueChanged<HermezMorphOrigin?> onOpen) {
    if (widget.faceBuilder != null) return widget.faceBuilder!(context, onOpen);
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
    final answerMessages = widget.answerMessages;
    final currentAnswer = widget.currentAnswer;
    Widget details(BuildContext context) => Localizations.override(
      context: context,
      // Chat uses standalone Material UI; the existing detail page includes
      // Flutter Material widgets. Both localization types must cross the route.
      delegates: [
        ...conduitLocalizationsDelegates,
        ...AppLocalizations.localizationsDelegates,
      ],
      child:
          detailsBuilder?.call(context) ??
          HermesLiveRunPage(
            key: ValueKey(sessionId),
            sessionId: sessionId,
            embedded: true,
            answerMessages: answerMessages,
            currentAnswer: currentAnswer,
          ),
    );
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
      if (widget.faceBuilder != null) {
        await pushHermezSheetRoute<void>(
          context,
          origin: origin,
          heightFactor: 0.88,
          builder: details,
        );
        return;
      }
      await pushHermezPanel<void>(
        context,
        origin: fixed,
        semanticLabel: 'Run details',
        surfaceColor: palette.surface,
        theme: hermezVisualTheme(Theme.of(context)),
        faceBuilder: (context, frame) => _face(context, (_) {}),
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: details(context),
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
