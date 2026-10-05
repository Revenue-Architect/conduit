import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:conduit/core/persistence/preferences_store.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/models/hermes_subagent.dart';
import 'package:conduit/features/hermes/models/hermes_team.dart';
import 'package:conduit/features/hermes/models/hermes_todo.dart';
import 'package:conduit/features/hermes/services/hermes_backend_service.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_transport.dart';
import 'package:conduit/features/hermes/services/hermes_live_activity.dart';
import 'package:conduit/features/spaces/services/hermes_spaces_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final class _MockWebSocketChannel extends Mock implements WebSocketChannel {}

final class _MockWebSocketSink extends Mock implements WebSocketSink {}

/// A scripted Desktop gateway: answers RPCs from [responder] and lets the
/// test push events.
final class _Gateway {
  _Gateway() {
    when(() => channel.ready).thenAnswer((_) async {});
    when(() => channel.stream).thenAnswer((_) {
      scheduleMicrotask(_ready);
      return incoming.stream;
    });
    when(() => channel.sink).thenReturn(sink);
    when(() => sink.close()).thenAnswer((_) async {});
    when(() => sink.add(any())).thenAnswer((invocation) {
      final frame = Map<String, dynamic>.from(
        jsonDecode(invocation.positionalArguments.single as String) as Map,
      );
      sent.add(frame);
      final id = frame['id'];
      if (id == null) return;
      final result = responder(
        frame['method']?.toString() ?? '',
        Map<String, dynamic>.from(frame['params'] as Map? ?? const {}),
      );
      if (result == null) return;
      scheduleMicrotask(
        () => incoming.add(
          jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
        ),
      );
    });
  }

  final channel = _MockWebSocketChannel();
  final sink = _MockWebSocketSink();
  final incoming = StreamController<dynamic>.broadcast();
  final sent = <Map<String, dynamic>>[];
  Map<String, dynamic>? Function(String method, Map<String, dynamic> params)
  responder = (_, _) => const {};

  void _ready() {
    if (incoming.isClosed) return;
    incoming.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {'type': 'gateway.ready', 'payload': {}},
      }),
    );
  }

  void event(String type, String sessionId, Map<String, dynamic> payload) =>
      incoming.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {'type': type, 'session_id': sessionId, 'payload': payload},
        }),
      );

  List<Map<String, dynamic>> calls(String method) => [
    for (final frame in sent)
      if (frame['method'] == method)
        Map<String, dynamic>.from(frame['params'] as Map? ?? const {}),
  ];

  Future<void> dispose() => incoming.close();
}

final class _Adapter implements HttpClientAdapter {
  _Adapter({
    this.spacesStatus = 200,
    this.spacesBody = const {'ok': true},
    this.authRequired = false,
    this.messages = const [],
  });

  /// Served for `/api/sessions/{id}/messages`.
  final List<Map<String, Object?>> messages;

  final int spacesStatus;
  final Map<String, Object?> spacesBody;

  /// Native sign-in only applies when the server requires auth, as the
  /// Umbrel's Hermes does.
  final bool authRequired;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path.endsWith('/messages')) {
      return ResponseBody.fromString(
        jsonEncode({'messages': messages}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.uri.path.contains('/api/plugins/spaces/')) {
      return ResponseBody.fromString(
        jsonEncode(spacesBody),
        spacesStatus,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'version': '0.21.1',
        'auth_required': authRequired,
        'gateway_running': true,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

HermesConfig _config({bool native = false}) => HermesConfig(
  enabled: true,
  baseUrl: 'https://hermes.example',
  mode: HermesBackendMode.desktopGateway,
  desktopAuthKind: native
      ? HermesDesktopAuthKind.nativePkce
      : HermesDesktopAuthKind.legacyToken,
  desktopCredentials: native
      ? HermesDesktopCredentials(
          nativeTokens: HermesDesktopTokenSet(
            accessToken: 'access',
            refreshToken: 'refresh',
            expiresAt: DateTime.utc(2099),
          ),
        )
      : HermesDesktopCredentials(legacyToken: 'session-token'),
);

Future<(HermesDesktopApiService, _Gateway)> _connected({
  _Adapter? adapter,
  bool native = false,
}) async {
  final gateway = _Gateway();
  // As the service builds its own: error bodies are not read by default.
  final dio = Dio(BaseOptions(receiveDataWhenStatusError: false))
    ..httpClientAdapter = adapter ?? _Adapter();
  final service = HermesDesktopApiService(
    config: _config(native: native),
    dio: dio,
    rpc: HermesDesktopRpcClient(
      channelFactory: (_, _, {httpClient}) => gateway.channel,
    ),
  );
  addTearDown(() async {
    service.close();
    await gateway.dispose();
  });
  return (service, gateway);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PreferencesStore.debugOverride(await SharedPreferences.getInstance());
  });
  tearDown(PreferencesStore.debugReset);

  Future<String> createSession(
    HermesDesktopApiService service,
    _Gateway gateway, {
    Map<String, dynamic>? info,
  }) async {
    gateway.responder = (method, _) => switch (method) {
      'session.create' => {
        'session_id': 'runtime-1',
        'stored_session_id': 'stored-1',
        'running': false,
        'info': info ?? const {},
      },
      _ => const {},
    };
    return service.createDesktopSession(
      options: const HermesDesktopSessionOptions(),
    );
  }

  test(
    'todo.updated keeps the newest plan and ignores stale revisions',
    () async {
      final (service, gateway) = await _connected();
      final stored = await createSession(service, gateway);
      gateway.event('todo.updated', 'runtime-1', {
        'revision': 3,
        'todos': [
          {'id': 'a', 'content': 'Read the docs', 'status': 'completed'},
          {'id': 'b', 'content': 'Write the code', 'status': 'in_progress'},
          {'id': 'c', 'content': 'Ship it', 'status': 'pending'},
        ],
      });
      await _settle();
      final plan = service.agenticSnapshotFor(stored).todo!;
      check(plan.revision).equals(3);
      check(plan.completed).equals(1);
      check(plan.total).equals(3);
      check(plan.current!.id).equals('b');

      gateway.event('todo.updated', 'runtime-1', {
        'revision': 2,
        'todos': [
          {'id': 'a', 'content': 'Old', 'status': 'pending'},
        ],
      });
      await _settle();
      check(service.agenticSnapshotFor(stored).todo!.revision).equals(3);
    },
  );

  test('a resume restores the plan Hermes kept with the session', () async {
    final (service, gateway) = await _connected();
    gateway.responder = (method, _) => switch (method) {
      'session.resume' => {
        'session_id': 'runtime-9',
        'stored_session_id': 'stored-9',
        'running': false,
        'info': {'model': 'gpt-6.1-sol', 'provider': 'openai-codex'},
        'todo_state': {
          'revision': 5,
          'todos': [
            {'id': 'x', 'content': 'Step', 'status': 'pending'},
          ],
        },
      },
      'session.interrupt' => const {},
      _ => const {},
    };
    await service.interrupt('stored-9');
    final snapshot = service.agenticSnapshotFor('stored-9');
    check(snapshot.todo!.revision).equals(5);
    check(snapshot.info!.model).equals('gpt-6.1-sol');
  });

  test('a resume without a plan recovers it from the transcript', () async {
    final (service, gateway) = await _connected(
      adapter: _Adapter(
        messages: [
          {
            'role': 'tool',
            'tool_name': 'todo_list',
            'content': jsonEncode({
              'revision': 2,
              'todos': [
                {'id': 'a', 'content': 'Recovered step', 'status': 'pending'},
              ],
            }),
          },
        ],
      ),
    );
    gateway.responder = (method, _) => switch (method) {
      'session.resume' => {
        'session_id': 'runtime-7',
        'stored_session_id': 'stored-7',
        'running': false,
        'info': const {},
      },
      _ => const {},
    };
    await service.interrupt('stored-7');
    service.restorePlanIfMissing('stored-7');
    for (var i = 0; i < 20; i++) {
      if (service.agenticSnapshotFor('stored-7').todo != null) break;
      await _settle();
    }
    check(service.agenticSnapshotFor('stored-7').todo!.items.single.content)
        .equals('Recovered step');
  });

  test('delegates are tracked and a finished one stays finished', () async {
    final (service, gateway) = await _connected();
    final stored = await createSession(service, gateway);
    gateway.event('subagent.start', 'runtime-1', {
      'subagent_id': 'sa-1',
      'goal': 'Research pricing',
      'model': 'grok-4.6',
    });
    gateway.event('subagent.tool', 'runtime-1', {
      'subagent_id': 'sa-1',
      'tool_name': 'web_search',
      'tool_preview': 'shopify plan pricing',
    });
    gateway.event('subagent.complete', 'runtime-1', {
      'subagent_id': 'sa-1',
      'status': 'completed',
      'summary': 'Found three tiers',
      'duration_seconds': 12.5,
    });
    gateway.event('subagent.progress', 'runtime-1', {
      'subagent_id': 'sa-1',
      'text': 'late progress',
    });
    await _settle();
    final worker = service.agenticSnapshotFor(stored).subagents.single;
    check(worker.status).equals(HermesSubagentStatus.completed);
    check(worker.summary).equals('Found three tiers');
    check(worker.model).equals('grok-4.6');
    check(worker.lines.map((line) => line.text))
        .not((it) => it.contains('late progress'));
  });

  test(
    'a run whose self-review reports after the reply still finished',
    () async {
      final (service, gateway) = await _connected();
      final stored = await createSession(service, gateway);
      gateway.event('tool.start', 'runtime-1', {
        'tool_id': 't-1',
        'name': 'terminal',
        'args': {'command': 'date'},
      });
      gateway.event('tool.complete', 'runtime-1', {
        'tool_id': 't-1',
        'name': 'terminal',
      });
      gateway.event('message.complete', 'runtime-1', {'text': 'It is Monday.'});
      // Hermes' background review lands after the turn has ended.
      gateway.event('review.summary', 'runtime-1', {'text': 'Saved a memory'});
      await _settle();
      final finished = service.recentlyFinished();
      check(finished.map((done) => done.storedId)).deepEquals([stored]);
      check(finished.single.failed).isFalse();

      // A new turn's work means it is no longer just finished.
      gateway.event('tool.start', 'runtime-1', {
        'tool_id': 't-2',
        'name': 'terminal',
        'args': {'command': 'ls'},
      });
      await _settle();
      check(service.recentlyFinished()).isEmpty();
    },
  );

  test(
    'a bridged tool call is recorded as the tool that actually ran',
    () async {
      final (service, gateway) = await _connected();
      final stored = await createSession(service, gateway);
      gateway.event('tool.start', 'runtime-1', {
        'tool_id': 'call-1',
        'name': 'tool_call',
        'context': 'tool_call(...)',
        'args': {
          'name': 'spaces_create_page',
          'arguments': {'title': 'Launch notes', 'space_id': 's'},
        },
      });
      gateway.event('tool.complete', 'runtime-1', {
        'tool_id': 'call-1',
        'name': 'tool_call',
        'duration_s': 0.4,
        'args': {
          'name': 'spaces_create_page',
          'arguments': {'title': 'Launch notes'},
        },
        'result': {
          'ok': true,
          'page': {
            'id': '11111111-2222-4333-8444-555555555555',
            'space_id': '66666666-7777-4888-8999-aaaaaaaaaaaa',
            'title': 'Launch notes',
          },
        },
      });
      await _settle();
      final events = service.activitySnapshotFor(stored);
      final started = events.firstWhere(
        (event) => event.kind == HermesLiveActivityKind.toolStarted,
      );
      check(started.detail).equals('spaces_create_page');
      check(started.preview).equals('Launch notes');
      final finished = events.firstWhere(
        (event) => event.kind == HermesLiveActivityKind.toolCompleted,
      );
      check(finished.toolId).equals('call-1');
      check(finished.duration).equals(const Duration(milliseconds: 400));
      check(finished.page!.title).equals('Launch notes');
    },
  );

  test('switching a chat model is session scoped and never global', () async {
    final (service, gateway) = await _connected();
    final stored = await createSession(service, gateway);
    gateway.responder = (method, params) => switch (method) {
      'config.set' when params['key'] == 'model' => {
        'key': 'model',
        'value': 'grok-4.6',
        'deferred': true,
      },
      _ => const {},
    };
    final outcome = await service.switchSessionModel(
      stored,
      const HermesSessionModelChoice(
        model: 'grok-4.6',
        provider: 'xai-oauth',
        reasoningEffort: 'high',
      ),
    );
    check(outcome).equals(HermesModelSwitchOutcome.nextTurn);
    final sets = gateway.calls('config.set');
    final model = sets.firstWhere((params) => params['key'] == 'model');
    check(model['value']).equals('grok-4.6 --provider xai-oauth --session');
    check(model['session_id']).equals('runtime-1');
    final effort = sets.firstWhere((params) => params['key'] == 'reasoning');
    check(effort['value']).equals('high');
    check(effort.containsKey('scope')).isFalse();
    check(service.agenticSnapshotFor(stored).info!.model).equals('grok-4.6');
    check(service.sessionModelChoice(stored)!.reasoningEffort).equals('high');
  });

  test('a fallback Hermes reports is shown, not masked by the pick', () async {
    final (service, gateway) = await _connected();
    final stored = await createSession(service, gateway);
    await service.switchSessionModel(
      stored,
      const HermesSessionModelChoice(model: 'free-model', provider: 'free'),
    );
    check(service.agenticSnapshotFor(stored).info!.model).equals('free-model');
    // The free provider rejected the call; Hermes' fallback chain served.
    gateway.event('session.info', 'runtime-1', {
      'model': 'mimo-v2.6-pro',
      'provider': 'xiaomi',
      'reasoning_effort': 'high',
      'running': false,
    });
    await _settle();
    check(service.agenticSnapshotFor(stored).info!.model)
        .equals('mimo-v2.6-pro');
    check(service.sessionModelChoice(stored)!.model).equals('free-model');
  });

  test('steering a delegate goes to subagent.steer for its session', () async {
    final (service, gateway) = await _connected();
    final stored = await createSession(service, gateway);
    gateway.responder = (method, _) => switch (method) {
      'subagent.steer' => {'status': 'queued', 'subagent_id': 'sa-1'},
      'subagent.interrupt' => {'found': true},
      _ => const {},
    };
    check(await service.steerSubagent(stored, 'sa-1', 'Use the EU prices'))
        .isTrue();
    check(await service.stopSubagent(stored, 'sa-1')).isTrue();
    final steer = gateway.calls('subagent.steer').single;
    check(steer['session_id']).equals('runtime-1');
    check(steer['text']).equals('Use the EU prices');
  });

  test(
    'team members are observed read-only from their room sessions',
    () async {
      final (service, gateway) = await _connected();
      gateway.responder = (method, params) => switch (method) {
        'session.list' when params['profile'] == 'kai' => {
          'sessions': [
            {'id': 'room-kai-stored', 'title': 'Group: team-1'},
          ],
        },
        'session.list' => {'sessions': const []},
        'session.active_list' => {
          'sessions': [
            {
              'id': 'room-kai-runtime',
              'session_key': 'room-kai-stored',
              'status': 'working',
              'preview': 'Here is what I found so far',
              'title': 'Group: team-1',
            },
          ],
        },
        'session.events.since' => {
          'epoch': 'e1',
          'latest_seq': 3,
          'truncated': false,
          'events': [
            {
              'seq': 1,
              'type': 'message.start',
              'session_id': 'room-kai-runtime',
            },
            {
              'seq': 2,
              'type': 'tool.start',
              'session_id': 'room-kai-runtime',
              'payload': {
                'tool_id': 't1',
                'name': 'web_search',
                'context': 'shopify api limits',
              },
            },
            {
              'seq': 3,
              'type': 'reasoning.available',
              'session_id': 'room-kai-runtime',
              'payload': {'text': 'Checking the rate limits first.'},
            },
          ],
        },
        _ => const {},
      };
      final live = await service.teamMembersLive('team-1', const [
        HermesTeamMember(memberId: 'm1', profile: 'kai', handle: 'kai'),
        HermesTeamMember(memberId: 'm2', profile: 'strong', handle: 'strong'),
      ]);
      final kai = live['kai']!;
      check(kai.working).isTrue();
      check(kai.preview).equals('Here is what I found so far');
      check(kai.thinking).equals('Checking the rate limits first.');
      check(kai.activity.single.preview).equals('shopify api limits');
      check(live.containsKey('strong')).isFalse();
      // Observation never takes a room session over.
      check(gateway.calls('session.resume')).isEmpty();
      check(gateway.calls('session.events.since').single['last_seen'])
          .equals(0);
    },
  );

  test('a stale Spaces save surfaces a typed revision conflict', () async {
    final (service, _) = await _connected(
      native: true,
      adapter: _Adapter(
        authRequired: true,
        spacesStatus: 409,
        spacesBody: {
          'error': 'revision_conflict',
          'message': 'The page changed.',
          'current_revision': 3,
        },
      ),
    );
    final client = HermesSpacesClient.forService(service, service.config)!;
    await check(
      client.updatePage(
        '11111111-2222-4333-8444-555555555555',
        expectedRevision: 2,
        content: 'mine',
      ),
    ).throws<SpacesRevisionConflict>(
      (it) =>
          it.has((error) => error.currentRevision, 'currentRevision').equals(3),
    );
  });

  test('plan parsing drops bad steps and flattens cycles', () {
    final plan = HermesTodoSnapshot.fromJson({
      'revision': 1,
      'todos': [
        {'id': 'a', 'content': 'A', 'status': 'pending', 'parent': 'b'},
        {'id': 'b', 'content': 'B', 'status': 'pending', 'parent': 'a'},
        {'id': '', 'content': 'no id', 'status': 'pending'},
        {'id': 'c', 'content': 'C', 'status': 'weird'},
        {'id': 'd', 'content': 'D', 'status': 'completed', 'parent': 'gone'},
      ],
    })!;
    check(plan.items.map((item) => item.id)).deepEquals(['a', 'b', 'd']);
    check(plan.items.every((item) => item.parent == null)).isTrue();
  });
}
