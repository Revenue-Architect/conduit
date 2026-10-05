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
  });

  const ConduitChromeGradientFade.top({
    super.key,
    required this.contentHeight,
    this.fadeHeight = kConduitChromeFadeHeight,
    this.backgroundColor,
    this.blurSigma = 0,
  }) : edge = ConduitChromeFadeEdge.top;

  const ConduitChromeGradientFade.bottom({
    super.key,
    required this.contentHeight,
    this.fadeHeight = kConduitChromeFadeHeight,
    this.backgroundColor,
    this.blurSigma = 0,
  }) : edge = ConduitChromeFadeEdge.bottom;

  final ConduitChromeFadeEdge edge;
  final double contentHeight;
  final double fadeHeight;
  final Color? backgroundColor;

  /// Frost under the chrome, as a Gaussian sigma at the outer edge. Zero
  /// keeps the edge gradient-only.
  final double blurSigma;

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
                    solid: contentHeight,
                    fade: fadeHeight,
                  ),
                  gradient,
                ],
              ),
      ),
    );
  }
}

/// Full blur behind the chrome, then a feathered edge that dissolves like a
/// cloud: thin slices whose blur eases to nothing on a smoothstep, starting
/// a little inside the chrome, so the frost never stops on a line. One
/// backdrop pass serves every slice.
class _ProgressiveBlur extends StatelessWidget {
  const _ProgressiveBlur({
    required this.edge,
    required this.sigma,
    required this.solid,
    required this.fade,
  });

  final ConduitChromeFadeEdge edge;
  final double sigma;
  final double solid;
  final double fade;

  /// Slices in the feather: thin enough that no step between two shows.
  static const _slices = 12;

  /// How far inside the chrome the feather begins.
  static const _overlap = 16.0;

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

    final full = math.max(0.0, solid - _overlap);
    final feather = solid + fade - full;
    double ease(double t) => 1 - t * t * (3 - 2 * t);
    final slices = [
      if (full > 0) slice(full, 1),
      for (var i = 0; i < _slices; i++)
        slice(feather / _slices, ease((i + 0.5) / _slices)),
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
