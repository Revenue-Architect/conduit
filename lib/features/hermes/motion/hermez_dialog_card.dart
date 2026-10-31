import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:flutter/material.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_dialog_route.dart';
import '../widgets/hermez_chat_palette.dart';
import 'hermez_card_route.dart';

/// Opens dialog content as the one card on Android (forms, questions and
/// errors; docs/app-design-2026-10-30/POPUPS-PLAN.md patterns A and B),
/// grown out of the control that was pressed. With [barrierDismissible]
/// false it must be answered: the scrim does nothing and there's no grabber.
/// iOS keeps the shared dialog route.
Future<T?> showHermezDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  if (!PlatformUiCapabilities.isIOS &&
      Theme.of(context).platform != TargetPlatform.iOS) {
    return pushHermezCard<T>(
      context,
      dismissible: barrierDismissible,
      builder: builder,
    );
  }
  return showConduitDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}

/// A dialog's title, content and actions. In the one card it is the card's
/// own content (title, body, answers on the right); anywhere else it is the
/// [AlertDialog] it replaces, with the same arguments.
class HermezDialogBody extends StatelessWidget {
  const HermezDialogBody({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.scrollable = false,
    this.backgroundColor,
    this.surfaceTintColor,
    this.shape,
    this.titleTextStyle,
    this.contentTextStyle,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  /// The rest only apply to the [AlertDialog]; the card scrolls and styles
  /// itself.
  final bool scrollable;
  final Color? backgroundColor;
  final Color? surfaceTintColor;
  final ShapeBorder? shape;
  final TextStyle? titleTextStyle;
  final TextStyle? contentTextStyle;

  @override
  Widget build(BuildContext context) {
    if (!HermezCardScope.within(context)) {
      return AlertDialog(
        title: title,
        content: content,
        actions: actions,
        scrollable: scrollable,
        backgroundColor: backgroundColor,
        surfaceTintColor: surfaceTintColor,
        shape: shape,
        titleTextStyle: titleTextStyle,
        contentTextStyle: contentTextStyle,
      );
    }
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final answers = actions ?? const <Widget>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            DefaultTextStyle.merge(
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.25,
                letterSpacing: -0.3,
                color: palette.ink,
              ),
              child: title!,
            ),
          if (content != null) ...[
            if (title != null) const SizedBox(height: 10),
            DefaultTextStyle.merge(
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 15,
                height: 1.45,
                color: palette.muted,
              ),
              child: content!,
            ),
          ],
          if (answers.isNotEmpty) ...[
            const SizedBox(height: 18),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 4,
              children: answers,
            ),
          ],
        ],
      ),
    );
  }
}
