import 'dart:async';

import 'package:conduit/core/services/socket_service.dart';
import 'package:conduit/core/providers/app_providers.dart';
import 'package:conduit/features/notifications/models/app_notification.dart';
import 'package:conduit/features/notifications/providers/notification_center.dart';
import 'package:conduit/features/notifications/providers/notification_socket_listener.dart';
import 'package:conduit/features/notifications/services/local_notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Local extends Mock implements LocalNotificationService {}

void main() {
  late _Local local;
  late StreamController<NotificationTap> taps;

  setUp(() {
    local = _Local();
    taps = StreamController<NotificationTap>.broadcast();
    addTearDown(taps.close);
    when(local.initialize).thenAnswer((_) async {});
    when(() => local.taps).thenAnswer((_) => taps.stream);
    when(local.launchTap).thenAnswer((_) async => null);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        localNotificationServiceProvider.overrideWithValue(local),
        socketServiceProvider.overrideWithValue(null),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('the center initializes the plugin and listens for taps', () async {
    final c = container();
    c.read(notificationCenterProvider);
    await pumpEventQueue();
    verify(local.initialize).called(1);
    expect(taps.hasListener, isTrue);

    await c.read(notificationCenterProvider.notifier).handleLaunchTap();
    verify(local.launchTap).called(1);
  });

  test('the Open WebUI socket listener no longer owns the plugin or taps', () {
    final c = container();
    c.read(notificationSocketListenerProvider);
    verifyNever(local.initialize);
    expect(taps.hasListener, isFalse);
  });

  test('disposing the center stops listening for taps', () async {
    final c = container();
    c.read(notificationCenterProvider);
    await pumpEventQueue();
    expect(taps.hasListener, isTrue);
    c.invalidate(notificationCenterProvider);
    await pumpEventQueue();
    // Rebuilt on the next read; the old subscription is gone.
    expect(taps.hasListener, isFalse);
  });

  test('the launch tap is opened once even if both startups ask', () async {
    final c = container();
    final center = c.read(notificationCenterProvider.notifier);
    await center.handleLaunchTap();
    await center.handleLaunchTap();
    verify(local.launchTap).called(1);
  });
}
