import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../models/hermes_config.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_live_activity.dart';
import 'hermez_bot_mark.dart';

/// What a bot is visibly doing. Presentation only, derived from what the
/// Desktop connection already reports for the bot's session; never stored.
enum HermezBotVisualState { idle, active, waiting, completed, failed }

/// The visual state for [session] from the connection's existing, local
/// turn state and activity history. No network, no new subscription to
/// Hermes: both streams are the service's own broadcasts.
HermezBotVisualState hermezBotVisualStateFor(
  HermesDesktopTurnState turn,
  List<HermesLiveActivityEvent> activity,
) {
  if (turn != HermesDesktopTurnState.running) {
    return HermezBotVisualState.idle;
  }
  final last = activity.isEmpty ? null : activity.last;
  return last?.kind == HermesLiveActivityKind.waitingForInput
      ? HermezBotVisualState.waiting
      : HermezBotVisualState.active;
}

/// A [HermezBotMark] that physically shows its bot's state.
///
/// - idle: still; marks of 56 px and up float by about 1.5 px.
/// - active (a live turn): a slow lift and breathing compression.
/// - waiting (the run asked the user something): motion stops except for
///   one short nudge every few seconds.
/// - completed / failed (a new event while shown): an upward impulse, or a
///   small recoil, that settles back to idle.
///
/// Only position and scale move (never opacity). Reduced motion keeps the
/// mark still. Completion and failure sounds belong to the run coordinator,
/// so this plays none.
class HermezBotPresence extends StatefulWidget {
  const HermezBotPresence({
    super.key,
    required this.identity,
    required this.size,
    this.label,
    this.service,
    this.sessionId,
  });

  final HermezBotIdentity identity;
  final double size;
  final String? label;

  /// The already-created Desktop connection, when there is one. Presence
  /// only reads its local broadcasts.
  final HermesDesktopApiService? service;

  /// The bot's Hermes session, when it has one.
  final String? sessionId;

  /// Repeating motion (float, breathing, nudge). Off under `flutter test`,
  /// where an endless animation would never settle; tests of the motion
  /// switch it on.
  @visibleForTesting
  static bool loopsEnabled = !Platform.environment.containsKey('FLUTTER_TEST');

  /// Marks at least this large get ambient idle motion.
  static const double ambientMinSize = 56;

  @override
  State<HermezBotPresence> createState() => _HermezBotPresenceState();
}

class _HermezBotPresenceState extends State<HermezBotPresence>
    with TickerProviderStateMixin {
  static const Duration _floatPeriod = Duration(milliseconds: 3600);
  static const Duration _breathPeriod = Duration(milliseconds: 1800);
  static const Duration _nudgePeriod = Duration(milliseconds: 3200);

  late final AnimationController _loop = AnimationController(vsync: this);
  late final AnimationController _impulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  HermezBotVisualState _state = HermezBotVisualState.idle;
  HermezBotVisualState _transient = HermezBotVisualState.idle;

  HermesDesktopApiService? _service;
  String? _session;
  StreamSubscription<HermesDesktopTurnState>? _turns;
  StreamSubscription<List<HermesLiveActivityEvent>>? _activity;
  HermesDesktopTurnState _turn = HermesDesktopTurnState.idle;
  List<HermesLiveActivityEvent> _events = const [];
  int? _seenEvents;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoop();
  }

  @override
  void didUpdateWidget(HermezBotPresence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.size != widget.size) _syncLoop();
  }

  @override
  void dispose() {
    unawaited(_turns?.cancel());
    unawaited(_activity?.cancel());
    _loop.dispose();
    _impulse.dispose();
    super.dispose();
  }

  void _bind(HermesDesktopApiService? service, String? session) {
    if (identical(service, _service) && session == _session) return;
    unawaited(_turns?.cancel());
    unawaited(_activity?.cancel());
    _turns = null;
    _activity = null;
    _service = service;
    _session = session;
    _turn = HermesDesktopTurnState.idle;
    _events = const [];
    _seenEvents = null;
    if (service == null || session == null || session.isEmpty) {
      // Called from build: assign directly, and move the clock after it.
      if (_state != HermezBotVisualState.idle) {
        _state = HermezBotVisualState.idle;
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncLoop());
      }
      return;
    }
    _turns = service.turnStatesFor(session).listen((turn) {
      _turn = turn;
      _setState(hermezBotVisualStateFor(_turn, _events));
    });
    _activity = service.activityFor(session).listen(_onActivity);
  }

  void _onActivity(List<HermesLiveActivityEvent> events) {
    _events = events;
    final seen = _seenEvents;
    _seenEvents = events.length;
    // The first snapshot is history: nothing reacts to it.
    if (seen != null && events.length > seen) {
      final kind = events.last.kind;
      if (kind == HermesLiveActivityKind.completed) {
        _react(HermezBotVisualState.completed);
      } else if (kind == HermesLiveActivityKind.failed) {
        _react(HermezBotVisualState.failed);
      }
    }
    _setState(hermezBotVisualStateFor(_turn, _events));
  }

  void _react(HermezBotVisualState transient) {
    if (!mounted || context.reduceMotion) return;
    _transient = transient;
    unawaited(_impulse.forward(from: 0));
  }

  void _setState(HermezBotVisualState next) {
    if (!mounted || next == _state) return;
    setState(() => _state = next);
    _syncLoop();
  }

  /// One repeating clock whose period depends on the state; stopped when
  /// nothing should move.
  void _syncLoop() {
    if (!mounted) return;
    final period = context.reduceMotion || !HermezBotPresence.loopsEnabled
        ? null
        : switch (_state) {
            HermezBotVisualState.active => _breathPeriod,
            HermezBotVisualState.waiting => _nudgePeriod,
            _ =>
              widget.size >= HermezBotPresence.ambientMinSize
                  ? _floatPeriod
                  : null,
          };
    if (period == null) {
      _loop
        ..stop()
        ..value = 0;
      return;
    }
    if (_loop.duration != period || !_loop.isAnimating) {
      _loop
        ..duration = period
        ..repeat();
    }
  }

  /// Offset and scale for the current frame.
  (Offset, double) _pose() {
    final t = _loop.value;
    final unit = widget.size / 88; // motion scales with the mark
    var dy = 0.0;
    var dx = 0.0;
    var scale = 1.0;
    switch (_state) {
      case HermezBotVisualState.active:
        // Lift and breathe: a machine holding energy.
        final wave = math.sin(t * 2 * math.pi);
        dy = (-2.0 - 1.2 * wave) * unit;
        scale = 1.0 + 0.018 * (0.5 + 0.5 * wave);
      case HermezBotVisualState.waiting:
        // Still, then one short nudge at the start of each period.
        const nudge = 0.14;
        if (t < nudge) {
          final p = t / nudge;
          dx = math.sin(p * math.pi * 3) * (1 - p) * 2.4 * unit;
        }
      case _:
        if (_loop.isAnimating) {
          dy = math.sin(t * 2 * math.pi) * 1.5 * unit;
        }
    }
    if (_impulse.isAnimating) {
      final p = _impulse.value;
      // A single impulse that settles: rise (or recoil) then return.
      final shape = math.sin(p * math.pi) * math.exp(-2.2 * p);
      if (_transient == HermezBotVisualState.completed) {
        dy += -7 * unit * shape;
        scale += 0.03 * shape;
      } else if (_transient == HermezBotVisualState.failed) {
        dy += 3 * unit * shape;
        dx += -2 * unit * shape;
        scale -= 0.035 * shape;
      }
    }
    return (Offset(dx, dy), scale);
  }

  @override
  Widget build(BuildContext context) {
    _bind(widget.service, widget.sessionId);
    final mark = RepaintBoundary(
      child: HermezBotMark(
        identity: widget.identity,
        size: widget.size,
        label: widget.label,
      ),
    );
    return AnimatedBuilder(
      animation: Listenable.merge([_loop, _impulse]),
      child: mark,
      builder: (context, mark) {
        final (offset, scale) = _pose();
        return Transform.translate(
          offset: offset,
          child: Transform.scale(scale: scale, child: mark),
        );
      },
    );
  }

  @visibleForTesting
  HermezBotVisualState get visualState => _state;
}
