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

/// Full blur over the chrome, then slices of lessening blur across the fade
/// so the frost has no hard edge. One backdrop pass serves every slice.
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

  static const _taper = [0.62, 0.34, 0.14];

  @override
  Widget build(BuildContext context) {
    Widget slice(double height, double strength) => SizedBox(
      height: height,
      child: ClipRect(
        child: BackdropFilter.grouped(
          filter: ImageFilter.blur(
            sigmaX: sigma * strength,
            sigmaY: sigma * strength,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    final slices = [
      slice(solid, 1),
      for (final strength in _taper) slice(fade / _taper.length, strength),
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
