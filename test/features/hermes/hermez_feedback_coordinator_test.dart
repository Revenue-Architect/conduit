import 'package:conduit/features/hermes/feedback/hermez_feedback.dart';
import 'package:conduit/features/hermes/feedback/hermez_feedback_coordinator.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/motion/hermez_motion_surface.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_live_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Backend implements HermezSoundBackend {
  _Backend({this.fail = false});

  final bool fail;
  final List<String> played = [];

  @override
  Future<void> start(Iterable<String> assets) async {
    if (fail) throw StateError('no audio');
  }

  @override
  void play(String asset, {required double volume, required double speed}) {
    if (fail) throw StateError('no audio');
    played.add(asset.split('/').last);
  }
}

HermesLiveActivityEvent _event(
  String session,
  HermesLiveActivityKind kind, {
  String? detail,
}) => HermesLiveActivityEvent(
  sessionId: session,
  kind: kind,
  title: kind.name,
  timestamp: DateTime(2026, 9, 29, 12),
  detail: detail,
);

void main() {
  late _Backend backend;
  late ProviderContainer container;
  late HermezFeedbackCoordinator coordinator;

  setUp(() async {
    backend = _Backend();
    final feedback = HermezFeedback.forTesting(
      backend: backend,
      haptic: (_) async {},
    );
    await feedback.startForTesting();
    final probe = Provider<HermezFeedbackCoordinator>((ref) {
      final c = HermezFeedbackCoordinator(ref, feedback: feedback);
      ref.onDispose(c.dispose);
      return c;
    });
    container = ProviderContainer();
    addTearDown(container.dispose);
    coordinator = container.read(probe);
    container.read(hermesActiveSessionProvider.notifier).set('s1');
  });

  test('a fresh run engages once; a resumed run does not', () {
    coordinator.handleTurnState(HermesDesktopTurnState.idle); // baseline
    coordinator.handleTurnState(HermesDesktopTurnState.running);
    coordinator.handleTurnState(HermesDesktopTurnState.running);
    expect(backend.played, ['run_engage.wav']);

    coordinator.handleTurnState(HermesDesktopTurnState.reconnecting);
    coordinator.handleTurnState(HermesDesktopTurnState.running);
    coordinator.handleTurnState(HermesDesktopTurnState.synchronizing);
    coordinator.handleTurnState(HermesDesktopTurnState.running);
    expect(backend.played, ['run_engage.wav']);
  });

  test('the first state after binding is only a baseline', () {
    coordinator.handleTurnState(HermesDesktopTurnState.running);
    expect(backend.played, isEmpty);
  });

  test('completion and failure resolve only a run seen starting', () {
    // Opening a finished chat: no run seen, no sound.
    coordinator.handleActivity(_event('s1', HermesLiveActivityKind.completed));
    expect(backend.played, isEmpty);

    coordinator.handleTurnState(HermesDesktopTurnState.idle);
    coordinator.handleTurnState(HermesDesktopTurnState.running);
    coordinator.handleActivity(_event('s1', HermesLiveActivityKind.completed));
    coordinator.handleActivity(_event('s1', HermesLiveActivityKind.completed));
    expect(backend.played, ['run_engage.wav', 'success.wav']);

    coordinator.handleTurnState(HermesDesktopTurnState.idle);
    coordinator.handleTurnState(HermesDesktopTurnState.running);
    coordinator.handleActivity(_event('s1', HermesLiveActivityKind.failed));
    expect(backend.played.last, 'failure.wav');
  });

  test('a request for the user alerts once per request', () {
    final wait = _event(
      's1',
      HermesLiveActivityKind.waitingForInput,
      detail: 'req-1',
    );
    coordinator.handleActivity(wait);
    coordinator.handleActivity(wait); // rebuild / replay
    expect(backend.played, ['attention.wav']);
    coordinator.handleActivity(
      _event('s1', HermesLiveActivityKind.waitingForInput, detail: 'req-2'),
    );
    expect(backend.played, ['attention.wav', 'attention.wav']);
  });

  test('tool activity and other sessions stay silent', () {
    coordinator.handleTurnState(HermesDesktopTurnState.idle);
    coordinator.handleTurnState(HermesDesktopTurnState.running);
    backend.played.clear();
    for (final kind in [
      HermesLiveActivityKind.toolStarted,
      HermesLiveActivityKind.toolProgress,
      HermesLiveActivityKind.toolCompleted,
      HermesLiveActivityKind.subagentStarted,
      HermesLiveActivityKind.review,
    ]) {
      coordinator.handleActivity(_event('s1', kind));
    }
    coordinator.handleActivity(
      _event('other', HermesLiveActivityKind.waitingForInput, detail: 'x'),
    );
    coordinator.handleActivity(_event('other', HermesLiveActivityKind.failed));
    expect(backend.played, isEmpty);
  });

  testWidgets('a surface with a cue runs its action exactly once, even when '
      'the sound engine throws', (tester) async {
    final previous = HermezFeedback.instance;
    final failing = HermezFeedback.forTesting(
      backend: _Backend(fail: true),
      haptic: (_) => throw StateError('no vibrator'),
    );
    await failing.startForTesting();
    HermezFeedback.instance = failing;
    addTearDown(() => HermezFeedback.instance = previous);

    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: HermezMotionSurface(
            feedbackCue: HermezFeedbackCue.botEngage,
            semanticLabel: 'Chat with Kai',
            onTap: () => calls++,
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Chat with Kai'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
