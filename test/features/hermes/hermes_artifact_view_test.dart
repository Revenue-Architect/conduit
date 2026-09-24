import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/providers/hermes_artifact_provider.dart';
import 'package:conduit/features/hermes/services/hermes_artifact_client.dart';
import 'package:conduit/features/hermes/services/hermes_media_parser.dart';
import 'package:conduit/features/hermes/widgets/hermes_artifact_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a fetched Hermes image inline', (tester) async {
    final adapter = _RecordingAdapter(
      (_) async => ResponseBody.fromBytes(await _pngBytes(), 200),
    );
    final client = _client(adapter);
    addTearDown(client.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [hermesArtifactClientProvider.overrideWith((_) => client)],
        child: MaterialApp(
          home: Scaffold(
            body: HermesArtifactView(artifact: _artifact('image.png')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(adapter.requests, hasLength(1));
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('file cards defer downloads until Open is tapped', (
    tester,
  ) async {
    final adapter = _RecordingAdapter(
      (_) async => ResponseBody.fromBytes(Uint8List.fromList([1, 2, 3]), 200),
    );
    final client = _client(adapter);
    addTearDown(client.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [hermesArtifactClientProvider.overrideWith((_) => client)],
        child: MaterialApp(
          home: Scaffold(
            body: HermesArtifactView(artifact: _artifact('report.pdf')),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(adapter.requests, isEmpty);

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(adapter.requests, hasLength(1));
  });

  testWidgets('shows a sign-in state when image authentication expires', (
    tester,
  ) async {
    final adapter = _RecordingAdapter(
      (_) async => ResponseBody.fromBytes(Uint8List(0), 401),
    );
    final client = _client(adapter);
    addTearDown(client.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [hermesArtifactClientProvider.overrideWith((_) => client)],
        child: MaterialApp(
          home: Scaffold(
            body: HermesArtifactView(artifact: _artifact('image.png')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Hermes sign-in expired. Sign in and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a missing-file state when a file is tapped', (
    tester,
  ) async {
    final adapter = _RecordingAdapter(
      (_) async => ResponseBody.fromBytes(Uint8List(0), 404),
    );
    final client = _client(adapter);
    addTearDown(client.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [hermesArtifactClientProvider.overrideWith((_) => client)],
        child: MaterialApp(
          home: Scaffold(
            body: HermesArtifactView(artifact: _artifact('report.pdf')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(adapter.requests, isEmpty);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(adapter.requests, hasLength(1));
    expect(find.text('This file is no longer available.'), findsOneWidget);
  });
}

HermesArtifactClient _client(_RecordingAdapter adapter) => HermesArtifactClient(
  config: HermesConfig(
    enabled: true,
    baseUrl: 'https://hermes.example/v1',
    mode: HermesBackendMode.desktopGateway,
    desktopAuthKind: HermesDesktopAuthKind.dashboardCookie,
    desktopCredentials: HermesDesktopCredentials(),
  ),
  dio: Dio()..httpClientAdapter = adapter,
  cookieReader: (_) async => const {},
);

HermesMediaArtifact _artifact(String filename) => HermesMediaArtifact(
  path: '/opt/data/$filename',
  filename: filename,
  kind: filename.endsWith('.png')
      ? HermesMediaKind.image
      : HermesMediaKind.file,
);

Future<Uint8List> _pngBytes() async {
  return base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
  );
}

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;
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
