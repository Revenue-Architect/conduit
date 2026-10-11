import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/services/hermes_live_activity.dart';
import 'package:conduit/features/hermes/widgets/hermes_live_activity_disclosure.dart';
import 'package:conduit/features/hermes/widgets/hermes_run_activity_orb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activity appears only for the active native Desktop turn', () {
    bool visible(HermesDesktopTurnState state, {String? activeId = 'one'}) =>
        shouldShowHermesLiveActivity(
          nativeConversation: true,
          conversationSessionId: 'one',
          activeSessionId: activeId,
          desktopService: true,
          turnState: state,
        );

    expect(visible(HermesDesktopTurnState.idle), isFalse);
    expect(visible(HermesDesktopTurnState.running), isTrue);
    expect(visible(HermesDesktopTurnState.synchronizing), isTrue);
    expect(visible(HermesDesktopTurnState.reconnecting), isTrue);
    expect(visible(HermesDesktopTurnState.running, activeId: 'two'), isFalse);
    expect(
      shouldShowHermesLiveActivity(
        nativeConversation: false,
        conversationSessionId: 'one',
        activeSessionId: 'one',
        desktopService: true,
        turnState: HermesDesktopTurnState.running,
      ),
      isFalse,
    );
  });

  testWidgets('single completed orb fits a narrow chat at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = HermesDesktopApiService(
      config: const HermesConfig(
        enabled: true,
        baseUrl: 'https://hermes.example/v1',
        mode: HermesBackendMode.desktopGateway,
        desktopAuthKind: HermesDesktopAuthKind.nativePkce,
      ),
    );
    addTearDown(service.close);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SizedBox(
              width: 320,
              child: HermesRunActivityOrb(
                sessionId: 'session-1',
                state: HermesDesktopTurnState.idle,
                summary: 'Explored skill_view (2), read_file',
                detailsBuilder: (_) =>
                    const Material(child: Text('Saved tools')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('hermes-run-orb-toggle')), findsOneWidget);
    expect(find.text('Explored skill_view (2), read_file'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'activity timeline renders a real event without a Material error',
    (tester) async {
      tester.view.physicalSize = const Size(320, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SizedBox(
              width: 320,
              height: 220,
              child: HermesLiveActivityTimeline(
                running: true,
                events: [
                  HermesLiveActivityEvent(
                    sessionId: 'session-1',
                    kind: HermesLiveActivityKind.toolStarted,
                    title: 'Started tool',
                    timestamp: DateTime.utc(2026, 9, 27, 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Started tool'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'historical events do not keep the live orb visible after completion',
    () {
      expect(
        shouldShowHermesLiveActivity(
          nativeConversation: true,
          conversationSessionId: 'session-1',
          activeSessionId: 'session-1',
          desktopService: true,
          turnState: HermesDesktopTurnState.idle,
          hasRecentActivity: true,
        ),
        isFalse,
      );
      expect(
        shouldShowHermesLiveActivity(
          nativeConversation: true,
          conversationSessionId: 'session-1',
          activeSessionId: 'session-2',
          desktopService: true,
          turnState: HermesDesktopTurnState.idle,
          hasRecentActivity: true,
        ),
        isFalse,
      );
    },
  );
}
