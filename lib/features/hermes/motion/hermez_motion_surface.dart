import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:nib_motion/nib_motion.dart';

import '../../../core/services/haptic_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../feedback/hermez_feedback.dart';
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
    this.feedbackCue,
    this.semanticsExpanded,
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

  /// Optional sound + haptic for a confirmed tap (never on pointer down, so a
  /// scroll that starts on the surface stays silent). When set, its haptic
  /// replaces the default selection tick. Fire and forget: the action never
  /// waits for it.
  final HermezFeedbackCue? feedbackCue;

  /// For a control that opens and closes something in place: whether it is
  /// open, announced as the button's expanded state.
  final bool? semanticsExpanded;

  @override
  State<HermezMotionSurface> createState() => _HermezMotionSurfaceState();
}

class _HermezMotionSurfaceState extends State<HermezMotionSurface> {
  final NibMotionController _press = NibMotionController();
  final GlobalKey _face = GlobalKey();
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
    final open = widget.onOpen;
    // Captured before the release so it is the object as it was drawn.
    final snapshot = open == null ? null : _captureFace();
    _release();
    final cue = widget.feedbackCue;
    if (cue != null) {
      HermezFeedback.play(cue);
    } else if (widget.haptic) {
      unawaited(ConduitHaptics.selectionClick());
    }
    if (open != null) {
      open(
        HermezMorphOrigin.of(
          context,
          radius: widget.originRadius,
          color: widget.originColor,
          borderColor: widget.originBorderColor,
          snapshot: snapshot,
        ),
      );
      return;
    }
    widget.onTap?.call();
  }

  /// The surface's own drawing at its own size, unscaled by the press.
  ui.Image? _captureFace() {
    final boundary = _face.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return null;
    try {
      return boundary.toImageSync(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactive = _interactive;
    Widget body = NibMotion(
      controller: _press,
      child: widget.onOpen == null
          ? widget.child
          : RepaintBoundary(key: _face, child: widget.child),
    );
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
      expanded: widget.semanticsExpanded,
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
