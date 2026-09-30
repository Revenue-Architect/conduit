import 'package:conduit/core/services/settings_service.dart';
import 'package:conduit/features/notifications/services/local_notification_service.dart';
import 'package:conduit/features/notifications/views/notification_settings_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

class _Local extends Mock implements LocalNotificationService {}

class _Settings extends AppSettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

Future<void> _pump(
  WidgetTester tester,
  AndroidNotificationHealth health,
) async {
  final local = _Local();
  when(local.androidHealth).thenAnswer((_) async => health);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localNotificationServiceProvider.overrideWithValue(local),
        appSettingsProvider.overrideWith(_Settings.new),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: NotificationHealthSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _fix = 'Open Android settings to turn notifications back on';

void main() {
  testWidgets('healthy: no second link to Android settings', (tester) async {
    await _pump(
      tester,
      const AndroidNotificationHealth(allowed: true, channelExists: true),
    );
    expect(find.text('ALLOWED'), findsOneWidget);
    expect(find.text(_fix), findsNothing);
  });

  testWidgets('permission refused: the fix is offered in place', (
    tester,
  ) async {
    await _pump(
      tester,
      const AndroidNotificationHealth(allowed: false, channelExists: true),
    );
    expect(find.text('NOT ALLOWED'), findsOneWidget);
    expect(find.text(_fix), findsOneWidget);
  });
}
