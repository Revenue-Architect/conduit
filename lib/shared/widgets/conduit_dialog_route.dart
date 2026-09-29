import 'package:flutter/widgets.dart';

import '../../features/hermes/motion/hermez_motion_route.dart'
    show hermezCurved;
import '../../features/hermes/motion/hermez_motion_tokens.dart';

/// A dialog route with no opacity animation.
///
/// Flutter's `showDialog` fades the dialog in and out. This route unfolds the
/// dialog from its center line on a spring and folds it away on close, so a
/// dialog behaves like a physical panel. The dialog inherits the themes of
/// the context that opened it, like `showDialog`.
class ConduitDialogRoute<T> extends RawDialogRoute<T> {
  ConduitDialogRoute({
    required BuildContext context,
    required WidgetBuilder builder,
    super.barrierDismissible = true,
    super.barrierColor = const Color(0x8A000000),
    super.barrierLabel = 'Dismiss',
    bool useSafeArea = true,
    bool useRootNavigator = true,
    super.settings,
  }) : super(
         pageBuilder: (buildContext, animation, secondaryAnimation) {
           final themes = InheritedTheme.capture(
             from: context,
             to: Navigator.of(context, rootNavigator: useRootNavigator).context,
           );
           Widget dialog = Builder(builder: builder);
           if (useSafeArea) dialog = SafeArea(child: dialog);
           return themes.wrap(dialog);
         },
         transitionDuration: _reduced(context)
             ? Duration.zero
             : HermezMotion.settleFor(HermezMotionWeight.medium),
         transitionBuilder: _unfold,
       );

  static bool _reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Widget _unfold(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final settle = hermezCurved(
      animation,
      HermezMotion.curveMedium,
      reverseOf: HermezMotion.curveLight,
    );
    return AnimatedBuilder(
      animation: settle,
      child: child,
      builder: (context, child) {
        final t = settle.value.clamp(0.0, 1.0);
        // The same wrappers at rest as in flight: dropping them when the
        // unfold finished remounted the dialog (and its focused field).
        return ClipRect(
          clipper: _CenterBand(t),
          clipBehavior: t >= 1 ? Clip.none : Clip.hardEdge,
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
        );
      },
    );
  }
}

/// Shows a dialog on a [ConduitDialogRoute]. Same contract as `showDialog`.
Future<T?> showConduitDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  bool useSafeArea = true,
}) => Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
  ConduitDialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    useSafeArea: useSafeArea,
  ),
);

class _CenterBand extends CustomClipper<Rect> {
  const _CenterBand(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) {
    final height = size.height * fraction;
    return Rect.fromLTWH(0, (size.height - height) / 2, size.width, height);
  }

  @override
  bool shouldReclip(_CenterBand oldClipper) => oldClipper.fraction != fraction;
}
