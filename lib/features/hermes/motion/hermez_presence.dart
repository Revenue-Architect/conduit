import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:nib_motion/nib_motion.dart';

import '../../../shared/theme/theme_extensions.dart';
import 'hermez_motion_route.dart';
import 'hermez_motion_tokens.dart';

/// Enter and leave for a widget that really mounts and unmounts.
///
/// Nothing fades. An entering child unrolls from its top edge while it slides
/// a few pixels into place; a leaving child rolls up. [presenceKey] must stay
/// stable for that object; rebuilds with the same key do not replay anything.
class HermezPresence extends StatelessWidget {
  const HermezPresence({
    super.key,
    required this.presenceKey,
    required this.child,
    this.weight = HermezMotionWeight.light,
    this.alignment = AlignmentDirectional.topStart,
  });

  final Key presenceKey;
  final Widget? child;
  final HermezMotionWeight weight;
  final AlignmentDirectional alignment;

  @override
  Widget build(BuildContext context) {
    final reduced = context.reduceMotion;
    final current = child;
    final curve = HermezMotion.curveFor(weight);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : HermezMotion.settleFor(weight),
      reverseDuration: reduced
          ? Duration.zero
          : HermezMotion.settleFor(HermezMotionWeight.light),
      switchInCurve: curve,
      switchOutCurve: HermezMotion.curveLight.flipped,
      layoutBuilder: (currentChild, previousChildren) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) =>
          HermezUnroll(animation: animation, child: child),
      child: current == null
          ? const SizedBox.shrink(key: ValueKey('hermez-presence-empty'))
          : KeyedSubtree(key: presenceKey, child: current),
    );
  }
}

/// Shows [child] only while [visible], unrolling in and rolling away.
class HermezReveal extends StatelessWidget {
  const HermezReveal({
    super.key,
    required this.visible,
    required this.child,
    this.weight = HermezMotionWeight.light,
    this.revealKey = const ValueKey('hermez-reveal'),
  });

  final bool visible;
  final Widget child;
  final HermezMotionWeight weight;
  final Key revealKey;

  @override
  Widget build(BuildContext context) => HermezPresence(
    presenceKey: revealKey,
    weight: weight,
    child: visible ? child : null,
  );
}

/// A section that slides out from under its top edge and back under it.
/// Used by presence, groups, and expanding panels. No opacity.
///
/// The content keeps its shape and travels with the moving edge, like a
/// drawer, instead of being sliced by a clip that sweeps across it; that
/// sweep read as the content being cut off at the end of every collapse.
class HermezUnroll extends StatelessWidget {
  const HermezUnroll({super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: animation,
    alignment: AlignmentDirectional.bottomStart,
    // Keep block content at full width while it unrolls, the way it sits in
    // the column around it.
    child: LayoutBuilder(
      builder: (context, constraints) => constraints.hasBoundedWidth
          ? SizedBox(width: constraints.maxWidth, child: child)
          : child,
    ),
  );
}

/// Fade-free [AnimatedSwitcher] transitions for the rest of the app.
abstract final class HermezSwitch {
  /// A glyph that changes meaning in place: the old one turns and shrinks
  /// away while the new one turns and grows in the same spot.
  static Widget glyph(Widget child, Animation<double> animation) =>
      ScaleTransition(
        scale: animation,
        child: RotationTransition(
          turns: animation.drive(Tween<double>(begin: -0.12, end: 0)),
          child: child,
        ),
      );

  /// A block that slides out from under its top edge and back under it,
  /// keeping its own width (unlike [HermezUnroll], which fills the column).
  static Widget unroll(Widget child, Animation<double> animation) =>
      SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.bottomCenter,
        child: child,
      );

  /// Keeps the leaving block above the arriving one, each at its own
  /// height, so the space closes smoothly instead of dropping at the end.
  static Widget column(Widget? current, List<Widget> previous) =>
      Column(mainAxisSize: MainAxisSize.min, children: [...previous, ?current]);
}

/// An icon that changes meaning in place: the old glyph turns and shrinks
/// away while the new one turns and grows in the same spot. No opacity.
class HermezIconSwap extends StatelessWidget {
  const HermezIconSwap({
    super.key,
    required this.icon,
    this.color,
    this.size = 24,
  });

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reduced = context.reduceMotion;
    return SizedBox.square(
      dimension: size,
      child: AnimatedSwitcher(
        duration: reduced
            ? Duration.zero
            : HermezMotion.settleFor(HermezMotionWeight.light),
        switchInCurve: HermezMotion.curveLight,
        switchOutCurve: HermezMotion.curveLight.flipped,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: RotationTransition(
            turns: Tween<double>(begin: -0.12, end: 0).animate(animation),
            child: child,
          ),
        ),
        child: Icon(icon, key: ValueKey(icon), color: color, size: size),
      ),
    );
  }
}

/// A container that changes size on a Hermez spring instead of a tween.
class HermezSize extends StatelessWidget {
  const HermezSize({
    super.key,
    required this.child,
    this.weight = HermezMotionWeight.medium,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final HermezMotionWeight weight;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: context.reduceMotion
        ? Duration.zero
        : HermezMotion.settleFor(weight),
    curve: HermezMotion.curveFor(weight),
    alignment: alignment,
    child: child,
  );
}

/// Secondary content of a destination that grew out of a shared object.
///
/// The section is laid out in place from the first frame, so nothing around
/// it moves. It unrolls from its top edge and settles upward after the shared
/// object has started to arrive, and rolls away first on Back. [order]
/// staggers nearby sections. Outside an expanding Hermez route, or with
/// reduced motion, this is a plain child.
class HermezEntrance extends StatelessWidget {
  const HermezEntrance({super.key, required this.order, required this.child});

  final int order;
  final Widget child;

  /// Expanding routes now zoom the whole destination as one object, so
  /// sections no longer move on their own timing. Kept as an explicit marker
  /// for secondary content; set [staggered] to restore the unroll.
  static const staggered = false;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (!staggered ||
        animation == null ||
        route is! HermezRouteTransitions ||
        route.effectiveMotion != HermezRouteMotion.expand ||
        context.reduceMotion) {
      return child;
    }
    final start = 0.16 + order.clamp(0, 6) * 0.06;
    final settle = CurvedAnimation(
      parent: animation,
      curve: Interval(start, 1, curve: HermezMotion.curveMedium),
      // On Back the route runs from 1 to 0: sections have rolled away by the
      // time the shared object is halfway home.
      reverseCurve: Interval(0.55, 1, curve: HermezMotion.curveMedium.flipped),
    );
    return AnimatedBuilder(
      animation: settle,
      child: child,
      builder: (context, child) {
        final value = settle.value.clamp(0.0, 1.0);
        if (value >= 1) return child!;
        return ClipRect(
          clipper: _TopReveal(value),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * HermezMotion.entranceRise),
            child: child,
          ),
        );
      },
    );
  }
}

class _TopReveal extends CustomClipper<Rect> {
  const _TopReveal(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(-8, -8, size.width + 16, size.height * fraction + 8);

  @override
  bool shouldReclip(_TopReveal oldClipper) => oldClipper.fraction != fraction;
}

/// A short keyed column whose children travel when they move, unroll when
/// they arrive, and roll away when they leave. Children must carry unique
/// keys. Do not wrap a long scrolling list.
class HermezMotionGroup extends StatefulWidget {
  const HermezMotionGroup({
    super.key,
    required this.children,
    this.weight = HermezMotionWeight.medium,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final HermezMotionWeight weight;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<HermezMotionGroup> createState() => _HermezMotionGroupState();
}

class _GroupEntry {
  _GroupEntry(this.widget, this.presence);

  Widget widget;
  final AnimationController presence;
  final GlobalKey anchor = GlobalKey();
  final NibMotionController flip = NibMotionController();
  bool exiting = false;

  void dispose() {
    presence.dispose();
    flip.dispose();
  }
}

class _HermezMotionGroupState extends State<HermezMotionGroup>
    with TickerProviderStateMixin {
  final Map<Key, _GroupEntry> _entries = {};
  List<Key> _order = [];

  @override
  void initState() {
    super.initState();
    for (final child in widget.children) {
      final key = child.key!;
      _entries[key] = _GroupEntry(
        child,
        AnimationController(vsync: this, value: 1),
      );
      _order.add(key);
    }
  }

  /// Where each child was after the last completed layout. Positions are only
  /// read after layout, never during a build, where an ancestor may still be
  /// waiting for its own layout.
  final Map<Key, Offset> _settled = {};
  bool _recordScheduled = false;

  Offset? _positionOf(_GroupEntry entry) {
    final box = entry.anchor.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    try {
      final position = box.localToGlobal(Offset.zero);
      return position.isFinite ? position : null;
    } catch (_) {
      return null;
    }
  }

  void _scheduleRecord() {
    if (_recordScheduled) return;
    _recordScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recordScheduled = false;
      if (!mounted) return;
      _settled.clear();
      for (final entry in _entries.entries) {
        if (entry.value.exiting) continue;
        final position = _positionOf(entry.value);
        if (position != null) _settled[entry.key] = position;
      }
    });
  }

  @override
  void didUpdateWidget(covariant HermezMotionGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reduced = context.reduceMotion;
    final before = <Key, Offset>{
      for (final key in _order)
        if (!_entries[key]!.exiting && _settled[key] != null)
          key: _settled[key]!,
    };

    final incoming = <Key, Widget>{
      for (final child in widget.children) child.key!: child,
    };
    final nextOrder = <Key>[...incoming.keys];
    // Keep leaving children where they were so the column closes around them.
    for (var index = 0; index < _order.length; index++) {
      final key = _order[index];
      if (incoming.containsKey(key)) continue;
      final previous = index == 0 ? null : _order[index - 1];
      final at = previous == null ? 0 : nextOrder.indexOf(previous) + 1;
      nextOrder.insert(at.clamp(0, nextOrder.length), key);
    }

    for (final entry in incoming.entries) {
      final existing = _entries[entry.key];
      if (existing != null) {
        existing.widget = entry.value;
        if (existing.exiting) {
          existing.exiting = false;
          _settle(existing.presence, 1, reduced);
        }
        continue;
      }
      final created = _GroupEntry(
        entry.value,
        AnimationController(vsync: this, value: reduced ? 1 : 0),
      );
      _entries[entry.key] = created;
      _settle(created.presence, 1, reduced);
    }

    for (final key in _order) {
      if (incoming.containsKey(key)) continue;
      final entry = _entries[key];
      if (entry == null || entry.exiting) continue;
      entry.exiting = true;
      if (reduced) {
        _remove(key);
        continue;
      }
      _settle(entry.presence, 0, reduced, light: true).whenComplete(() {
        if (!mounted) return;
        final current = _entries[key];
        if (current == null || !current.exiting) return;
        setState(() => _remove(key));
      });
    }

    _order = nextOrder.where(_entries.containsKey).toList();
    if (reduced || before.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final item in before.entries) {
        final entry = _entries[item.key];
        if (entry == null || entry.exiting) continue;
        final after = _positionOf(entry);
        if (after == null) continue;
        final delta = item.value - after;
        if (delta.distanceSquared < 0.25) continue;
        entry.flip.set(NibAnim(x: delta.dx, y: delta.dy));
        entry.flip.start(
          target: const NibAnim(x: 0, y: 0),
          transition: HermezMotion.transitionFor(widget.weight),
        );
      }
    });
  }

  void _remove(Key key) {
    _entries.remove(key)?.dispose();
    _order.remove(key);
  }

  TickerFuture _settle(
    AnimationController controller,
    double target,
    bool reduced, {
    bool light = false,
  }) {
    if (reduced) {
      controller.value = target;
      return TickerFuture.complete();
    }
    final spring = light
        ? HermezMotion.springLight
        : HermezMotion.springFor(widget.weight);
    return controller.animateWith(
      SpringSimulation(spring.toFlutter(), controller.value, target, 0),
    );
  }

  @override
  void dispose() {
    for (final entry in _entries.values) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleRecord();
    return _buildColumn();
  }

  Widget _buildColumn() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: widget.crossAxisAlignment,
    children: [
      for (final key in _order)
        if (_entries[key] case final entry?)
          KeyedSubtree(
            key: key,
            child: IgnorePointer(
              ignoring: entry.exiting,
              child: HermezUnroll(
                animation: entry.presence,
                child: NibMotion(
                  key: entry.anchor,
                  controller: entry.flip,
                  child: entry.widget,
                ),
              ),
            ),
          ),
    ],
  );
}
