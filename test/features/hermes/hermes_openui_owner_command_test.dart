import 'package:conduit/features/hermes/services/hermes_inline_ui_capability.dart';
import 'package:conduit/features/hermes/widgets/hermes_openui_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = 'obj_6d56eea654909589a3e4db5f';

void main() {
  group('hermesOpenuiOwnerCommand', () {
    test('exact initiative commands pass through unchanged', () {
      for (final message in [
        '/initiative handled $_id --version 3',
        '/initiative snooze $_id --version 3 +1d',
        '/initiative dismiss $_id --version 3 reason:not_relevant',
        '/initiative weights apply 0123456789ab',
        '/initiative weights skip 0123456789ab',
      ]) {
        expect(hermesOpenuiOwnerCommand(message, null), message);
      }
    });

    test('a revision note becomes one shell-quoted argument', () {
      expect(
        hermesOpenuiOwnerCommand('/initiative rewrite $_id --version 2', {
          'note': " Shorter, and don't\nmention price ",
        }),
        "/initiative rewrite $_id --version 2 "
        "'Shorter, and don'\"'\"'t\nmention price'",
      );
    });

    test('an empty revision keeps the normal interaction path', () {
      expect(
        hermesOpenuiOwnerCommand('/initiative rewrite $_id --version 2', {
          'note': '  ',
        }),
        isNull,
      );
    });

    test('anything else keeps the normal interaction path', () {
      for (final message in [
        'Approve the draft for objective x (version 1).',
        '/initiative approve $_id --version 1',
        '/initiative handled $_id --version 1; rm -rf /',
        '/initiative pause',
        '/initiative weights apply ../../etc',
        '/new',
      ]) {
        expect(hermesOpenuiOwnerCommand(message, null), isNull, reason: message);
      }
    });
  });

  test('slash commands are sent without the inline UI suffix', () {
    const command = '/initiative list';
    expect(hermesInlineUiTurnText(command), command);
    expect(hermesInlineUiTurnText('hello'), isNot('hello'));
  });

  testWidgets('a card button sends its exact command, not an A2UI envelope', (
    tester,
  ) async {
    final sent = <String>[];
    const code =
        'root = Stack(['
        'Row([Button("I handled it", "/initiative handled $_id --version 4", "secondary")]),'
        'Form("revise_x", [TextArea("note", "What should change?", "", ""),'
        'Button("Send revision", "/initiative rewrite $_id --version 4", "primary")])])';
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: HermesOpenuiSurface(
            payload: code,
            surfaceId: 'owner-command',
            onInteraction: sent.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('I handled it'));
    await tester.pumpAndSettle();
    expect(sent, ['/initiative handled $_id --version 4']);

    await tester.enterText(find.byType(TextField), 'Make it shorter');
    await tester.tap(find.text('Send revision'));
    await tester.pumpAndSettle();
    expect(sent.last, "/initiative rewrite $_id --version 4 'Make it shorter'");
  });
}
