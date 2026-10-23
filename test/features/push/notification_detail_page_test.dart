import 'package:conduit/features/push/services/push_gateway_client.dart';
import 'package:conduit/features/push/views/notification_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a targetless notification exposes its saved text without a chat',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationDetailProvider((reference: 'notice-42', kind: null))
                .overrideWith(
                  (ref) async => const PushNotificationDetail(
                    title: 'Saved update',
                    body: 'The full content beyond the notification preview.',
                  ),
                ),
          ],
          child: const MaterialApp(
            home: NotificationDetailPage(reference: 'notice-42'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('The full content beyond the notification preview.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('failed detail loading retries the same notification', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationDetailProvider((reference: 'notice-42', kind: null))
              .overrideWith((ref) async {
                if (++attempts == 1) {
                  throw const PushGatewayException(
                    message: 'Could not reach Hermes.',
                  );
                }
                return const PushNotificationDetail(
                  title: 'Recovered update',
                  body: 'Actual saved content',
                );
              }),
        ],
        child: const MaterialApp(
          home: NotificationDetailPage(reference: 'notice-42'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not reach Hermes.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Actual saved content'), findsOneWidget);
    expect(attempts, 2);
  });
}
