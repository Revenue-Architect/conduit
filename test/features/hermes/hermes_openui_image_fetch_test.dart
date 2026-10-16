import 'dart:async';
import 'dart:io';

import 'package:conduit/features/hermes/widgets/hermes_openui_images.dart';
import 'package:flutter_test/flutter_test.dart';

// Plain tests only: with no widget binding the HttpClient is real, and the
// server is a loopback socket, so nothing leaves the machine.
void main() {
  test('bounded fetch sends no cookies or credentials, requires an image', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = <HttpHeaders>[];
    unawaited(
      server.forEach((request) async {
        seen.add(request.headers);
        final response = request.response;
        switch (request.uri.path) {
          case '/ok.png':
            response.headers.contentType = ContentType('image', 'png');
            response.add(const [1, 2, 3]);
          case '/page.html':
            response.headers.contentType = ContentType.html;
            response.write('<html></html>');
          case '/big.png':
            response.headers.contentType = ContentType('image', 'png');
            response.add(List.filled(5000, 7));
          default:
            response.statusCode = HttpStatus.notFound;
        }
        await response.close();
      }),
    );
    final base = 'http://127.0.0.1:${server.port}';
    expect(
      await fetchHermesOpenuiImageBytes(Uri.parse('$base/ok.png')),
      [1, 2, 3],
    );
    final headers = seen.single;
    expect(headers.value(HttpHeaders.cookieHeader), isNull);
    expect(headers.value(HttpHeaders.authorizationHeader), isNull);
    expect(headers.value(HttpHeaders.refererHeader), isNull);
    for (final path in ['/page.html', '/missing.png']) {
      await expectLater(
        fetchHermesOpenuiImageBytes(Uri.parse('$base$path')),
        throwsA(isA<HttpException>()),
        reason: path,
      );
    }
    await expectLater(
      fetchHermesOpenuiImageBytes(Uri.parse('$base/big.png'), maxBytes: 1000),
      throwsA(isA<HttpException>()),
    );
  });
}
