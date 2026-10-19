import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:conduit/features/push/models/approval.dart';
import 'package:conduit/features/push/services/push_gateway_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int code, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  code,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Dio _dio(_FakeAdapter adapter) =>
    Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = adapter;

const _origin = 'https://umbrel.tail4c9e01.ts.net:8450';
const _token = 'hpd_secret-token-value';

Map<String, dynamic> _row(String id) => {
  'id': id,
  'action_type': 'restart_container',
  'description': 'Restart it',
  'status': 'pending',
  'created_at': '2026-10-19T15:00:00+00:00',
  'expires_at': '2026-10-19T15:40:00+00:00',
  'requested_by': 'chief',
  'payload_digest': 'dg',
};

void main() {
  group('origin and code normalization', () {
    test('gateway origins', () {
      check(normalizeGatewayOrigin('umbrel.tail4c9e01.ts.net:8450'))
          .equals('https://umbrel.tail4c9e01.ts.net:8450');
      check(normalizeGatewayOrigin(' https://h.example:8450/phone/v1/ '))
          .equals('https://h.example:8450');
      check(normalizeGatewayOrigin('http://192.168.2.107:18768'))
          .equals('http://192.168.2.107:18768');
      check(normalizeGatewayOrigin('')).isNull();
      check(normalizeGatewayOrigin('ftp://h.example')).isNull();
      check(normalizeGatewayOrigin('https://user:pw@h.example')).isNull();
    });

    test('pairing codes ignore spaces, dashes and case', () {
      check(normalizePairingCode(' ab3k-9x2 mq ')).equals('AB3K9X2MQ');
    });
  });

  group('pair', () {
    test('posts the code and reads the credentials', () async {
      final adapter = _FakeAdapter(
        (o) => _json(200, {
          'device_id': 'dev-1',
          'token': 'hpd_new',
          'expires_at': 1776000000,
          'scopes': ['approvals:read', 'approvals:decide'],
          'gateway_epoch': 1,
        }),
      );
      final result = await PushGatewayClient.pair(
        origin: _origin,
        code: 'ab3k-9x2mq4',
        deviceName: 'Phone',
        appVersion: '1.0+184',
        dio: _dio(adapter),
      );
      check(result.deviceId).equals('dev-1');
      check(result.token).equals('hpd_new');
      check(result.scopes).deepEquals(['approvals:read', 'approvals:decide']);
      check(result.gatewayEpoch).equals('1');
      final request = adapter.requests.single;
      check(request.uri.toString()).equals('$_origin/phone/v1/pair');
      check(request.method).equals('POST');
      check(request.headers['Authorization']).isNull();
      final body = request.data as Map;
      check(body['code']).equals('AB3K9X2MQ4');
      check(body['platform']).equals('android');
      check(body['device_name']).equals('Phone');
    });

    test('a bad code is an unauthorized-style error', () async {
      final adapter = _FakeAdapter(
        (o) => _json(401, {'error': 'invalid_code'}),
      );
      await check(
        PushGatewayClient.pair(
          origin: _origin,
          code: 'WRONGCODE1',
          deviceName: 'Phone',
          appVersion: '1',
          dio: _dio(adapter),
        ),
      ).throws<PushGatewayException>(
        (it) => it
          ..has((e) => e.isUnauthorized, 'isUnauthorized').isTrue()
          ..has((e) => e.code, 'code').equals('invalid_code'),
      );
    });

    test('a reply without a token is rejected', () async {
      final adapter = _FakeAdapter((o) => _json(200, {'device_id': 'x'}));
      await check(
        PushGatewayClient.pair(
          origin: _origin,
          code: 'ABCDEFGH23',
          deviceName: 'Phone',
          appVersion: '1',
          dio: _dio(adapter),
        ),
      ).throws<PushGatewayException>();
    });
  });

  group('approvals', () {
    test(
      'token rotation uses the device token and validates its replacement',
      () async {
        final adapter = _FakeAdapter(
          (o) => _json(200, {
            'token': 'hpd_renewed',
            'expires_at': 1800000000,
            'scopes': ['inbox:read'],
          }),
        );
        final client = PushGatewayClient(
          origin: _origin,
          token: _token,
          dio: _dio(adapter),
        );
        final result = await client.rotateToken('dev-1', 'epoch-1');
        expect(result.token, 'hpd_renewed');
        expect(result.gatewayEpoch, 'epoch-1');
        expect(
          adapter.requests.single.uri.path,
          '/phone/v1/devices/me/token/rotate',
        );
        expect(
          adapter.requests.single.headers['Authorization'],
          'Bearer $_token',
        );
      },
    );

    test('malformed token rotation is rejected', () async {
      final adapter = _FakeAdapter((o) => _json(200, {'token': 'hpd_bad'}));
      final client = PushGatewayClient(
        origin: _origin,
        token: _token,
        dio: _dio(adapter),
      );
      await expectLater(
        client.rotateToken('dev-1', 'epoch-1'),
        throwsA(isA<PushGatewayException>()),
      );
    });
    test('list sends the bearer token and query', () async {
      final adapter = _FakeAdapter(
        (o) => _json(200, {
          'items': [_row('a-1'), _row('a-2')],
          'next_before': '2026-10-01T00:00:00+00:00',
        }),
      );
      final client = PushGatewayClient(
        origin: _origin,
        token: _token,
        dio: _dio(adapter),
      );
      final page = await client.listApprovals(
        status: 'all',
        limit: 30,
        before: '2026-10-10T00:00:00+00:00',
      );
      check(page.items).length.equals(2);
      check(page.nextBefore).equals('2026-10-01T00:00:00+00:00');
      final request = adapter.requests.single;
      check(request.headers['Authorization']).equals('Bearer $_token');
      check(request.uri.path).equals('/phone/v1/approvals');
      check(request.uri.queryParameters).deepEquals({
        'status': 'all',
        'limit': '30',
        'before': '2026-10-10T00:00:00+00:00',
      });
    });

    test('detail unwraps an item', () async {
      final adapter = _FakeAdapter((o) => _json(200, {'item': _row('a-1')}));
      final client = PushGatewayClient(
        origin: _origin,
        token: _token,
        dio: _dio(adapter),
      );
      final approval = await client.getApproval('a-1');
      check(approval.id).equals('a-1');
      check(adapter.requests.single.uri.path).equals('/phone/v1/approvals/a-1');
    });

    test('detail also accepts a bare object', () async {
      final adapter = _FakeAdapter((o) => _json(200, _row('a-9')));
      final client = PushGatewayClient(
        origin: _origin,
        token: _token,
        dio: _dio(adapter),
      );
      check((await client.getApproval('a-9')).id).equals('a-9');
    });

    test('decision body, digest and idempotency key', () async {
      final adapter = _FakeAdapter(
        (o) => _json(200, {'id': 'a-1', 'status': 'approved'}),
      );
      final client = PushGatewayClient(
        origin: _origin,
        token: _token,
        dio: _dio(adapter),
      );
      final status = await client.decide(
        id: 'a-1',
        decision: ApprovalDecision.approve,
        digest: 'dg',
        deviceId: 'dev-1',
      );
      check(status).equals(ApprovalStatus.approved);
      final request = adapter.requests.single;
      check(request.method).equals('POST');
      check(request.uri.path).equals('/phone/v1/approvals/a-1/decision');
      check(request.headers['Idempotency-Key']).equals('dec-a-1-approve-dev-1');
      check(request.headers['Authorization']).equals('Bearer $_token');
      check(request.data as Map)
          .deepEquals({'decision': 'approve', 'digest': 'dg'});
    });

    test(
      'a replayed decision with no status still reports the decision',
      () async {
        final adapter = _FakeAdapter((o) => _json(200, {'replayed': true}));
        final client = PushGatewayClient(
          origin: _origin,
          token: _token,
          dio: _dio(adapter),
        );
        final status = await client.decide(
          id: 'a-1',
          decision: ApprovalDecision.deny,
          digest: 'dg',
          deviceId: 'dev-1',
        );
        check(status).equals(ApprovalStatus.denied);
      },
    );

    test('409 conflict carries the current status', () async {
      final adapter = _FakeAdapter(
        (o) => _json(409, {'error': 'conflict', 'status': 'denied'}),
      );
      final client = PushGatewayClient(
        origin: _origin,
        token: _token,
        dio: _dio(adapter),
      );
      await check(
        client.decide(
          id: 'a-1',
          decision: ApprovalDecision.approve,
          digest: 'dg',
          deviceId: 'd',
        ),
      ).throws<PushGatewayException>(
        (it) => it
          ..has((e) => e.isConflict, 'isConflict').isTrue()
          ..has(
            (e) => e.currentStatus,
            'currentStatus',
          ).equals(ApprovalStatus.denied)
          ..has((e) => e.isDigestMismatch, 'isDigestMismatch').isFalse(),
      );
    });

    test('digest mismatch is its own case', () async {
      final adapter = _FakeAdapter(
        (o) => _json(409, {'error': 'digest_mismatch'}),
      );
      final client = PushGatewayClient(
        origin: _origin,
        token: _token,
        dio: _dio(adapter),
      );
      await check(
        client.decide(
          id: 'a-1',
          decision: ApprovalDecision.approve,
          digest: 'old',
          deviceId: 'd',
        ),
      ).throws<PushGatewayException>(
        (it) => it.has((e) => e.isDigestMismatch, 'isDigestMismatch').isTrue(),
      );
    });

    test('404, 401 and 500 map to distinct failures', () async {
      for (final (code, test) in <(int, bool Function(PushGatewayException))>[
        (404, (e) => e.isNotFound),
        (401, (e) => e.isUnauthorized),
        (403, (e) => e.isUnauthorized),
        (500, (e) => e.statusCode == 500 && !e.isNetwork),
      ]) {
        final adapter = _FakeAdapter((o) => _json(code, {'error': 'x'}));
        final client = PushGatewayClient(
          origin: _origin,
          token: _token,
          dio: _dio(adapter),
        );
        try {
          await client.getApproval('a-1');
          fail('expected an error for $code');
        } on PushGatewayException catch (error) {
          check(test(error)).isTrue();
        }
      }
    });

    test('a network failure is reported without the token', () async {
      final adapter = _FakeAdapter((o) => throw const SocketLikeError());
      final client = PushGatewayClient(
        origin: _origin,
        token: _token,
        dio: _dio(adapter),
      );
      try {
        await client.listApprovals();
        fail('expected an error');
      } on PushGatewayException catch (error) {
        check(error.isNetwork).isTrue();
        check(error.message.contains(_token)).isFalse();
        check(error.toString().contains(_token)).isFalse();
      }
    });
  });
}

class SocketLikeError implements Exception {
  const SocketLikeError();
}
