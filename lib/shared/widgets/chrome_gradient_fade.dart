import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../theme/theme_extensions.dart';

const double kConduitChromeFadeHeight = 30.0;

enum ConduitChromeFadeEdge { top, bottom }

/// Chrome edge used when custom Flutter bars replace native bars.
///
/// By default it is a gradient only: transparent custom chrome gets the same
/// soft scroll-edge separation as the adaptive bars while the content under
/// it stays readable. With [blurSigma] the content under the chrome is also
/// frosted, fully behind the bar and easing off through the fade, so floating
/// controls never sit on readable text.
class ConduitChromeGradientFade extends StatelessWidget {
  const ConduitChromeGradientFade({
    super.key,
    required this.edge,
    required this.contentHeight,
    this.fadeHeight = kConduitChromeFadeHeight,
    this.backgroundColor,
    this.blurSigma = 0,
    this.blurExtent,
  });

  const ConduitChromeGradientFade.top({
    super.key,
    required this.contentHeight,
    this.fadeHeight = kConduitChromeFadeHeight,
    this.backgroundColor,
    this.blurSigma = 0,
    this.blurExtent,
  }) : edge = ConduitChromeFadeEdge.top;

  const ConduitChromeGradientFade.bottom({
    super.key,
    required this.contentHeight,
    this.fadeHeight = kConduitChromeFadeHeight,
    this.backgroundColor,
    this.blurSigma = 0,
    this.blurExtent,
  }) : edge = ConduitChromeFadeEdge.bottom;

  final ConduitChromeFadeEdge edge;
  final double contentHeight;
  final double fadeHeight;
  final Color? backgroundColor;

  /// Frost under the chrome, as a Gaussian sigma at the outer edge. Zero
  /// keeps the edge gradient-only.
  final double blurSigma;

  /// How far from the edge the frost has fully faded out. Defaults to the
  /// whole edge (chrome plus fade); the chat screen ends it just under its
  /// floating controls.
  final double? blurExtent;

  @override
  Widget build(BuildContext context) {
    final baseColor = backgroundColor ?? context.conduitTheme.surfaceBackground;
    final height = contentHeight + fadeHeight;
    final colors = edge == ConduitChromeFadeEdge.top
        ? [
            baseColor.withValues(alpha: 0.92),
            baseColor.withValues(alpha: 0.72),
            baseColor.withValues(alpha: 0.28),
            baseColor.withValues(alpha: 0.0),
          ]
        : [
            baseColor.withValues(alpha: 0.0),
            baseColor.withValues(alpha: 0.28),
            baseColor.withValues(alpha: 0.72),
            baseColor.withValues(alpha: 0.92),
          ];

    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: const [0.0, 0.3, 0.65, 1.0],
        ),
      ),
    );
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: blurSigma <= 0
            ? gradient
            : Stack(
                fit: StackFit.expand,
                children: [
                  _ProgressiveBlur(
                    edge: edge,
                    sigma: blurSigma,
                    extent: (blurExtent ?? height).clamp(0.0, height),
                    total: height,
                  ),
                  gradient,
                ],
              ),
      ),
    );
  }
}

/// Full blur from the edge, then a feathered end that dissolves like a
/// cloud: thin slices whose blur eases to nothing on a smoothstep, gone at
/// the extent, so the frost never stops on a line. One backdrop pass serves
/// every slice.
class _ProgressiveBlur extends StatelessWidget {
  const _ProgressiveBlur({
    required this.edge,
    required this.sigma,
    required this.extent,
    required this.total,
  });

  final ConduitChromeFadeEdge edge;
  final double sigma;

  /// Where the frost has fully faded, from the edge.
  final double extent;
  final double total;

  /// Slices in the feather: thin enough that no step between two shows.
  static const _slices = 12;

  /// How long the feather is: the frost thins out over this distance and
  /// is gone at [extent].
  static const _feather = 32.0;

  @override
  Widget build(BuildContext context) {
    Widget slice(double height, double strength) {
      final blur = sigma * strength;
      return SizedBox(
        height: height,
        // Past the point where blur is visible, nothing is drawn at all.
        child: blur < 0.05
            ? null
            : ClipRect(
                child: BackdropFilter.grouped(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: const SizedBox.expand(),
                ),
              ),
      );
    }

    final feather = math.min(_feather, extent);
    final full = extent - feather;
    double ease(double t) => 1 - t * t * (3 - 2 * t);
    final slices = [
      if (full > 0) slice(full, 1),
      for (var i = 0; i < _slices; i++)
        slice(feather / _slices, ease((i + 0.5) / _slices)),
      if (total > extent) SizedBox(height: total - extent),
    ];
    return BackdropGroup(
      child: Column(
        children: edge == ConduitChromeFadeEdge.top
            ? slices
            : slices.reversed.toList(),
      ),
    );
  }
}
