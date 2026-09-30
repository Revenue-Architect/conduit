import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';


import 'package:flutter/physics.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../motion/hermez_motion_tokens.dart';
import 'hermez_chat_palette.dart';

/// Light hitting a physical surface where the finger is.
///
/// A small local highlight and a brighter stretch of the border follow the
/// finger; on release, cancel, or once the touch turns into a scroll, the
/// light draws back to nothing on the Hermez light spring. Only the light's
/// radius and position move (static alpha, no fades). Pointer tracking is a
/// translucent [Listener], so it never joins the gesture arena: taps,
/// scrolls, and the surface's own press are untouched. Off with reduced
/// motion.
class HermezTouchLight extends StatefulWidget {
  const HermezTouchLight({
    super.key,
    required this.child,
    required this.borderRadius,
    this.dark = false,
    this.accent,
  });

  final Widget child;
  final double borderRadius;

  /// A dark technical surface: a graphite highlight and an orange edge.
  final bool dark;

  /// Edge color on dark surfaces.
  final Color? accent;

  /// How far the light reaches from the finger, in logical px.
  static const double reach = 72;

  @override
  State<HermezTouchLight> createState() => _HermezTouchLightState();
}

class _HermezTouchLightState extends State<HermezTouchLight>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<Offset?> _finger = ValueNotifier<Offset?>(null);
  late final AnimationController _radius = AnimationController.unbounded(
    vsync: this,
  );
  Offset? _down;
  int? _pointer;

  @override
  void dispose() {
    _finger.dispose();
    _radius.dispose();
    super.dispose();
  }

  void _to(double target) {
    _radius.animateWith(
      SpringSimulation(
        HermezMotion.springLight.toFlutter(),
        _radius.value,
        target,
        _radius.velocity,
      ),
    );
  }

  void _onDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _down = event.localPosition;
    _finger.value = event.localPosition;
    _to(1);
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final down = _down;
    if (down != null &&
        (event.localPosition - down).distance > HermezMotion.pressSlop) {
      // The touch became a scroll or a drag: the light leaves with it.
      _release();
      return;
    }
    _finger.value = event.localPosition;
  }

  void _release([PointerEvent? event]) {
    if (event != null && event.pointer != _pointer) return;
    _pointer = null;
    _down = null;
    _to(0);
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _release,
      onPointerCancel: _release,
      child: CustomPaint(
        foregroundPainter: _LightPainter(
          finger: _finger,
          radius: _radius,
          borderRadius: widget.borderRadius,
          dark: widget.dark,
          accent:
              widget.accent ??
              HermezChatPalette.forBrightness(Theme.of(context).brightness)
                  .accent,
        ),
        child: widget.child,
      ),
    );
  }
}

class _LightPainter extends CustomPainter {
  _LightPainter({
    required this.finger,
    required this.radius,
    required this.borderRadius,
    required this.dark,
    required this.accent,
  }) : super(repaint: Listenable.merge([finger, radius]));

  final ValueListenable<Offset?> finger;
  final Animation<double> radius;
  final double borderRadius;
  final bool dark;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final at = finger.value;
    final r = radius.value.clamp(0.0, 1.2) * HermezTouchLight.reach;
    if (at == null || r < 1) return;
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );
    canvas
      ..save()
      ..clipRRect(shape);
    // Surface reflection near the finger (static alpha). A white shell
    // cannot get brighter than white, so light surfaces take a faint warm
    // reflection of the Hermez signal color; dark ones a graphite sheen.
    final sheen = dark
        ? const Color(0x2EC9CDD3)
        : accent.withValues(alpha: 0.075);
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..shader = ui.Gradient.radial(at, r, [
          sheen,
          sheen.withValues(alpha: 0),
        ]),
    );
    canvas.restore();
    // The border catches the light where the finger is.
    final edge = dark
        ? accent
        : Color.lerp(accent, const Color(0xFF6B7078), 0.45)!;
    canvas.drawRRect(
      shape.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = ui.Gradient.radial(at, r * 1.35, [
          edge.withValues(alpha: dark ? 0.85 : 0.7),
          edge.withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(_LightPainter oldDelegate) =>
      oldDelegate.dark != dark ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.accent != accent ||
      !identical(oldDelegate.finger, finger) ||
      !identical(oldDelegate.radius, radius);
}
