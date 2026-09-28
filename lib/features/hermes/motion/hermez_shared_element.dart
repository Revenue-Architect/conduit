import 'package:flutter/material.dart';

import '../../../shared/theme/theme_extensions.dart';

/// Cross-route continuity for one object. Backed by Flutter [Hero].
///
/// Reduced motion drops the flight and leaves the child in place so navigation
/// still works. A null [id] also skips the flight, which avoids empty-profile
/// collisions.
class HermezMorph extends StatelessWidget {
  const HermezMorph({super.key, required this.id, required this.child});

  final String? id;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tag = id;
    if (tag == null || context.reduceMotion) return child;
    return Hero(
      tag: tag,
      flightShuttleBuilder:
          (
            flightContext,
            animation,
            flightDirection,
            fromHeroContext,
            toHeroContext,
          ) {
            final hero = toHeroContext.widget;
            return hero is Hero ? hero.child : hero;
          },
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
