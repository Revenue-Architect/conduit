import 'package:conduit/core/models/model.dart';
import 'package:conduit/core/models/socket_transport_availability.dart';
import 'package:conduit/core/providers/app_providers.dart';
import 'package:conduit/core/providers/backend_mode_providers.dart';
import 'package:conduit/core/services/optimized_storage_service.dart';
import 'package:conduit/core/services/settings_service.dart';
import 'package:conduit/features/profile/views/app_customization_page.dart';
import 'package:conduit/features/profile/views/personalization_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the default model is set from Chat, not Personalization', (
    tester,
  ) async {
    final overrides = [
      openWebUiAccountAvailableProvider.overrideWithValue(false),
      preferredBackendProvider.overrideWith(_DirectBackend.new),
      appSettingsProvider.overrideWithValue(const AppSettings()),
      apiServiceProvider.overrideWithValue(null),
      modelsProvider.overrideWith(_DirectModels.new),
      optimizedStorageServiceProvider.overrideWithValue(
        _FakeOptimizedStorageService(),
      ),
      socketServiceProvider.overrideWithValue(null),
    ];
    Widget app(Widget home) => ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        localizationsDelegates: conduitLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

    await tester.pumpWidget(
      app(const AppCustomizationPage(section: AppCustomizationSection.chat)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Default model'), findsOneWidget);
    await tester.tap(find.text('Server provided'));
    await tester.pumpAndSettle();
    expect(find.text('Direct Alpha'), findsOneWidget);
    expect(find.text('Direct Beta'), findsOneWidget);

    await tester.pumpWidget(app(const PersonalizationPage()));
    await tester.pumpAndSettle();

    expect(find.text('Default model'), findsNothing);
    expect(find.text('Server provided'), findsNothing);
  });

  testWidgets('OpenRouter Personalization exposes the image generation model', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openWebUiAccountAvailableProvider.overrideWithValue(false),
          appSettingsProvider.overrideWithValue(
            const AppSettings(
              openRouterImageGenerationModel: 'openai/gpt-5-image-mini',
            ),
          ),
          apiServiceProvider.overrideWithValue(null),
          modelsProvider.overrideWith(_OpenRouterModels.new),
        ],
        child: const MaterialApp(
          localizationsDelegates: conduitLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PersonalizationPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Default image generation model'), findsWidgets);
    expect(find.text('openai/gpt-5-image-mini'), findsOneWidget);
  });
}

class _DirectModels extends Models {
  @override
  Future<List<Model>> build() async => const [
    Model(
      id: 'direct:alpha',
      name: 'Direct Alpha',
      metadata: {'backend': 'direct'},
    ),
    Model(
      id: 'direct:beta',
      name: 'Direct Beta',
      metadata: {'backend': 'direct'},
    ),
  ];
}

class _OpenRouterModels extends Models {
  @override
  Future<List<Model>> build() async => const [
    Model(
      id: 'direct:openrouter:text-model',
      name: 'OpenRouter Text Model',
      capabilities: {'openrouter': true, 'image_generation': true},
      metadata: {'backend': 'direct'},
    ),
  ];
}

class _DirectBackend extends PreferredBackendController {
  @override
  PreferredBackend build() => PreferredBackend.direct;
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
