import 'dart:math' as math;
import 'dart:ui' as ui;

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

  /// The frost shader, once loaded. Until then, and where shader filters are
  /// unsupported (widget tests), the frost falls back to sliced blurs.
  static final ValueNotifier<ui.FragmentProgram?> _frostProgram = ValueNotifier(
    null,
  );
  static bool _frostRequested = false;

  /// Starts loading the frost shader; safe to call more than once.
  static void precacheFrost() {
    if (_frostRequested || !ui.ImageFilter.isShaderFilterSupported) return;
    _frostRequested = true;
    ui.FragmentProgram.fromAsset(
      'shaders/hermez_progressive_blur.frag',
    ).then((program) => _frostProgram.value = program, onError: (Object _) {});
  }

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

    // A frosted top edge is the app's own background behind the chrome,
    // then thins out with the frost through the fade, so it blends in with
    // no line.
    final frostedTop = blurSigma > 0 && edge == ConduitChromeFadeEdge.top;
    final solid = height <= 0 ? 0.0 : (contentHeight / height).clamp(0.0, 1.0);
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: frostedTop
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  baseColor.withValues(alpha: 0.97),
                  baseColor.withValues(alpha: 0.9),
                  baseColor.withValues(alpha: 0.55),
                  baseColor.withValues(alpha: 0.18),
                  baseColor.withValues(alpha: 0.0),
                ],
                stops: [
                  0.0,
                  solid * 0.85,
                  solid + (1 - solid) * 0.3,
                  solid + (1 - solid) * 0.7,
                  1.0,
                ],
              )
            : LinearGradient(
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
            : Stack(fit: StackFit.expand, children: [_frost(height), gradient]),
      ),
    );
  }

  Widget _frost(double height) {
    final extent = (blurExtent ?? height).clamp(0.0, height);
    Widget sliced() => _ProgressiveBlur(
      edge: edge,
      sigma: blurSigma,
      extent: extent,
      total: height,
    );
    // The shader measures from the screen's top edge, so it serves a top
    // edge only; a bottom frost keeps the sliced version.
    if (edge != ConduitChromeFadeEdge.top) return sliced();
    precacheFrost();
    return ValueListenableBuilder<ui.FragmentProgram?>(
      valueListenable: _frostProgram,
      builder: (context, program, _) => program == null
          ? sliced()
          : _ShaderFrost(program: program, sigma: blurSigma, extent: extent),
    );
  }
}

/// One continuous frost: a separable Gaussian whose radius eases from full
/// at the edge to nothing at [extent], with no slices and no visible line.
/// Two passes (horizontal, vertical) whatever its size.
class _ShaderFrost extends StatefulWidget {
  const _ShaderFrost({
    required this.program,
    required this.sigma,
    required this.extent,
  });

  final ui.FragmentProgram program;
  final double sigma;
  final double extent;

  /// How long the frost takes to dissolve, ending at [extent].
  static const feather = 25.0;

  @override
  State<_ShaderFrost> createState() => _ShaderFrostState();
}

class _ShaderFrostState extends State<_ShaderFrost> {
  late final ui.FragmentShader _horizontal = widget.program.fragmentShader();
  late final ui.FragmentShader _vertical = widget.program.fragmentShader();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final end = widget.extent * dpr;
    final full = math.max(0.0, widget.extent - _ShaderFrost.feather) * dpr;
    // Uniform 0-1 is the texture size, set by the engine.
    void configure(ui.FragmentShader shader, double dx, double dy) => shader
      ..setFloat(2, widget.sigma * dpr)
      ..setFloat(3, full)
      ..setFloat(4, end)
      ..setFloat(5, dx)
      ..setFloat(6, dy);
    configure(_horizontal, 1, 0);
    configure(_vertical, 0, 1);
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: widget.extent,
        width: double.infinity,
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.compose(
              outer: ui.ImageFilter.shader(_vertical),
              inner: ui.ImageFilter.shader(_horizontal),
            ),
            child: const SizedBox.expand(),
          ),
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

  /// Slices in the feather. Every slice is its own blur pass, redrawn on
  /// each scroll frame, so keep this small: 12 slices cost a fifth of the
  /// chat's frames at 120 Hz (S25, profile build). Under the gradient a
  /// 3-step feather reads the same.
  static const _slices = 3;

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
                  filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
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
