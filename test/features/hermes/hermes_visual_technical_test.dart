import 'dart:convert';
import 'dart:io';

import 'package:conduit/features/hermes/feedback/hermez_feedback.dart';
import 'package:conduit/features/hermes/services/hermes_a2ui_layout_normalizer.dart';
import 'package:conduit/features/hermes/widgets/hermes_a2ui_surface.dart';
import 'package:conduit/features/hermes/widgets/hermes_visual_catalog.dart';
import 'package:conduit/features/hermes/widgets/hermez_chat_palette.dart';
import 'package:conduit/features/hermes/widgets/hermez_visual_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _catalogId =
    'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';

String _payload(List<Map<String, Object?>> components) => [
  jsonEncode({
    'version': 'v0.9',
    'createSurface': {'surfaceId': 'technical', 'catalogId': _catalogId},
  }),
  jsonEncode({
    'version': 'v0.9',
    'updateComponents': {'surfaceId': 'technical', 'components': components},
  }),
].join('\n');

class _Sound implements HermezSoundBackend {
  @override
  Future<void> start(Iterable<String> assets) async {}

  @override
  void play(String asset, {required double volume, required double speed}) {}
}

Future<void> _pump(
  WidgetTester tester,
  List<Map<String, Object?>> components, {
  double width = 360,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  bool isBusy = false,
  List<String>? interactions,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: hermezVisualTheme(ThemeData(brightness: brightness)),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 2400),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: HermesA2uiSurface(
              payload: _payload(components),
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

Future<void> _one(
  WidgetTester tester,
  Map<String, Object?> root, {
  double width = 360,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) => _pump(
  tester,
  [
    {'id': 'root', ...root},
  ],
  width: width,
  textScale: textScale,
  brightness: brightness,
);

void _clean(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  expect(find.textContaining('Visual unavailable'), findsNothing);
}

void main() {
  late HermezFeedback previous;
  setUp(() async {
    previous = HermezFeedback.instance;
    final feedback = HermezFeedback.forTesting(
      backend: _Sound(),
      haptic: (_) async {},
    );
    await feedback.startForTesting();
    HermezFeedback.instance = feedback;
  });
  tearDown(() => HermezFeedback.instance = previous);

  test('the technical components are registered', () {
    final names = createHermesVisualCatalog().items.map((i) => i.name).toSet();
    expect(
      names,
      containsAll(const [
        'CommandBlock',
        'TaskTile',
        'KeyValueGrid',
        'ComparisonCard',
      ]),
    );
  });

  group('CommandBlock', () {
    late List<String> clipboard;
    setUp(() {
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

    testWidgets('shell, SQL, JSON and multiline text render', (tester) async {
      for (final (language, content, heading) in [
        ('shell', 'docker compose restart nvr', 'SHELL COMMAND'),
        ('sql', 'SELECT id FROM orders WHERE total > 100;', 'SQL'),
        ('json', '{\n  "enabled": true\n}', 'JSON'),
        ('text', 'line one\nline two\nline three', 'TEXT'),
      ]) {
        await _one(tester, {
          'component': 'CommandBlock',
          'language': language,
          'content': content,
        });
        expect(find.text(heading), findsOneWidget, reason: language);
        expect(find.text(content), findsOneWidget, reason: language);
        _clean(tester);
      }
    });

    testWidgets('Copy puts the command on the clipboard and sends nothing to '
        'Hermes, even on a locked surface', (tester) async {
      final interactions = <String>[];
      await _pump(
        tester,
        [
          {
            'id': 'root',
            'component': 'CommandBlock',
            'label': 'Command',
            'language': 'shell',
            'content': 'docker compose restart nvr',
          },
        ],
        interactions: interactions,
        isBusy: true,
      );
      await tester.tap(find.text('COPY'));
      await tester.pump();
      expect(clipboard, ['docker compose restart nvr']);
      expect(interactions, isEmpty);
      expect(find.text('COPIED'), findsOneWidget);
    });

    testWidgets('copyable false hides Copy; the label names the content', (
      tester,
    ) async {
      await _one(tester, {
        'component': 'CommandBlock',
        'language': 'shell',
        'content': 'ls -la',
        'copyable': false,
      });
      expect(find.text('COPY'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('^Shell command. ls -la')),
        findsOneWidget,
      );
    });
  });

  group('TaskTile', () {
    testWidgets('every status, with assignee, due and priority', (
      tester,
    ) async {
      for (final (status, word) in [
        ('todo', 'TO DO'),
        ('in_progress', 'IN PROGRESS'),
        ('blocked', 'BLOCKED'),
        ('done', 'DONE'),
        ('unknown', 'UNKNOWN'),
      ]) {
        await _one(tester, {
          'component': 'TaskTile',
          'title': 'Trail certificates',
          'status': status,
          'assignee': 'Kai',
          'due': 'Nov 11',
          'priority': 'high',
        });
        expect(find.text(word), findsOneWidget, reason: status);
        expect(find.text('Kai · Due Nov 11 · HIGH'), findsOneWidget);
        _clean(tester);
      }
    });

    testWidgets('large text on 320px', (tester) async {
      await _one(
        tester,
        {
          'component': 'TaskTile',
          'title': 'Generate and email donor certificates for everyone',
          'status': 'in_progress',
          'assignee': 'Kai',
          'due': 'Nov 11',
          'priority': 'urgent',
          'countLabel': '12 / 40',
          'detail': 'Waiting on the final donor list from the finance team.',
        },
        width: 320,
        textScale: 2,
      );
      _clean(tester);
    });
  });

  group('KeyValueGrid', () {
    final grid = {
      'component': 'KeyValueGrid',
      'title': 'Server',
      'items': [
        {'label': 'Model', 'value': 'Qwen 27B'},
        {'label': 'Profile', 'value': 'Local'},
        {'label': 'Status', 'value': 'Running'},
        {'label': 'Uptime', 'value': '14h 22m'},
      ],
    };

    testWidgets('two columns at 412px, 100% text', (tester) async {
      await _one(tester, grid, width: 412);
      expect(find.byKey(const ValueKey('hermez-facts-columns')), findsOne);
      _clean(tester);
    });

    testWidgets('stacked at 320px, 200% text, without overflow', (
      tester,
    ) async {
      await _one(tester, grid, width: 320, textScale: 2);
      expect(find.byKey(const ValueKey('hermez-facts-stacked')), findsOne);
      _clean(tester);
    });
  });

  group('ComparisonCard', () {
    Map<String, Object?> card(int facts, {String title = 'Option A'}) => {
      'component': 'ComparisonCard',
      'title': title,
      'badge': 'Local',
      'facts': [
        for (var i = 0; i < facts; i++)
          {
            'label': 'Fact $i',
            'value': i == 0 ? r'$12 per month, billed annually' : 'Value $i',
            if (i == 1) 'state': 'ok',
            if (i == 2) 'state': 'warning',
            if (i == 3) 'state': 'error',
          },
      ],
    };

    testWidgets('1 and 8 facts, states, long title, 200% text', (tester) async {
      await _one(tester, card(1));
      expect(find.text('OPTION A'), findsOneWidget);
      _clean(tester);
      await _one(
        tester,
        card(8, title: 'A very long option name for a hosted inference plan'),
        width: 320,
        textScale: 2,
      );
      expect(find.text('Value 7'), findsOneWidget);
      _clean(tester);
    });

    testWidgets('two cards in a Row are stacked, never a table', (
      tester,
    ) async {
      final result = normalizeHermesA2uiPayload(
        _payload([
          {
            'id': 'root',
            'component': 'Row',
            'children': ['a', 'b'],
          },
          {'id': 'a', ...card(2)},
          {'id': 'b', ...card(2, title: 'Option B')},
        ]),
        catalog: createHermesVisualCatalog(),
      );
      expect(result.isReady, isTrue);
      expect(result.payload, contains('"component":"Column"'));
    });
  });

  test('Row[TaskTile, TaskTile] becomes a Column', () {
    final result = normalizeHermesA2uiPayload(
      _payload([
        {
          'id': 'root',
          'component': 'Row',
          'children': ['a', 'b'],
        },
        {
          'id': 'a',
          'component': 'TaskTile',
          'title': 'A',
          'status': 'todo',
          'weight': 1,
        },
        {
          'id': 'b',
          'component': 'TaskTile',
          'title': 'B',
          'status': 'done',
          'weight': 1,
        },
      ]),
      catalog: createHermesVisualCatalog(),
    );
    expect(result.payload, contains('"component":"Column"'));
  });

  testWidgets('every technical component renders in Orange and Red, light '
      'and dark', (tester) async {
    final previousSignal = HermezChatPalette.signal;
    addTearDown(() => HermezChatPalette.signal = previousSignal);
    for (final signal in HermezSignal.values) {
      HermezChatPalette.signal = signal;
      for (final brightness in Brightness.values) {
        for (final root in <Map<String, Object?>>[
          {'component': 'CommandBlock', 'content': 'ls'},
          {'component': 'TaskTile', 'title': 'T', 'status': 'blocked'},
          {
            'component': 'KeyValueGrid',
            'items': [
              {'label': 'A', 'value': 'B'},
            ],
          },
          {
            'component': 'ComparisonCard',
            'title': 'A',
            'facts': [
              {'label': 'Cost', 'value': r'$1', 'state': 'ok'},
            ],
          },
        ]) {
          await _one(tester, root, brightness: brightness);
          _clean(tester);
        }
      }
    }
  });

  test('no component source hard-codes a signal color or does I/O', () {
    for (final path in [
      'lib/features/hermes/widgets/hermes_visual_technical.dart',
      'lib/features/hermes/widgets/hermes_visual_personal.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final banned in [
        'FF5A26',
        'FF6A36',
        'E3192B',
        'dart:io',
        'package:http',
        'package:dio',
        'url_launcher',
        'path_provider',
        'dispatchEvent',
        'Process.run',
      ]) {
        expect(source.contains(banned), isFalse, reason: '$path: $banned');
      }
    }
  });
}
