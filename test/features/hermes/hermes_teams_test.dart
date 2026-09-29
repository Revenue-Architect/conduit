import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/features/hermes/services/hermes_desktop_transport.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/models/hermes_team.dart';
import 'package:conduit/features/hermes/models/hermes_team_timeline.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/views/hermes_teams_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _roomJson = {
  'room_id': 'team-1',
  'name': 'Launch review',
  'members': [
    {'member_id': 'm-kai', 'profile': 'kai', 'handle': 'kai'},
    {
      'member_id': 'm-strong',
      'profile': 'strong',
      'handle': 'strong',
      'display_name': 'Strong',
    },
  ],
  'updated_at': 1790600000.5,
  'latest_seq': 4,
};

Map<String, Object?> _event(
  int seq,
  String kind, {
  String actor = 'gateway',
  String actorId = 'gw',
  Map<String, Object?> payload = const {},
}) => {
  'room_id': 'team-1',
  'seq': seq,
  'event_id': 'e$seq',
  'kind': kind,
  'actor': {'kind': actor, 'id': actorId},
  'payload': payload,
  'created_at': 1790600000 + seq,
};

HermesTeamEvent _parsed(Map<String, Object?> json) =>
    HermesTeamEvent.fromJson(json)!;

void main() {
  final team = HermesTeam.fromJson(_roomJson)!;

  test('rooms and members parse; bad ids are rejected', () {
    expect(team.name, 'Launch review');
    expect(team.members.map((member) => member.label), ['kai', 'Strong']);
    expect(team.memberById('m-strong')?.profile, 'strong');
    expect(HermesTeam.fromJson({..._roomJson, 'room_id': '../x'}), isNull);
    expect(HermesTeamMember.rosterFor('kai', title: 'Kai'), {
      'member_id': 'm-kai',
      'profile': 'kai',
      'handle': 'kai',
      'display_name': 'Kai',
    });
    expect(isValidHermesTeamId(newHermesTeamId('team')), isTrue);
    expect(newHermesTeamId('u'), isNot(newHermesTeamId('u')));
  });

  test('approvals and retries come from the driver status', () {
    final status = HermesTeamStatus.fromJson({
      'running': true,
      'working': true,
      'blocked': false,
      'pending_actions': [
        {'kind': 'retry', 'task_id': 't-1'},
        {
          'kind': 'approval',
          'task_id': 't-2',
          'member_id': 'm-kai',
          'execution_generation': 3,
          'request_id': 'r-9',
          'approval': {'description': 'Run the deploy script'},
        },
        {'kind': 'approval', 'task_id': 't-3'},
      ],
    });
    expect(status.working, isTrue);
    expect(status.retries, ['t-1']);
    expect(status.approvals.single.requestId, 'r-9');
    expect(status.approvals.single.description, 'Run the deploy script');
  });

  test('the timeline shows messages, passes, failures, and who thinks', () {
    final timeline = HermesTeamTimeline.from([
      _parsed(
        _event(
          1,
          'message.user',
          actor: 'user',
          actorId: 'me',
          payload: {'text': 'Plan the launch'},
        ),
      ),
      _parsed(
        _event(
          2,
          'turn.started',
          payload: {'member_id': 'm-kai', 'turn_id': 'a'},
        ),
      ),
      _parsed(
        _event(
          3,
          'message.member',
          actor: 'member',
          actorId: 'm-kai',
          payload: {
            'member_id': 'm-kai',
            'turn_id': 'a',
            'text': 'Draft ready',
          },
        ),
      ),
      _parsed(
        _event(
          4,
          'turn.settled',
          payload: {'member_id': 'm-strong', 'turn_id': 'b', 'passed': true},
        ),
      ),
      _parsed(
        _event(
          5,
          'turn.failed',
          payload: {
            'member_id': 'm-strong',
            'turn_id': 'c',
            'error': 'model timeout\ntrace',
          },
        ),
      ),
      _parsed(
        _event(
          6,
          'turn.started',
          payload: {'member_id': 'm-kai', 'turn_id': 'd'},
        ),
      ),
      _parsed(_event(7, 'room.renamed', actor: 'system')),
    ], team);
    expect(timeline.lines.map((line) => line.text), [
      'Plan the launch',
      'Draft ready',
      'Strong passed',
      "Strong couldn't reply: model timeout",
    ]);
    expect(timeline.lines[1].member?.profile, 'kai');
    expect(timeline.lines[3].kind, HermesTeamLineKind.problem);
    expect(timeline.thinking.single.profile, 'kai');

    final settled = HermesTeamTimeline.from([
      _parsed(
        _event(
          1,
          'turn.started',
          payload: {'member_id': 'm-kai', 'turn_id': 'a'},
        ),
      ),
      _parsed(_event(2, 'room.activity', payload: {'status': 'settled'})),
    ], team);
    expect(settled.thinking, isEmpty);
    expect(settled.lines.single.text, 'The team is done');
  });

  test('log pages merge in order without duplicates', () {
    final first = [_parsed(_event(1, 'x')), _parsed(_event(2, 'x'))];
    final merged = mergeHermesTeamEvents(first, [
      _parsed(_event(3, 'x')),
      _parsed(_event(2, 'x')),
    ]);
    expect(merged.map((event) => event.seq), [1, 2, 3]);
  });

  testWidgets('a team room shows the discussion and sends to it', (
    tester,
  ) async {
    final gateway = _TeamGateway();
    final service = HermesDesktopApiService(
      config: HermesConfig(
        enabled: true,
        baseUrl: 'https://hermes.example',
        mode: HermesBackendMode.desktopGateway,
        desktopCredentials: HermesDesktopCredentials(
          legacyToken: 'session-token',
        ),
      ),
      dio: Dio()..httpClientAdapter = _StatusAdapter(),
      rpc: HermesDesktopRpcClient(
        channelFactory: (_, _, {httpClient}) => gateway.channel,
      ),
    );
    addTearDown(() async {
      service.close();
      await gateway.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hermesApiServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: HermesTeamRoomPage(roomId: 'team-1')),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Launch review'), findsOneWidget);
    expect(find.text('Plan the launch'), findsOneWidget);
    expect(find.text('Draft ready'), findsOneWidget);
    expect(find.text('@kai'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'check the numbers');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(gateway.sentTexts, ['check the numbers']);
    expect(find.text('check the numbers'), findsOneWidget);
    expect(find.text('Strong is thinking'), findsOneWidget);
    expect(find.byTooltip('Stop the team'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Leaving the room stops its polling.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
}

final class _MockWebSocketChannel extends Mock implements WebSocketChannel {}

final class _MockWebSocketSink extends Mock implements WebSocketSink {}

/// A gateway that hosts one Group Chat room and answers `groups.*`.
final class _TeamGateway {
  _TeamGateway() {
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
      final id = frame['id'];
      if (id == null) return;
      final params = frame['params'] is Map
          ? Map<String, dynamic>.from(frame['params'] as Map)
          : const <String, dynamic>{};
      final result = _answer(frame['method']?.toString() ?? '', params);
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
  final sentTexts = <String>[];
  bool _working = false;
  final _log = <Map<String, Object?>>[
    _event(
      1,
      'message.user',
      actor: 'user',
      actorId: 'me',
      payload: {'text': 'Plan the launch'},
    ),
    _event(
      2,
      'message.member',
      actor: 'member',
      actorId: 'm-kai',
      payload: {'member_id': 'm-kai', 'turn_id': 'a', 'text': 'Draft ready'},
    ),
  ];

  Map<String, Object?> _answer(String method, Map<String, dynamic> params) {
    switch (method) {
      case 'groups.state':
        return {
          'room': _roomJson,
          'driver_status': {
            'running': true,
            'working': _working,
            'blocked': false,
            'counts': <String, int>{},
            'pending_actions': const <Object>[],
            'peer_routes': const <Object>[],
          },
        };
      case 'groups.log':
        final since = (params['since_seq'] as num?)?.toInt() ?? 0;
        return {
          'events': [
            for (final row in _log)
              if ((row['seq']! as int) > since) row,
          ],
          'cursor': _log.length,
          'latest_seq': _log.length,
          'has_more': false,
          'authority': {'gateway_id': 'gw', 'epoch': 1},
        };
      case 'groups.send':
        final payload = params['payload'] as Map;
        final text = payload['text'] as String;
        sentTexts.add(text);
        _working = true;
        _log
          ..add(
            _event(
              _log.length + 1,
              'message.user',
              actor: 'user',
              actorId: 'me',
              payload: {'text': text},
            ),
          )
          ..add(
            _event(
              _log.length + 2,
              'turn.started',
              payload: {'member_id': 'm-strong', 'turn_id': 'z'},
            ),
          );
        return {'event': _log[_log.length - 2], 'accepted': true};
      default:
        return const {};
    }
  }

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

  Future<void> dispose() => incoming.close();
}

final class _StatusAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'version': '2026.9.14',
      'auth_required': false,
      'gateway_running': true,
    }),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}
