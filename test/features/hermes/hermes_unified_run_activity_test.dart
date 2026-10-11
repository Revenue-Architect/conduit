import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/core/models/chat_message.dart';
import 'package:conduit/core/services/settings_service.dart';
import 'package:conduit/features/chat/providers/text_to_speech_provider.dart';
import 'package:conduit/features/chat/widgets/assistant_message_widget.dart';
import 'package:conduit/features/chat/widgets/streaming_status_widget.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/providers/hermes_agentic_providers.dart';
import 'package:conduit/features/hermes/providers/hermes_live_run_providers.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_agentic_state.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/services/hermes_pending_decision_store.dart';
import 'package:conduit/features/hermes/services/hermes_run_history.dart';
import 'package:conduit/features/hermes/services/hermes_message_mapper.dart';
import 'package:conduit/features/hermes/views/hermes_live_run_page.dart';
import 'package:conduit/features/hermes/widgets/hermes_run_activity_orb.dart';
import 'package:conduit/features/hermes/widgets/hermes_unified_activity_timeline.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thinking_orbs/thinking_orbs.dart';

class _Tts extends TextToSpeechController {
  @override
  TextToSpeechState build() => const TextToSpeechState();
}

final _answer = ChatMessage(
  id: 'answer-1',
  role: 'assistant',
  content: 'Read your file.',
  timestamp: DateTime.utc(2026, 10, 10),
  model: 'default',
  metadata: const {'transport': 'hermesRun', 'hermesSessionId': 'session-1'},
  statusHistory: const [
    ChatStatusUpdate(
      action: 'hermes_tool_read_file',
      description: 'read_file',
      done: true,
      items: [
        ChatStatusItem(
          title: 'Result',
          snippet: 'Actual saved file result',
          presentation: ChatStatusItemPresentation.detail,
        ),
      ],
    ),
  ],
);

List<Map<String, dynamic>> _history() => [
  {'id': 'user-1', 'role': 'user', 'content': 'Read the file'},
  {
    'id': 'call-message',
    'role': 'assistant',
    'content': '',
    'tool_calls': [
      {
        'id': 'call-1',
        'function': {'name': 'read_file', 'arguments': '{"path":"notes.txt"}'},
      },
    ],
  },
  {
    'role': 'tool',
    'tool_call_id': 'call-1',
    'content': 'Actual saved file result',
  },
  {'id': 'answer-1', 'role': 'assistant', 'content': 'Read your file.'},
  {'role': 'user', 'content': 'Another question'},
  {'id': 'answer-2', 'role': 'assistant', 'content': 'Another answer'},
];

void main() {
  test('live continuation stays in one answer, next user turn detaches it', () {
    final continuation = _answer.copyWith(id: 'continuation');
    expect(hermesCurrentAnswerMessages([_answer, continuation], [_answer]), [
      _answer,
      continuation,
    ]);
    expect(
      hermesCurrentAnswerMessages(
        [
          _answer,
          _answer.copyWith(id: 'next-user', role: 'user'),
          _answer.copyWith(id: 'next-answer'),
        ],
        [_answer],
      ),
      isEmpty,
    );
    expect(
      hermesCurrentAnswerMessages(
        [_answer.copyWith(id: 'other-chat')],
        [_answer],
      ),
      isEmpty,
    );
  });
  test(
    'stored model is authoritative, profile display name is not a model',
    () {
      expect(hermesTranscriptModel(_history()), isNull);
      expect(
        hermesTranscriptModel([
          {'role': 'assistant', 'model': 'gpt-6-luna'},
        ]),
        'gpt-6-luna',
      );
    },
  );
  test('JSON-encoded stored calls preserve paired tool results', () {
    final raw = _history();
    raw[1]['tool_calls'] = jsonEncode(raw[1]['tool_calls']);
    final messages = hermesMessagesToChatMessages(raw, sessionId: 'session-1');
    final statuses = messages
        .expand((message) => message.statusHistory)
        .toList();
    expect(statuses, hasLength(1));
    expect(statuses.single.done, isTrue);
    expect(statuses.single.items.last.snippet, 'Actual saved file result');
    raw[1]['tool_calls'] = '[broken';
    expect(
      hermesMessagesToChatMessages(raw)
          .expand((message) => message.statusHistory),
      isEmpty,
    );
  });
  test('answer identity scopes history without selecting another turn', () {
    final turn = hermesAnswerTranscript(_history(), [_answer]);
    expect(turn.where((message) => message['role'] == 'tool'), hasLength(1));
    expect(turn.any((message) => message['id'] == 'answer-2'), isFalse);
    expect(
      hermesAnswerTranscript(_history(), [_answer.copyWith(id: 'optimistic')]),
      hasLength(3),
    );
    expect(
      hermesAnswerTranscript(
        [
          ..._history(),
          {'role': 'assistant', 'content': 'Read your file.'},
        ],
        [_answer.copyWith(id: 'optimistic')],
      ),
      isEmpty,
    );
  });
  test('restored tool details redact configured credentials', () {
    final safe = hermesSafeRunStatuses(
      [
        const ChatStatusUpdate(
          items: [
            ChatStatusItem(
              title: 'Result',
              snippet: 'token=private-credential',
            ),
          ],
        ),
      ],
      ['private-credential'],
    );
    expect(
      safe.single.items.single.snippet,
      isNot(contains('private-credential')),
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'finished answer has one control and its sheet contains tools at $scale',
      (tester) async {
        final service = HermesDesktopApiService(
          config: HermesConfig(
            enabled: true,
            baseUrl: 'https://hermes.example',
            mode: HermesBackendMode.desktopGateway,
            desktopCredentials: HermesDesktopCredentials(
              legacyToken: 'test-token',
            ),
          ),
          dio: Dio()..httpClientAdapter = _Adapter(),
        );
        addTearDown(service.close);
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              hermesApiServiceProvider.overrideWithValue(service),
              textToSpeechControllerProvider.overrideWith(_Tts.new),
              streamingHapticsEnabledProvider.overrideWithValue(false),
              hermesSessionsProvider.overrideWith(_Sessions.new),
              hermesAgenticStateProvider('session-1').overrideWith(
                (ref) => Stream.value(HermesAgenticSnapshot.empty),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light(TweakcnThemes.t3Chat),
              localizationsDelegates: conduitLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      AssistantMessageWidget(
                        message: _answer,
                        modelName: 'default',
                        animateOnMount: false,
                        onDelete: () {},
                      ),
                      AssistantMessageWidget(
                        message: _answer.copyWith(
                          id: 'continuation',
                          content: 'Continued answer.',
                        ),
                        modelName: 'default',
                        showModelHeader: false,
                        animateOnMount: false,
                        onDelete: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HermesRunActivityOrb), findsOneWidget);
        expect(
          find.byKey(const ValueKey('hermes-run-orb-toggle')),
          findsOneWidget,
        );
        expect(find.byType(StreamingStatusWidget), findsNothing);
        expect(find.byType(ThinkingOrb), findsNothing);
        expect(find.text('Explored read_file'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('hermes-run-orb-toggle')));
        await tester.pumpAndSettle();
        expect(find.byType(HermesLiveRunPage), findsOneWidget);
        final scroll = find
            .descendant(
              of: find
                  .descendant(
                    of: find.byType(HermesLiveRunPage),
                    matching: find.byType(ListView),
                  )
                  .first,
              matching: find.byType(Scrollable),
            )
            .first;
        // Tool output is folded under its row until asked for.
        await tester.scrollUntilVisible(
          find.text('Show output').first,
          150,
          scrollable: scroll,
        );
        await tester.ensureVisible(find.text('Show output').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Show output').first);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.textContaining('Actual saved file result'),
          150,
          scrollable: scroll,
        );
        expect(find.byType(HermesUnifiedActivityTimeline), findsOneWidget);
        expect(find.textContaining('Actual saved file result'), findsOneWidget);
        expect(find.text('Steer'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close run details'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('hermes-run-orb-toggle')),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'pending clarification stays prominent on idle orb and in sheet',
    (tester) async {
      final service = HermesDesktopApiService(
        config: const HermesConfig(
          enabled: true,
          baseUrl: 'https://hermes.example',
          mode: HermesBackendMode.desktopGateway,
        ),
        dio: Dio()..httpClientAdapter = _Adapter(),
      );
      addTearDown(service.close);
      final decision = HermesPendingDesktopDecision(
        origin: 'https://hermes.example',
        storedSessionId: 'session-1',
        runtimeId: 'runtime-1',
        requestId: 'request-1',
        kind: HermesPendingDesktopDecisionKind.clarification,
        expiresAt: DateTime.utc(2030),
        prompt: 'Which city?',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermesApiServiceProvider.overrideWithValue(service),
            hermesSessionTurnStateProvider(
              'session-1',
            ).overrideWith((ref) => Stream.value(HermesDesktopTurnState.idle)),
            hermesPendingSessionDecisionsProvider('session-1')
                .overrideWith((ref) async => [decision]),
            hermesSessionsProvider.overrideWith(_Sessions.new),
            hermesAgenticStateProvider(
              'session-1',
            ).overrideWith((ref) => Stream.value(HermesAgenticSnapshot.empty)),
          ],
          child: MaterialApp(
            localizationsDelegates: conduitLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: HermesMessageActivity(
                messages: [_answer],
                currentAnswer: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Input needed'), findsOneWidget);
      expect(
        tester.widget<ThinkingOrb>(find.byType(ThinkingOrb)).state,
        OrbState.listening,
      );
      await tester.tap(find.byKey(const ValueKey('hermes-run-orb-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Which city?'), findsOneWidget);
      await tester.tap(find.byTooltip('Close run details'));
      await tester.pumpAndSettle();
      expect(find.text('Input needed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Sessions extends HermesSessionsController {
  @override
  Future<List<Never>> build() async => const [];
}

class _Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(
      options.uri.path == '/api/status'
          ? {'auth_required': false}
          : {'messages': _history()},
    ),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}
