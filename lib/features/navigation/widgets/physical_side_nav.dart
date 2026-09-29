import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Mobile side navigation as a physical sheet: the app surface slides off to
/// the right to reveal the navigation that was underneath it all along,
/// leaving a narrow return rail on the right edge.
///
/// Everything is derived from one progress value (0 closed, 1 open), so the
/// surface, the navigation, the rail, the rounding, and the label stagger
/// move as one mechanism and reverse from wherever they are. The owner of
/// the [Animation] decides timing; this file only maps progress to geometry
/// and paints it.

/// Default timing for driving [PhysicalSideNav] (from Calendar-Master).
const Duration kSideNavDuration = Duration(milliseconds: 520);
const Curve kSideNavCurve = Cubic(0.22, 0.61, 0.36, 1.0);

/// Per-item delay of the navigation label stagger, relative to
/// [kSideNavDuration].
const Duration kSideNavItemStagger = Duration(milliseconds: 30);

/// Where every part of the side navigation sits at one progress value.
@immutable
class SideNavGeometry {
  const SideNavGeometry({
    required this.progress,
    required this.chatOffset,
    required this.navigationOffset,
    required this.navigationWidth,
    required this.railRect,
    required this.railExposedWidth,
    required this.cornerRadius,
    required this.verticalInset,
  });

  final double progress;

  /// Horizontal translation of the full-width app surface.
  final double chatOffset;

  /// Horizontal translation of the navigation layer underneath.
  final double navigationOffset;

  /// Width the navigation is laid out at: everything left of the rail.
  final double navigationWidth;

  /// The return rail, in viewport coordinates. Its right edge is glued to the
  /// app surface's left edge.
  final Rect railRect;

  /// How much of the rail is on screen.
  final double railExposedWidth;

  /// Rounding of the departing surface.
  final double cornerRadius;

  /// Top and bottom inset of the departing surface.
  final double verticalInset;

  /// The rail takes taps once a sliver of it is actually visible.
  bool get railInteractive => railExposedWidth >= 2;

  /// Navigation takes input whenever it is showing at all.
  bool get navigationInteractive => progress > 0;

  /// The app surface takes input only when it is fully in place.
  bool get chatInteractive => progress <= 0;
}

/// Pure geometry for [PhysicalSideNav]; see [SideNavGeometry].
SideNavGeometry sideNavGeometryFor({
  required Size viewport,
  required double progress,
  double railWidth = 44,
  double railInset = 14,
  double maxCornerRadius = 16,
  double maxVerticalInset = 14,
  double navigationDrift = 0.36,
}) {
  final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
  final width = math.max(0.0, viewport.width);
  final height = math.max(0.0, viewport.height);
  final chatOffset = width * p;
  final navigationWidth = math.max(0.0, width - railWidth);
  final railRect = Rect.fromLTWH(
    chatOffset - railWidth,
    railInset,
    railWidth,
    math.max(0.0, height - railInset * 2),
  );
  final exposed =
      (math.min(width, railRect.right) - math.max(0.0, railRect.left)).clamp(
        0.0,
        railWidth,
      );
  return SideNavGeometry(
    progress: p,
    chatOffset: chatOffset,
    navigationOffset: -navigationDrift * navigationWidth * (1 - p),
    navigationWidth: navigationWidth,
    railRect: railRect,
    railExposedWidth: exposed.toDouble(),
    cornerRadius: maxCornerRadius * p,
    verticalInset: maxVerticalInset * p,
  );
}

/// Local progress of navigation item [index] at master [progress]: each
/// item starts [kSideNavItemStagger] later and all finish together, so the
/// stagger runs backwards exactly as it runs forwards.
double sideNavItemProgress(double progress, int index) {
  final p = progress.clamp(0.0, 1.0);
  final step =
      kSideNavItemStagger.inMicroseconds / kSideNavDuration.inMicroseconds;
  // Past a few items the delay would eat most of the travel; later items
  // move with the last delayed one.
  final delay = math.min(math.max(0, index) * step, 0.5);
  return ((p - delay) / (1 - delay)).clamp(0.0, 1.0);
}

/// Publishes the side navigation's progress to [SideNavItem]s underneath.
class SideNavProgressScope extends InheritedWidget {
  const SideNavProgressScope({
    super.key,
    required this.progress,
    required super.child,
  });

  final Animation<double> progress;

  static Animation<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SideNavProgressScope>()
      ?.progress;

  @override
  bool updateShouldNotify(SideNavProgressScope oldWidget) =>
      !identical(progress, oldWidget.progress);
}

/// A navigation block that settles into place with the side navigation:
/// from 14 px to the left and transparent to in place and opaque, [index]
/// steps behind the first. Outside a [SideNavProgressScope] (for example in
/// the persistent tablet sidebar) it is just [child].
class SideNavItem extends StatelessWidget {
  const SideNavItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  static const double shift = 14;

  @override
  Widget build(BuildContext context) {
    final progress = SideNavProgressScope.maybeOf(context);
    if (progress == null) return child;
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final local = sideNavItemProgress(progress.value, index);
        return Opacity(
          opacity: local,
          child: Transform.translate(
            offset: Offset(-shift * (1 - local), 0),
            child: child,
          ),
        );
      },
    );
  }
}

/// The physical side navigation shell.
///
/// [child] (the app surface) and [navigation] are passed through as stable
/// children: an animation frame only updates transforms, the clip, the rail,
/// and item presentation. Neither subtree is rebuilt or remounted by the
/// motion.
class PhysicalSideNav extends StatelessWidget {
  const PhysicalSideNav({
    super.key,
    required this.progress,
    required this.navigation,
    required this.child,
    required this.railLabel,
    required this.onReturn,
    this.railSemanticLabel = 'Return to chat',
    this.stageColor,
    this.railColor,
    this.railForegroundColor,
    this.onRailDragStart,
    this.onRailDragUpdate,
    this.onRailDragEnd,
    this.onRailDragCancel,
  });

  /// 0 closed, 1 open. The owner applies timing and easing.
  final Animation<double> progress;
  final Widget navigation;
  final Widget child;

  /// What the rail shows, laid out along its length (bottom to top).
  final Widget railLabel;
  final VoidCallback onReturn;
  final String railSemanticLabel;

  /// Fill behind everything, seen around the departing surface.
  final Color? stageColor;
  final Color? railColor;
  final Color? railForegroundColor;

  final GestureDragStartCallback? onRailDragStart;
  final GestureDragUpdateCallback? onRailDragUpdate;
  final GestureDragEndCallback? onRailDragEnd;
  final GestureDragCancelCallback? onRailDragCancel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        SideNavGeometry geometry() =>
            sideNavGeometryFor(viewport: viewport, progress: progress.value);
        final navigationWidth = geometry().navigationWidth;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (stageColor != null)
              Positioned.fill(child: ColoredBox(color: stageColor!)),
            // Underneath: the navigation, settling a little into place.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: navigationWidth,
              child: SideNavProgressScope(
                progress: progress,
                child: AnimatedBuilder(
                  animation: progress,
                  child: RepaintBoundary(child: navigation),
                  builder: (context, navigation) {
                    final g = geometry();
                    return Transform.translate(
                      offset: Offset(g.navigationOffset, 0),
                      child: IgnorePointer(
                        ignoring: !g.navigationInteractive,
                        child: ExcludeSemantics(
                          excluding: !g.navigationInteractive,
                          child: navigation,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // On top: the app surface at full width, moving as a sheet.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: progress,
                child: RepaintBoundary(child: child),
                builder: (context, surface) {
                  final g = geometry();
                  return Transform.translate(
                    offset: Offset(g.chatOffset, 0),
                    child: ClipRRect(
                      clipper: _InsetRRect(g.verticalInset, g.cornerRadius),
                      // No clip layer at rest.
                      clipBehavior: g.progress > 0 ? Clip.antiAlias : Clip.none,
                      // Taps reach the surface only when it is fully in
                      // place; a drag already in progress keeps its pointer.
                      child: IgnorePointer(
                        ignoring: !g.chatInteractive,
                        child: ExcludeSemantics(
                          excluding: g.progress >= 1,
                          child: surface,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // The handle of the departing surface.
            AnimatedBuilder(
              animation: progress,
              child: _ReturnRail(
                label: railLabel,
                semanticLabel: railSemanticLabel,
                onTap: onReturn,
                color: railColor,
                foregroundColor: railForegroundColor,
                onDragStart: onRailDragStart,
                onDragUpdate: onRailDragUpdate,
                onDragEnd: onRailDragEnd,
                onDragCancel: onRailDragCancel,
              ),
              builder: (context, rail) {
                final g = geometry();
                return Positioned.fromRect(
                  rect: g.railRect,
                  child: IgnorePointer(
                    ignoring: !g.railInteractive,
                    child: ExcludeSemantics(
                      excluding: !g.railInteractive,
                      child: rail,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _InsetRRect extends CustomClipper<RRect> {
  const _InsetRRect(this.inset, this.radius);

  final double inset;
  final double radius;

  @override
  RRect getClip(Size size) => RRect.fromLTRBR(
    0,
    inset,
    size.width,
    math.max(inset, size.height - inset),
    Radius.circular(radius),
  );

  @override
  bool shouldReclip(_InsetRRect oldClipper) =>
      oldClipper.inset != inset || oldClipper.radius != radius;
}

class _ReturnRail extends StatelessWidget {
  const _ReturnRail({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.color,
    this.foregroundColor,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
  });

  final Widget label;
  final String semanticLabel;
  final VoidCallback onTap;
  final Color? color;
  final Color? foregroundColor;
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;
  final GestureDragCancelCallback? onDragCancel;

  @override
  Widget build(BuildContext context) {
    final foreground = foregroundColor ?? const Color(0xFFFFFFFF);
    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onHorizontalDragStart: onDragStart,
        onHorizontalDragUpdate: onDragUpdate,
        onHorizontalDragEnd: onDragEnd,
        onHorizontalDragCancel: onDragCancel,
        child: DecoratedBox(
          key: const ValueKey<String>('side-nav-return-rail'),
          decoration: BoxDecoration(
            color: color ?? const Color(0xFF17181C),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: RotatedBox(
              quarterTurns: 3,
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: foreground,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: foreground, size: 16),
                  child: label,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
