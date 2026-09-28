import 'package:flutter/material.dart';
import 'package:nib_motion/nib_motion.dart';

import '../../../shared/theme/theme_extensions.dart';
import 'hermez_motion_tokens.dart';

/// Enter and leave for a widget that really mounts and unmounts.
///
/// [presenceKey] must stay stable for that object. Rebuilds that keep the same
/// key do not replay the entrance.
class HermezPresence extends StatelessWidget {
  const HermezPresence({
    super.key,
    required this.presenceKey,
    required this.child,
    this.weight = HermezMotionWeight.light,
  });

  final Key presenceKey;
  final Widget? child;
  final HermezMotionWeight weight;

  @override
  Widget build(BuildContext context) {
    final reduced = context.reduceMotion;
    final current = child;
    return NibPresence(
      children: [
        if (current != null)
          NibMotion(
            key: presenceKey,
            initial: reduced ? null : const NibAnim(opacity: 0, y: 8),
            animate: const NibAnim(opacity: 1, y: 0),
            exit: reduced
                ? const NibAnim(opacity: 0)
                : const NibAnim(opacity: 0, y: 4),
            transition: reduced
                ? const NibTransition(duration: Duration(milliseconds: 90))
                : HermezMotion.transitionFor(weight),
            child: current,
          ),
      ],
    );
  }
}

/// FLIP reflow for a small set of keyed children. Do not wrap a long scroll view.
class HermezMotionGroup extends StatelessWidget {
  const HermezMotionGroup({
    super.key,
    required this.children,
    this.weight = HermezMotionWeight.medium,
  });

  final List<Widget> children;
  final HermezMotionWeight weight;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return NibLayoutGroup(
      transition: HermezMotion.transitionFor(weight),
      children: children,
    );
  }
}
