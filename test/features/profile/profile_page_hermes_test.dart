import 'package:conduit/core/models/model.dart';
import 'package:conduit/core/providers/app_providers.dart';
import 'package:conduit/core/providers/backend_mode_providers.dart';
import 'package:conduit/core/models/socket_transport_availability.dart';
import 'package:conduit/core/services/optimized_storage_service.dart';
import 'package:conduit/core/services/settings_service.dart';
import 'package:conduit/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit/features/direct_connections/models/direct_connection_profile.dart';
import 'package:conduit/features/direct_connections/providers/direct_connection_providers.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/profile/views/profile_page.dart';
import 'package:conduit/features/workspace/models/workspace_capabilities.dart';
import 'package:conduit/features/workspace/providers/workspace_capabilities_provider.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness({required bool direct, List<Model> models = const []}) {
  return ProviderScope(
    key: ValueKey(models.length),
    overrides: [
      currentUserProvider2.overrideWithValue(null),
      currentUserProvider.overrideWith((ref) async => null),
      isAuthLoadingProvider2.overrideWithValue(false),
      apiServiceProvider.overrideWithValue(null),
      hermesOnlyModeProvider.overrideWithValue(!direct),
      appSettingsProvider.overrideWithValue(const AppSettings()),
      optimizedStorageServiceProvider.overrideWithValue(
        _FakeOptimizedStorageService(),
      ),
      modelsProvider.overrideWith(() => _Models(models)),
      hermesBotsProvider.overrideWith((ref) async => const []),
      directConnectionProfilesProvider.overrideWith(_NoProfiles.new),
      workspaceCapabilitiesProvider.overrideWith(
        (ref) async => WorkspaceCapabilities.none,
      ),
      if (direct)
        preferredBackendProvider.overrideWith(
          () => _DirectPreferredBackendController(),
        ),
    ],
    child: const MaterialApp(
      localizationsDelegates: conduitLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProfilePage(),
    ),
  );
}

void main() {
  testWidgets('Hermes-only profile exposes only app-local settings', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(direct: false));
    await tester.pumpAndSettle();

    expect(find.text('All settings'), findsOneWidget);
    expect(find.text('Personalization'), findsNothing);
    expect(find.text('No email'), findsNothing);

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Hermes Agent'), findsOneWidget);
    expect(find.byKey(const Key('hermes-settings-logo')), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Direct connections'), 300);
    expect(find.text('Direct connections'), findsOneWidget);
    expect(find.text('OpenAI-compatible APIs and Ollama'), findsOneWidget);
    expect(
      find.text('Connect to Open WebUI'),
      kShowOpenWebUi ? findsOneWidget : findsNothing,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-donations')),
      300,
    );
    expect(find.text('About'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Buy me a coffee'),
        matching: find.byKey(const Key('settings-donations')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('settings-sign-out')), findsNothing);
  });

  testWidgets(
    'direct-only profile offers Personalization only with an image model',
    (tester) async {
      await tester.pumpWidget(_harness(direct: true));
      await tester.pumpAndSettle();

      // The default model moved to Chat; with nothing else to set there is no
      // empty Personalization page to open.
      expect(find.text('Personalization'), findsNothing);
      expect(find.text('Chat'), findsOneWidget);

      await tester.pumpWidget(
        _harness(
          direct: true,
          models: const [
            Model(
              id: 'direct:openrouter:text-model',
              name: 'OpenRouter Text Model',
              capabilities: {'openrouter': true, 'image_generation': true},
              metadata: {'backend': 'direct'},
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Personalization'), findsOneWidget);
    },
  );
}

class _DirectPreferredBackendController extends PreferredBackendController {
  @override
  PreferredBackend build() => PreferredBackend.direct;
}

class _Models extends Models {
  _Models(this._models);

  final List<Model> _models;

  @override
  Future<List<Model>> build() async => _models;
}

class _NoProfiles extends DirectConnectionProfilesController {
  @override
  Future<List<DirectConnectionProfile>> build() async => const [];
}

class _FakeOptimizedStorageService extends Fake
    implements OptimizedStorageService {
  @override
  String? getThemeMode() => null;

  @override
  String? getThemePaletteId() => null;

  @override
  String? getLocaleCode() => null;

  @override
  SocketTransportAvailability? getLocalTransportOptionsSync() => null;
}
