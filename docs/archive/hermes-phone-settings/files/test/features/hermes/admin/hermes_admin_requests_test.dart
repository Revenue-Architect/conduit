import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/features/hermes/admin/hermes_admin_client.dart';
import 'package:conduit/features/hermes/admin/hermes_admin_models.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_transport.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final class _MockChannel extends Mock implements WebSocketChannel {}

final class _MockSink extends Mock implements WebSocketSink {}

typedef _RpcHandler = Object? Function(Map<String, dynamic> params);

/// A Desktop Gateway that answers scripted methods and records every method
/// it is asked for. A handler may throw [HermesDesktopRpcException] to send a
/// JSON-RPC error frame.
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
      final id = frame['id'];
      if (id == null) return;
      final method = frame['method']?.toString() ?? '';
      final params = Map<String, dynamic>.from(frame['params'] as Map);
      methods.add(method);
      requests.add((method: method, params: params));
      Map<String, Object?> reply;
      try {
        final result = handlers[method]?.call(params) ?? <String, Object?>{};
        reply = {'jsonrpc': '2.0', 'id': id, 'result': result};
      } on HermesDesktopRpcException catch (error) {
        reply = {
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': error.code, 'message': error.message},
        };
      }
      scheduleMicrotask(() => incoming.add(jsonEncode(reply)));
    });
  }

  final channel = _MockChannel();
  final sink = _MockSink();
  final incoming = StreamController<dynamic>.broadcast();
  final methods = <String>[];
  final requests = <({String method, Map<String, dynamic> params})>[];
  final handlers = <String, _RpcHandler>{};

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

/// A dashboard that records REST requests and answers scripted routes.
final class _Rest implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  /// Keyed `VERB /path`. A route not listed answers 404 "No such API
  /// endpoint", as Hermes 0.21.5 does.
  final routes = <String, ({int status, Object? body})>{};

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final key = '${options.method} ${options.uri.path}';
    final route = options.uri.path == '/api/status'
        ? (
            status: 200,
            body: <String, Object?>{
              'version': '0.21.5',
              'auth_required': false,
              'gateway_running': true,
            },
          )
        : routes[key] ??
              (
                status: 404,
                body: {'detail': 'No such API endpoint: ${options.uri.path}'},
              );
    return ResponseBody.fromString(
      jsonEncode(route.body),
      route.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Iterable<RequestOptions> get adminRequests =>
      requests.where((r) => r.uri.path != '/api/status');
}

void main() {
  group('hermesAdminRouteAllowed', () {
    test('accepts the routes the admin client uses', () {
      for (final (method, path) in const [
        ('DELETE', '/api/profiles/qa-bot'),
        ('GET', '/api/profiles/qa-bot/soul'),
        ('PUT', '/api/profiles/qa-bot/soul'),
        ('GET', '/api/env'),
        ('PUT', '/api/env'),
        ('DELETE', '/api/env'),
        ('GET', '/api/providers/oauth'),
        ('POST', '/api/providers/oauth/nous/start'),
        ('GET', '/api/providers/oauth/nous/poll/abc-123'),
        ('DELETE', '/api/providers/oauth/nous'),
        ('DELETE', '/api/providers/oauth/sessions/abc-123'),
        ('POST', '/api/providers/validate'),
        ('POST', '/api/model/set'),
        ('GET', '/api/config'),
        ('PUT', '/api/config'),
        ('GET', '/api/config/raw'),
        ('PUT', '/api/config/raw'),
        ('GET', '/api/config/schema'),
        ('GET', '/api/config/defaults'),
        ('GET', '/api/tools/toolsets'),
        ('PUT', '/api/tools/toolsets/web'),
        ('PUT', '/api/skills/toggle'),
        ('PUT', '/api/mcp/servers/github/enabled'),
        ('GET', '/api/learning/node'),
        ('PUT', '/api/learning/node'),
        ('DELETE', '/api/learning/node'),
        ('POST', '/api/gateway/restart'),
        ('put', '/api/env'),
      ]) {
        expect(
          hermesAdminRouteAllowed(method, path),
          isTrue,
          reason: '$method $path',
        );
      }
    });

    test('refuses everything else, including reveal and shell', () {
      for (final (method, path) in const [
        ('POST', '/api/env/reveal'),
        ('GET', '/api/env/reveal'),
        ('POST', '/api/shell'),
        ('GET', '/api/shell'),
        ('POST', '/api/cli/exec'),
        ('GET', '/api/sessions'),
        ('GET', '/api/profiles'),
        ('POST', '/api/profiles'),
        ('PATCH', '/api/profiles/qa-bot'),
        ('GET', '/api/profiles/qa-bot'),
        ('DELETE', '/api/profiles/Qa-Bot'),
        ('POST', '/api/config'),
        ('DELETE', '/api/config/raw'),
        ('POST', '/api/learning/node'),
        ('PUT', '/api/providers/validate'),
        ('GET', '/api/tools/toolsets/web/config'),
        ('PUT', '/api/mcp/servers/github'),
        ('GET', '/api/env/'),
        ('GET', '/api/env?x=1'),
        ('GET', '/api/env#frag'),
        ('GET', 'https://evil.example/api/env'),
        ('GET', '/api/env/../shell'),
        ('PUT', '/api/mcp/servers/..%2Fshell/enabled'),
        ('PUT', '/api/mcp/servers/%2e%2e/enabled'),
        ('PUT', '/api/tools/toolsets/web%5Cx'),
        ('GET', ''),
      ]) {
        expect(
          hermesAdminRouteAllowed(method, path),
          isFalse,
          reason: '$method $path',
        );
      }
    });
  });

  group('over a real service', () {
    late _Gateway gateway;
    late _Rest rest;
    late HermesDesktopApiService service;
    late HermesAdminClient client;

    setUp(() {
      gateway = _Gateway();
      rest = _Rest();
      service = HermesDesktopApiService(
        config: HermesConfig(
          enabled: true,
          baseUrl: 'https://hermes.example',
          mode: HermesBackendMode.desktopGateway,
          desktopCredentials: HermesDesktopCredentials(
            legacyToken: 'session-token',
          ),
        ),
        dio: Dio()..httpClientAdapter = rest,
        rpc: HermesDesktopRpcClient(
          channelFactory: (_, _, {httpClient}) => gateway.channel,
        ),
      );
      client = HermesAdminClient.fromService(service);
    });

    tearDown(() async {
      service.close();
      await gateway.dispose();
    });

    test('the extension refuses a path outside the admin allowlist before '
        'building a request', () async {
      await expectLater(
        service.requestAdminJson('POST', '/api/shell'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.requestAdminJson('POST', '/api/env/reveal'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.requestAdminJson('GET', '/api/sessions'),
        throwsA(isA<StateError>()),
      );
      expect(rest.requests, isEmpty);
    });

    test('an allowed request goes out with the session credentials and the '
        'profile the caller named', () async {
      rest.routes['GET /api/env'] = (
        status: 200,
        body: {
          'OPENAI_API_KEY': {
            'is_set': true,
            'redacted_value': 'sk-...wxyz',
            'is_password': true,
          },
        },
      );
      final keys = await client.listEnvKeys('ops');
      expect(keys.single.redactedValue, 'sk-...wxyz');
      final sent = rest.adminRequests.single;
      expect(sent.method, 'GET');
      expect(sent.uri.path, '/api/env');
      expect(sent.uri.queryParameters, {'profile': 'ops'});
      expect(sent.headers['X-Hermes-Session-Token'], 'session-token');
    });

    test('a request body reaches Hermes and an error body is kept', () async {
      rest.routes['PUT /api/learning/node'] = (
        status: 404,
        body: {'detail': 'not found'},
      );
      await expectLater(
        client.updateLearningNode('ops', 'memory:memory:9', 'text'),
        throwsA(isA<HermesAdminNotFound>()),
      );
      final sent = rest.adminRequests.single;
      expect(sent.data, {
        'id': 'memory:memory:9',
        'content': 'text',
        'profile': 'ops',
      });
    });

    test('a real 404 for a missing profile and a real unknown route map '
        'differently', () async {
      rest.routes['GET /api/env'] = (
        status: 404,
        body: {'detail': "Profile 'ghost' does not exist."},
      );
      await expectLater(
        client.listEnvKeys('ghost'),
        throwsA(isA<HermesAdminNotFound>()),
      );
      // GET /api/config/schema is not scripted: Hermes answers "No such API
      // endpoint".
      await expectLater(
        client.configSchema('ops'),
        throwsA(isA<HermesAdminUnavailable>()),
      );
    });

    test('a missing mutating route answers 405 and is unavailable', () async {
      rest.routes['PUT /api/skills/toggle'] = (
        status: 405,
        body: {'detail': 'Method Not Allowed'},
      );
      await expectLater(
        client.setSkillEnabled('ops', 'git', false),
        throwsA(isA<HermesAdminUnavailable>()),
      );
    });

    test(
      'RPC calls open the gateway first and carry their parameters',
      () async {
        gateway.handlers['profiles.list'] = (_) => {
          'profiles': [
            {'name': 'default', 'is_default': true},
          ],
        };
        final profiles = await client.listProfiles();
        expect(profiles.single.name, 'default');
        expect(gateway.methods, contains('profiles.list'));
        final request = gateway.requests.firstWhere(
          (r) => r.method == 'profiles.list',
        );
        expect(request.params['include_sessions'], false);
      },
    );

    test('an unknown RPC method becomes "unavailable" end to end', () async {
      gateway.handlers['plugins.manage'] = (_) =>
          throw const HermesDesktopRpcException(
            'unknown method: plugins.manage',
            code: -32601,
          );
      await expectLater(
        client.plugins('ops'),
        throwsA(isA<HermesAdminUnavailable>()),
      );
    });

    test('MCP calls carry the profile through the gateway', () async {
      gateway.handlers['mcp.servers.list'] = (_) => {
        'servers': [
          {'name': 'github', 'enabled': true},
        ],
      };
      final servers = await client.mcpServers('ops');
      expect(servers.single.name, 'github');
      final request = gateway.requests.firstWhere(
        (r) => r.method == 'mcp.servers.list',
      );
      expect(request.params['profile'], 'ops');
    });

    test('an MCP call falls back to REST scoped to the profile when the '
        'gateway predates it', () async {
      gateway.handlers['mcp.servers.list'] = (_) =>
          throw const HermesDesktopRpcException('unknown method', code: -32601);
      rest.routes['GET /api/mcp/servers'] = (
        status: 200,
        body: {
          'servers': [
            {'name': 'github', 'enabled': true},
          ],
        },
      );
      final servers = await client.mcpServers('ops');
      expect(servers.single.name, 'github');
      final sent = rest.adminRequests.single;
      expect(sent.uri.path, '/api/mcp/servers');
      expect(sent.uri.queryParameters['profile'], 'ops');
    });

    test('an MCP method with no REST twin is "unavailable"', () async {
      gateway.handlers['mcp.servers.oauth.cancel'] = (_) =>
          throw const HermesDesktopRpcException('unknown method', code: -32601);
      await expectLater(
        client.cancelMcpOAuth('ops', 'github', 'flow-1'),
        throwsA(isA<HermesAdminUnavailable>()),
      );
    });

    test('the MCP extension forwards only MCP methods', () async {
      await expectLater(
        service.requestAdminMcp('cli.exec'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.requestAdminMcp('shell.exec'),
        throwsA(isA<StateError>()),
      );
      expect(gateway.methods, isEmpty);
    });

    test(
      'a full settings pass never calls cli.exec, shell.exec or reveal',
      () async {
        rest.routes['GET /api/env'] = (status: 200, body: <String, Object?>{});
        rest.routes['GET /api/tools/toolsets'] = (
          status: 200,
          body: <Object?>[],
        );
        rest.routes['PUT /api/tools/toolsets/web'] = (
          status: 200,
          body: {'ok': true},
        );
        await client.listProfiles();
        await client.describeProfile('ops');
        await client.listEnvKeys('ops');
        await client.toolsets('ops');
        await client.setToolsetEnabled('ops', 'web', true);
        await client.mcpServers('ops');
        await client.plugins('ops');
        await client.reloadMcp(confirm: true);
        await client.modelOptions('ops');

        for (final method in gateway.methods) {
          expect(method, isNot(startsWith('cli.')));
          expect(method, isNot(startsWith('shell.')));
        }
        for (final request in rest.requests) {
          expect(request.uri.path, isNot(contains('reveal')));
          expect(request.uri.path, isNot(contains('shell')));
        }
        // Toolsets were written by the per-toolset REST route.
        expect(
          rest.adminRequests.any(
            (r) => r.method == 'PUT' && r.uri.path == '/api/tools/toolsets/web',
          ),
          isTrue,
        );
        expect(gateway.methods, isNot(contains('profiles.configure')));
      },
    );

    test('a closed service refuses admin requests', () async {
      service.close();
      await expectLater(
        service.requestAdminJson('GET', '/api/env'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
