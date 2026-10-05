import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'hermez_chat_palette.dart';
import 'hermez_live.dart';

/// One clock for every sweeping band on screen (skeletons, the live sheen),
/// so they all move in phase. Driven by a per-widget ticker that reads the
/// shared frame time; still under tests and reduced motion.
mixin _HermezSweep<T extends StatefulWidget> on State<T>, TickerProvider {
  static const period = Duration(milliseconds: 1600);

  final ValueNotifier<double> sweepPhase = ValueNotifier(0.5);
  Ticker? _ticker;

  bool get sweepActive;

  void syncSweep() {
    final run = sweepActive && HermezLiveMotion.on(context);
    if (run) {
      _ticker ??= createTicker((_) {
        final now = SchedulerBinding.instance.currentFrameTimeStamp;
        sweepPhase.value =
            (now.inMicroseconds % period.inMicroseconds) /
            period.inMicroseconds;
      });
      if (!_ticker!.isActive) _ticker!.start();
    } else {
      _ticker?.stop();
      // At rest the band sits mid-way, as if paused.
      sweepPhase.value = 0.5;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncSweep();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    sweepPhase.dispose();
    super.dispose();
  }
}

/// Slides a gradient whose band sits at its centre from fully off the
/// leading edge to fully off the trailing edge, tilted 18 degrees.
class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.phase, this.band);

  final double phase;
  final double band;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final travel = bounds.width + band;
    final dx = -travel / 2 + travel * phase;
    final c = bounds.center;
    return Matrix4.translationValues(c.dx, c.dy, 0)
      ..multiply(Matrix4.rotationZ(18 * math.pi / 180))
      ..multiply(Matrix4.translationValues(dx - c.dx, -c.dy, 0));
  }
}

Shader _sweepShader(Rect bounds, double phase, Color base, Color highlight) {
  final width = math.max(bounds.width, 1.0);
  final band = math.max(72.0, width * 0.45);
  final half = (band / width / 2).clamp(0.0, 0.49);
  return LinearGradient(
    colors: [base, base, highlight, base, base],
    stops: [0, 0.5 - half, 0.5, 0.5 + half, 1],
    transform: _SweepTransform(phase, band),
  ).createShader(bounds);
}

/// Placeholder bones for content on its way, one band sweeping across
/// them. The band only lights the bones (it is masked by them), and every
/// skeleton on screen sweeps in phase. Content replaces it in place; nothing
/// fades. Adapted from SwiftPieces' Skeleton Loader.
class HermezSkeleton extends StatefulWidget {
  const HermezSkeleton({super.key, required this.child});

  /// Rows of a typical list: a leading mark, a title and a line under it.
  factory HermezSkeleton.rows({Key? key, int count = 4, bool leading = true}) =>
      HermezSkeleton(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < count; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  children: [
                    if (leading) ...[
                      const HermezBone.circle(size: 30),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Varied lengths read as real titles, not a grid.
                          HermezBone(
                            widthFactor: const [0.62, 0.48, 0.7, 0.55][i % 4],
                          ),
                          const SizedBox(height: 8),
                          HermezBone(
                            height: 10,
                            widthFactor: const [0.38, 0.3, 0.42, 0.34][i % 4],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  /// A paragraph: full lines, the last one short.
  factory HermezSkeleton.lines({Key? key, int count = 3}) => HermezSkeleton(
    key: key,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: 9),
          HermezBone(widthFactor: i == count - 1 ? 0.62 : 1),
        ],
      ],
    ),
  );

  final Widget child;

  @override
  State<HermezSkeleton> createState() => _HermezSkeletonState();
}

class _HermezSkeletonState extends State<HermezSkeleton>
    with SingleTickerProviderStateMixin, _HermezSweep {
  @override
  bool get sweepActive => true;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final base = palette.ink.withValues(alpha: 0.075);
    final highlight = palette.ink.withValues(alpha: 0.15);
    return Semantics(
      label: 'Loading',
      excludeSemantics: true,
      child: ValueListenableBuilder<double>(
        valueListenable: sweepPhase,
        // The bones are only a mask: the sweep paints them, so the band
        // never touches the space between them.
        builder: (context, phase, child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) =>
              _sweepShader(bounds, phase, base, highlight),
          child: child,
        ),
        child: _BoneColor(color: Colors.white, child: widget.child),
      ),
    );
  }
}

class _BoneColor extends InheritedWidget {
  const _BoneColor({required this.color, required super.child});

  final Color color;

  @override
  bool updateShouldNotify(_BoneColor old) => old.color != color;
}

/// One placeholder shape inside a [HermezSkeleton].
class HermezBone extends StatelessWidget {
  const HermezBone({
    super.key,
    this.height = 13,
    this.width,
    this.widthFactor = 1,
    this.radius = 6,
  });

  const HermezBone.circle({super.key, required double size})
    : height = size,
      width = size,
      widthFactor = 1,
      radius = size / 2;

  final double height;
  final double? width;
  final double widthFactor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color =
        context.dependOnInheritedWidgetOfExactType<_BoneColor>()?.color ??
        Colors.grey.withValues(alpha: 0.15);
    final bone = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return width != null
        ? bone
        : FractionallySizedBox(widthFactor: widthFactor, child: bone);
  }
}

/// A light band travelling through [child]'s glyphs while [active]: work is
/// in progress. The band lights what is drawn and nothing else. Adapted
/// from the text form of SwiftPieces' Thinking State.
class HermezSheen extends StatefulWidget {
  const HermezSheen({super.key, required this.child, this.active = true});

  final Widget child;
  final bool active;

  @override
  State<HermezSheen> createState() => _HermezSheenState();
}

class _HermezSheenState extends State<HermezSheen>
    with SingleTickerProviderStateMixin, _HermezSweep {
  @override
  bool get sweepActive => widget.active;

  @override
  void didUpdateWidget(covariant HermezSheen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) syncSweep();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || !HermezLiveMotion.on(context)) return widget.child;
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    // Lifts the glyphs toward the canvas inside the band; the text keeps
    // its own colour everywhere else.
    final highlight = palette.canvas.withValues(alpha: 0.55);
    return ValueListenableBuilder<double>(
      valueListenable: sweepPhase,
      builder: (context, phase, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) =>
            _sweepShader(bounds, phase, Colors.transparent, highlight),
        child: child,
      ),
      child: widget.child,
    );
  }
}
