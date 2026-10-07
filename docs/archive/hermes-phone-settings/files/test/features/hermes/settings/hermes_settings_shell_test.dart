import 'package:conduit/core/persistence/persistence_keys.dart';
import 'package:conduit/core/persistence/preferences_store.dart';
import 'package:conduit/features/desktop/hermez_desktop.dart';
import 'package:conduit/features/hermes/admin/hermes_admin_models.dart';
import 'package:conduit/features/hermes/admin/hermes_admin_providers.dart';
import 'package:conduit/features/hermes/settings/hermes_settings_categories.dart';
import 'package:conduit/features/hermes/settings/hermes_settings_shell.dart';
import 'package:conduit/features/hermes/settings/widgets/hermes_bot_scope_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

HermesAdminProfile _bot(String name, {String display = ''}) =>
    HermesAdminProfile(
      name: name,
      description: '',
      displayName: display,
      model: '',
      provider: '',
      isDefault: name == 'default',
      skillCount: 0,
      hasAvatar: false,
      uiMeta: const {},
      uiMetaRevisions: const {},
    );

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  List<HermesAdminProfile> bots = const [],
}) async {
  tester.view
    ..physicalSize = const Size(1280, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      // No live Hermes: every page shows its "unavailable" state.
      hermesAdminClientProvider.overrideWithValue(null),
      hermesAdminProfilesProvider.overrideWith((ref) async => bots),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: child),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PreferencesStore.debugOverride(await SharedPreferences.getInstance());
  });
  tearDown(() {
    PreferencesStore.debugReset();
    HermezDesktop.debugResetOverride();
  });

  testWidgets('desktop shows categories beside the selected detail', (
    tester,
  ) async {
    HermezDesktop.debugIsActiveOverride = true;
    await _pump(
      tester,
      const HermesSettingsShell(initial: HermesSettingsCategory.tools),
    );

    for (final category in HermesSettingsCategory.values) {
      expect(
        find.byKey(ValueKey('hermes-settings-category-${category.slug}')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('hermes-settings-detail-tools')),
      findsOneWidget,
    );
    final list = tester.getRect(
      find.byKey(const ValueKey('hermes-settings-category-tools')),
    );
    final detail = tester.getRect(
      find.byKey(const ValueKey('hermes-settings-detail-tools')),
    );
    expect(detail.left, greaterThan(list.right));

    await tester.tap(
      find.byKey(const ValueKey('hermes-settings-category-models')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('hermes-settings-detail-models')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('hermes-settings-detail-tools')),
      findsNothing,
    );
  });

  testWidgets('the bot chip changes the scope and remembers it', (
    tester,
  ) async {
    HermezDesktop.debugIsActiveOverride = true;
    final container = await _pump(
      tester,
      const HermesSettingsShell(initial: HermesSettingsCategory.models),
      bots: [_bot('default'), _bot('ops', display: 'Ops bot')],
    );

    await tester.tap(find.byKey(const ValueKey('hermes-bot-scope-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ops bot').last);
    await tester.pumpAndSettle();

    expect(container.read(hermesResolvedSettingsScopeProvider), 'ops');
    expect(
      PreferencesStore.getString(PreferenceKeys.hermesSettingsScope),
      'ops',
    );
    // A fresh read (a relaunch) comes back to the same bot.
    final relaunched = ProviderContainer(
      overrides: [
        hermesAdminProfilesProvider.overrideWith(
          (ref) async => [_bot('default'), _bot('ops')],
        ),
      ],
    );
    addTearDown(relaunched.dispose);
    expect(relaunched.read(hermesSettingsScopeProvider), 'ops');
  });

  testWidgets('a remembered bot that was deleted falls back to default', (
    tester,
  ) async {
    await PreferencesStore.put(PreferenceKeys.hermesSettingsScope, 'gone');
    final container = await _pump(
      tester,
      const HermesSettingsCategoryPage(category: HermesSettingsCategory.tools),
      bots: [_bot('default'), _bot('ops')],
    );
    expect(container.read(hermesSettingsScopeProvider), 'gone');
    expect(container.read(hermesResolvedSettingsScopeProvider), 'default');
  });

  testWidgets('"Server (root)" is offered only on Advanced config', (
    tester,
  ) async {
    HermezDesktop.debugIsActiveOverride = true;
    await _pump(
      tester,
      const HermesSettingsShell(initial: HermesSettingsCategory.tools),
      bots: [_bot('default')],
    );
    await tester.tap(find.byKey(const ValueKey('hermes-bot-scope-chip')));
    await tester.pumpAndSettle();
    expect(find.text('Server (root)'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('hermes-settings-category-advanced')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hermes-bot-scope-chip')));
    await tester.pumpAndSettle();
    expect(find.text('Server (root)'), findsOneWidget);
    await tester.tap(find.text('Server (root)'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<HermesBotScopeChip>(find.byType(HermesBotScopeChip))
          .root,
      isTrue,
    );
  });

  testWidgets('the phone pushes a category page with the scope row', (
    tester,
  ) async {
    HermezDesktop.debugIsActiveOverride = false;
    await _pump(
      tester,
      const HermesSettingsCategoryPage(category: HermesSettingsCategory.models),
      bots: [_bot('default')],
    );
    expect(find.text('Models & providers'), findsOneWidget);
    expect(find.byType(HermesBotScopeChip), findsOneWidget);
    expect(find.byType(HermesSettingsShell), findsNothing);
  });

  test('categories round-trip through their route slugs', () {
    for (final category in HermesSettingsCategory.values) {
      expect(HermesSettingsCategory.fromSlug(category.slug), category);
    }
    expect(HermesSettingsCategory.fromSlug('bots'), isNull);
    expect(HermesSettingsCategory.connection.isBotScoped, isFalse);
    expect(HermesSettingsCategory.advanced.allowsRoot, isTrue);
    expect(HermesSettingsCategory.models.allowsRoot, isFalse);
  });
}
