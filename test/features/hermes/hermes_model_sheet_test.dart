import 'package:conduit/features/hermes/providers/hermes_agentic_providers.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_agentic_state.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/services/hermes_backend_service.dart';
import 'package:conduit/features/hermes/sheets/hermes_model_sheet.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Desktop extends Mock implements HermesDesktopApiService {}

void main() {
  const key = (storedId: 'session-model', profile: 'default');
  Future<void> open(WidgetTester tester, {bool catalogFailure = false}) async {
    final service = _Desktop();
    when(() => service.sessionModelChoice('session-model')).thenReturn(
      const HermesSessionModelChoice(model: 'next-model', provider: 'litellm'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermesApiServiceProvider.overrideWithValue(service),
          hermesModelCatalogProvider(key).overrideWith((ref) async {
            if (catalogFailure) throw StateError('catalog unavailable');
            return const HermesModelCatalog(
              options: [],
              currentModel: 'old-model',
              currentProvider: 'litellm',
            );
          }),
          hermesAgenticStateProvider('session-model').overrideWith(
            (ref) => Stream.value(
              const HermesAgenticSnapshot(
                info: HermesSessionRuntimeInfo(
                  model: 'old-model',
                  provider: 'litellm',
                  running: true,
                ),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(TweakcnThemes.t3Chat),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHermesModelSheet(
                  context,
                  sessionId: 'session-model',
                  profile: 'default',
                ),
                child: const Text('Open models'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open models'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'pending model and older session info do not invent a failed reply',
    (tester) async {
      await open(tester);
      expect(find.textContaining('failed on the last message'), findsNothing);
      expect(find.textContaining('so Hermes used its fallback'), findsNothing);
      expect(find.text('old-model'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('actual model catalog failure still offers retry', (
    tester,
  ) async {
    await open(tester, catalogFailure: true);
    expect(find.text("Could not load this profile's models."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
