import 'package:flutter/material.dart';
import 'package:nib_motion/nib_motion.dart';

import '../../../shared/theme/theme_extensions.dart';
import 'hermez_motion_tokens.dart';

/// Press acknowledgement for a Hermez card or control.
///
/// The tap fires immediately. The spring is visual only and never gates the
/// action. Reduced motion keeps the hit target and skips the scale.
class HermezMotionSurface extends StatelessWidget {
  const HermezMotionSurface({
    super.key,
    required this.child,
    this.onTap,
    this.weight = HermezMotionWeight.medium,
    this.enabled = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final HermezMotionWeight weight;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final reduced = context.reduceMotion;
    final tappable = enabled && onTap != null;
    final action = onTap;
    Widget body = child;
    if (!reduced && tappable) {
      body = NibMotion(
        whileTap: NibAnim(scale: HermezMotion.pressScale(weight)),
        transition: HermezMotion.transitionFor(weight),
        child: child,
      );
    }
    if (action == null) return body;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: _TapSlop(
        enabled: tappable,
        onTap: action,
        child: body,
      ),
    );
  }
}

/// Fires [onTap] on a short press without competing with NibMotion's tap
/// recognizer or with a parent scroll view.
class _TapSlop extends StatefulWidget {
  const _TapSlop({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_TapSlop> createState() => _TapSlopState();
}

class _TapSlopState extends State<_TapSlop> {
  Offset? _down;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: widget.enabled
          ? (event) => _down = event.position
          : null,
      onPointerCancel: widget.enabled ? (_) => _down = null : null,
      onPointerUp: widget.enabled
          ? (event) {
              final start = _down;
              _down = null;
              if (start == null) return;
              if ((event.position - start).distance > 18) return;
              widget.onTap();
            }
          : null,
      child: widget.child,
    );
  }
}
