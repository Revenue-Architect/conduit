import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/theme/theme_extensions.dart';
import 'hermez_motion_tokens.dart';

/// Hermez page transition. The shared element, when one exists, is the motion.
/// This shell only establishes the destination and lets the source recede.
Page<void> buildHermezMotionPage({
  required LocalKey pageKey,
  required Widget child,
  String? name,
  HermezRouteMotion motion = HermezRouteMotion.standard,
  bool reducedMotion = false,
}) {
  final duration = reducedMotion
      ? const Duration(milliseconds: 120)
      : const Duration(milliseconds: 380);
  return CustomTransitionPage<void>(
    key: pageKey,
    name: name,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
      return buildHermezRouteTransition(
        context: context,
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        motion: motion,
        child: pageChild,
      );
    },
  );
}

Widget buildHermezRouteTransition({
  required BuildContext context,
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required HermezRouteMotion motion,
  required Widget child,
}) {
  if (context.reduceMotion) {
    return FadeTransition(opacity: animation, child: child);
  }
  final incoming = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  final outgoing = CurvedAnimation(
    parent: secondaryAnimation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  final beginOffset = switch (motion) {
    HermezRouteMotion.sharedAxis => const Offset(0.035, 0),
    HermezRouteMotion.morph => Offset.zero,
    HermezRouteMotion.modal => const Offset(0, 0.02),
    HermezRouteMotion.standard => const Offset(0, 0.012),
  };
  final beginScale = motion == HermezRouteMotion.morph ? 1.0 : 0.992;
  return FadeTransition(
    opacity: motion == HermezRouteMotion.morph
        ? const AlwaysStoppedAnimation<double>(1)
        : incoming,
    child: SlideTransition(
      position: Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(
        incoming,
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: beginScale, end: 1).animate(incoming),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 1,
            end: HermezMotion.sourceBackgroundScale,
          ).animate(outgoing),
          child: FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.94).animate(outgoing),
            child: child,
          ),
        ),
      ),
    ),
  );
}
