import 'dart:async';
import 'dart:convert';

import 'package:conduit/features/hermes/services/hermes_desktop_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final class _Channel extends Mock implements WebSocketChannel {}

final class _Sink extends Mock implements WebSocketSink {}

final class _Gateway {
  _Gateway() {
    when(() => channel.ready).thenAnswer((_) async {});
    when(() => channel.stream).thenAnswer((_) => incoming.stream);
    when(() => channel.sink).thenReturn(sink);
    when(() => sink.close()).thenAnswer((_) async {});
    when(() => sink.add(any())).thenAnswer((call) {
      final frame = jsonDecode(
        call.positionalArguments.single as String,
      ) as Map<String, dynamic>;
      sent.add(frame);
      if (frame['method'] == 'client.capabilities') {
        receive({
          'id': frame['id'],
          if (legacy) 'error': {'code': -32601, 'message': 'Unknown method'},
          if (!legacy)
            'result': {
              'server_requests': ['approval', 'clarify'],
            },
        });
      }
    });
  }

  final channel = _Channel();
  final sink = _Sink();
  final incoming = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  bool legacy = false;

  void receive(Map<String, dynamic> frame) =>
      incoming.add(jsonEncode({'jsonrpc': '2.0', ...frame}));

  Future<HermesDesktopRpcClient> connect() async {
    final client = HermesDesktopRpcClient(
      channelFactory: (_, _, {httpClient}) => channel,
    );
    addTearDown(() async {
      await client.close();
      await incoming.close();
    });
    final connecting = client.connect(Uri.parse('wss://hermes.example/api/ws'));
    receive({
      'method': 'event',
      'params': {'type': 'gateway.ready'},
    });
    await connecting;
    return client;
  }
}

void main() {
  for (final legacy in [false, true]) {
    test(
      'capability negotiation leaves ${legacy ? 'v6' : 'v8'} usable',
      () async {
        final gateway = _Gateway()..legacy = legacy;
        final client = await gateway.connect();
        await client.advertiseServerRequests();
        expect(client.isReady, isTrue);
        expect(gateway.sent.single['method'], 'client.capabilities');
        expect(gateway.sent.single['params'], {'server_requests': true});
      },
    );
  }

  test('approval preserves the queue id, including on cancellation', () async {
    final gateway = _Gateway();
    final client = await gateway.connect();
    final events = <HermesDesktopEvent>[];
    final subscription = client.events.listen(events.add);
    addTearDown(subscription.cancel);
    gateway.receive({
      'id': 'srq-approval',
      'method': 'approval',
      'params': {
        'session_id': 'runtime-kai',
        'request_id': 'queue-approval',
        'command': 'echo test',
        'choices': ['once', 'deny'],
      },
    });
    gateway.receive({
      'method': 'event',
      'params': {
        'type': 'request.cancel',
        'session_id': 'runtime-kai',
        'payload': {'id': 'srq-approval', 'method': 'approval'},
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(events.map((e) => e.type), [
      'approval.request',
      'approval.expire',
      'request.cancel',
    ]);
    expect(events[0].payload['request_id'], 'queue-approval');
    expect(events[1].payload['request_id'], 'queue-approval');
    expect(events[1].sessionId, 'runtime-kai');
    expect(gateway.sent, isEmpty);
  });

  test(
    'resume replays and deduplicates unanswered requests before returning',
    () async {
      final gateway = _Gateway();
      final client = await gateway.connect();
      client.setDefaultParams({'profile': 'default'});
      final events = <HermesDesktopEvent>[];
      final subscription = client.events.listen(events.add);
      addTearDown(subscription.cancel);
      final request = client.request<Object?>(
        'session.resume',
        params: {'session_id': 'stored-kai', 'profile': 'kai'},
      );
      final openRequest = {
        'id': 'srq-clarify',
        'method': 'clarify',
        'params': {'session_id': 'runtime-kai', 'question': 'Which option?'},
      };
      gateway.receive({
        'id': gateway.sent.single['id'],
        'result': {
          'session_id': 'runtime-kai',
          'stored_session_id': 'stored-kai',
          'open_requests': [openRequest, openRequest],
        },
      });
      await request;
      expect(events, hasLength(1));
      expect(events.single.sessionId, 'runtime-kai');
      expect(events.single.payload['request_id'], 'srq-clarify');
      expect(
        client.answerServerRequest('srq-clarify', {'answer': 'blue'}),
        isTrue,
      );
      expect(gateway.sent.last, {
        'jsonrpc': '2.0',
        'id': 'srq-clarify',
        'result': {'answer': 'blue'},
      });
      expect(gateway.sent.first['params'], {
        'session_id': 'stored-kai',
        'profile': 'kai',
      });
    },
  );

  test(
    'unknown replayed desktop host requests are rejected, not invoked',
    () async {
      final gateway = _Gateway();
      final client = await gateway.connect();
      final request = client.request<Object?>('session.events.since');
      gateway.receive({
        'id': gateway.sent.single['id'],
        'result': {
          'open_requests': [
            {'id': 'host-1', 'method': 'terminal.open', 'params': {}},
          ],
        },
      });
      await request;
      expect(gateway.sent.last['id'], 'host-1');
      expect((gateway.sent.last['error'] as Map)['code'], -32601);
    },
  );

  test('legacy approval notification remains unchanged', () async {
    final gateway = _Gateway();
    final client = await gateway.connect();
    final event = client.events.first;
    gateway.receive({
      'method': 'event',
      'params': {
        'type': 'approval.request',
        'session_id': 'runtime-default',
        'payload': {'request_id': 'old-queue', 'command': 'echo test'},
      },
    });
    expect((await event).payload['request_id'], 'old-queue');
    expect(gateway.sent, isEmpty);
  });
}
