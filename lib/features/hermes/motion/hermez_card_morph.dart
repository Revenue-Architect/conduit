import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../widgets/hermez_chat_palette.dart';
import 'hermez_card_route.dart';

/// One step of a card becoming the next (docs/app-design-2026-10-30, "One
/// card"; Morphlet): the row or button that was pressed grows into the next
/// step inside the same card, and going back folds that step into the row it
/// came from. The step before blurs away underneath, never a plain fade.
///
/// [child] must carry a key that changes with the step; [depth] says which
/// way the card is going (deeper grows, shallower folds). In a full-height
/// card [raised] springs the card up for this step, or back to resting.
class HermezCardMorph extends StatefulWidget {
  const HermezCardMorph({
    super.key,
    required this.child,
    required this.depth,
    this.raised,
  });

  final Widget child;
  final int depth;
  final bool? raised;

  @override
  State<HermezCardMorph> createState() => _HermezCardMorphState();
}

class _HermezCardMorphState extends State<HermezCardMorph>
    with SingleTickerProviderStateMixin {
  late Widget _current = widget.child;
  Widget? _leaving;
  bool _forward = true;
  Rect? _rect;

  /// Where each deeper step grew from, so going back folds it there.
  final Map<int, Rect> _from = {};

  /// Each step keeps its state as it moves between the layers.
  final Map<Key?, GlobalKey> _keys = {};

  Widget _keep(Widget step) => KeyedSubtree(
    key: _keys.putIfAbsent(step.key, GlobalKey.new),
    child: step,
  );

  late final AnimationController _t =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 380),
        reverseDuration: const Duration(milliseconds: 300),
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _leaving != null) {
          setState(() {
            _leaving = null;
            _keys.removeWhere((key, _) => key != _current.key);
          });
        }
      });

  static const Curve _land = Cubic(0.34, 1.28, 0.64, 1);

  @override
  void didUpdateWidget(HermezCardMorph old) {
    super.didUpdateWidget(old);
    if (widget.raised != null && widget.raised != old.raised) {
      final detents = HermezCardDetents.maybeOf(context);
      widget.raised! ? detents?.raise() : detents?.rest();
    }
    if (widget.child.key == _current.key) {
      _current = widget.child;
      return;
    }
    _leaving = _current;
    _current = widget.child;
    _forward = widget.depth >= old.depth;
    final box = context.findRenderObject();
    final bounds = box is RenderBox && box.hasSize
        ? Offset.zero & box.size
        : null;
    Rect? rect;
    if (_forward) {
      final pressed = HermezPressOrigin.take();
      if (pressed != null && box is RenderBox && box.attached) {
        final topLeft = box.globalToLocal(pressed.$1.topLeft);
        rect = topLeft & pressed.$1.size;
      }
      if (rect != null) _from[widget.depth] = rect;
    } else {
      rect = _from.remove(old.depth);
    }
    if (bounds != null) {
      // A step with no press (or one off the card) grows from mid-card.
      rect = rect == null || !bounds.overlaps(rect)
          ? Rect.fromCenter(
              center: bounds.center,
              width: bounds.width * 0.86,
              height: bounds.height * 0.3,
            )
          : rect;
    }
    _rect = rect;
    if (MediaQuery.of(context).disableAnimations) {
      _leaving = null;
      _keys.removeWhere((key, _) => key != _current.key);
      _t.value = 1;
    } else {
      _t.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  static Widget _soft(double sigma, double opacity, Widget child) {
    final faded = Opacity(opacity: opacity.clamp(0.0, 1.0), child: child);
    return sigma < 0.3
        ? faded
        : ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: faded,
          );
  }

  @override
  Widget build(BuildContext context) {
    final leaving = _leaving;
    if (leaving == null) return _keep(_current);
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final raw = _t.value;
        // The shape travels with the springy landing; the content clears
        // on a plain ease so it never overshoots into a blur.
        final shape = _forward
            ? _land.transform(raw)
            : 1 - Curves.easeInCubic.transform(raw);
        final clear = Curves.easeOut.transform(raw);
        final grown = _forward ? _current : leaving;
        final under = _forward ? leaving : _current;
        final grownClear = _forward
            ? Curves.easeOut.transform((raw * 1.4).clamp(0.0, 1.0))
            : 1 - Curves.easeIn.transform((raw * 1.6).clamp(0.0, 1.0));
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _forward,
                child: _soft(
                  _forward ? clear * 8 : (1 - clear) * 8,
                  _forward ? 1 - clear * 0.7 : 0.3 + clear * 0.7,
                  _keep(under),
                ),
              ),
            ),
            ClipRRect(
              clipper: _MorphClip(_rect, shape),
              child: IgnorePointer(
                ignoring: !_forward,
                child: ColoredBox(
                  color: palette.raised,
                  child: _soft((1 - grownClear) * 8, grownClear, _keep(grown)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The growing step's outline: the pressed row's rect at 0, the card's
/// whole inside at 1, its corners rounding from a row's to the card's.
class _MorphClip extends CustomClipper<RRect> {
  _MorphClip(this.from, this.t);

  final Rect? from;
  final double t;

  @override
  RRect getClip(Size size) {
    final end = Offset.zero & size;
    final start = from ?? end;
    final rect = Rect.lerp(start, end, t)!;
    final radius = 16 + (24 - 16) * t.clamp(0.0, 1.0);
    return RRect.fromRectAndRadius(rect, Radius.circular(radius));
  }

  @override
  bool shouldReclip(_MorphClip old) => old.t != t || old.from != from;
}
