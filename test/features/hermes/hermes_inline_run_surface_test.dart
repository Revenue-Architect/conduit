import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/providers/hermes_live_run_providers.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/services/hermes_pending_decision_store.dart';
import 'package:conduit/features/hermes/services/hermes_steel_viewer.dart';
import 'package:conduit/features/hermes/widgets/hermes_inline_run_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HermesDesktopApiService service;

  setUp(() {
    service = HermesDesktopApiService(
      config: const HermesConfig(
        enabled: true,
        baseUrl: 'https://hermes.example/v1',
        mode: HermesBackendMode.desktopGateway,
        desktopAuthKind: HermesDesktopAuthKind.nativePkce,
      ),
    );
  });
  tearDown(() => service.close());

  Future<void> mount(
    WidgetTester tester, {
    List<HermesPendingDesktopDecision> decisions = const [],
    String viewerUrl = '',
    Future<bool> Function(String, String)? steer,
    Future<void> Function(String)? interrupt,
    HermesDesktopTurnState state = HermesDesktopTurnState.running,
  }) async {
    tester.view.physicalSize = const Size(320, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermesApiServiceProvider.overrideWithValue(service),
          hermesPendingSessionDecisionsProvider('session-1')
              .overrideWith((ref) async => decisions),
          hermesSteelViewerUrlProvider.overrideWith(
            () => TestSteelViewerUrlController(viewerUrl),
          ),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: HermesInlineRunSurface(
                  service: service,
                  sessionId: 'session-1',
                  turnState: state,
                  activityStream: const Stream.empty(),
                  steerRun: steer,
                  interruptRun: interrupt,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('running actions fit 320dp with 200% text', (tester) async {
    await mount(tester);
    expect(find.text('Hermes is working'), findsOneWidget);
    await tester.tap(find.text('Hermes is working'));
    await tester.pumpAndSettle();
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Steer'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('browser is discoverable before expanding activity', (
    tester,
  ) async {
    await mount(tester, viewerUrl: 'http://steel.example/v1/sessions/debug');
    expect(find.text('Watch browser'), findsOneWidget);
    expect(find.text('Recent activity'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stop requires confirmation and targets exact session', (
    tester,
  ) async {
    final interrupted = <String>[];
    await mount(tester, interrupt: (id) async => interrupted.add(id));
    await tester.tap(find.text('Hermes is working'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(interrupted, isEmpty);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop').last);
    await tester.pumpAndSettle();
    expect(interrupted, ['session-1']);
  });

  testWidgets('steer sends user text to the exact active session', (
    tester,
  ) async {
    final submitted = <String>[];
    await mount(
      tester,
      steer: (id, text) async {
        submitted.add('$id:$text');
        return true;
      },
    );
    await tester.tap(find.text('Hermes is working'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Steer'));
    await tester.pump();
    // The pill grows into a field in place; nothing opens over the chat.
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    // Empty field: the trailing control closes.
    expect(find.byTooltip('Close steer'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Focus on the pricing');
    await tester.pump();
    await tester.tap(find.byTooltip('Send to Hermes'));
    await tester.pumpAndSettle();
    expect(submitted, ['session-1:Focus on the pricing']);
    // Accepted: the field contracts back into the Steer pill.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Steer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rejected steer keeps the field and its text', (tester) async {
    await mount(tester, steer: (id, text) async => false);
    await tester.tap(find.text('Hermes is working'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Steer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Try the other store');
    await tester.pump();
    await tester.tap(find.byTooltip('Send to Hermes'));
    await tester.pumpAndSettle();
    expect(find.text('This run cannot be steered right now.'), findsOneWidget);
    expect(find.text('Try the other store'), findsOneWidget);
    await tester.tap(find.byTooltip('Send to Hermes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending exact-session decision shows review even while idle', (
    tester,
  ) async {
    await mount(
      tester,
      state: HermesDesktopTurnState.idle,
      decisions: [
        HermesPendingDesktopDecision(
          origin: 'https://hermes.example',
          storedSessionId: 'session-1',
          runtimeId: 'run-1',
          requestId: 'request-1',
          kind: HermesPendingDesktopDecisionKind.approval,
          expiresAt: DateTime.utc(2030),
          prompt: 'Run terminal command?',
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Input needed'), findsOneWidget);
    expect(find.text('Run terminal command?'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Run terminal command?'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Input needed'), findsOneWidget);
  });

  testWidgets('browser action is hidden without URL and visible with one', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Hermes is working'));
    await tester.pumpAndSettle();
    expect(find.text('Watch browser'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester, viewerUrl: 'http://steel.example/v1/sessions/debug');
    await tester.tap(find.text('Hermes is working'));
    await tester.pumpAndSettle();
    expect(find.text('Watch browser'), findsOneWidget);
  });
}

class TestSteelViewerUrlController extends HermesSteelViewerUrlController {
  TestSteelViewerUrlController(this.testUrl);
  final String testUrl;

  @override
  String build() => testUrl;
}
