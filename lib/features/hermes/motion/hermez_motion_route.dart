import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'hermez_morph_origin.dart';
import 'hermez_motion_tokens.dart';

/// What a Hermez route becomes when it has finished growing.
enum HermezExpandShape {
  /// The whole screen.
  page,

  /// A sheet anchored to the bottom edge. It can be dragged down to close.
  sheet,
}

/// Page for GoRouter destinations owned by Hermez.
///
/// Nothing in these transitions animates opacity. A destination either grows
/// out of the object that opened it ([HermezRouteMotion.expand]) or slides in
/// over its sibling ([HermezRouteMotion.standard]). The screen underneath
/// recedes or shifts back and returns on Back.
class HermezMotionPage<T> extends Page<T> {
  const HermezMotionPage({
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
    required this.child,
    this.motion = HermezRouteMotion.standard,
    this.origin,
    this.reducedMotion = false,
  });

  final Widget child;
  final HermezRouteMotion motion;
  final HermezMorphOrigin? origin;
  final bool reducedMotion;

  @override
  Route<T> createRoute(BuildContext context) => _HermezPageBasedRoute<T>(this);
}

/// Builds a Hermez page for a GoRouter route.
Page<void> buildHermezMotionPage({
  required LocalKey pageKey,
  required Widget child,
  String? name,
  HermezRouteMotion motion = HermezRouteMotion.standard,
  HermezMorphOrigin? origin,
  bool reducedMotion = false,
}) => HermezMotionPage<void>(
  key: pageKey,
  name: name,
  motion: motion,
  origin: origin,
  reducedMotion: reducedMotion,
  child: child,
);

/// Pushes a Hermez sheet that grows out of [origin], or rises from the bottom
/// edge when there is no source object. Tapping outside, Back, or dragging it
/// down closes it. Closing never implies an action.
///
/// The result arrives once the sheet has finished contracting home, so a
/// caller that navigates next never starts under a sheet still in flight.
Future<T?> pushHermezSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  HermezMorphOrigin? origin,
  double heightFactor = 0.91,
  bool reducedMotion = false,
}) async {
  final route = HermezRoute<T>(
    builder: builder,
    motion: HermezRouteMotion.expand,
    shape: HermezExpandShape.sheet,
    origin: origin,
    heightFactor: heightFactor,
    reducedMotion: reducedMotion,
  );
  final result = await Navigator.of(context).push<T>(route);
  await route.completed;
  return result;
}

/// A Hermez route for imperative navigation.
class HermezRoute<T> extends PageRoute<T> with HermezRouteTransitions<T> {
  HermezRoute({
    required this.builder,
    this.motion = HermezRouteMotion.standard,
    this.shape = HermezExpandShape.page,
    this.origin,
    this.heightFactor = 0.91,
    this.reducedMotion = false,
    super.settings,
  });

  final WidgetBuilder builder;
  @override
  final HermezRouteMotion motion;
  @override
  final HermezExpandShape shape;
  @override
  final HermezMorphOrigin? origin;
  @override
  final double heightFactor;
  @override
  final bool reducedMotion;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final page = HeroMode(
      // A destination that grows out of an object moves as that one object;
      // its parts do not fly on their own paths.
      enabled: effectiveMotion != HermezRouteMotion.expand,
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: builder(context),
      ),
    );
    return shape == HermezExpandShape.sheet
        ? _HermezSheetPlacement(route: this, child: page)
        : page;
  }
}

/// Places a sheet inside its full-screen route page: lifted above the
/// keyboard, offset by a drag in progress, and draggable down to close.
class _HermezSheetPlacement<T> extends StatelessWidget {
  const _HermezSheetPlacement({required this.route, required this.child});

  final HermezRouteTransitions<T> route;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final target = _HermezSheetFrame._sheetRect(
          constraints.biggest,
          media,
          route.heightFactor,
        );
        final sheet = MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(
              top: 0,
              bottom: media.viewInsets.bottom > 0 ? 0 : media.padding.bottom,
            ),
            viewPadding: media.viewPadding.copyWith(top: 0),
            viewInsets: media.viewInsets.copyWith(bottom: 0),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: (details) =>
                route._handleDragUpdate(details, target.height),
            onVerticalDragEnd: (details) =>
                route._handleDragEnd(details, target.height),
            child: child,
          ),
        );
        return ValueListenableBuilder<double>(
          valueListenable: route._dragOffset,
          child: sheet,
          builder: (context, drag, sheet) => Stack(
            children: [
              Positioned.fromRect(
                rect: target.shift(Offset(0, drag)),
                child: sheet!,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HermezPageBasedRoute<T> extends PageRoute<T>
    with HermezRouteTransitions<T> {
  _HermezPageBasedRoute(HermezMotionPage<T> page) : super(settings: page);

  HermezMotionPage<T> get _page => settings as HermezMotionPage<T>;

  @override
  HermezRouteMotion get motion => _page.motion;
  @override
  HermezExpandShape get shape => HermezExpandShape.page;
  @override
  HermezMorphOrigin? get origin => _page.origin;
  @override
  double get heightFactor => 1;
  @override
  bool get reducedMotion => _page.reducedMotion;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => HeroMode(
    enabled: effectiveMotion != HermezRouteMotion.expand,
    child: Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: _page.child,
    ),
  );
}

/// Shared transition behavior for Hermez routes.
mixin HermezRouteTransitions<T> on PageRoute<T> {
  HermezRouteMotion get motion;
  HermezExpandShape get shape;
  HermezMorphOrigin? get origin;
  double get heightFactor;
  bool get reducedMotion;

  /// What this route does to the screen under it.
  HermezCoverKind get coverKind => switch (effectiveMotion) {
    HermezRouteMotion.expand =>
      shape == HermezExpandShape.sheet
          ? HermezCoverKind.lift
          : HermezCoverKind.recede,
    HermezRouteMotion.standard => HermezCoverKind.shift,
    HermezRouteMotion.none => HermezCoverKind.none,
  };

  HermezRouteMotion get effectiveMotion {
    if (reducedMotion) return HermezRouteMotion.none;
    if (motion == HermezRouteMotion.expand &&
        origin == null &&
        shape == HermezExpandShape.page) {
      return HermezRouteMotion.standard;
    }
    return motion;
  }

  HermezMotionWeight get _weight => effectiveMotion == HermezRouteMotion.expand
      ? HermezMotionWeight.heavy
      : HermezMotionWeight.medium;

  HermezCoverKind _nextCover = HermezCoverKind.shift;
  final ValueNotifier<double> _dragOffset = ValueNotifier<double>(0);
  AnimationController? _dragSettle;

  @override
  Duration get transitionDuration => effectiveMotion == HermezRouteMotion.none
      ? Duration.zero
      : HermezMotion.settleFor(_weight);

  // Leaving is quicker than arriving: the object returns home decisively.
  @override
  Duration get reverseTransitionDuration =>
      effectiveMotion == HermezRouteMotion.expand
      ? HermezMotion.settleFor(HermezMotionWeight.medium)
      : transitionDuration;

  bool _slideOut = false;

  @override
  bool didPop(T? result) {
    // Leaving for another destination (Chat) also removes the screen this
    // object came from, so it slides away instead of contracting into a
    // card that is no longer there.
    if (HermezRouteExits.leavingElsewhere) _slideOut = true;
    return super.didPop(result);
  }

  // A page that grows out of an object keeps the source screen painted
  // underneath, so Back can contract into it on the first frame instead of
  // waiting for the source to be rebuilt onstage.
  @override
  bool get opaque =>
      shape == HermezExpandShape.page &&
      effectiveMotion != HermezRouteMotion.expand;

  @override
  bool get barrierDismissible => shape == HermezExpandShape.sheet;

  @override
  String? get barrierLabel => shape == HermezExpandShape.sheet ? 'Close' : null;

  @override
  Color? get barrierColor => null;

  @override
  bool get maintainState => true;

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    if (nextRoute == null) {
      _nextSheet = null;
      return;
    }
    _nextCover = nextRoute is HermezRouteTransitions
        ? nextRoute.coverKind
        : HermezCoverKind.shift;
    _nextSheet =
        nextRoute is HermezRouteTransitions &&
            nextRoute.coverKind == HermezCoverKind.lift
        ? nextRoute
        : null;
  }

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    super.didChangePrevious(previousRoute);
    _liftsPrevious = previousRoute is HermezRouteTransitions;
  }

  /// The sheet on top of this screen, whose drag this screen follows.
  HermezRouteTransitions<dynamic>? _nextSheet;

  /// Whether the screen under this sheet is a Hermez screen that lifts.
  bool _liftsPrevious = false;

  /// This sheet's height, from its last layout.
  double _sheetExtent = 0;

  /// How far this sheet has been dragged down, as a fraction of its height.
  double get _dragRelease => _sheetExtent <= 0
      ? 0
      : (_dragOffset.value / _sheetExtent).clamp(0.0, 1.0);

  @override
  void dispose() {
    _dragSettle?.dispose();
    _dragOffset.dispose();
    super.dispose();
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curve = HermezMotion.curveFor(_weight);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Every wrapper below is present on every frame, whatever the route is
    // doing. Swapping one widget type for another (a slide for a scale when
    // a route was pushed on top, a slide-out when leaving) remounted the
    // whole page in the middle of the motion and read as a stutter.
    final Widget moving = switch (effectiveMotion) {
      HermezRouteMotion.none =>
        shape == HermezExpandShape.sheet
            ? _HermezSheetFrame(
                route: this,
                progress: kAlwaysCompleteAnimation,
                child: child,
              )
            : child,
      HermezRouteMotion.standard => HermezPushTransition(
        animation: hermezCurved(animation, curve),
        child: child,
      ),
      // Leaving for another destination slides the grown page away instead
      // of contracting it into a card that is disappearing too.
      HermezRouteMotion.expand => SlideTransition(
        position: _slideOut
            ? hermezCurved(animation, HermezMotion.curveMedium).drive(
                Tween<Offset>(begin: Offset(rtl ? -1 : 1, 0), end: Offset.zero),
              )
            : _still,
        child: _HermezSheetFrame(
          route: this,
          progress: hermezCurved(animation, curve),
          child: child,
        ),
      ),
    };
    final sheet = _nextSheet;
    return HermezCoveredTransition(
      kind: reducedMotion ? HermezCoverKind.none : _nextCover,
      animation: hermezCurved(
        secondaryAnimation,
        _nextCover == HermezCoverKind.recede ||
                _nextCover == HermezCoverKind.lift
            ? HermezMotion.curveHeavy
            : HermezMotion.curveMedium,
      ),
      // A sheet dragged down lets this screen settle back with it.
      follow: sheet?._dragOffset,
      release: sheet == null ? null : () => sheet._dragRelease,
      child: moving,
    );
  }

  static const Animation<Offset> _still = AlwaysStoppedAnimation(Offset.zero);

  void _handleDragUpdate(DragUpdateDetails details, double extent) {
    _dragSettle?.stop();
    _dragOffset.value = math.max(0, _dragOffset.value + details.delta.dy);
  }

  void _handleDragEnd(DragEndDetails details, double extent) {
    final velocity = details.primaryVelocity ?? 0;
    final offset = _dragOffset.value;
    if (velocity > 700 || offset > extent * 0.28) {
      if (isCurrent) navigator?.pop();
      return;
    }
    final nav = navigator;
    if (nav == null) {
      _dragOffset.value = 0;
      return;
    }
    final settle = _dragSettle ??= AnimationController.unbounded(vsync: nav)
      ..addListener(() => _dragOffset.value = math.max(0, _dragSettle!.value));
    settle.value = offset;
    settle.animateWith(
      SpringSimulation(
        HermezMotion.springMedium.toFlutter(),
        offset,
        0,
        velocity,
      ),
    );
  }
}

/// What a route does to the screen it covers.
enum HermezCoverKind {
  /// Scale back slightly: something is coming toward the user.
  recede,

  /// Move back along the reading direction: a sibling is sliding over.
  shift,

  /// Scale back slightly and rise: a sheet grew out of this screen and
  /// pushed it up. It settles back down as the sheet shrinks or is dragged.
  lift,

  /// Stay still.
  none,
}

/// A sibling page sliding over the one it came from. No opacity change.
class HermezPushTransition extends StatelessWidget {
  const HermezPushTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset(rtl ? -1 : 1, 0),
        end: Offset.zero,
      ).animate(animation),
      // The leading-edge shadow exists only while the page is moving.
      child: CustomPaint(
        painter: _EdgeShadowPainter(animation, rtl: rtl),
        child: child,
      ),
    );
  }
}

class _EdgeShadowPainter extends CustomPainter {
  _EdgeShadowPainter(this.animation, {required this.rtl})
    : super(repaint: animation);

  final Animation<double> animation;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0 || t >= 1) return;
    const width = 28.0;
    final rect = rtl
        ? Rect.fromLTWH(size.width, 0, width, size.height)
        : Rect.fromLTWH(-width, 0, width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: rtl ? Alignment.centerLeft : Alignment.centerRight,
          end: rtl ? Alignment.centerRight : Alignment.centerLeft,
          colors: const [Color(0x24000000), Color(0x00000000)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_EdgeShadowPainter oldDelegate) =>
      oldDelegate.animation != animation || oldDelegate.rtl != rtl;
}

/// The screen underneath a Hermez route while that route arrives or leaves.
class HermezCoveredTransition extends StatelessWidget {
  const HermezCoveredTransition({
    super.key,
    required this.kind,
    required this.animation,
    required this.child,
    this.follow,
    this.release,
  });

  final HermezCoverKind kind;
  final Animation<double> animation;
  final Widget child;

  /// Something besides [animation] that moves this screen, such as the drag
  /// of the sheet on top of it.
  final Listenable? follow;

  /// How much of the cover to give back, from 0 to 1, read on every frame.
  final double Function()? release;

  /// How far a sheet lifts the screen it grew out of.
  static double liftFor(Size screen) =>
      (screen.height * 0.06).clamp(32.0, 64.0);

  /// Where [rect], laid out on a covered screen of [screen] size, is drawn
  /// when that screen is lifted by [value] (0 to 1). A sheet uses this to
  /// start from, and return to, the card where it really is on screen.
  static Rect liftRect(
    Rect rect, {
    required Size screen,
    required double value,
  }) {
    final scale = 1 - (1 - HermezMotion.sourceBackgroundScale) * value;
    final center = screen.center(Offset.zero);
    final rise = Offset(0, -liftFor(screen) * value);
    Offset map(Offset point) => center + (point + rise - center) * scale;
    return Rect.fromPoints(map(rect.topLeft), map(rect.bottomRight));
  }

  @override
  Widget build(BuildContext context) {
    // One structure for every kind, so a route pushed on top (which changes
    // the kind) never remounts the page underneath mid-flight. Neutral
    // values (scale 1, no offset) paint the child directly.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final follow = this.follow;
    // The lift is measured from this screen's own laid-out size, the same
    // size the sheet on top uses to follow the card, so both always agree.
    return LayoutBuilder(
      builder: (context, constraints) {
        final lift = liftFor(constraints.biggest);
        return AnimatedBuilder(
          animation: follow == null
              ? animation
              : Listenable.merge([animation, follow]),
          child: child,
          builder: (context, child) {
            final value = animation.value * (1 - (release?.call() ?? 0));
            final scale =
                kind == HermezCoverKind.recede || kind == HermezCoverKind.lift
                ? 1 - (1 - HermezMotion.sourceBackgroundScale) * value
                : 1.0;
            return Transform.scale(
              scale: scale,
              child: FractionalTranslation(
                translation: Offset(
                  kind == HermezCoverKind.shift
                      ? (rtl ? 1 : -1) * HermezMotion.pushBackShift * value
                      : 0,
                  0,
                ),
                child: Transform.translate(
                  offset: Offset(
                    0,
                    kind == HermezCoverKind.lift ? -lift * value : 0,
                  ),
                  child: child,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Grows a route out of its origin rectangle into a page or a sheet.
///
/// The destination is laid out once at its final size and revealed through a
/// rounded aperture that travels from the source object. Shared parts fly
/// above it as Hero flights; everything else is uncovered as the aperture
/// grows.
class _HermezSheetFrame<T> extends StatelessWidget {
  const _HermezSheetFrame({
    required this.route,
    required this.progress,
    required this.child,
  });

  final HermezRouteTransitions<T> route;
  final Animation<double> progress;
  final Widget child;

  static const _sheetRadius = 30.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sheet = route.shape == HermezExpandShape.sheet;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final target = sheet
            ? _sheetRect(size, media, route.heightFactor)
            : Offset.zero & size;
        final targetRadius = sheet
            ? const BorderRadius.vertical(top: Radius.circular(_sheetRadius))
            : BorderRadius.zero;
        final origin = route.origin;
        final fallback = Rect.fromLTWH(
          target.left,
          size.height,
          target.width,
          target.height,
        );
        // The page subtree stays full screen at the navigator origin (Hero
        // flights measure against it); a sheet places itself inside it via
        // [_HermezSheetPlacement]. This frame only clips.
        final content = child;
        return AnimatedBuilder(
          animation: Listenable.merge([progress, route._dragOffset]),
          child: content,
          builder: (context, content) {
            // A page sliding away keeps its full size; only a contraction
            // home runs the aperture backwards.
            final t = route._slideOut ? 1.0 : progress.value;
            final settledT = t.clamp(0.0, 1.0);
            final drag = route._dragOffset.value;
            if (sheet) route._sheetExtent = target.height;
            final end = target.shift(Offset(0, drag));
            final measured = origin?.resolve();
            // The screen underneath lifts with the sheet; start from and
            // return to the card where it is actually drawn, so the object
            // never leaves its card mid-motion.
            final from = measured == null
                ? fallback
                : sheet && route._liftsPrevious
                ? HermezCoveredTransition.liftRect(
                    measured,
                    screen: size,
                    value: t.clamp(0.0, 1.0) * (1 - route._dragRelease),
                  )
                : measured;
            final rect = Rect.lerp(from, end, t)!;
            final originRadius = BorderRadius.circular(
              origin?.radius ?? (sheet ? _sheetRadius : 0),
            );
            final radius = BorderRadius.lerp(
              origin == null && sheet ? targetRadius : originRadius,
              targetRadius,
              settledT,
            )!;
            final surface = Theme.of(context).colorScheme.surface;
            final slabColor = Color.lerp(
              origin?.color ?? surface,
              surface,
              settledT,
            )!;
            final aperture = radius.toRRect(rect);
            final lift = sheet ? 1.0 : (1 - settledT);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (sheet)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Color.lerp(
                          const Color(0x00000000),
                          const Color(0x52000000),
                          (settledT * (1 - drag / (target.height * 1.6))).clamp(
                            0.0,
                            1.0,
                          ),
                        )!,
                      ),
                    ),
                  ),
                Positioned.fromRect(
                  rect: rect,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: slabColor,
                        borderRadius: radius,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0x2E000000),
                            blurRadius: lerpDouble(0, 30, settledT)! * lift,
                            spreadRadius: lerpDouble(0, -2, settledT)! * lift,
                            offset: Offset(
                              0,
                              lerpDouble(0, 10, settledT)! * lift,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ClipRRect(
                    clipper: _ApertureClipper(aperture),
                    // A settled full page needs no clip; keeping one costs a
                    // clip layer on every scroll frame. Same widget either
                    // way, so nothing remounts when it changes.
                    clipBehavior: !sheet && settledT >= 1 && drag == 0
                        ? Clip.none
                        : Clip.antiAlias,
                    // One object: the whole destination scales out of the
                    // source and back into it, so text, decoration, and
                    // surfaces all move together on one spring.
                    child: _landing(
                      origin: origin,
                      rect: rect,
                      t: settledT,
                      destination: Transform(
                        transform: _zoom(rect, end),
                        child: content,
                      ),
                    ),
                  ),
                ),
                // The source's outline thins away as it grows, and returns as
                // it contracts, so the object keeps its edge at both ends.
                if (origin?.borderColor case final edge?)
                  if (settledT < 0.5)
                    Positioned.fromRect(
                      rect: rect,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: radius,
                            border: Border.all(
                              color: edge,
                              width: 1 - settledT * 2,
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        );
      },
    );
  }

  /// Near the source, the destination slides up and away inside the
  /// aperture and uncovers the source object's own face, which rides the
  /// aperture at its own proportions. Contracting, the card's content is
  /// already in place when the route ends; opening, the destination slides
  /// down over it. Nothing fades and nothing is swapped on a single frame.
  /// Same widgets at every [t], so nothing remounts.
  static Widget _landing({
    required HermezMorphOrigin? origin,
    required Rect rect,
    required double t,
    required Widget destination,
  }) {
    final face = origin?.snapshot;
    // 0 while the aperture is near the source, 1 once it has grown clear.
    final raw = face == null ? 1.0 : ((t - 0.12) / 0.38).clamp(0.0, 1.0);
    final cover = raw * raw * (3 - 2 * raw);
    final faceHeight = face == null || face.width == 0
        ? rect.height
        : rect.width * face.height / face.width;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (face != null)
          Positioned.fromRect(
            rect: Rect.fromLTWH(rect.left, rect.top, rect.width, faceHeight),
            child: RawImage(image: face, fit: BoxFit.fill),
          ),
        // The destination slides down and out through the aperture's bottom
        // as one piece, uncovering the source's face from the top, where the
        // face sits. Its top edge travels with it, so no more of the (much
        // taller) page scrolls into view while it leaves.
        ClipRect(
          clipper: _LeavingEdge(rect, cover),
          clipBehavior: cover >= 1 ? Clip.none : Clip.hardEdge,
          child: Transform.translate(
            offset: Offset(0, (1 - cover) * rect.height),
            child: destination,
          ),
        ),
      ],
    );
  }

  /// Maps the destination's final rectangle onto the travelling aperture:
  /// its top-left corner rides the aperture and it scales uniformly by width.
  static Matrix4 _zoom(Rect rect, Rect end) {
    if (end.width <= 0) return Matrix4.identity();
    final scale = (rect.width / end.width).clamp(0.05, 1.5);
    return Matrix4.identity()
      ..translateByDouble(rect.left, rect.top, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-end.left, -end.top, 0, 1);
  }

  static Rect _sheetRect(Size size, MediaQueryData media, double factor) {
    final top = media.padding.top + 8;
    final bottom = size.height - media.viewInsets.bottom;
    final height = math.min(bottom - top, size.height * factor);
    return Rect.fromLTRB(0, bottom - math.max(height, 0), size.width, bottom);
  }
}

/// The part of the aperture the leaving destination still covers: the
/// bottom [cover] of it, below an edge that moves down as it leaves.
class _LeavingEdge extends CustomClipper<Rect> {
  const _LeavingEdge(this.aperture, this.cover);
  final Rect aperture;
  final double cover;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    aperture.left,
    aperture.top + aperture.height * (1 - cover),
    aperture.right,
    aperture.bottom,
  );

  @override
  bool shouldReclip(_LeavingEdge oldClipper) =>
      oldClipper.aperture != aperture || oldClipper.cover != cover;
}

class _ApertureClipper extends CustomClipper<RRect> {
  const _ApertureClipper(this.rrect);
  final RRect rrect;

  @override
  RRect getClip(Size size) => rrect;

  @override
  bool shouldReclip(_ApertureClipper oldClipper) => oldClipper.rrect != rrect;
}

/// Platform page transitions for non-Hermez Material routes on Android: the
/// same fade-free push used by Hermez sibling routes.
class HermezPushPageTransitionsBuilder extends PageTransitionsBuilder {
  const HermezPushPageTransitionsBuilder();

  @override
  Duration get transitionDuration =>
      HermezMotion.settleFor(HermezMotionWeight.medium);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curve = HermezMotion.curveMedium;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final arriving = hermezCurved(animation, curve);
    return HermezCoveredTransition(
      kind: HermezCoverKind.shift,
      animation: hermezCurved(secondaryAnimation, curve),
      child: route.fullscreenDialog
          ? SlideTransition(
              position: arriving.drive(
                Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero),
              ),
              child: child,
            )
          : HermezPushTransition(animation: arriving, child: child),
    );
  }
}

/// Marks the next Hermez exits as leaving for another destination, such as
/// opening a conversation from Home or Bot Detail. Routes removed in that
/// moment slide away instead of contracting into their source card, because
/// the source screen is being removed too.
abstract final class HermezRouteExits {
  static DateTime? _until;

  static void leaveForAnotherDestination() {
    _until = DateTime.now().add(const Duration(milliseconds: 400));
  }

  static bool get leavingElsewhere {
    final until = _until;
    return until != null && DateTime.now().isBefore(until);
  }
}

final Expando<Map<(Curve, Curve?), CurvedAnimation>> _curvedCache = Expando();

/// [parent] on a Hermez spring, rising on [curve] and falling on the mirror
/// of [reverseOf] (default [curve]) so both directions start at speed and
/// settle gently.
///
/// Route transitions are rebuilt on every animation frame. A new
/// [CurvedAnimation] per frame adds a status listener to the route's
/// controller that is never removed, and every one of them runs when the
/// transition finishes. This returns one shared instance per parent and
/// curve instead.
Animation<double> hermezCurved(
  Animation<double> parent,
  Curve curve, {
  Curve? reverseOf,
}) {
  final byCurve = _curvedCache[parent] ??= <(Curve, Curve?), CurvedAnimation>{};
  return byCurve[(curve, reverseOf)] ??= CurvedAnimation(
    parent: parent,
    curve: curve,
    reverseCurve: (reverseOf ?? curve).flipped,
  );
}
