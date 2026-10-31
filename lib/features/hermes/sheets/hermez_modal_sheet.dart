import 'package:flutter/material.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../motion/hermez_card_route.dart';
import '../motion/hermez_motion.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_surfaces.dart';
import '../widgets/hermez_visual_theme.dart';

/// Shared detail sheet. Existing callers keep [showHermezSheet].
typedef HermezDetailSheet = HermezModalSheet;

/// Opens a Hermez sheet as the one card, grown out of the control that was
/// pressed. Long, scrolling content gets the full-height card (it rests and
/// springs up); with [fit] short content (a picker, a small form, a summary)
/// gets the card sized to it. Dismissing it never implies a backend action;
/// callers must resolve requests explicitly.
Future<T?> showHermezSheet<T>(
  BuildContext context, {
  required String title,
  String? eyebrow,
  required Widget body,
  Widget? footer,
  HermezMorphOrigin? origin,
  String? titleMorphId,
  Widget? leading,
  Widget? subtitle,
  bool fit = false,
}) => pushHermezSheetRoute<T>(
  context,
  origin: origin,
  fit: fit,
  builder: (_) => HermezModalSheet(
    title: title,
    eyebrow: eyebrow,
    body: body,
    footer: footer,
    titleMorphId: titleMorphId,
    leading: leading,
    subtitle: subtitle,
  ),
);

/// Pushes any Hermez sheet content on the Hermez sheet route.
Future<T?> pushHermezSheetRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  HermezMorphOrigin? origin,
  double heightFactor = 0.91,
  bool fit = false,
}) {
  Widget themed(BuildContext sheetContext) => Theme(
    data: hermezVisualTheme(Theme.of(sheetContext)),
    child: builder(sheetContext),
  );
  if (fit) {
    return pushHermezCard<T>(
      context,
      origin: origin,
      builder: themed,
      scrollsContent: false,
    );
  }
  return pushHermezSheet<T>(
    context,
    origin: origin,
    heightFactor: heightFactor,
    reducedMotion: context.reduceMotion,
    builder: themed,
  );
}

class HermezModalSheet extends StatelessWidget {
  const HermezModalSheet({
    super.key,
    required this.title,
    this.eyebrow,
    required this.body,
    this.footer,
    this.titleMorphId,
    this.leading,
    this.subtitle,
  });

  final String title;
  final String? eyebrow;
  final Widget body;
  final Widget? footer;

  /// Lets the title arrive from the row or card that opened the sheet.
  final String? titleMorphId;

  /// An identity tile beside the title (a bot mark, a file icon).
  final Widget? leading;

  /// A line under the title, such as who powers a scheduled agent.
  final Widget? subtitle;

  static TextStyle titleStyle(HermezChatPalette palette) =>
      HermezType.display(palette).copyWith(fontSize: 28);

  @override
  Widget build(BuildContext sheetContext) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(sheetContext).brightness,
    );
    return Theme(
      data: hermezVisualTheme(Theme.of(sheetContext)),
      child: Material(
        color: palette.raised,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _layout(sheetContext, palette, fit: !constraints.hasTightHeight),
        ),
      ),
    );
  }

  Widget _layout(
    BuildContext sheetContext,
    HermezChatPalette palette, {
    required bool fit,
  }) {
    const bodyPadding = EdgeInsets.fromLTRB(20, 10, 20, 20);
    return Column(
      mainAxisSize: fit ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: fit
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: [
        if (!fit) ...[
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: palette.ink.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ],
        Padding(
          padding: EdgeInsets.fromLTRB(22, fit ? 8 : 16, 14, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
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
                            Flexible(
                              child: Text(
                                eyebrow!.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HermezType.technical(palette.ink)
                                    .copyWith(letterSpacing: 2.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    HermezMorphText(
                      title,
                      id: titleMorphId,
                      maxLines: 3,
                      style: titleStyle(palette),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      subtitle!,
                    ],
                  ],
                ),
              ),
              IgnorePointer(
                child: CustomPaint(
                  size: const Size(28, 36),
                  painter: _SheetSlashPainter(palette.accent),
                ),
              ),
              _CloseDisc(onPressed: () => Navigator.pop(sheetContext)),
            ],
          ),
        ),
        // Content-sized, the body scrolls only once it outgrows the card;
        // the title and the footer's buttons stay put either way.
        if (fit)
          Flexible(
            child: SingleChildScrollView(padding: bodyPadding, child: body),
          )
        else
          Expanded(
            child: SingleChildScrollView(padding: bodyPadding, child: body),
          ),
        if (footer != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: footer,
            ),
          ),
      ],
    );
  }
}

class _CloseDisc extends StatelessWidget {
  const _CloseDisc({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Tooltip(
      message: 'Close',
      child: HermezMotionSurface(
        weight: HermezMotionWeight.light,
        semanticLabel: 'Close',
        onTap: onPressed,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: palette.canvas,
            shape: BoxShape.circle,
            border: Border.all(color: palette.border.withValues(alpha: 0.7)),
          ),
          child: Icon(Icons.close_rounded, color: palette.ink, size: 22),
        ),
      ),
    );
  }
}

class _SheetSlashPainter extends CustomPainter {
  const _SheetSlashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.85),
      Offset(size.width * 0.85, size.height * 0.1),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SheetSlashPainter oldDelegate) =>
      color != oldDelegate.color;
}
