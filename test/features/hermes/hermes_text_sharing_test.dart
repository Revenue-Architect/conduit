import 'package:conduit/features/hermes/views/hermes_text_sharing_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const channel = MethodChannel('app.cogwheel.conduit/text-sharing');
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'pairing does not enable sharing and keeps a readable permission explanation',
    (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return {
              'paired': call.method == 'enroll',
              'enabled': false,
              'lastSync': '',
              'sentToday': 0,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(const MaterialApp(home: HermesTextSharingPage()));
      await tester.pumpAndSettle();
      expect(find.text('Pair phone'), findsOneWidget);
      expect(calls, ['status']);
      await tester.enterText(find.byType(TextField), 'TESTCODE');
      await tester.tap(find.text('Pair phone'));
      await tester.pumpAndSettle();
      expect(calls, ['status', 'enroll']);
      expect(find.text('Not synced yet'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(find.text('Forget device'), findsOneWidget);
    },
  );
}
