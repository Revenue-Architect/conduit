import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nib_motion/nib_motion.dart';

import '../../../core/services/haptic_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'hermez_morph_origin.dart';
import 'hermez_motion_tokens.dart';

/// A physical Hermez card or control.
///
/// The surface compresses the moment a finger lands, before the gesture arena
/// decides whether this is a tap or a scroll, and springs back when the finger
/// lifts or starts to scroll. The action fires on a real tap only and is never
/// delayed by the spring.
///
/// [onOpen] receives where this surface sits so the destination can grow out
/// of it. Reduced motion keeps the hit target and the action and skips the
/// compression.
class HermezMotionSurface extends StatefulWidget {
  const HermezMotionSurface({
    super.key,
    required this.child,
    this.onTap,
    this.onOpen,
    this.onLongPress,
    this.weight = HermezMotionWeight.medium,
    this.enabled = true,
    this.semanticLabel,
    this.originRadius = 18,
    this.originColor,
    this.originBorderColor,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Like [onTap], with the surface's current position for an expanding
  /// destination. When both are set only [onOpen] runs.
  final ValueChanged<HermezMorphOrigin?>? onOpen;
  final VoidCallback? onLongPress;
  final HermezMotionWeight weight;
  final bool enabled;
  final String? semanticLabel;
  final double originRadius;
  final Color? originColor;
  final Color? originBorderColor;
  final bool haptic;

  @override
  State<HermezMotionSurface> createState() => _HermezMotionSurfaceState();
}

class _HermezMotionSurfaceState extends State<HermezMotionSurface> {
  final NibMotionController _press = NibMotionController();
  Offset? _down;
  bool _pressed = false;

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onOpen != null);

  @override
  void didUpdateWidget(covariant HermezMotionSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_interactive && _pressed) _release();
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _compress() {
    if (_pressed || context.reduceMotion) return;
    _pressed = true;
    unawaited(
      _press.start(
        target: NibAnim(scale: HermezMotion.pressScale(widget.weight)),
        transition: HermezMotion.transitionFor(HermezMotionWeight.light),
      ),
    );
  }

  void _release() {
    _down = null;
    if (!_pressed) return;
    _pressed = false;
    unawaited(
      _press.start(
        target: const NibAnim(scale: 1),
        transition: HermezMotion.transitionFor(widget.weight),
      ),
    );
  }

  void _activate() {
    if (!_interactive) return;
    _release();
    if (widget.haptic) unawaited(ConduitHaptics.selectionClick());
    final open = widget.onOpen;
    if (open != null) {
      open(
        HermezMorphOrigin.of(
          context,
          radius: widget.originRadius,
          color: widget.originColor,
          borderColor: widget.originBorderColor,
        ),
      );
      return;
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final interactive = _interactive;
    Widget body = NibMotion(controller: _press, child: widget.child);
    if (!interactive && widget.onLongPress == null) return body;
    body = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: interactive
          ? (event) {
              _down = event.position;
              _compress();
            }
          : null,
      onPointerMove: interactive
          ? (event) {
              final start = _down;
              if (start == null) return;
              if ((event.position - start).distance > HermezMotion.pressSlop) {
                _release();
              }
            }
          : null,
      onPointerUp: interactive ? (_) => _release() : null,
      onPointerCancel: interactive ? (_) => _release() : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: interactive ? _activate : null,
        onTapCancel: interactive ? _release : null,
        onLongPress: widget.onLongPress,
        child: body,
      ),
    );
    return Semantics(
      container: true,
      button: true,
      enabled: interactive,
      label: widget.semanticLabel,
      onTap: interactive ? _activate : null,
      onLongPress: widget.onLongPress,
      child: FocusableActionDetector(
        enabled: interactive,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: body,
      ),
    );
  }
}
