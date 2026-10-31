import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/providers/hermes_artifact_provider.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_artifact_client.dart';
import 'package:conduit/features/hermes/sky/hermez_weather.dart';
import 'package:conduit/features/hermes/views/hermes_artifacts_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoSessions extends HermesSessionsController {
  @override
  Future<List<HermesSessionSummary>> build() async => const [];
}

class _Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}

final class _ListingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'entries': [
        {
          'name': 'push-relay-split.pdf',
          'path': '/opt/data/artifacts/push-relay-split.pdf',
          'isDirectory': false,
        },
      ],
    }),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  // The rule: a file opens as the one card, in place. It is a popup route
  // over Artifacts, never a page pushed on top of it (s07b).
  testWidgets('an artifact opens as the card, not a new page', (tester) async {
    final client = HermesArtifactClient(
      config: const HermesConfig(
        enabled: true,
        baseUrl: 'https://hermes.example/v1',
        mode: HermesBackendMode.desktopGateway,
        desktopAuthKind: HermesDesktopAuthKind.dashboardCookie,
      ),
      dio: Dio()..httpClientAdapter = _ListingAdapter(),
      cookieReader: (_) async => const {},
    );
    final routes = _Routes();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermesArtifactClientProvider.overrideWithValue(client),
          hermesSessionsProvider.overrideWith(_NoSessions.new),
          hermezWeatherProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          navigatorObservers: [routes],
          home: const HermesArtifactsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pagesBefore = routes.pushed.whereType<PageRoute<dynamic>>().length;

    await tester.tap(find.text('push-relay-split.pdf'));
    await tester.pumpAndSettle();

    final opened = routes.pushed.skip(1).toList();
    expect(opened, hasLength(1));
    expect(opened.single, isNot(isA<PageRoute<dynamic>>()));
    expect(
      routes.pushed.whereType<PageRoute<dynamic>>(),
      hasLength(pagesBefore),
    );
    // The card is over the list, which is still there beneath it.
    expect(find.text('Related conversation'), findsNothing);
    expect(find.text('Source unavailable'), findsOneWidget);
    expect(find.text('Artifacts'), findsOneWidget);
  });
}
