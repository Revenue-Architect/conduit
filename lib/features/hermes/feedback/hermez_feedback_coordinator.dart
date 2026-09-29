import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/services/voice_call_service.dart';
import '../models/hermes_config.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_backend_service.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_live_activity.dart';
import 'hermez_feedback.dart';

/// Turns real Hermes run transitions into sensory cues for the chat the user
/// is looking at.
///
/// It only reads what the existing Desktop connection already publishes
/// (turn states and live activity events, both broadcast, so nothing
/// historical replays) and never calls the service. Nothing it does can
/// change a session, a decision, or a run:
/// - a run engages only on a fresh idle -> running transition (not after a
///   reconnect or a resync);
/// - a finish or failure resolves only a run this process saw start;
/// - a request for the user alerts once per request;
/// - tool activity is silent, and other sessions stay with notifications.
final hermezFeedbackCoordinatorProvider = Provider<HermezFeedbackCoordinator>((
  ref,
) {
  final coordinator = HermezFeedbackCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  ref.listen<HermesBackendService?>(
    hermesApiServiceProvider,
    (_, next) => coordinator.bind(next),
    fireImmediately: true,
  );
  return coordinator;
});

class HermezFeedbackCoordinator {
  HermezFeedbackCoordinator(this._ref, {HermezFeedback? feedback})
    : _feedback = feedback ?? HermezFeedback.instance {
    // Voice mode owns the speaker: interface sounds stay quiet during it.
    _removeVoiceSuppressor = _feedback.addSoundSuppressor(_voiceActive);
  }

  final Ref _ref;
  final HermezFeedback _feedback;
  late final VoidCallback _removeVoiceSuppressor;

  HermesDesktopApiService? _service;
  StreamSubscription<HermesLiveActivityEvent>? _activity;
  StreamSubscription<HermesDesktopTurnState>? _turns;

  HermesDesktopTurnState? _lastTurn;

  /// Visible sessions whose run started while this process watched.
  final Set<String> _armed = {};
  final Set<String> _alerted = {};

  bool _voiceActive() {
    if (!_ref.exists(voiceCallServiceProvider)) return false;
    return switch (_ref.read(voiceCallServiceProvider).state) {
      VoiceCallState.idle ||
      VoiceCallState.error ||
      VoiceCallState.disconnected => false,
      _ => true,
    };
  }

  void bind(HermesBackendService? service) {
    if (identical(service, _service)) return;
    _unbind();
    if (service is! HermesDesktopApiService) return;
    _service = service;
    _turns = service.turnStates.listen(_onTurnState);
    _activity = service.activityEvents.listen(_onActivity);
  }

  void _unbind() {
    unawaited(_turns?.cancel());
    unawaited(_activity?.cancel());
    _turns = null;
    _activity = null;
    _service = null;
    _lastTurn = null;
    _armed.clear();
    _alerted.clear();
  }

  void dispose() {
    _removeVoiceSuppressor();
    _unbind();
  }

  String? get _visibleSession => _ref.read(hermesActiveSessionProvider);

  @visibleForTesting
  void handleTurnState(HermesDesktopTurnState state) => _onTurnState(state);

  @visibleForTesting
  void handleActivity(HermesLiveActivityEvent event) => _onActivity(event);

  void _onTurnState(HermesDesktopTurnState state) {
    final previous = _lastTurn;
    _lastTurn = state;
    if (state != HermesDesktopTurnState.running) return;
    // The first state seen is a baseline; a resumed or resynchronized run is
    // not a new one.
    if (previous != HermesDesktopTurnState.idle) return;
    final visible = _visibleSession;
    if (visible == null) return;
    _armed.add(visible);
    _alerted.clear();
    _feedback.trigger(HermezFeedbackCue.runEngage);
  }

  void _onActivity(HermesLiveActivityEvent event) {
    final visible = _visibleSession;
    if (visible == null || event.sessionId != visible) return;
    switch (event.kind) {
      case HermesLiveActivityKind.waitingForInput:
        final key = event.detail ?? '${event.timestamp.millisecondsSinceEpoch}';
        if (_alerted.add('$visible:$key')) {
          _feedback.trigger(HermezFeedbackCue.runNeedsAttention);
        }
      case HermesLiveActivityKind.completed:
        if (_armed.remove(visible)) {
          _feedback.trigger(HermezFeedbackCue.runComplete);
        }
      case HermesLiveActivityKind.failed:
        if (_armed.remove(visible)) {
          _feedback.trigger(HermezFeedbackCue.runFailed);
        }
      case HermesLiveActivityKind.toolStarted ||
          HermesLiveActivityKind.toolProgress ||
          HermesLiveActivityKind.toolCompleted ||
          HermesLiveActivityKind.subagentStarted ||
          HermesLiveActivityKind.subagentProgress ||
          HermesLiveActivityKind.subagentCompleted ||
          HermesLiveActivityKind.review:
        // Long autonomous runs would be intolerable with a cue per tool.
        break;
    }
  }
}
