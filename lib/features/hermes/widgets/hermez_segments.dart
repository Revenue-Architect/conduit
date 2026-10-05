import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../feedback/hermez_feedback.dart';
import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';

/// A segmented control whose block can be tapped to or dragged: it follows
/// the finger, resists like a rubber band past either end, and settles on
/// a Hermez spring carrying the flick's speed. Label ink flips exactly
/// where the block covers it (a clip, not a fade). Adapted from SwiftPieces'
/// Glass Segments, as a bordered block rather than glass.
class HermezSegments extends StatefulWidget {
  const HermezSegments({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.height = 40,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  State<HermezSegments> createState() => _HermezSegmentsState();
}

class _HermezSegmentsState extends State<HermezSegments>
    with SingleTickerProviderStateMixin {
  // The block's position in segments: 0 is the first, n - 1 the last.
  late final AnimationController _pos = AnimationController.unbounded(
    vsync: this,
    value: widget.index.toDouble(),
  );
  bool _dragging = false;
  double _dragStart = 0;
  double _dragDx = 0;
  int _lastCrossed = 0;

  int get _last => widget.labels.length - 1;

  @override
  void didUpdateWidget(covariant HermezSegments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.index != widget.index) {
      _settle(widget.index);
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  void _settle(int target, {double velocity = 0}) {
    if (context.reduceMotion) {
      _pos.value = target.toDouble();
      return;
    }
    _pos.animateWith(
      SpringSimulation(
        HermezMotion.springMedium.toFlutter(),
        _pos.value,
        target.toDouble(),
        velocity,
      ),
    );
  }

  void _select(int i) {
    if (i == widget.index && !_dragging) return;
    HermezFeedback.play(HermezFeedbackCue.controlSelect);
    _settle(i);
    widget.onChanged(i);
  }

  /// Past either end the block moves less the further it goes.
  double _rubber(double raw) {
    double band(double over) => over * 0.55 / (1 + 0.55 * over.abs());
    if (raw < 0) return band(raw);
    if (raw > _last) return _last + band(raw - _last);
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final n = widget.labels.length;
    return Container(
      height: widget.height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / n;
          Widget labels({required bool selected}) => Row(
            children: [
              for (final label in widget.labels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? palette.ink : palette.muted,
                        fontSize: 13.5,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _select(
              (details.localPosition.dx / width).floor().clamp(0, _last),
            ),
            onHorizontalDragStart: (details) {
              final at = details.localPosition.dx / width;
              // Only the block itself is grabbed; elsewhere a drag is
              // a tap that wandered.
              if ((at - 0.5 - _pos.value).abs() > 0.5) return;
              _pos.stop();
              setState(() => _dragging = true);
              _dragStart = _pos.value;
              _dragDx = 0;
              _lastCrossed = _pos.value.round().clamp(0, _last);
            },
            onHorizontalDragUpdate: (details) {
              if (!_dragging) return;
              _dragDx += details.delta.dx;
              _pos.value = _rubber(_dragStart + _dragDx / width);
              final crossed = _pos.value.round().clamp(0, _last);
              if (crossed != _lastCrossed) {
                _lastCrossed = crossed;
                HermezFeedback.play(HermezFeedbackCue.controlSelect);
              }
            },
            onHorizontalDragEnd: (details) {
              if (!_dragging) return;
              final velocity = details.velocity.pixelsPerSecond.dx / width;
              // Where the flick was heading, a fifth of a second on.
              final target = (_pos.value + velocity * 0.2).round().clamp(
                0,
                _last,
              );
              setState(() => _dragging = false);
              _settle(target, velocity: velocity);
              if (target != widget.index) widget.onChanged(target);
            },
            onHorizontalDragCancel: () {
              if (!_dragging) return;
              setState(() => _dragging = false);
              _settle(widget.index);
            },
            child: AnimatedBuilder(
              animation: _pos,
              builder: (context, _) {
                final left = _pos.value * width;
                final block = Rect.fromLTWH(
                  left,
                  0,
                  width,
                  constraints.maxHeight,
                );
                return Stack(
                  children: [
                    Positioned.fromRect(
                      rect: block,
                      child: AnimatedScale(
                        // Lifts a touch while held.
                        scale: _dragging ? 1.03 : 1,
                        duration: HermezMotion.settleFor(
                          HermezMotionWeight.light,
                        ),
                        curve: HermezMotion.curveLight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: palette.border),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: ExcludeSemantics(child: labels(selected: false)),
                    ),
                    Positioned.fill(
                      child: ClipRect(
                        clipper: _RectClipper(block),
                        child: ExcludeSemantics(child: labels(selected: true)),
                      ),
                    ),
                    // Each segment says what it is, and which one is on.
                    Positioned.fill(
                      child: Row(
                        children: [
                          for (final (i, label) in widget.labels.indexed)
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: i == widget.index,
                                label: label,
                                onTap: () => _select(i),
                                child: const SizedBox.expand(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _RectClipper extends CustomClipper<Rect> {
  const _RectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_RectClipper old) => old.rect != rect;
}
