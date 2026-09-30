import 'dart:convert';

import 'package:conduit/features/hermes/services/hermes_a2ui_layout_normalizer.dart';
import 'package:conduit/features/hermes/widgets/hermes_a2ui_surface.dart';
import 'package:conduit/features/hermes/widgets/hermes_visual_catalog.dart';
import 'package:conduit/features/hermes/widgets/hermez_chat_palette.dart';
import 'package:conduit/features/hermes/widgets/hermez_visual_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _catalogId =
    'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';

String _payload(List<Map<String, Object?>> components) => [
  jsonEncode({
    'version': 'v0.9',
    'createSurface': {'surfaceId': 'personal', 'catalogId': _catalogId},
  }),
  jsonEncode({
    'version': 'v0.9',
    'updateComponents': {'surfaceId': 'personal', 'components': components},
  }),
].join('\n');

Future<void> _pump(
  WidgetTester tester,
  Map<String, Object?> root, {
  double width = 360,
  double textScale = 1,
  Brightness brightness = Brightness.light,
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
              payload: _payload([
                {'id': 'root', ...root},
              ]),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void _noOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  expect(find.text('Visual unavailable'), findsNothing);
}

Map<String, Object?> _progress(Map<String, Object?> extra) => {
  'component': 'ProgressMeter',
  'label': 'Migration',
  'current': 412,
  'total': 600,
  'unit': 'products',
  ...extra,
};

void main() {
  test('the personal components are registered', () {
    final names = createHermesVisualCatalog().items.map((i) => i.name).toSet();
    expect(
      names,
      containsAll(const [
        'ProgressMeter',
        'ActivityFeed',
        'ScheduleTile',
        'MessagePreview',
      ]),
    );
  });

  group('ProgressMeter', () {
    testWidgets('shows real counts, the derived percent and a bar', (
      tester,
    ) async {
      await _pump(tester, _progress({}));
      expect(find.text('MIGRATION / 69%'), findsOneWidget);
      expect(find.text('412 / 600 PRODUCTS'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('412 of 600 products. 68.7 percent')),
        findsOneWidget,
      );
      _noOverflow(tester);
    });

    testWidgets('0 of total and complete', (tester) async {
      await _pump(tester, _progress({'current': 0}));
      expect(find.text('MIGRATION / 0%'), findsOneWidget);
      await _pump(tester, _progress({'current': 600}));
      expect(find.text('MIGRATION / 100%'), findsOneWidget);
      _noOverflow(tester);
    });

    testWidgets('over the total is shown truthfully, not clamped', (
      tester,
    ) async {
      await _pump(tester, _progress({'current': 630}));
      expect(find.text('630 / 600 PRODUCTS'), findsOneWidget);
      expect(find.text('MIGRATION / 105%'), findsOneWidget);
      expect(find.text('OVER'), findsOneWidget);
      _noOverflow(tester);
    });

    testWidgets('invalid totals and counts are rejected', (tester) async {
      for (final bad in [
        {'total': 0},
        {'total': -5},
        {'current': -1},
        {'current': 'almost done'},
        {'total': 'lots'},
      ]) {
        await _pump(tester, _progress(bad));
        // Rejected by the schema preflight or the widget: never displayed.
        expect(find.textContaining('MIGRATION'), findsNothing, reason: '$bad');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('warning state uses the warning color and a word', (
      tester,
    ) async {
      await _pump(tester, _progress({'state': 'warning'}));
      expect(find.text('WARNING'), findsOneWidget);
      final box = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('hermez-progress-meter')),
      );
      final warning = Theme.of(tester.element(find.text('WARNING')))
          .extension<HermezStatusColors>()!
          .warning;
      expect(
        ((box.decoration as BoxDecoration).border! as Border).top.color,
        warning,
      );
    });

    testWidgets('segmented, 200% text at 320px', (tester) async {
      await _pump(
        tester,
        _progress({'segmented': true, 'detail': 'Validating variants'}),
        width: 320,
        textScale: 2,
      );
      expect(find.byKey(const ValueKey('hermez-progress-segments')), findsOne);
      _noOverflow(tester);
    });
  });

  group('ActivityFeed', () {
    List<Map<String, Object?>> events(int count) => [
      for (var i = 0; i < count; i++)
        {
          'title': 'Event $i',
          if (i.isEven) 'time': '11:${(i + 10).toString().padLeft(2, '0')}',
          if (i % 3 == 0) 'detail': 'Detail for event $i ' * 3,
          if (i == 1) 'state': 'warning',
          if (i == 2) 'state': 'error',
          if (i == 3) 'state': 'ok',
        },
    ];

    testWidgets('one event, and 20 with missing times and states', (
      tester,
    ) async {
      await _pump(tester, {
        'component': 'ActivityFeed',
        'items': [
          {'title': 'Browser opened Shopify', 'time': '11:42'},
        ],
      });
      expect(find.text('ACTIVITY'), findsOneWidget);
      expect(find.text('11:42'), findsOneWidget);
      _noOverflow(tester);

      await _pump(tester, {'component': 'ActivityFeed', 'items': events(20)});
      expect(find.text('Event 19'), findsOneWidget);
      // No time is invented for events that had none.
      expect(find.textContaining('11:'), findsNWidgets(10));
      _noOverflow(tester);
    });

    testWidgets('more than 20 or none is rejected', (tester) async {
      await _pump(tester, {'component': 'ActivityFeed', 'items': events(21)});
      expect(find.text('ACTIVITY'), findsNothing);
      await _pump(tester, {'component': 'ActivityFeed', 'items': const []});
      expect(find.text('ACTIVITY'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact, 200% text at 320px', (tester) async {
      await _pump(
        tester,
        {'component': 'ActivityFeed', 'compact': true, 'items': events(6)},
        width: 320,
        textScale: 2,
      );
      _noOverflow(tester);
    });
  });

  group('ScheduleTile', () {
    testWidgets('start only, and start, end, location, owner, state', (
      tester,
    ) async {
      await _pump(tester, {
        'component': 'ScheduleTile',
        'title': 'Dentist',
        'start': '14:30',
      });
      expect(find.text('Dentist'), findsOneWidget);
      expect(find.text('14:30'), findsOneWidget);
      _noOverflow(tester);

      await _pump(tester, {
        'component': 'ScheduleTile',
        'title': 'Morning Brief',
        'start': '09:00',
        'end': '09:15',
        'location': 'Downtown',
        'owner': 'Kai',
        'date': 'Daily',
        'state': 'warning',
      });
      expect(find.text('Daily · Downtown · Kai'), findsOneWidget);
      expect(find.text('WARNING'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp('Morning Brief, starts 09:00, ends 09:15'),
        ),
        findsOneWidget,
      );
      _noOverflow(tester);
    });

    testWidgets('a long name at 200% text on 320px', (tester) async {
      await _pump(
        tester,
        {
          'component': 'ScheduleTile',
          'title': 'Quarterly planning review with the whole leadership team',
          'start': '10:00 AM',
          'end': '11:30 AM',
          'location': 'Conference room 4, second floor',
        },
        width: 320,
        textScale: 2,
      );
      _noOverflow(tester);
    });
  });

  group('MessagePreview', () {
    Map<String, Object?> message(Map<String, Object?> extra) => {
      'component': 'MessagePreview',
      'sender': 'Georgia Sigurdson',
      'title': 'Trail Together follow-up',
      'preview': 'Just have a few follow-up questions about the rollout.',
      'timestamp': '10:42 AM',
      ...extra,
    };

    testWidgets('email, Teams and AgentMail channels', (tester) async {
      for (final (channel, label) in [
        ('email', 'EMAIL'),
        ('teams', 'TEAMS'),
        ('agentmail', 'AGENTMAIL'),
      ]) {
        await _pump(tester, message({'channel': channel}));
        expect(find.text(label), findsOneWidget, reason: channel);
        _noOverflow(tester);
      }
    });

    testWidgets('unread and important are words, not only color', (
      tester,
    ) async {
      await _pump(
        tester,
        message({
          'channel': 'email',
          'unread': true,
          'importance': 'important',
        }),
      );
      expect(find.text('● UNREAD'), findsOneWidget);
      expect(find.text('! IMPORTANT'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp('^Unread email from Georgia Sigurdson, Trail Together'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('no subject, long preview truncates, large text', (
      tester,
    ) async {
      final long = 'A preview that keeps going. ' * 8;
      await _pump(
        tester,
        message({'title': null, 'preview': long.substring(0, 220)})
          ..remove('title'),
        width: 320,
        textScale: 2,
      );
      final preview = tester.widget<Text>(
        find.textContaining('A preview that keeps going.'),
      );
      expect(preview.maxLines, 3);
      _noOverflow(tester);
    });
  });

  testWidgets('every personal component renders in Orange and Red, light '
      'and dark', (tester) async {
    final previous = HermezChatPalette.signal;
    addTearDown(() => HermezChatPalette.signal = previous);
    for (final signal in HermezSignal.values) {
      HermezChatPalette.signal = signal;
      for (final brightness in Brightness.values) {
        for (final root in <Map<String, Object?>>[
          _progress({}),
          {
            'component': 'ActivityFeed',
            'items': [
              {'title': 'Validated', 'state': 'ok'},
            ],
          },
          {'component': 'ScheduleTile', 'title': 'Dentist', 'start': '14:30'},
          {
            'component': 'MessagePreview',
            'sender': 'Kai',
            'preview': 'Done.',
            'unread': true,
          },
        ]) {
          await _pump(tester, root, brightness: brightness);
          _noOverflow(tester);
        }
      }
    }
  });

  group('normalizer', () {
    final catalog = createHermesVisualCatalog();

    Map<String, dynamic> rowAfter(List<Map<String, Object?>> children) {
      final components = <Map<String, Object?>>[
        {
          'id': 'root',
          'component': 'Row',
          'children': [for (final c in children) c['id']],
        },
        ...children,
      ];
      final result = normalizeHermesA2uiPayload(
        _payload(components),
        catalog: catalog,
      );
      expect(result.isReady, isTrue);
      final update = jsonDecode(
        result.payload.trim().split('\n').last,
      ) as Map<String, dynamic>;
      return ((update['updateComponents'] as Map)['components'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((c) => c['id'] == 'root');
    }

    test('rich personal objects in a Row become a Column, even weighted', () {
      for (final pair in <List<Map<String, Object?>>>[
        [
          {'id': 'a', ..._progress({})},
          {'id': 'b', 'component': 'Text', 'text': 'x'},
        ],
        [
          {
            'id': 'a',
            'component': 'ScheduleTile',
            'title': 'A',
            'start': '9',
            'weight': 1,
          },
          {
            'id': 'b',
            'component': 'ScheduleTile',
            'title': 'B',
            'start': '10',
            'weight': 1,
          },
        ],
        [
          {
            'id': 'a',
            'component': 'MessagePreview',
            'sender': 'A',
            'preview': 'x',
          },
          {
            'id': 'b',
            'component': 'MessagePreview',
            'sender': 'B',
            'preview': 'y',
          },
        ],
      ]) {
        expect(rowAfter(pair)['component'], 'Column');
      }
    });

    test('MetricTile pairs stay a weighted Row', () {
      final root = rowAfter([
        {'id': 'a', 'component': 'MetricTile', 'label': 'CPU', 'value': 12},
        {'id': 'b', 'component': 'MetricTile', 'label': 'RAM', 'value': 40},
      ]);
      expect(root['component'], 'Row');
    });
  });
}
