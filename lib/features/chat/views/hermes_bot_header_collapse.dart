import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// When the chat's top-center bot avatar and name collapse and expand.
///
/// Only the user's own scrolling moves it: a drag that travels
/// [collapseDistance] from where it started collapses the header, and it
/// expands only once the user is back at the latest messages and has stayed
/// there for [settleDelay]. Pauses while reading older messages keep it
/// compact, and resuming a drag cancels a pending expansion.
///
/// Callers forward viewport changes with [userScrolled] only while
/// [tracksUserMotion] is true (a drag, its fling, or a jump-to-latest the user
/// asked for), so streamed text, auto-follow, keyboard insets, overscroll
/// bounce and layout passes never change the header on their own.
class HermesBotHeaderCollapse {
  HermesBotHeaderCollapse({
    this.collapseDistance = 48,
    this.settleDelay = const Duration(milliseconds: 700),
    this.motionIdle = const Duration(milliseconds: 250),
    this.motionCap = const Duration(milliseconds: 1500),
  });

  final double collapseDistance;
  final Duration settleDelay;

  /// A released drag's fling (or a requested jump) counts as user motion until
  /// the viewport has been still this long...
  final Duration motionIdle;

  /// ...or at most this long, so a streaming reply can't keep it open.
  final Duration motionCap;

  /// True while the header shows the 33 dp avatar without its name.
  final ValueNotifier<bool> compact = ValueNotifier(false);

  bool _dragging = false;
  double? _dragOrigin;
  bool _motion = false;
  bool _atLatest = true;
  Timer? _expand;
  Timer? _idle;
  Timer? _cap;

  @visibleForTesting
  bool get expansionPending => _expand != null;

  /// Whether viewport changes right now come from the user's own scrolling.
  bool get tracksUserMotion => _dragging || _motion;

  void userDragStarted(double distanceFromLatest) {
    _dragging = true;
    _dragOrigin = math.max(0, distanceFromLatest);
    _endMotionWindow();
    _cancelExpansion();
  }

  /// A viewport change during user motion. [atLatest] is whether the latest
  /// messages are in view (the same threshold the jump button uses).
  void userScrolled(double distanceFromLatest, {required bool atLatest}) {
    if (!tracksUserMotion) return;
    _atLatest = atLatest;
    if (_dragging) {
      final origin = _dragOrigin;
      // Overscroll past the latest edge reports a negative distance: clamp it
      // so a bounce never counts as travel.
      final travelled = origin == null
          ? 0.0
          : (math.max(0.0, distanceFromLatest) - origin).abs();
      if (!compact.value && travelled >= collapseDistance) {
        compact.value = true;
      }
      _cancelExpansion();
      return;
    }
    _touchMotionWindow();
    if (!atLatest) {
      _cancelExpansion();
    } else if (_expand == null) {
      _scheduleExpansion();
    }
  }

  void userDragEnded({required bool atLatest}) {
    _dragging = false;
    _dragOrigin = null;
    _atLatest = atLatest;
    _openMotionWindow();
    if (atLatest) {
      _scheduleExpansion();
    } else {
      _cancelExpansion();
    }
  }

  /// The user asked to go to the latest messages (the jump button). The
  /// header expands once the view gets there and stays.
  void userRequestedLatest() {
    if (_dragging) return;
    _openMotionWindow();
  }

  /// A different conversation opened: start expanded and forget old motion.
  void reset() {
    _dragging = false;
    _dragOrigin = null;
    _atLatest = true;
    _endMotionWindow();
    _cancelExpansion();
    compact.value = false;
  }

  void dispose() {
    _endMotionWindow();
    _cancelExpansion();
    compact.dispose();
  }

  void _scheduleExpansion() {
    if (!compact.value) return;
    _expand?.cancel();
    _expand = Timer(settleDelay, () {
      _expand = null;
      if (_dragging || !_atLatest) return;
      compact.value = false;
    });
  }

  void _cancelExpansion() {
    _expand?.cancel();
    _expand = null;
  }

  void _openMotionWindow() {
    _endMotionWindow();
    _motion = true;
    _touchMotionWindow();
    _cap = Timer(motionCap, _endMotionWindow);
  }

  void _touchMotionWindow() {
    if (!_motion) return;
    _idle?.cancel();
    _idle = Timer(motionIdle, _endMotionWindow);
  }

  void _endMotionWindow() {
    _motion = false;
    _idle?.cancel();
    _idle = null;
    _cap?.cancel();
    _cap = null;
  }
}
