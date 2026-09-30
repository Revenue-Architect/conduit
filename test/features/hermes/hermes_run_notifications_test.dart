import 'package:conduit/core/services/settings_service.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_live_activity.dart';
import 'package:conduit/features/hermes/services/hermes_run_notifications.dart';
import 'package:conduit/features/notifications/models/app_notification.dart';
import 'package:conduit/features/notifications/providers/notification_socket_listener.dart'
    show notificationRouterProvider;
import 'package:conduit/features/notifications/services/active_view_tracker.dart';
import 'package:conduit/features/notifications/services/local_notification_service.dart';
import 'package:conduit/features/notifications/services/notification_router.dart';
import 'package:conduit/features/notifications/services/notification_sound_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockLocalNotifications extends Mock
    implements LocalNotificationService {}

class _MockSound extends Mock implements NotificationSoundService {}

class _Sessions extends HermesSessionsController {
  @override
  Future<List<HermesSessionSummary>> build() async => const [
    HermesSessionSummary(
      id: 'session-1',
      title: 'Explain the gap',
      profile: 'kai',
    ),
  ];
}

const _allOn = AppSettings(
  notificationsEnabled: true,
  notificationSound: false,
  notificationSoundAlways: false,
  notificationInAppBanner: true,
  notificationSystem: true,
  notificationChatEnabled: true,
  notificationChannelEnabled: true,
);

HermesLiveActivityEvent _event(HermesLiveActivityKind kind, {int at = 0}) =>
    HermesLiveActivityEvent(
      sessionId: 'session-1',
      kind: kind,
      title: kind.name,
      timestamp: DateTime.utc(2026, 9, 30, 12, 0, at),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      const AppNotification(
        kind: NotificationKind.hermesRun,
        title: '',
        body: '',
        sourceId: '',
        dedupKey: '',
      ),
    );
  });

  late _MockLocalNotifications local;
  late List<AppNotification> system;
  late List<AppNotification> banners;

  setUp(() {
    local = _MockLocalNotifications();
    system = [];
    banners = [];
    when(() => local.show(any(), playSound: any(named: 'playSound')))
        .thenAnswer((invocation) async {
          system.add(invocation.positionalArguments.single as AppNotification);
        });
  });

  /// A notifier wired to a real router with fake surfaces.
  Future<HermesRunNotifier> notifier({
    bool foreground = false,
    ActiveView view = const ActiveView(),
  }) async {
    final sound = _MockSound();
    when(() => sound.play()).thenAnswer((_) async {});
    final container = ProviderContainer(
      overrides: [
        hermesApiServiceProvider.overrideWithValue(null),
        hermesSessionsProvider.overrideWith(_Sessions.new),
        notificationRouterProvider.overrideWithValue(
          NotificationRouter(
            readSettings: () => _allOn,
            readActiveView: () => view,
            isAppForeground: () => foreground,
            localNotifications: local,
            sound: sound,
            showInAppBanner: banners.add,
            onChannelUnread: (_) {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(hermesSessionsProvider.future);
    return container.read(hermesRunNotifierProvider);
  }

  test('a run that starts and completes notifies once', () async {
    final hermes = await notifier();
    hermes
      ..debugActivity(_event(HermesLiveActivityKind.toolStarted))
      ..debugActivity(_event(HermesLiveActivityKind.completed, at: 5));
    await pumpEventQueue();
    expect(system.map((n) => n.title), ['kai finished']);
    expect(system.single.kind, NotificationKind.hermesRun);
    expect(system.single.sourceId, 'session-1');
  });

  test('a run that starts and fails notifies', () async {
    final hermes = await notifier();
    hermes
      ..debugActivity(_event(HermesLiveActivityKind.toolStarted))
      ..debugActivity(_event(HermesLiveActivityKind.failed, at: 5));
    await pumpEventQueue();
    expect(system.map((n) => n.title), ['kai hit a problem']);
  });

  test('waiting for an approval notifies without a run start', () async {
    final hermes = await notifier();
    hermes.debugActivity(_event(HermesLiveActivityKind.waitingForInput));
    await pumpEventQueue();
    expect(system.map((n) => n.title), ['kai needs you']);
    expect(system.single.kind, NotificationKind.hermesAttention);
  });

  test('a replayed completion with no start is suppressed', () async {
    final hermes = await notifier();
    hermes.debugActivity(_event(HermesLiveActivityKind.completed));
    await pumpEventQueue();
    expect(system, isEmpty);
  });

  test('a duplicate completion is suppressed', () async {
    final hermes = await notifier();
    hermes
      ..debugActivity(_event(HermesLiveActivityKind.toolStarted))
      ..debugActivity(_event(HermesLiveActivityKind.completed, at: 5))
      ..debugActivity(_event(HermesLiveActivityKind.completed, at: 6));
    await pumpEventQueue();
    expect(system, hasLength(1));
  });

  test('in the background, the conversation last open still gets a system '
      'notification', () async {
    final hermes = await notifier(
      view: const ActiveView(hermesSessionId: 'session-1'),
    );
    hermes
      ..debugActivity(_event(HermesLiveActivityKind.toolStarted))
      ..debugActivity(_event(HermesLiveActivityKind.completed, at: 5));
    await pumpEventQueue();
    expect(system, hasLength(1));
    expect(banners, isEmpty);
  });

  test(
    'in the foreground, the conversation being viewed raises nothing',
    () async {
      final hermes = await notifier(
        foreground: true,
        view: const ActiveView(hermesSessionId: 'session-1'),
      );
      hermes
        ..debugActivity(_event(HermesLiveActivityKind.toolStarted))
        ..debugActivity(_event(HermesLiveActivityKind.completed, at: 5));
      await pumpEventQueue();
      expect(system, isEmpty);
      expect(banners, isEmpty);
    },
  );

  test('in the foreground, another conversation shows in-app only', () async {
    final hermes = await notifier(foreground: true);
    hermes
      ..debugActivity(_event(HermesLiveActivityKind.toolStarted))
      ..debugActivity(_event(HermesLiveActivityKind.completed, at: 5));
    await pumpEventQueue();
    expect(system, isEmpty);
    expect(banners.map((n) => n.title), ['kai finished']);
  });
}
