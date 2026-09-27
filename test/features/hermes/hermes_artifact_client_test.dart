import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/services/hermes_artifact_client.dart';
import 'package:conduit/features/hermes/services/hermes_media_parser.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HermesArtifactClient', () {
    test(
      'lists only validated artifact files with existing Dashboard auth',
      () async {
        final adapter = _RecordingAdapter(
          (_) => ResponseBody.fromString(
            jsonEncode({
              'entries': [
                {
                  'name': 'My Report.pdf',
                  'path': '/opt/data/artifacts/My Report.pdf',
                  'isDirectory': false,
                },
                {
                  'name': 'folder',
                  'path': '/opt/data/artifacts/folder',
                  'isDirectory': true,
                },
                {
                  'name': '../secret',
                  'path': '/opt/data/artifacts/../secret',
                  'isDirectory': false,
                },
                {
                  'name': 'other.png',
                  'path': '/tmp/other.png',
                  'isDirectory': false,
                },
              ],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          ),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final client = HermesArtifactClient(
          config: _config(),
          dio: dio,
          cookieReader: (_) async => const {'session': 'cookie-value'},
        );
        final files = await client.listDirectory('/opt/data/artifacts');
        expect(files.map((file) => file.name), ['My Report.pdf']);
        expect(adapter.requests.single.uri.path, '/api/fs/list');
        expect(
          adapter.requests.single.uri.queryParameters['path'],
          '/opt/data/artifacts',
        );
        expect(
          adapter.requests.single.headers['Cookie'],
          'session=cookie-value',
        );
        expect(adapter.requests.single.followRedirects, isFalse);
        await expectLater(
          client.listDirectory('/opt/data'),
          throwsA(isA<HermesArtifactException>()),
        );
        expect(adapter.requests, hasLength(1));
        dio.close(force: true);
      },
    );

    test(
      'artifact download support matches the authenticated HTTPS endpoint',
      () {
        expect(supportsHermesArtifactDownloads(_config()), isTrue);
        expect(
          supportsHermesArtifactDownloads(
            _config(baseUrl: 'http://hermes.example/v1'),
          ),
          isFalse,
        );
        expect(
          supportsHermesArtifactDownloads(
            _config(mode: HermesBackendMode.responsesApi),
          ),
          isFalse,
        );
        expect(
          supportsHermesArtifactDownloads(
            _config(authKind: HermesDesktopAuthKind.nativePkce),
          ),
          isTrue,
        );
        expect(
          supportsHermesArtifactDownloads(
            _config(authKind: HermesDesktopAuthKind.legacyToken),
          ),
          isFalse,
        );
      },
    );

    test(
      'downloads bytes with the Dashboard cookie and configured headers',
      () async {
        final adapter = _RecordingAdapter(
          (_) => ResponseBody.fromBytes(
            Uint8List.fromList([1, 2, 3]),
            200,
            headers: {
              Headers.contentTypeHeader: ['image/png'],
            },
          ),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final cookieUrls = <String>[];
        final client = HermesArtifactClient(
          config: _config(),
          dio: dio,
          cookieReader: (url) async {
            cookieUrls.add(url);
            return const {'session': 'cookie-value'};
          },
        );

        final result = await client.download(
          _artifact('/opt/data/My Image.png'),
        );

        expect(result.bytes, [1, 2, 3]);
        expect(result.contentType, 'image/png');
        expect(adapter.requests, hasLength(1));
        final request = adapter.requests.single;
        expect(request.method, 'GET');
        expect(request.uri.origin, 'https://hermes.example');
        expect(request.uri.path, '/api/fs/download');
        expect(request.uri.queryParameters, {
          'path': '/opt/data/My Image.png',
          'profile': 'default',
        });
        expect(request.responseType, ResponseType.bytes);
        expect(request.followRedirects, isFalse);
        expect(request.headers['CF-Access-Client-Id'], 'access-id');
        expect(request.headers['Cookie'], 'session=cookie-value');
        final cookieLookupUri = Uri.parse(cookieUrls.single);
        expect(cookieLookupUri.origin, 'https://hermes.example');
        expect(cookieLookupUri.path, '/api/fs/download');
        expect(cookieLookupUri.hasQuery, isFalse);
        expect(
          jsonEncode(request.uri.queryParameters),
          isNot(contains('cookie')),
        );
        dio.close(force: true);
      },
    );

    test(
      'preserves a configured Cookie header when adding WebView cookies',
      () async {
        final adapter = _RecordingAdapter(
          (_) => ResponseBody.fromBytes(Uint8List(0), 200),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final client = HermesArtifactClient(
          config: _config(accessHeaders: const {'Cookie': 'proxy=one'}),
          dio: dio,
          cookieReader: (_) async => const {'session': 'two'},
        );

        await client.download(_artifact('/opt/data/file.txt'));

        expect(
          adapter.requests.single.headers['Cookie'],
          'proxy=one; session=two',
        );
        dio.close(force: true);
      },
    );

    test(
      'downloads bytes with existing PKCE auth without reading WebView cookies',
      () async {
        final adapter = _RecordingAdapter(
          (_) => ResponseBody.fromBytes(
            Uint8List.fromList([4, 5, 6]),
            200,
            headers: {
              Headers.contentTypeHeader: ['image/png'],
            },
          ),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        var cookieReads = 0;
        var authorizationReads = 0;
        final client = HermesArtifactClient(
          config: _config(authKind: HermesDesktopAuthKind.nativePkce),
          dio: dio,
          cookieReader: (_) async {
            cookieReads++;
            return const {};
          },
          nativeAuthorizationReader: () async {
            authorizationReads++;
            return const {
              'Authorization': 'Bearer native-test-token',
              'CF-Access-Client-Id': 'access-id',
            };
          },
        );

        final result = await client.download(
          _artifact('/opt/data/hermes_mobile_test.png'),
          sessionId: 'session-42',
        );

        expect(result.bytes, [4, 5, 6]);
        expect(adapter.requests, hasLength(1));
        final request = adapter.requests.single;
        expect(request.uri.queryParameters, {
          'path': '/opt/data/hermes_mobile_test.png',
          'profile': 'default',
          'session_id': 'session-42',
        });
        expect(request.headers['Authorization'], 'Bearer native-test-token');
        expect(request.headers['CF-Access-Client-Id'], 'access-id');
        expect(cookieReads, 0);
        expect(authorizationReads, 1);
        dio.close(force: true);
      },
    );

    test(
      'allows an unauthenticated HTTPS Gateway in native PKCE mode',
      () async {
        final adapter = _RecordingAdapter(
          (_) => ResponseBody.fromBytes(Uint8List.fromList([7, 8, 9]), 200),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        var cookieReads = 0;
        final client = HermesArtifactClient(
          config: _config(authKind: HermesDesktopAuthKind.nativePkce),
          dio: dio,
          cookieReader: (_) async {
            cookieReads++;
            return const {};
          },
          nativeAuthorizationReader: () async => null,
        );

        final result = await client.download(_artifact('/opt/data/file.png'));

        expect(result.bytes, [7, 8, 9]);
        expect(
          adapter.requests.single.headers.containsKey('Authorization'),
          isFalse,
        );
        expect(cookieReads, 0);
        dio.close(force: true);
      },
    );

    test(
      'maps missing native PKCE credentials to authExpired on 401',
      () async {
        final adapter = _RecordingAdapter(
          (_) => ResponseBody.fromBytes(Uint8List(0), 401),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final client = HermesArtifactClient(
          config: _config(authKind: HermesDesktopAuthKind.nativePkce),
          dio: dio,
          nativeAuthorizationReader: () async => null,
        );

        await expectLater(
          client.download(_artifact('/opt/data/file.png')),
          throwsA(
            isA<HermesArtifactException>().having(
              (error) => error.kind,
              'kind',
              HermesArtifactFailureKind.authExpired,
            ),
          ),
        );
        dio.close(force: true);
      },
    );

    test(
      'forwards the configured profile and validated session context',
      () async {
        final adapter = _RecordingAdapter(
          (_) => ResponseBody.fromBytes(Uint8List(0), 200),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final client = HermesArtifactClient(
          config: _config(desktopProfile: 'research'),
          dio: dio,
          cookieReader: (_) async => const {},
        );

        await client.download(
          _artifact('reports/summary.pdf'),
          sessionId: 'session-42',
        );

        expect(adapter.requests.single.uri.queryParameters, {
          'path': 'reports/summary.pdf',
          'profile': 'research',
          'session_id': 'session-42',
        });
        dio.close(force: true);
      },
    );

    for (final (status, kind) in <(int, HermesArtifactFailureKind)>[
      (401, HermesArtifactFailureKind.authExpired),
      (403, HermesArtifactFailureKind.authExpired),
      (404, HermesArtifactFailureKind.missing),
      (302, HermesArtifactFailureKind.unavailable),
      (500, HermesArtifactFailureKind.unavailable),
    ]) {
      test('maps HTTP $status to ${kind.name}', () async {
        final adapter = _RecordingAdapter(
          (_) => ResponseBody.fromBytes(Uint8List(0), status),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final client = HermesArtifactClient(
          config: _config(),
          dio: dio,
          cookieReader: (_) async => const {},
        );

        await expectLater(
          client.download(_artifact('/opt/data/file.pdf')),
          throwsA(
            isA<HermesArtifactException>().having(
              (error) => error.kind,
              'kind',
              kind,
            ),
          ),
        );
        // A cross-origin 302 is returned as a failure; the adapter is called
        // only once and no credentials can be forwarded to Location.
        expect(adapter.requests, hasLength(1));
        expect(adapter.requests.single.followRedirects, isFalse);
        dio.close(force: true);
      });
    }

    test(
      'rejects HTTP and non-Dashboard auth before reading cookies',
      () async {
        var cookieReads = 0;
        final adapter = _RecordingAdapter(
          (_) => ResponseBody.fromBytes(Uint8List(0), 200),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final client = HermesArtifactClient(
          config: _config(baseUrl: 'http://hermes.example/v1'),
          dio: dio,
          cookieReader: (_) async {
            cookieReads++;
            return const {};
          },
        );

        await expectLater(
          client.download(_artifact('/opt/data/file.pdf')),
          throwsA(
            isA<HermesArtifactException>().having(
              (error) => error.kind,
              'kind',
              HermesArtifactFailureKind.unavailable,
            ),
          ),
        );
        expect(cookieReads, 0);
        expect(adapter.requests, isEmpty);
        dio.close(force: true);
      },
    );

    test(
      'requires PKCE authorization and never falls back to Dashboard cookies',
      () async {
        var cookieReads = 0;
        final adapter = _RecordingAdapter(
          (_) => ResponseBody.fromBytes(Uint8List(0), 401),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final client = HermesArtifactClient(
          config: _config(authKind: HermesDesktopAuthKind.nativePkce),
          dio: dio,
          cookieReader: (_) async {
            cookieReads++;
            return const {};
          },
        );

        await expectLater(
          client.download(_artifact('/opt/data/file.pdf')),
          throwsA(
            isA<HermesArtifactException>().having(
              (error) => error.kind,
              'kind',
              HermesArtifactFailureKind.authExpired,
            ),
          ),
        );
        expect(cookieReads, 0);
        expect(adapter.requests, hasLength(1));
        expect(
          adapter.requests.single.headers.containsKey('Authorization'),
          isFalse,
        );
        expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
        dio.close(force: true);
      },
    );

    test('preserves a configured path prefix in the Hermes endpoint', () async {
      final adapter = _RecordingAdapter(
        (_) => ResponseBody.fromBytes(Uint8List(0), 200),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final client = HermesArtifactClient(
        config: _config(baseUrl: 'https://hermes.example/gateway/v1'),
        dio: dio,
        cookieReader: (_) async => const {},
      );

      await client.download(_artifact('/opt/data/file.pdf'));

      expect(adapter.requests.single.uri.path, '/gateway/api/fs/download');
      dio.close(force: true);
    });
  });
}

HermesConfig _config({
  String baseUrl = 'https://hermes.example/v1',
  HermesBackendMode mode = HermesBackendMode.desktopGateway,
  HermesDesktopAuthKind authKind = HermesDesktopAuthKind.dashboardCookie,
  String desktopProfile = 'default',
  Map<String, String> accessHeaders = const {
    'CF-Access-Client-Id': 'access-id',
  },
}) => HermesConfig(
  enabled: true,
  baseUrl: baseUrl,
  mode: mode,
  desktopAuthKind: authKind,
  desktopProfile: desktopProfile,
  desktopCredentials: HermesDesktopCredentials(accessHeaders: accessHeaders),
);

HermesMediaArtifact _artifact(String path) => HermesMediaArtifact(
  path: path,
  filename: path.split('/').last,
  kind: HermesMediaKind.file,
);

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}
