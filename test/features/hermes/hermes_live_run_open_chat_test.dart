import 'package:conduit/features/hermes/models/hermes_session.dart';
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
