import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../../navigation/widgets/physical_side_nav.dart'
    show kSideNavCurve, kSideNavItemStagger, snapToDevicePixels;
import 'hermez_chat_palette.dart';

/// One destination in the bottom dock.
@immutable
class HermesDockDestination {
  const HermesDockDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badge = false,
    this.unread = 0,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// A small accent dot: something here needs the owner.
  final bool badge;

  /// Conversations here with something the owner has not seen. Shown as a
  /// count, which takes the dot's place.
  final int unread;
}

/// Height of the dock itself, without the system inset under it.
const double kHermesDockHeight = 62;

/// Gap between the dock and the bottom system inset.
const double kHermesDockGap = 10;

/// How far content must keep clear of the bottom edge so its last row (or a
/// docked composer) is never hidden under the floating dock.
double hermesDockClearance(BuildContext context) =>
    HermesDockScope.maybeOf(context) == null
    ? 0
    : kHermesDockHeight +
          kHermesDockGap +
          math.max(MediaQuery.paddingOf(context).bottom, 8);

/// Published by the tab shell: which tab shows, and a way to switch.
class HermesDockScope extends InheritedWidget {
  const HermesDockScope({
    super.key,
    required this.index,
    required this.select,
    required super.child,
  });

  final int index;
  final ValueChanged<int> select;

  static HermesDockScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HermesDockScope>();

  @override
  bool updateShouldNotify(HermesDockScope oldWidget) =>
      oldWidget.index != index || oldWidget.select != select;
}

/// The bottom navigation: a floating pill drawn in the opposite theme (dark
/// under a light app, light under a dark one), the same material as the side
/// navigation it replaces on phones. The selection is one indicator that
/// glides between destinations on the side navigation's curve; the
/// destinations settle in with its stagger when the dock arrives. It steps
/// out of the way while the keyboard is up.
class HermesTabDock extends StatefulWidget {
  const HermesTabDock({
    super.key,
    required this.destinations,
    required this.index,
    required this.onSelect,
  });

  final List<HermesDockDestination> destinations;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  State<HermesTabDock> createState() => _HermesTabDockState();
}

class _HermesTabDockState extends State<HermesTabDock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _arrival = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void initState() {
    super.initState();
    _arrival.forward();
  }

  @override
  void dispose() {
    _arrival.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == widget.index) return;
    HapticFeedback.selectionClick();
    widget.onSelect(index);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // Reversed: the dock wears the other mode's canvas and ink.
    final reversed = HermezChatPalette.forBrightness(
      brightness == Brightness.dark ? Brightness.light : Brightness.dark,
    );
    final app = HermezChatPalette.forBrightness(brightness);
    final reduceMotion = context.reduceMotion;
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottom = math.max(MediaQuery.paddingOf(context).bottom, 8.0);
    final count = widget.destinations.length;
    final glide = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 380);

    return AnimatedSlide(
      offset: keyboardUp ? const Offset(0, 1.6) : Offset.zero,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: kSideNavCurve,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + kHermesDockGap),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: reversed.canvas,
              borderRadius: BorderRadius.circular(kHermesDockHeight / 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF000000).withValues(
                    alpha: brightness == Brightness.dark ? 0.45 : 0.18,
                  ),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SizedBox(
              height: kHermesDockHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const inset = 6.0;
                  final slot = (constraints.maxWidth - inset * 2) / count;
                  return Stack(
                    children: [
                      // The one selection, gliding between destinations.
                      AnimatedPositioned(
                        duration: glide,
                        curve: kSideNavCurve,
                        left: inset + slot * widget.index,
                        top: inset,
                        bottom: inset,
                        width: slot,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: reversed.surface,
                            borderRadius: BorderRadius.circular(
                              (kHermesDockHeight - inset * 2) / 2,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: inset),
                        child: Row(
                          children: [
                            for (var i = 0; i < count; i++)
                              Expanded(
                                child: _DockItem(
                                  destination: widget.destinations[i],
                                  selected: i == widget.index,
                                  arrival: _arrival,
                                  order: i,
                                  reduceMotion: reduceMotion,
                                  ink: reversed.ink,
                                  muted: reversed.muted,
                                  cutout: reversed.canvas,
                                  accent: app.accent,
                                  onTap: () => _select(i),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatefulWidget {
  const _DockItem({
    required this.destination,
    required this.selected,
    required this.arrival,
    required this.order,
    required this.reduceMotion,
    required this.ink,
    required this.muted,
    required this.cutout,
    required this.accent,
    required this.onTap,
  });

  final HermesDockDestination destination;
  final bool selected;
  final Animation<double> arrival;
  final int order;
  final bool reduceMotion;
  final Color ink, muted, cutout, accent;
  final VoidCallback onTap;

  @override
  State<_DockItem> createState() => _DockItemState();
}

class _DockItemState extends State<_DockItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.destination;
    final color = widget.selected ? widget.ink : widget.muted;
    final item = Semantics(
      button: true,
      selected: widget.selected,
      label: [
        d.label,
        if (d.unread > 0) '${d.unread} unread',
        if (d.badge) 'needs you',
      ].join(', '),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: widget.reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: Icon(
                      widget.selected ? d.selectedIcon : d.icon,
                      key: ValueKey(widget.selected),
                      size: 22,
                      color: color,
                    ),
                  ),
                  if (d.unread > 0)
                    Positioned(
                      left: 13,
                      top: -7,
                      child: _UnreadCount(
                        count: d.unread,
                        fill: widget.accent,
                        cutout: widget.cutout,
                        reduceMotion: widget.reduceMotion,
                      ),
                    )
                  else if (d.badge)
                    Positioned(
                      right: -3,
                      top: -1,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: widget.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
                child: Text(
                  d.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (widget.reduceMotion) return item;
    // Destinations settle into place one after another as the dock arrives,
    // like the side navigation's blocks: a rise, no fade.
    return AnimatedBuilder(
      animation: widget.arrival,
      child: RepaintBoundary(child: item),
      builder: (context, child) {
        final step =
            kSideNavItemStagger.inMicroseconds /
            const Duration(milliseconds: 520).inMicroseconds;
        final delay = math.min(widget.order * step, 0.5);
        final local = kSideNavCurve.transform(
          ((widget.arrival.value - delay) / (1 - delay)).clamp(0.0, 1.0),
        );
        return Transform.translate(
          offset: Offset(
            0,
            snapToDevicePixels(
              14 * (1 - local),
              MediaQuery.devicePixelRatioOf(context),
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// The unread count on a destination: an accent pill cut out of the dock, so
/// it reads on the icon it overlaps. It springs in when it first appears and
/// pops when the number changes.
class _UnreadCount extends StatelessWidget {
  const _UnreadCount({
    required this.count,
    required this.fill,
    required this.cutout,
    required this.reduceMotion,
  });

  final int count;
  final Color fill, cutout;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final label = count > 9 ? '9+' : '$count';
    final ink = fill.computeLuminance() > 0.5
        ? const Color(0xFF111111)
        : const Color(0xFFFFFFFF);
    final pill = Container(
      constraints: const BoxConstraints(minWidth: 19),
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 4.5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cutout, width: 2),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: ink,
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    if (reduceMotion) return pill;
    return TweenAnimationBuilder<double>(
      // A new number starts the pop again.
      key: ValueKey(label),
      tween: Tween(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: t, child: child),
      child: pill,
    );
  }
}
