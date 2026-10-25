import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../../navigation/widgets/physical_side_nav.dart'
    show kSideNavCurve, snapToDevicePixels;
import '../../profile/views/profile_page.dart';
import '../manga/manga_pick_launch.dart' show openMangaPick;
import '../providers/hermes_providers.dart' show hermesBotsProvider;
import '../widgets/hermes_home_needs_you.dart' show watchHermesNeedsYou;
import '../widgets/hermes_tab_dock.dart';
import 'hermes_conversations_page.dart';
import 'hermes_home_page.dart';
import 'hermes_work_page.dart';

/// Phone home of the Hermes app: Home, Chats, Work and You behind one floating
/// bottom dock. Each tab keeps its own state and scroll position; switching
/// settles the arriving tab into place from the side it came from.
/// The tab the shell showed last, for this app session.
int _lastHermesTab = 0;

class HermesTabShell extends ConsumerStatefulWidget {
  const HermesTabShell({super.key, this.initialIndex, this.openPick = false});

  /// Open Pick, the character selector, over Home: the cold-start landing.
  final bool openPick;

  /// The tab to open on; null reopens the tab last shown, so Back from a
  /// chat lands where the chat was opened from.
  final int? initialIndex;

  @override
  ConsumerState<HermesTabShell> createState() => _HermesTabShellState();
}

class _HermesTabShellState extends ConsumerState<HermesTabShell> {
  late int _index = widget.initialIndex ?? _lastHermesTab;
  int _previous = 0;

  /// Pick opens on launch once per app process, not on every rebuild.
  static bool _launchPickShown = false;

  @override
  void initState() {
    super.initState();
    _lastHermesTab = _index;
    if (widget.openPick && !_launchPickShown) {
      _launchPickShown = true;
      unawaited(_openPickWhenReady());
    }
  }

  /// Waits for the bot list (Pick needs it), then lands on Pick.
  Future<void> _openPickWhenReady() async {
    try {
      await ref.read(hermesBotsProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    await openMangaPick(context, ref, instant: true);
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() {
      _previous = _index;
      _index = index;
    });
    _lastHermesTab = index;
  }

  @override
  Widget build(BuildContext context) {
    // The same list Work's Needs you shows, so the dot and the section agree.
    final needsYou = watchHermesNeedsYou(ref).any((item) => item.actionable);
    final pages = const <Widget>[
      // Home is the hub; Work is what needs the owner and what is running.
      HermesWorkPage(),
      HermesConversationsPage(),
      HermesHomePage(),
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
        // Back on another tab returns Home before it leaves the app.
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
                    const HermesDockDestination(
                      label: 'Home',
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home_rounded,
                    ),
                    const HermesDockDestination(
                      label: 'Chats',
                      icon: Icons.chat_bubble_outline_rounded,
                      selectedIcon: Icons.chat_bubble_rounded,
                    ),
                    HermesDockDestination(
                      label: 'Work',
                      icon: Icons.layers_outlined,
                      selectedIcon: Icons.layers_rounded,
                      badge: needsYou && _index != 2,
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
