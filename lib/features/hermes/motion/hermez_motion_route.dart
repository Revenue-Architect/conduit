import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../feedback/hermez_feedback.dart';
import '../widgets/hermez_chat_palette.dart';
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
/// A destination either grows out of the object that opened it
/// ([HermezRouteMotion.expand]) or slides in over its sibling
/// ([HermezRouteMotion.standard]). The only fade is inside a growing object:
/// its content and the source's own face hand over to each other near the
/// source, so it starts and ends on exactly what the card shows. The screen underneath
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
      // A destination moves as one object: grown out of its source, or slid
      // in as a sibling. Its parts never fly on their own paths (a slide-in
      // from the side navigation must not pull a title up from a Home card).
      enabled: false,
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
            // Scrolling content wins the vertical drag, so the sheet also
            // follows a pull past the top of its content: the same drag keeps
            // going, moving the sheet instead of the list.
            child: NotificationListener<OverscrollIndicatorNotification>(
              onNotification: (notification) {
                if (notification.leading && route._dragOffset.value > 0) {
                  notification.disallowIndicator();
                }
                return false;
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  route._handleContentScroll(notification, target.height);
                  return false;
                },
                child: child,
              ),
            ),
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
    enabled: false,
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

  /// A sheet pushes the screen it grew out of and pulls it back, so it moves
  /// with that screen's weight in both directions.
  bool get _pushes =>
      effectiveMotion == HermezRouteMotion.expand &&
      shape == HermezExpandShape.sheet;

  HermezSpringCurve get _curve =>
      _pushes ? HermezMotion.curvePush : HermezMotion.curveFor(_weight);

  HermezCoverKind _nextCover = HermezCoverKind.shift;
  final ValueNotifier<double> _dragOffset = ValueNotifier<double>(0);
  AnimationController? _dragSettle;

  /// Whether the current drag is past the dismiss threshold (one detent each
  /// way per crossing; reset when the drag ends).
  bool _pastDismiss = false;

  /// Where a sheet drag commits to closing (share of the sheet's height),
  /// and the slightly lower point it must return above to un-commit, so
  /// jitter around the line cannot fire repeated detents.
  static const double _dismissFraction = 0.28;
  static const double _detentHysteresis = 0.04;

  @override
  Duration get transitionDuration => effectiveMotion == HermezRouteMotion.none
      ? Duration.zero
      : _curve.settleDuration;

  // Leaving is quicker than arriving: the object returns home decisively.
  // A sheet is the exception: pulling the screen back down takes the same
  // effort as pushing it up.
  @override
  Duration get reverseTransitionDuration => _pushes
      ? transitionDuration
      : effectiveMotion == HermezRouteMotion.expand
      ? HermezMotion.settleFor(HermezMotionWeight.medium)
      : transitionDuration;

  bool _slideOut = false;

  @override
  bool didPop(T? result) {
    // Leaving for another destination (Chat) also removes the screen this
    // object came from, so it slides away instead of contracting into a
    // card that is no longer there.
    if (HermezRouteExits.leavingElsewhere) _slideOut = true;
    // Contracting home lands on the object as it looks now (edited, toggled,
    // updated while this was open), not as it looked when it was opened.
    if (!_slideOut && effectiveMotion == HermezRouteMotion.expand) {
      origin?.refreshFace();
    }
    final popped = super.didPop(result);
    // The object returns into the card it came from: a soft closing latch.
    if (popped &&
        !_slideOut &&
        effectiveMotion == HermezRouteMotion.expand &&
        origin != null) {
      HermezFeedback.play(HermezFeedbackCue.objectClose);
    }
    return popped;
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

  /// The sheet on top of this screen, whose edge pushes this screen.
  HermezRouteTransitions<dynamic>? _nextSheet;

  /// This sheet's resting rectangle and the screen size, from its last
  /// layout.
  Rect? _sheetTarget;
  Size _screen = Size.zero;

  /// How far this sheet pushes the screen it grew out of up, in pixels, at
  /// progress [t]: exactly as far as its top edge has risen above the card
  /// once it spans the screen, less any drag. The aperture is drawn from the
  /// same geometry, so the edge and the screen above it stay in contact.
  double _pushAt(double t) {
    final target = _sheetTarget;
    if (target == null) return 0;
    final card = origin?.resolve();
    // A sheet with no card to grow from gives the screen a gentle lift.
    if (card == null) {
      return HermezCoveredTransition.liftFor(_screen) *
          t.clamp(0.0, 1.0) *
          (1 - (_dragOffset.value / target.height).clamp(0.0, 1.0));
    }
    final top = hermezSheetAperture(
      card,
      target.shift(Offset(0, _dragOffset.value)),
      t,
    ).top;
    return math.max(0, card.top - top);
  }

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
    final curve = _curve;
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
          progress: hermezCurved(
            animation,
            curve,
            reverseOf: _pushes ? HermezMotion.sheetClose : null,
          ),
          child: child,
        ),
      ),
    };
    final sheet = _nextSheet;
    return HermezCoveredTransition(
      kind: reducedMotion ? HermezCoverKind.none : _nextCover,
      animation: hermezCurved(
        secondaryAnimation,
        switch (_nextCover) {
          HermezCoverKind.recede => HermezMotion.curveHeavy,
          // The same curve the sheet on top moves on, so the push and the
          // sheet's edge stay in contact.
          HermezCoverKind.lift => HermezMotion.curvePush,
          _ => HermezMotion.curveMedium,
        },
        reverseOf: _nextCover == HermezCoverKind.lift
            ? HermezMotion.sheetClose
            : null,
      ),
      // The sheet's rising edge pushes this screen up, and its drag pulls
      // it back down.
      follow: sheet?._dragOffset,
      push: sheet?._pushAt,
      backdrop: shape == HermezExpandShape.page
          ? HermezChatPalette.forBrightness(Theme.of(context).brightness).canvas
          : null,
      child: moving,
    );
  }

  static const Animation<Offset> _still = AlwaysStoppedAnimation(Offset.zero);

  void _handleDragUpdate(DragUpdateDetails details, double extent) {
    _dragSettle?.stop();
    final offset = math.max(0.0, _dragOffset.value + details.delta.dy);
    _dragOffset.value = offset;
    // A tactile detent where letting go would close the sheet.
    final past = _pastDismiss
        ? offset > extent * (_dismissFraction - _detentHysteresis)
        : offset > extent * _dismissFraction;
    if (past != _pastDismiss) {
      _pastDismiss = past;
      HermezFeedback.play(HermezFeedbackCue.sheetDetent);
    }
  }

  /// A vertical pull past the top of the sheet's content moves the sheet.
  void _handleContentScroll(ScrollNotification notification, double extent) {
    if (notification.metrics.axis != Axis.vertical) return;
    switch (notification) {
      case OverscrollNotification(:final dragDetails?, :final overscroll)
          when overscroll < 0 || _dragOffset.value > 0:
        _handleDragUpdate(
          DragUpdateDetails(
            globalPosition: dragDetails.globalPosition,
            delta: Offset(0, -overscroll),
            primaryDelta: -overscroll,
          ),
          extent,
        );
      case ScrollUpdateNotification(:final dragDetails?, :final scrollDelta?)
          when _dragOffset.value > 0 && scrollDelta > 0:
        // Pushing back up takes the sheet up first.
        _handleDragUpdate(
          DragUpdateDetails(
            globalPosition: dragDetails.globalPosition,
            delta: Offset(0, -scrollDelta),
            primaryDelta: -scrollDelta,
          ),
          extent,
        );
      case ScrollEndNotification(:final dragDetails) when _dragOffset.value > 0:
        final velocity = dragDetails?.primaryVelocity ?? 0;
        _handleDragEnd(
          DragEndDetails(
            velocity: Velocity(pixelsPerSecond: Offset(0, velocity)),
            primaryVelocity: velocity,
          ),
          extent,
        );
      default:
        break;
    }
  }

  void _handleDragEnd(DragEndDetails details, double extent) {
    _pastDismiss = false;
    final velocity = details.primaryVelocity ?? 0;
    final offset = _dragOffset.value;
    if (velocity > 700 || offset > extent * _dismissFraction) {
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
    this.push,
    this.backdrop,
  });

  final HermezCoverKind kind;
  final Animation<double> animation;
  final Widget child;

  /// For [HermezCoverKind.lift] on a full page: what shows in the strip the
  /// page uncovers as it rises, instead of whatever lies behind the route
  /// (the side navigation's list). Null keeps the strip see-through, as a
  /// sheet under a sheet must be.
  final Color? backdrop;

  /// Something besides [animation] that moves this screen, such as the drag
  /// of the sheet on top of it.
  final Listenable? follow;

  /// For [HermezCoverKind.lift]: how far up the sheet on top pushes this
  /// screen at a given progress, in pixels.
  final double Function(double value)? push;

  /// The gentle lift for a sheet that did not grow out of a card.
  static double liftFor(Size screen) =>
      (screen.height * 0.06).clamp(32.0, 64.0);

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
            final value = animation.value;
            // A pushed screen moves as a solid object: it rises, it does
            // not also shrink.
            final scale = kind == HermezCoverKind.recede
                ? 1 - (1 - HermezMotion.sourceBackgroundScale) * value
                : 1.0;
            final rise = kind != HermezCoverKind.lift
                ? 0.0
                : push?.call(value) ?? lift * value;
            final backdrop = this.backdrop;
            return Transform.scale(
              scale: scale,
              child: FractionalTranslation(
                translation: Offset(
                  kind == HermezCoverKind.shift
                      ? (rtl ? 1 : -1) * HermezMotion.pushBackShift * value
                      : 0,
                  0,
                ),
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    // Never hit-tested: taps outside a sheet still reach its
                    // barrier.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _UncoveredStripPainter(
                            color: backdrop,
                            height: rise,
                          ),
                        ),
                      ),
                    ),
                    Transform.translate(offset: Offset(0, -rise), child: child),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Fills the strip a rising page uncovers at its bottom edge.
class _UncoveredStripPainter extends CustomPainter {
  const _UncoveredStripPainter({required this.color, required this.height});

  final Color? color;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final color = this.color;
    if (color == null || height <= 0) return;
    canvas.drawRect(
      Rect.fromLTRB(0, size.height - height - 1, size.width, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_UncoveredStripPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.height != height;
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
            if (sheet) {
              route
                .._sheetTarget = target
                .._screen = size;
            }
            final end = target.shift(Offset(0, drag));
            final measured = origin?.resolve();
            // A card grows into a sheet as one object: it first widens to
            // the screen's width, then its top edge rises and pushes the
            // screen above it up (see [HermezRouteTransitions._pushAt]).
            final rect = sheet && measured != null
                ? hermezSheetAperture(measured, end, t)
                : Rect.lerp(measured ?? fallback, end, t)!;
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
                      slab: slabColor,
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

  /// The destination and the source object's face share the travelling
  /// aperture and both move with it; neither slides inside it. Near the
  /// source the destination dissolves into the face, which rides the
  /// aperture's top at its own proportions, so a contraction ends on the
  /// card's own content and a growth starts from it. The two overlap, so the
  /// object is never empty for long. Without a face (a live browser view
  /// cannot be drawn) the destination stays as it is. A function of [t]
  /// alone, so reversing mid-flight never jumps, and the same widgets at
  /// every [t], so nothing remounts.
  static Widget _landing({
    required HermezMorphOrigin? origin,
    required Rect rect,
    required double t,
    required Color slab,
    required Widget destination,
  }) {
    final face = origin?.snapshot;
    final faceHeight = face == null || face.width == 0
        ? rect.height
        : rect.width * face.height / face.width;
    // In sequence, not overlapping: the sheet's content is covered by the
    // card's surface before the card's face comes up on it, so the two
    // texts are never on screen together.
    final shown = face == null ? 1.0 : _smooth((t - 0.22) / 0.26);
    final faceShown = face == null ? 0.0 : 1 - _smooth((t - 0.04) / 0.18);
    // No offscreen layers: fading the whole destination through Opacity
    // cost a full-screen layer and dropped frames as the hand-over began.
    // The object's own surface is painted over the destination instead,
    // and the face draws itself translucent. The destination is either
    // drawn or skipped (opacity 0 or 1 needs no layer).
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: shown > 0 ? 1 : 0, child: destination),
        IgnorePointer(
          child: ColoredBox(
            color: slab.withValues(alpha: slab.a * (1 - shown)),
          ),
        ),
        if (face != null)
          Positioned.fromRect(
            rect: Rect.fromLTWH(rect.left, rect.top, rect.width, faceHeight),
            // A picture over the destination: it must never take its taps.
            child: IgnorePointer(
              child: RawImage(
                image: face,
                fit: BoxFit.fill,
                opacity: AlwaysStoppedAnimation(faceShown),
              ),
            ),
          ),
      ],
    );
  }

  static double _smooth(double x) {
    final v = x.clamp(0.0, 1.0);
    return v * v * (3 - 2 * v);
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

/// The outline of a card growing into a sheet at progress [t] (0 to 1).
///
/// The card widens to the sheet's width almost in place, and its top edge
/// rises to the sheet's top, starting gently as it widens. The bottom edge
/// travels to the sheet's bottom throughout. [card] is where the card is
/// laid out on the screen underneath, which the rising edge pushes up by
/// exactly as much as the edge has risen, so the two stay in contact.
Rect hermezSheetAperture(Rect card, Rect end, double t) {
  const widen = 0.34;
  const riseFrom = 0.12;
  final across = Curves.easeOut.transform((t / widen).clamp(0.0, 1.0));
  // The rise starts slowly, as if taking the screen's weight, then carries
  // it: resistance at first contact rather than a snap. It begins while the
  // card is still widening and spans most of the motion, so the edge never
  // has to cross the screen in the short, fastest part of a close.
  final rise = Curves.easeInOut.transform(
    ((t - riseFrom) / (1 - riseFrom)).clamp(0.0, 1.0),
  );
  return Rect.fromLTRB(
    lerpDouble(card.left, end.left, across)!,
    lerpDouble(card.top, end.top, rise)!,
    lerpDouble(card.right, end.right, across)!,
    lerpDouble(card.bottom, end.bottom, t)!,
  );
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
