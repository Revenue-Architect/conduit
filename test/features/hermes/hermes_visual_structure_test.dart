import 'dart:convert';
import 'dart:io';

import 'package:conduit/features/hermes/feedback/hermez_feedback.dart';
import 'package:conduit/features/hermes/widgets/hermes_a2ui_surface.dart';
import 'package:conduit/features/hermes/widgets/hermes_visual_catalog.dart';
import 'package:conduit/features/hermes/widgets/hermez_bot_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart' show Surface;

const _catalogId =
    'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';

String _payload(List<Map<String, Object?>> components) => [
  jsonEncode({
    'version': 'v0.9',
    'createSurface': {'surfaceId': 'structure', 'catalogId': _catalogId},
  }),
  jsonEncode({
    'version': 'v0.9',
    'updateComponents': {'surfaceId': 'structure', 'components': components},
  }),
].join('\n');

class _Sound implements HermezSoundBackend {
  final List<String> played = [];

  @override
  Future<void> start(Iterable<String> assets) async {}

  @override
  void play(String asset, {required double volume, required double speed}) =>
      played.add(asset.split('/').last);
}

Future<void> _pump(
  WidgetTester tester,
  String payload, {
  double width = 360,
  double textScale = 1,
  bool reduceMotion = false,
  bool isBusy = false,
  List<String>? interactions,
  Widget? below,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1400),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                HermesA2uiSurface(
                  payload: payload,
                  onInteraction: interactions?.add,
                  isBusy: isBusy,
                ),
                ?below,
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

const _below = Text('BELOW', key: ValueKey('below'));

void main() {
  late _Sound sound;
  late HermezFeedback previous;

  setUp(() async {
    sound = _Sound();
    previous = HermezFeedback.instance;
    final feedback = HermezFeedback.forTesting(
      backend: sound,
      haptic: (_) async {},
    );
    await feedback.startForTesting();
    HermezFeedback.instance = feedback;
  });
  tearDown(() => HermezFeedback.instance = previous);

  test('the structure components are registered in the Hermes catalog', () {
    final names = createHermesVisualCatalog().items.map((i) => i.name).toSet();
    expect(
      names,
      containsAll(const [
        'InfoRow',
        'StepRail',
        'ActionCallout',
        'ArtifactTile',
        'BotBadge',
        'ExpandableSection',
      ]),
    );
  });

  group('fixtures at 300px and 200% text', () {
    for (final scenario in const [
      (
        fixture: 'status-overview',
        expected: ['NVR', 'DETAILS / 4', 'Inspect storage'],
      ),
      (
        fixture: 'workstreams',
        expected: ['Evidence', 'Release', 'Confirm the rollback owner'],
      ),
      (fixture: 'project-timeline', expected: ['Discovery', 'Validation']),
      (
        fixture: 'action-needed',
        expected: ['Approve the refund for order 1042?', 'Approve', 'Hold'],
      ),
      (
        fixture: 'artifact-summary',
        expected: ['launch-brief.md', 'inventory-map.csv', 'Open'],
      ),
      (fixture: 'bot-workstreams', expected: ['Kai', 'Fast', 'Strong']),
      (fixture: 'expandable-details', expected: ['EVIDENCE / 3']),
      (
        fixture: 'mixed-executive-summary',
        expected: ['Q4 LAUNCH', 'UAT', 'RISKS / 2'],
      ),
    ]) {
      testWidgets(scenario.fixture, (tester) async {
        final payload = File(
          'test/fixtures/hermes/a2ui/${scenario.fixture}.jsonl',
        ).readAsStringSync();
        await _pump(tester, payload, width: 300, textScale: 2);
        expect(tester.takeException(), isNull);
        expect(find.byType(Surface), findsOneWidget);
        expect(find.textContaining('Visual unavailable'), findsNothing);
        for (final text in scenario.expected) {
          expect(find.text(text), findsWidgets, reason: text);
        }
      });
    }
  });

  group('invalid values fall back to a readable notice', () {
    for (final entry in <String, Map<String, Object?>>{
      'InfoRow missing title': {'component': 'InfoRow', 'detail': 'x'},
      'InfoRow bad state': {
        'component': 'InfoRow',
        'title': 'x',
        'state': 'great',
      },
      'InfoRow title too long': {'component': 'InfoRow', 'title': 'x' * 81},
      'StepRail no steps': {'component': 'StepRail', 'steps': <Object>[]},
      'StepRail bad state': {
        'component': 'StepRail',
        'steps': [
          {'label': 'a', 'state': 'doing'},
        ],
      },
      'ActionCallout missing title': {
        'component': 'ActionCallout',
        'eyebrow': 'Next',
      },
      'ActionCallout bad tone': {
        'component': 'ActionCallout',
        'title': 'x',
        'tone': 'loud',
      },
      'ArtifactTile bad kind': {
        'component': 'ArtifactTile',
        'name': 'a',
        'kind': 'zip',
      },
      'BotBadge bad identity': {
        'component': 'BotBadge',
        'label': 'Kai',
        'identity': 'gpt',
      },
      'ExpandableSection negative count': {
        'component': 'ExpandableSection',
        'title': 'x',
        'count': -1,
        'child': 'c',
      },
    }.entries) {
      testWidgets(entry.key, (tester) async {
        await _pump(
          tester,
          _payload([
            {'id': 'root', ...entry.value},
            {'id': 'c', 'component': 'Text', 'text': 'child'},
          ]),
        );
        expect(tester.takeException(), isNull);
        // Rejected up front by the normalizer's schema check, or by the
        // component itself: either way a notice, never a crash or raw JSON.
        expect(
          find.textContaining(
            RegExp('Visual unavailable|could not be displayed safely'),
          ),
          findsOneWidget,
        );
      });
    }
  });

  testWidgets('long text within limits wraps at 300px and 200% text', (
    tester,
  ) async {
    final long = List.filled(15, 'wrapping').join(' ');
    await _pump(
      tester,
      _payload([
        {
          'id': 'root',
          'component': 'Column',
          'children': ['info', 'steps', 'call', 'tile', 'bot'],
        },
        {
          'id': 'info',
          'component': 'InfoRow',
          'title': long.substring(0, 80),
          'detail': long,
          'meta': 'Meta value',
          'state': 'warning',
          'icon': 'storage',
        },
        {
          'id': 'steps',
          'component': 'StepRail',
          'steps': [
            {
              'label': long.substring(0, 60),
              'detail': long.substring(0, 120),
              'state': 'done',
            },
            {'label': 'Next', 'state': 'current', 'meta': 'Nov 23'},
          ],
        },
        {
          'id': 'call',
          'component': 'ActionCallout',
          'eyebrow': 'Needs you',
          'title': long.substring(0, 100),
          'detail': long,
          'tone': 'attention',
        },
        {
          'id': 'tile',
          'component': 'ArtifactTile',
          'name': '${long.substring(0, 70)}.md',
          'kind': 'document',
          'sizeLabel': '12 KB',
          'detail': long.substring(0, 120),
        },
        {
          'id': 'bot',
          'component': 'BotBadge',
          'label': long.substring(0, 40),
          'identity': 'kai',
          'detail': long.substring(0, 80),
        },
      ]),
      width: 300,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Visual unavailable'), findsNothing);
  });

  testWidgets('BotBadge renders every identity with a bot mark', (
    tester,
  ) async {
    const identities = [
      'neutral',
      'kai',
      'local',
      'autopilot',
      'fast',
      'strong',
    ];
    await _pump(
      tester,
      _payload([
        {
          'id': 'root',
          'component': 'Column',
          'children': [for (final i in identities) 'b-$i'],
        },
        for (final i in identities)
          {
            'id': 'b-$i',
            'component': 'BotBadge',
            'label': 'Bot $i',
            'identity': i,
            'detail': 'Working on $i',
          },
      ]),
      width: 300,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(HermezBotMark), findsNWidgets(identities.length));
    for (final i in identities) {
      expect(find.text('Bot $i'), findsOneWidget);
    }
  });

  group('ExpandableSection', () {
    String section({bool initiallyExpanded = false}) => _payload([
      {
        'id': 'root',
        'component': 'ExpandableSection',
        'title': 'Evidence',
        'subtitle': '6 sources reviewed',
        'count': 2,
        'child': 'list',
        'initiallyExpanded': initiallyExpanded,
      },
      {
        'id': 'list',
        'component': 'Column',
        'children': ['e1', 'go'],
      },
      {
        'id': 'e1',
        'component': 'InfoRow',
        'title': 'Vendor benchmark',
        'detail': 'A is 2x faster',
      },
      {
        'id': 'go',
        'component': 'Button',
        'child': 'go-label',
        'action': {
          'event': {'name': 'evidence.review'},
        },
      },
      {'id': 'go-label', 'component': 'Text', 'text': 'Review'},
    ]);

    double belowY(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(const ValueKey('below'))).dy;

    testWidgets('starts collapsed, opens and closes, moving content below, '
        'with no A2UI event', (tester) async {
      final interactions = <String>[];
      await _pump(tester, section(), interactions: interactions, below: _below);
      final closedY = belowY(tester);
      expect(find.text('Vendor benchmark'), findsNothing);

      await tester.tap(find.text('EVIDENCE / 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final midY = belowY(tester);
      await tester.pumpAndSettle();
      expect(midY, greaterThan(closedY));
      expect(belowY(tester), greaterThan(midY));
      expect(find.text('Vendor benchmark'), findsOneWidget);

      await tester.tap(find.text('EVIDENCE / 2'));
      await tester.pumpAndSettle();
      expect(belowY(tester), closedY);
      expect(find.text('Vendor benchmark'), findsNothing);

      expect(interactions, isEmpty);
      expect(sound.played, ['object_open.wav', 'object_close.wav']);
    });

    testWidgets('initiallyExpanded builds open and silent', (tester) async {
      await _pump(tester, section(initiallyExpanded: true));
      expect(find.text('Vendor benchmark'), findsOneWidget);
      expect(sound.played, isEmpty);
    });

    testWidgets('a rapid second tap reverses from where it is', (tester) async {
      await _pump(tester, section(), below: _below);
      final closedY = belowY(tester);
      await tester.tap(find.text('EVIDENCE / 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final beforeReverse = belowY(tester);
      expect(beforeReverse, greaterThan(closedY));

      await tester.tap(find.text('EVIDENCE / 2'), warnIfMissed: false);
      await tester.pump();
      expect((belowY(tester) - beforeReverse).abs(), lessThan(12));
      await tester.pumpAndSettle();
      expect(belowY(tester), closedY);
    });

    testWidgets('reduced motion changes the layout at once', (tester) async {
      await _pump(tester, section(), reduceMotion: true, below: _below);
      final closedY = belowY(tester);
      await tester.tap(find.text('EVIDENCE / 2'));
      await tester.pump();
      final openY = belowY(tester);
      expect(openY, greaterThan(closedY + 20));
      // The first frame is already the final layout.
      await tester.pumpAndSettle();
      expect(belowY(tester), openY);
    });

    testWidgets('hidden content is out of the semantics tree', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, section());
      expect(find.bySemanticsLabel(RegExp('Vendor benchmark')), findsNothing);
      await tester.tap(find.text('EVIDENCE / 2'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Vendor benchmark')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a Button inside still sends exactly one interaction', (
      tester,
    ) async {
      final interactions = <String>[];
      await _pump(tester, section(), interactions: interactions);
      await tester.tap(find.text('EVIDENCE / 2'));
      await tester.pumpAndSettle();
      expect(interactions, isEmpty);

      await tester.tap(find.text('Review'));
      await tester.pump();
      expect(interactions, hasLength(1));
      final action =
          (jsonDecode(
                interactions.single.substring('[A2UI_INTERACTION]\n'.length),
              ) as Map<String, dynamic>)['action']
              as Map<String, dynamic>;
      expect(action['name'], 'evidence.review');
    });
  });

  group('on a locked surface', () {
    String section() => _payload([
      {
        'id': 'root',
        'component': 'Column',
        'children': ['more', 'outside'],
      },
      {
        'id': 'more',
        'component': 'ExpandableSection',
        'title': 'Evidence',
        'child': 'go',
      },
      {
        'id': 'go',
        'component': 'Button',
        'child': 'go-label',
        'action': {
          'event': {'name': 'evidence.review'},
        },
      },
      {'id': 'go-label', 'component': 'Text', 'text': 'Review'},
      {
        'id': 'outside',
        'component': 'Button',
        'child': 'outside-label',
        'action': {
          'event': {'name': 'outside.tap'},
        },
      },
      {'id': 'outside-label', 'component': 'Text', 'text': 'Outside'},
    ]);

    testWidgets('a read-only compartment still opens', (tester) async {
      await _pump(tester, section());
      await tester.tap(find.text('EVIDENCE'));
      await tester.pumpAndSettle();
      expect(find.text('Review'), findsOneWidget);
    });

    testWidgets('while busy the compartment opens but no Button sends', (
      tester,
    ) async {
      final interactions = <String>[];
      await _pump(tester, section(), isBusy: true, interactions: interactions);
      await tester.tap(find.text('EVIDENCE'));
      await tester.pumpAndSettle();
      expect(find.text('Review'), findsOneWidget);
      await tester.tap(find.text('Review'), warnIfMissed: false);
      await tester.tap(find.text('Outside'), warnIfMissed: false);
      await tester.pump();
      expect(interactions, isEmpty);
    });
  });

  testWidgets('an ActionCallout action Button sends exactly one interaction', (
    tester,
  ) async {
    final interactions = <String>[];
    final payload = File('test/fixtures/hermes/a2ui/action-needed.jsonl')
        .readAsStringSync();
    await _pump(tester, payload, interactions: interactions);
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(interactions, hasLength(1));
    expect(interactions.single, contains('refund.approve'));
  });

  test('the structure components make no I/O and dispatch no events', () {
    final source = File(
      'lib/features/hermes/widgets/hermes_visual_structure.dart',
    ).readAsStringSync();
    for (final banned in [
      'dart:io',
      'package:http',
      'package:dio',
      'url_launcher',
      'path_provider',
      'file_picker',
      'dispatchEvent',
      'services/',
      'providers/',
    ]) {
      expect(source.contains(banned), isFalse, reason: banned);
    }
  });
}
