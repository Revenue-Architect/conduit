import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/views/hermes_live_run_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

class _NoSessions extends HermesSessionsController {
  @override
  Future<List<HermesSessionSummary>> build() async => const [];
}

void main() {
  test(
    'an origin link cannot pick a same-id session belonging to another profile',
    () {
      const rows = [
        HermesSessionSummary(
          id: 'origin',
          title: 'Other profile',
          profile: 'default',
        ),
      ];
      expect(matchingOriginatingHermesSession(rows, 'origin', 'kai'), isNull);
      expect(
        matchingOriginatingHermesSession(rows, 'origin', 'default')?.title,
        'Other profile',
      );
    },
  );
  test(
    'a cold origin link retains its profile without needing cached sessions',
    () {
      expect(matchingOriginatingHermesSession([], 'origin', 'kai'), isNull);
      final service = HermesDesktopApiService(
        config: const HermesConfig(
          enabled: true,
          baseUrl: 'https://hermes.example',
          mode: HermesBackendMode.desktopGateway,
        ),
      );
      addTearDown(service.close);
      const page = HermesLiveRunPage(
        sessionId: 'origin',
        profile: 'kai',
        openChat: true,
      );
      service.bindSessionProfile(page.sessionId, page.profile!);
      expect(service.boundProfileFor('origin'), 'kai');
    },
  );
  testWidgets('a finished-run tap shows nothing while it opens, and the live '
      'page if the chat cannot be opened', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermesApiServiceProvider.overrideWithValue(null),
          hermesSessionsProvider.overrideWith(_NoSessions.new),
        ],
        child: const MaterialApp(
          home: HermesLiveRunPage(sessionId: 'session-1', openChat: true),
        ),
      ),
    );
    await tester.pump();
    // Waiting for Hermes: a blank page, no live-page flash.
    expect(find.text('Live run is unavailable.'), findsNothing);
    expect(find.textContaining('LIVE ACTIVITY'), findsNothing);

    // Hermes never becomes ready: fall back to the live page.
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
    expect(find.text('Live run is unavailable.'), findsOneWidget);
  });
}
