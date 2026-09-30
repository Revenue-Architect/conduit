import 'dart:io';

import 'package:conduit/features/hermes/feedback/hermez_feedback.dart';
import 'package:conduit/features/hermes/services/hermes_a2ui_layout_normalizer.dart';
import 'package:conduit/features/hermes/widgets/hermes_a2ui_surface.dart';
import 'package:conduit/features/hermes/widgets/hermes_visual_catalog.dart';
import 'package:conduit/features/hermes/widgets/hermez_visual_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sound implements HermezSoundBackend {
  @override
  Future<void> start(Iterable<String> assets) async {}

  @override
  void play(String asset, {required double volume, required double speed}) {}
}

Future<void> _pump(
  WidgetTester tester,
  String payload, {
  bool isBusy = false,
  List<String>? interactions,
  double width = 360,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: hermezVisualTheme(ThemeData()),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 3000),
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

/// Every fenced ```a2ui block in a Markdown file.
List<String> _blocks(String path) {
  final source = File(path).readAsStringSync().replaceAll('\r\n', '\n');
  return RegExp(r'```a2ui\n([\s\S]*?)\n```')
      .allMatches(source)
      .map((m) => m.group(1)!)
      .toList();
}

void main() {
  final fixture = File(
    'test/fixtures/hermes/a2ui/agent-run-summary.jsonl',
  ).readAsStringSync();
  late List<String> clipboard;

  setUp(() async {
    final feedback = HermezFeedback.forTesting(
      backend: _Sound(),
      haptic: (_) async {},
    );
    await feedback.startForTesting();
    HermezFeedback.instance = feedback;
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  testWidgets('an agent run surface renders; expand and copy are local; the '
      'Button sends exactly one turn', (tester) async {
    final interactions = <String>[];
    await _pump(tester, fixture, interactions: interactions);
    expect(tester.takeException(), isNull);
    expect(find.text('Kai'), findsOneWidget);
    expect(find.text('412 / 600 PRODUCTS'), findsOneWidget);
    expect(find.text('ACTIVITY'), findsOneWidget);

    await tester.tap(find.text('DETAILS / 1'));
    await tester.pumpAndSettle();
    expect(find.text('3 SKUs skipped'), findsOneWidget);
    await tester.tap(find.text('COPY'));
    await tester.pump();
    expect(clipboard, ['hermes kanban retry t_ded59ae7']);
    expect(interactions, isEmpty);

    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(interactions, hasLength(1));
    expect(interactions.single, contains('migration.retry'));
  });

  testWidgets('a locked surface blocks the Button but keeps expand and copy', (
    tester,
  ) async {
    final interactions = <String>[];
    await _pump(tester, fixture, interactions: interactions, isBusy: true);
    await tester.tap(find.text('DETAILS / 1'));
    await tester.pumpAndSettle();
    expect(find.text('3 SKUs skipped'), findsOneWidget);
    await tester.tap(find.text('COPY'));
    await tester.pump();
    expect(clipboard, hasLength(1));
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'), warnIfMissed: false);
    await tester.pump();
    expect(interactions, isEmpty);
  });

  testWidgets('every pattern in the authoring guide renders at 320px and '
      '200% text', (tester) async {
    final blocks = _blocks('docs/hermes-a2ui-mobile/references/patterns.md');
    expect(blocks.length, greaterThanOrEqualTo(24));
    final catalog = createHermesVisualCatalog();
    for (final (index, block) in blocks.indexed) {
      final normalized = normalizeHermesA2uiPayload(block, catalog: catalog);
      expect(normalized.isReady, isTrue, reason: 'pattern block $index');
      await _pump(tester, block, width: 320, textScale: 2);
      expect(tester.takeException(), isNull, reason: 'pattern block $index');
      expect(
        find.textContaining('Visual unavailable'),
        findsNothing,
        reason: 'pattern block $index',
      );
    }
  });
}
