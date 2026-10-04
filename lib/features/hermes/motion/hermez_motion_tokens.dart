import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';
import 'package:nib_motion/nib_motion.dart';

import '../models/hermes_config.dart';

/// Physical weights for Hermez objects. Screens pick a weight, not raw springs.
///
/// Larger objects carry more mass: they compress less and settle slower.
enum HermezMotionWeight { light, medium, heavy }

/// How a Hermez route relates to the screen it came from.
enum HermezRouteMotion {
  /// A sibling destination with no single source object. The page slides in
  /// from the trailing edge and the source shifts back. No opacity change.
  standard,

  /// The destination grows out of the object the user touched. Requires a
  /// [HermezMorphOrigin]; without one it falls back to [standard].
  expand,

  /// No transition: reduced motion, or a native-sheet handoff.
  none,
}

/// Hermez-owned motion constants.
///
/// Conduit's `AnimationService` still serves the rest of the app. Hermez
/// physical motion does not go through those shortened duration helpers, and
/// nothing in Hermez animates opacity: objects travel, grow, and recede.
abstract final class HermezMotion {
  static const springLight = NibSpringDescription(
    mass: 0.65,
    stiffness: 420,
    damping: 32,
  );
  // Critically damped (response ~0.32 s). A slightly bouncy spring here
  // overshot by 0.5 %; clamped to [0, 1] that became a dead hold for the
  // second half of every medium animation, so closes stopped, sat still,
  // and then snapped when the route or presence finished.
  static const springMedium = NibSpringDescription(
    mass: 1,
    stiffness: 385,
    damping: 39.3,
  );
  // A growing page or sheet: critically damped, ~0.38 s to rest.
  static const springHeavy = NibSpringDescription(
    mass: 1,
    stiffness: 300,
    damping: 34,
  );

  // A sheet pushing the screen it grew out of: heavier and slower than a
  // page, still critically damped, so the push and the pull read as moving
  // real weight (~0.6 s to rest).
  static const springPush = NibSpringDescription(
    mass: 1.7,
    stiffness: 210,
    damping: 37.8,
  );

  static const staggerFast = Duration(milliseconds: 25);
  static const staggerNormal = Duration(milliseconds: 35);

  /// Source screen recedes this far while an expanding object covers it.
  static const sourceBackgroundScale = 0.988;

  /// How far a sibling page shifts back while another slides over it, as a
  /// fraction of its width.
  static const pushBackShift = 0.14;

  /// Secondary content travels this far into place behind a shared object.
  static const entranceRise = 26.0;

  static const pressLight = 0.955;
  static const pressCard = 0.978;
  static const pressHeavy = 0.99;

  /// Pointer travel that turns a press into a scroll.
  static const pressSlop = 12.0;

  static final HermezSpringCurve curveLight = HermezSpringCurve(springLight);
  static final HermezSpringCurve curveMedium = HermezSpringCurve(springMedium);
  static final HermezSpringCurve curveHeavy = HermezSpringCurve(springHeavy);
  static final HermezSpringCurve curvePush = HermezSpringCurve(springPush);

  /// A sheet going home into its card. The flipped spring left at full
  /// speed and threw the sheet down in its first tenth of a second; this
  /// eases off the screen and settles into the card.
  static const Curve sheetClose = Curves.easeInOut;

  static NibSpringDescription springFor(HermezMotionWeight weight) =>
      switch (weight) {
        HermezMotionWeight.light => springLight,
        HermezMotionWeight.medium => springMedium,
        HermezMotionWeight.heavy => springHeavy,
      };

  static HermezSpringCurve curveFor(HermezMotionWeight weight) =>
      switch (weight) {
        HermezMotionWeight.light => curveLight,
        HermezMotionWeight.medium => curveMedium,
        HermezMotionWeight.heavy => curveHeavy,
      };

  /// How long a spring of this weight takes to settle from rest to rest.
  static Duration settleFor(HermezMotionWeight weight) =>
      curveFor(weight).settleDuration;

  static NibTransition transitionFor(HermezMotionWeight weight) =>
      NibTransition(spring: springFor(weight));

  static double pressScale(HermezMotionWeight weight) => switch (weight) {
    HermezMotionWeight.light => pressLight,
    HermezMotionWeight.medium => pressCard,
    HermezMotionWeight.heavy => pressHeavy,
  };
}

/// A [Curve] that follows a Hermez spring from rest at 0 to rest at 1.
///
/// Route controllers and [AnimatedSize] are driven by time. This lets them
/// move with the same physics as NibMotion's spring solver: the curve is the
/// spring's own position, sampled over the time it takes to settle.
class HermezSpringCurve extends Curve {
  HermezSpringCurve(this.spring)
    : _simulation = SpringSimulation(spring.toFlutter(), 0, 1, 0),
      _settleSeconds = _settleTime(spring) {
    _endValue = _simulation.x(_settleSeconds);
  }

  final NibSpringDescription spring;
  final SpringSimulation _simulation;
  final double _settleSeconds;
  late final double _endValue;

  Duration get settleDuration =>
      Duration(microseconds: (_settleSeconds * 1e6).round());

  // The spring is sampled up to the moment it is visibly at rest and scaled
  // so that moment is exactly 1. Without the scaling the last frame jumped
  // the remaining fraction (a pixel or more on a full-screen zoom) when the
  // controller snapped to its end. Hermez springs are close to critically
  // damped, so any overshoot is a fraction of a pixel; clamping keeps Hero
  // flights and intervals, which require values in [0, 1], safe.
  @override
  double transformInternal(double t) =>
      (_simulation.x(t * _settleSeconds) / _endValue).clamp(0.0, 1.0);

  static double _settleTime(NibSpringDescription spring) {
    final simulation = SpringSimulation(spring.toFlutter(), 0, 1, 0);
    const step = 1 / 600;
    for (var time = step; time < 3; time += step) {
      // Visibly at rest: within 0.8 % of the target and moving under a
      // pixel a frame. The curve is rescaled so this moment is exactly 1.
      // A tighter test only added a long, invisible tail that kept routes
      // (and whatever waits for them) running after the motion had ended.
      if ((simulation.x(time) - 1).abs() < 0.008 &&
          simulation.dx(time).abs() < 0.15) {
        return time;
      }
    }
    return 3;
  }
}

/// Stable shared-element id for one Hermes profile. Null when the name cannot
/// be a profile, so two empty routes cannot share a Hero tag.
String? hermezBotMorphId(String profile) {
  if (!HermesConfig.isValidDesktopProfile(profile)) return null;
  return 'bot:$profile';
}

/// Part of a morphing object. The whole object and each part it carries keep
/// separate tags so every part can fly with its own geometry.
String? hermezMorphPart(String? id, String part) =>
    id == null ? null : '$id#$part';

/// The Home schedule summary and the Jobs workspace it opens.
const hermezScheduleMorphId = 'schedule:summary';

/// The Home board summary and the Kanban workspace it opens.
const hermezBoardMorphId = 'kanban:summary';

String? hermezKanbanTaskMorphId(String? board, String? taskId) {
  if (board == null || board.isEmpty || taskId == null || taskId.isEmpty) {
    return null;
  }
  return 'kanban:$board:$taskId';
}

String? hermezArtifactMorphId(String? path) =>
    path == null || path.isEmpty ? null : 'artifact:$path';

String? hermezJobMorphId(String? profile, String? jobId) =>
    jobId == null || jobId.isEmpty ? null : 'job:${profile ?? ''}:$jobId';

String? hermezBrowserMorphId(String? sessionId) =>
    sessionId == null || sessionId.isEmpty
    ? null
    : 'session:$sessionId:browser';
