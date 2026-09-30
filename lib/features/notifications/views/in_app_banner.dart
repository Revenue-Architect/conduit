import 'dart:async';

import 'package:flutter/material.dart';

import '../../hermes/feedback/hermez_feedback.dart';
import '../../hermes/motion/hermez_motion_tokens.dart';
import '../../hermes/widgets/hermez_chat_palette.dart';

/// An in-app notification that drops in from the top edge above whatever
/// page is showing, including pages with their own Scaffold (a
/// ScaffoldMessenger snackbar is drawn only on the Scaffold it reaches,
/// which is not the page on screen once another route covers it).
///
/// One at a time: a new banner replaces the one showing. It leaves on its
/// own after [duration], on a swipe up, or when tapped (which opens it).
/// Nothing fades: it slides in on a spring and back out the way it came.
abstract final class HermezInAppBanner {
  static _BannerHandle? _current;

  static void show(
    OverlayState overlay, {
    required String title,
    required String body,
    required VoidCallback onOpen,
    Duration duration = const Duration(seconds: 5),
  }) {
    _current?.remove();
    final handle = _BannerHandle();
    final entry = OverlayEntry(
      builder: (context) => _BannerHost(
        handle: handle,
        title: title,
        body: body,
        onOpen: onOpen,
        duration: duration,
      ),
    );
    handle.entry = entry;
    _current = handle;
    overlay.insert(entry);
  }

  /// Removes any banner at once (tests, sign-out).
  @visibleForTesting
  static void hide() {
    _current?.remove();
    _current = null;
  }
}

class _BannerHandle {
  OverlayEntry? entry;
  void remove() {
    final e = entry;
    entry = null;
    if (e != null && e.mounted) e.remove();
    if (HermezInAppBanner._current == this) HermezInAppBanner._current = null;
  }
}

class _BannerHost extends StatefulWidget {
  const _BannerHost({
    required this.handle,
    required this.title,
    required this.body,
    required this.onOpen,
    required this.duration,
  });

  final _BannerHandle handle;
  final String title;
  final String body;
  final VoidCallback onOpen;
  final Duration duration;

  @override
  State<_BannerHost> createState() => _BannerHostState();
}

class _BannerHostState extends State<_BannerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: HermezMotion.settleFor(HermezMotionWeight.medium),
    reverseDuration: const Duration(milliseconds: 200),
  );
  Timer? _timer;
  double _drag = 0;
  bool _leaving = false;

  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _leave);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (_slide.isDismissed && !_leaving) {
      _reduced = reduced;
      if (reduced) {
        _slide.value = 1;
      } else {
        unawaited(_slide.forward());
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _slide.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    if (!_reduced) await _slide.reverse();
    widget.handle.remove();
  }

  void _open() {
    HermezFeedback.play(HermezFeedbackCue.objectOpen);
    widget.onOpen();
    unawaited(_leave());
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final curve = CurvedAnimation(
      parent: _slide,
      curve: HermezMotion.curveMedium,
      reverseCurve: Curves.easeInCubic,
    );
    return Positioned(
      left: 12,
      right: 12,
      top: media.padding.top + 8,
      child: AnimatedBuilder(
        animation: curve,
        builder: (context, child) => FractionalTranslation(
          translation: Offset(0, -1.3 * (1 - curve.value)),
          child: Transform.translate(offset: Offset(0, _drag), child: child),
        ),
        child: GestureDetector(
          onTap: _open,
          onVerticalDragUpdate: (details) => setState(
            () => _drag = (_drag + details.delta.dy).clamp(-200, 12),
          ),
          onVerticalDragEnd: (details) {
            if (_drag < -24 || (details.primaryVelocity ?? 0) < -300) {
              unawaited(_leave());
            } else {
              setState(() => _drag = 0);
            }
          },
          child: Semantics(
            container: true,
            liveRegion: true,
            button: true,
            label: '${widget.title}. ${widget.body}',
            onTapHint: 'Open',
            child: Material(
              color: palette.surface,
              elevation: 8,
              shadowColor: const Color(0x33000000),
              borderRadius: BorderRadius.circular(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: palette.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (widget.body.isNotEmpty)
                              Text(
                                widget.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: palette.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
