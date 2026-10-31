import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../../navigation/widgets/physical_side_nav.dart'
    show kSideNavCurve, snapToDevicePixels;
import '../../profile/views/profile_page.dart';
import '../manga/manga_pick_launch.dart' show MangaPickTab;
import '../providers/hermes_unread_providers.dart'
    show hermesUnreadSessionIdsProvider;
import '../widgets/hermes_home_needs_you.dart' show watchHermesNeedsYou;
import '../widgets/hermes_tab_dock.dart';
import 'hermes_home_page.dart';

/// Phone home of the Hermes app: Today, Chats and You behind one floating
/// bottom dock (docs/app-design-2026-10-30: Work folds into Today). Each tab keeps its own state and scroll position; switching
/// settles the arriving tab into place from the side it came from.
/// The tab the shell showed last, for this app session.
int _lastHermesTab = 0;

class HermesTabShell extends ConsumerStatefulWidget {
  const HermesTabShell({super.key, this.initialIndex, this.openPick = false});

  /// Land on Chats (the character selector): the cold-start landing.
  final bool openPick;

  /// The tab to open on; null reopens the tab last shown, so Back from a
  /// chat lands where the chat was opened from.
  final int? initialIndex;

  @override
  ConsumerState<HermesTabShell> createState() => _HermesTabShellState();
}

class _HermesTabShellState extends ConsumerState<HermesTabShell> {
  // A cold start lands on Chats, the character selector.
  late int _index = widget.openPick ? 1 : widget.initialIndex ?? _lastHermesTab;
  int _previous = 0;

  void _select(int index) {
    if (index == _index) return;
    setState(() {
      _previous = _index;
      _index = index;
    });
    _lastHermesTab = index;
  }

  /// Today's icon follows the sky: the moon from 19:00 to 6:00.
  bool get _night {
    final hour = DateTime.now().hour;
    return hour >= 19 || hour < 6;
  }

  @override
  Widget build(BuildContext context) {
    // The same list Today's Needs you shows, so the dot and the section agree.
    final needsYou = watchHermesNeedsYou(ref).any((item) => item.actionable);
    // Work's inbox holds Chief's Bot Chat and the other conversations.
    final unread = ref.watch(
      hermesUnreadSessionIdsProvider.select((ids) => ids.length),
    );
    final pages = const <Widget>[
      // Today: what happened and what needs the owner, then what is running.
      HermesHomePage(),
      // Chats is the character selector: pick a bot, give it a task.
      MangaPickTab(),
      ProfilePage(),
    ];
    // The shell owns its system bars: arriving from the side navigation (drawn
    // in the opposite theme) must not leave its icon colours behind.
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
      child: PopScope(
        // Back on another tab returns to Today before it leaves the app.
        canPop: _index == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _select(0);
        },
        child: HermesDockScope(
          index: _index,
          select: _select,
          child: Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(
                  index: _index,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      _TabPane(
                        active: i == _index,
                        fromRight: _index > _previous,
                        child: pages[i],
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: HermesTabDock(
                  index: _index,
                  onSelect: _select,
                  destinations: [
                    HermesDockDestination(
                      label: 'Today',
                      icon: _night
                          ? Icons.dark_mode_outlined
                          : Icons.wb_sunny_outlined,
                      selectedIcon: _night
                          ? Icons.dark_mode_rounded
                          : Icons.wb_sunny_rounded,
                      badge: needsYou && _index != 0,
                    ),
                    HermesDockDestination(
                      label: 'Chats',
                      icon: Icons.chat_bubble_outline_rounded,
                      selectedIcon: Icons.chat_bubble_rounded,
                      unread: unread,
                    ),
                    const HermesDockDestination(
                      label: 'You',
                      icon: Icons.person_outline_rounded,
                      selectedIcon: Icons.person_rounded,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settles a tab into place when it becomes the shown one: a short slide from
/// the side of travel on the side navigation's curve, no fade (a fading page
/// renders offscreen every frame).
class _TabPane extends StatefulWidget {
  const _TabPane({
    required this.active,
    required this.fromRight,
    required this.child,
  });

  final bool active;
  final bool fromRight;
  final Widget child;

  @override
  State<_TabPane> createState() => _TabPaneState();
}

class _TabPaneState extends State<_TabPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  @override
  void didUpdateWidget(_TabPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !context.reduceMotion) {
      _settle.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: widget.active,
    child: AnimatedBuilder(
      animation: _settle,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final t = kSideNavCurve.transform(_settle.value);
        final shift = (widget.fromRight ? 18.0 : -18.0) * (1 - t);
        return Transform.translate(
          offset: Offset(
            snapToDevicePixels(shift, MediaQuery.devicePixelRatioOf(context)),
            0,
          ),
          child: child,
        );
      },
    ),
  );
}
