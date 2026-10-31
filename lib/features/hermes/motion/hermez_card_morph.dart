import 'package:flutter/material.dart';

import 'hermez_card_route.dart';

/// How long one step takes to become the next. A form focuses its first
/// field after this, so the keyboard doesn't reshape the card mid-change.
const kHermezCardMorphDuration = Duration(milliseconds: 200);

/// One step of a card becoming the next (docs/app-design-2026-10-30, "One
/// card"), timed to the owner's Morphlet reference recording: the step
/// changes in place in a fifth of a second, the old one dissolving as the new
/// one rises a few points into it, while the card springs to the new step's
/// height. Nothing grows out of the pressed row; the card itself is the
/// thing that reshapes.
///
/// [child] must carry a key that changes with the step; [depth] says which
/// way the card is going (deeper rises from below, back settles from above).
/// In a full-height card [raised] springs the card up for this step, or back
/// to resting.
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

  /// Each step keeps its state as it moves between the layers.
  final Map<Key?, GlobalKey> _keys = {};

  Widget _keep(Widget step) => KeyedSubtree(
    key: _keys.putIfAbsent(step.key, GlobalKey.new),
    child: step,
  );

  late final AnimationController _t =
      AnimationController(
        vsync: this,
        duration: kHermezCardMorphDuration,
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _leaving != null) {
          setState(() {
            _leaving = null;
            _keys.removeWhere((key, _) => key != _current.key);
          });
        }
      });

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
    if (MediaQuery.of(context).disableAnimations) {
      _leaving = null;
      _keys.removeWhere((key, _) => key != _current.key);
      _t.value = 1;
      return;
    }
    // The new step's first build is the heavy frame. Hold the change at its
    // start through it and run from the next frame, so that frame doesn't
    // eat the opening of the motion and make it jump.
    _t.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _leaving != null) _t.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  static const Curve _out = Cubic(0.23, 1, 0.32, 1);

  @override
  Widget build(BuildContext context) {
    final leaving = _leaving;
    if (leaving == null) return _keep(_current);
    // Compositor only per frame: two opacities and one offset follow [_t];
    // neither step rebuilds or repaints, and nothing is blurred.
    final out = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _t,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      ),
    );
    final into = CurvedAnimation(
      parent: _t,
      curve: const Interval(0.1, 1, curve: _out),
    );
    final rise = Tween<Offset>(
      begin: Offset(0, _forward ? 10 : -10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _t, curve: _out));
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: FadeTransition(
              opacity: out,
              child: RepaintBoundary(child: _keep(leaving)),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: rise,
          builder: (context, child) =>
              Transform.translate(offset: rise.value, child: child),
          child: FadeTransition(
            opacity: into,
            child: RepaintBoundary(child: _keep(_current)),
          ),
        ),
      ],
    );
  }
}
