import 'dart:convert';

import 'package:conduit/features/hermes/widgets/hermes_a2ui_surface.dart';
import 'package:conduit/features/hermes/widgets/hermez_chat_palette.dart';
import 'package:conduit/features/hermes/widgets/hermez_visual_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _catalogId =
    'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';

String _payload(List<Map<String, Object?>> components) => [
  jsonEncode({
    'version': 'v0.9',
    'createSurface': {'surfaceId': 'visual', 'catalogId': _catalogId},
  }),
  jsonEncode({
    'version': 'v0.9',
    'updateComponents': {'surfaceId': 'visual', 'components': components},
  }),
].join('\n');

Future<void> _pump(
  WidgetTester tester,
  String payload, {
  Brightness brightness = Brightness.light,
  double width = 360,
  double textScale = 1,
  bool isBusy = false,
  List<String>? interactions,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final base = ThemeData(brightness: brightness);
  await tester.pumpWidget(
    MaterialApp(
      theme: hermezVisualTheme(base),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1200),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: HermesA2uiSurface(
              payload: payload,
              onInteraction: interactions?.add,
              isBusy: isBusy,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Map<String, Object?> _callout(String tone) => {
  'id': 'root',
  'component': 'ActionCallout',
  'eyebrow': 'NEEDS YOU',
  'title': 'Confirm API access',
  'tone': tone,
};

Border _calloutBorder(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.byKey(const ValueKey('hermez-action-callout')),
  );
  return (box.decoration as BoxDecoration).border! as Border;
}

List<Map<String, Object?>> _button(String? variant, {String label = 'Go'}) => [
  {
    'id': 'root',
    'component': 'Button',
    'child': 'label',
    'action': {
      'event': {'name': 'go'},
    },
    'variant': ?variant,
  },
  {'id': 'label', 'component': 'Text', 'text': label},
];

Material _buttonMaterial(WidgetTester tester) => tester.widget<Material>(
  find
      .descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
        matching: find.byType(Material),
      )
      .first,
);

void main() {
  final signals = {'orange': HermezSignal.orange, 'red': HermezSignal.red};
  final previous = HermezChatPalette.signal;
  tearDown(() => HermezChatPalette.signal = previous);

  for (final MapEntry(key: name, value: signal) in signals.entries) {
    for (final brightness in Brightness.values) {
      group('Hermez $name, ${brightness.name}', () {
        setUp(() => HermezChatPalette.signal = signal);

        testWidgets('ActionCallout state is the whole outline, no edge strip', (
          tester,
        ) async {
          final palette = HermezChatPalette.forBrightness(brightness);
          await _pump(
            tester,
            _payload([_callout('attention')]),
            brightness: brightness,
          );
          final border = _calloutBorder(tester);
          expect(border.isUniform, isTrue);
          expect(border.left.color, palette.accent);
          expect(border.right.color, palette.accent);
          expect(border.top.width, greaterThan(1));
          // The old 4px signal strip is gone.
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.constraints?.maxWidth == 4 &&
                  widget.constraints?.minWidth == 4,
            ),
            findsNothing,
          );
          expect(find.byType(IntrinsicHeight), findsNothing);
          expect(tester.takeException(), isNull);
        });

        testWidgets('error uses danger and neutral the quiet border', (
          tester,
        ) async {
          final palette = HermezChatPalette.forBrightness(brightness);
          await _pump(
            tester,
            _payload([_callout('error')]),
            brightness: brightness,
          );
          final danger = Theme.of(
            tester.element(find.text('Confirm API access')),
          ).extension<HermezStatusColors>()!.danger;
          expect(_calloutBorder(tester).left.color, danger);
          expect(danger, isNot(palette.accent));

          await _pump(
            tester,
            _payload([_callout('neutral')]),
            brightness: brightness,
          );
          final neutral = _calloutBorder(tester);
          expect(neutral.left.color, palette.border);
          expect(neutral.left.width, 1);
        });

        testWidgets('Button variants: primary fill, default outline, '
            'borderless bare', (tester) async {
          final palette = HermezChatPalette.forBrightness(brightness);
          await _pump(
            tester,
            _payload(_button('primary')),
            brightness: brightness,
          );
          var material = _buttonMaterial(tester);
          expect(material.color, palette.accent);
          expect(material.elevation, 0);
          final label = tester.widget<Text>(find.text('Go'));
          final labelColor =
              label.style?.color ??
              DefaultTextStyle.of(tester.element(find.text('Go'))).style.color;
          expect(labelColor, palette.onAccent);
          if (signal == HermezSignal.red) {
            expect(palette.onAccent, const Color(0xFFFFFFFF));
          }

          await _pump(tester, _payload(_button(null)), brightness: brightness);
          material = _buttonMaterial(tester);
          expect(material.color, palette.surface);
          expect(
            (material.shape! as RoundedRectangleBorder).side.color,
            palette.border,
          );

          await _pump(
            tester,
            _payload(_button('borderless')),
            brightness: brightness,
          );
          material = _buttonMaterial(tester);
          expect(
            (material.shape! as RoundedRectangleBorder).side,
            BorderSide.none,
          );
          expect(
            tester.getSize(find.byType(TextButton)).height,
            greaterThanOrEqualTo(48),
          );
        });
      });
    }
  }

  testWidgets('a Button press dispatches exactly one interaction', (
    tester,
  ) async {
    final interactions = <String>[];
    await _pump(tester, _payload(_button(null)), interactions: interactions);
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(interactions, hasLength(1));
    expect(interactions.single, contains('go'));
  });

  testWidgets('a locked surface blocks the Button', (tester) async {
    final interactions = <String>[];
    await _pump(
      tester,
      _payload(_button('primary')),
      interactions: interactions,
      isBusy: true,
    );
    await tester.tap(find.text('Go'), warnIfMissed: false);
    await tester.pump();
    expect(interactions, isEmpty);
  });

  testWidgets('a long label wraps at 200% text on 320px', (tester) async {
    await _pump(
      tester,
      _payload(
        _button(
          'primary',
          label: 'Approve the refund and notify the customer by email',
        ),
      ),
      width: 320,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(ElevatedButton)).height,
      greaterThan(48),
    );
  });
}
