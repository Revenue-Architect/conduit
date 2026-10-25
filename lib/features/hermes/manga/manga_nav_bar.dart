import 'package:flutter/material.dart';

import '../widgets/hermes_tab_dock.dart'
    show HermesDockDestination, hermesDockClearance;
import 'manga_theme.dart';
import 'manga_widgets.dart';

/// The page's bottom bar: flat on the paper with a hairline above, M3's
/// active-indicator pill behind the chosen icon. Exactly as tall as the
/// clearance the pages already leave for the floating dock, so nothing
/// scrolls under it twice.
///
/// Tabs change tens of times a day, so the only motion is the pill's tint
/// cross-fading in 180 ms; no slide, no bounce.
class MangaNavBar extends StatelessWidget {
  const MangaNavBar({
    super.key,
    required this.destinations,
    required this.index,
    required this.onSelect,
  });

  final List<HermesDockDestination> destinations;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    final height = hermesDockClearance(context);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: ink.ground,
          border: Border(top: BorderSide(color: ink.rule)),
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: MangaPress(
                  semanticLabel: destinations[i].label,
                  scale: .95,
                  onTap: () => onSelect(i),
                  child: _Item(
                    destination: destinations[i],
                    selected: i == index,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.destination, required this.selected});

  final HermesDockDestination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    final colour = selected ? ink.ink : ink.ink3;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: MangaMotion.swap,
              curve: MangaMotion.easeOut,
              width: 64,
              height: 32,
              decoration: BoxDecoration(
                color: selected
                    ? ink.ink.withValues(alpha: .12)
                    : ink.ink.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 24,
                color: colour,
              ),
            ),
            if (destination.badge)
              Positioned(
                right: 14,
                top: 3,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: ink.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(destination.label, style: MangaType.label(colour)),
      ],
    );
  }
}
