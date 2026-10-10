import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/motion/hermez_panel_morph.dart';
import 'package:conduit/features/hermes/providers/hermes_agentic_providers.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_agentic_state.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/views/hermes_live_run_page.dart';
import 'package:conduit/features/hermes/widgets/hermes_run_details_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'hermes_run_history_test.dart' show savedRunMessages;

void main() {
  for (final width in [320.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'completed history and button-panel round trip at $width/$scale',
        (tester) async {
          final adapter = _SavedAdapter();
          final service = HermesDesktopApiService(
            config: HermesConfig(
              enabled: true,
              baseUrl: 'https://hermes.example',
              mode: HermesBackendMode.desktopGateway,
              desktopCredentials: HermesDesktopCredentials(
                legacyToken: 'test-token',
              ),
            ),
            dio: Dio()..httpClientAdapter = adapter,
          );
          addTearDown(service.close);
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                hermesApiServiceProvider.overrideWithValue(service),
                hermesSessionsProvider.overrideWith(_Sessions.new),
                hermesAgenticStateProvider('session-1').overrideWith(
                  (ref) => Stream.value(HermesAgenticSnapshot.empty),
                ),
              ],
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 900),
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: const Scaffold(
                    body: Align(
                      alignment: Alignment.topRight,
                      child: HermesRunDetailsButton(
                        sessionId: 'session-1',
                        compact: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getSize(find.byType(HermesRunDetailsButton)),
            const Size(48, 48),
          );
          final triggerRect = tester.getRect(
            find.byType(HermesRunDetailsButton),
          );
          await tester.tap(find.byType(HermesRunDetailsButton));
          await tester.pumpAndSettle();
          expect(find.byType(HermesLiveRunPage), findsOneWidget);
          expect(
            tester
                .renderObject<RenderHermezPanelMorph>(
                  find.byType(HermezPanelMorph),
                )
                .originRect,
            triggerRect,
          );
          expect(adapter.reads, ['session-1']);
          expect(find.text('Finished'), findsOneWidget);
          final list = find
              .descendant(
                of: find.byType(HermesLiveRunPage),
                matching: find.byType(Scrollable),
              )
              .last;
          await tester.scrollUntilVisible(
            find.text('Earlier saved conclusion'),
            180,
            scrollable: list,
          );
          expect(find.text('Earlier saved conclusion'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Latest saved conclusion'),
            150,
            scrollable: list,
          );
          expect(find.text('Latest saved conclusion'), findsOneWidget);
          expect(tester.takeException(), isNull);
          // The close control returns the shared surface to the original trigger.
          await tester.tap(find.byTooltip('Close run details'));
          await tester.pumpAndSettle();
          expect(find.byType(HermesLiveRunPage), findsNothing);
          expect(find.byType(HermesRunDetailsButton), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'saved history failure is recoverable without losing the detail surface',
    (tester) async {
      final adapter = _SavedAdapter()..failNext = true;
      final service = HermesDesktopApiService(
        config: HermesConfig(
          enabled: true,
          baseUrl: 'https://hermes.example',
          mode: HermesBackendMode.desktopGateway,
          desktopCredentials: HermesDesktopCredentials(
            legacyToken: 'test-token',
          ),
        ),
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(service.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermesApiServiceProvider.overrideWithValue(service),
            hermesSessionsProvider.overrideWith(_Sessions.new),
            hermesAgenticStateProvider(
              'session-1',
            ).overrideWith((ref) => Stream.value(HermesAgenticSnapshot.empty)),
          ],
          child: const MaterialApp(
            home: HermesLiveRunPage(sessionId: 'session-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Saved activity is unavailable. Live activity is still shown.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Finished'), findsOneWidget);
      expect(adapter.reads, ['session-1', 'session-1']);
      expect(tester.takeException(), isNull);
    },
  );
}

class _SavedAdapter implements HttpClientAdapter {
  bool failNext = false;
  final reads = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final status = options.uri.path == '/api/status';
    if (!status) reads.add(options.uri.pathSegments[2]);
    if (!status && failNext) {
      failNext = false;
      return ResponseBody.fromString(
        '{}',
        503,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(
        status ? {'auth_required': false} : {'messages': savedRunMessages()},
      ),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Sessions extends HermesSessionsController {
  @override
  Future<List<HermesSessionSummary>> build() async => const [
    HermesSessionSummary(
      id: 'session-1',
      title: 'Saved run',
      profile: 'strong',
    ),
  ];
}
