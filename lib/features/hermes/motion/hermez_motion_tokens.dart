import 'package:nib_motion/nib_motion.dart';

import '../../../core/services/navigation_service.dart';
import '../models/hermes_config.dart';

/// Physical weights for Hermez objects. Screens pick a weight, not raw springs.
enum HermezMotionWeight { light, medium, heavy }

/// How a Hermez route relates to the screen it came from.
enum HermezRouteMotion { standard, morph, sharedAxis, modal }

/// Hermez-owned motion constants.
///
/// Conduit's [AnimationService] still serves the rest of the app. Hermez
/// physical motion does not go through those shortened duration helpers.
abstract final class HermezMotion {
  static const springLight = NibSpringDescription(
    mass: 0.65,
    stiffness: 420,
    damping: 32,
  );
  static const springMedium = NibSpringDescription(
    mass: 0.9,
    stiffness: 340,
    damping: 30,
  );
  static const springHeavy = NibSpringDescription(
    mass: 1.1,
    stiffness: 260,
    damping: 28,
  );

  static const staggerFast = Duration(milliseconds: 25);
  static const staggerNormal = Duration(milliseconds: 35);

  /// Source screen recedes this far while a morph route covers it.
  static const sourceBackgroundScale = 0.988;

  static const pressLight = 0.96;
  static const pressCard = 0.98;
  static const pressHeavy = 0.99;

  static NibSpringDescription springFor(HermezMotionWeight weight) =>
      switch (weight) {
        HermezMotionWeight.light => springLight,
        HermezMotionWeight.medium => springMedium,
        HermezMotionWeight.heavy => springHeavy,
      };

  static NibTransition transitionFor(HermezMotionWeight weight) =>
      NibTransition(spring: springFor(weight));

  static double pressScale(HermezMotionWeight weight) => switch (weight) {
    HermezMotionWeight.light => pressLight,
    HermezMotionWeight.medium => pressCard,
    HermezMotionWeight.heavy => pressHeavy,
  };
}

/// Stable shared-element id for one Hermes profile. Null when the name cannot
/// be a profile, so two empty routes cannot share a Hero tag.
String? hermezBotMorphId(String profile) {
  if (!HermesConfig.isValidDesktopProfile(profile)) return null;
  return 'bot:$profile';
}

/// Route category for Hermes destinations. Non-Hermes routes stay on the
/// existing platform transition.
HermezRouteMotion hermezRouteMotionFor(String? routeName) =>
    switch (routeName) {
      RouteNames.hermesBotDetail => HermezRouteMotion.morph,
      _ => HermezRouteMotion.standard,
    };
