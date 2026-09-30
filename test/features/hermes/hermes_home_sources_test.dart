import 'package:conduit/core/services/navigation_service.dart';
import 'package:conduit/features/hermes/kanban/hermes_kanban_summary_provider.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/motion/hermez_morph_origin.dart';
import 'package:conduit/features/hermes/motion/hermez_panel_morph.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/providers/hermes_session_totals_provider.dart';
import 'package:conduit/features/hermes/sheets/hermez_modal_sheet.dart';
import 'package:conduit/features/hermes/views/hermes_conversations_page.dart';
import 'package:conduit/features/hermes/views/hermes_home_page.dart';
import 'package:conduit/features/hermes/views/hermes_teams_page.dart';
import 'package:conduit/features/hermes/widgets/hermes_home_presence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Sessions extends HermesSessionsController {
  @override
  Future<List<HermesSessionSummary>> build() async => const [
    HermesSessionSummary(
      id: 's-1',
      title: 'Inventory migration',
      profile: 'kai',
    ),
    HermesSessionSummary(id: 's-2', title: 'Proposal review', profile: 'kai'),
    HermesSessionSummary(id: 's-3', title: 'Umbrel setup', profile: 'local'),
  ];
}

const _bots = [
  HermesBot(name: 'kai', title: 'Kai', description: 'Kaizen'),
  HermesBot(name: 'local', title: 'Local'),
];

/// Where each destination was opened from, by route name.
final _opened = <String, Object?>{};

GoRouter _router() {
  GoRoute dest(String path, String name) => GoRoute(
    path: path,
    name: name,
    builder: (context, state) {
      _opened[name] = state.extra;
      return Scaffold(body: Center(child: Text('dest:$name')));
    },
  );
  return GoRouter(
    initialLocation: Routes.hermesHome,
    routes: [
      GoRoute(
        path: Routes.hermesHome,
        builder: (context, state) => const HermesHomePage(),
      ),
      dest(Routes.hermesConversations, RouteNames.hermesConversations),
      dest(Routes.hermesTeams, RouteNames.hermesTeams),
      dest(Routes.hermesAttention, RouteNames.hermesAttention),
      dest(Routes.hermesArtifacts, RouteNames.hermesArtifacts),
    ],
  );
}

Future<void> _pumpHome(WidgetTester tester) async {
  _opened.clear();
  await tester.binding.setSurfaceSize(const Size(412, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = _router();
  addTearDown(router.dispose);
  NavigationService.attachRouter(router);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hermesApiServiceProvider.overrideWithValue(null),
        hermesBotsProvider.overrideWith((ref) async => _bots),
        hermesHomeProfileJobsProvider.overrideWith((ref) async => []),
        hermesSessionsProvider.overrideWith(_Sessions.new),
        hermesKanbanSummaryProvider.overrideWith((ref) async => null),
        hermesTeamsProvider.overrideWith((ref) async => []),
        hermesHomePendingDecisionsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Recent See all grows the whole Recent block into '
      'Conversations', (tester) async {
    await _pumpHome(tester);
    final block = tester.getRect(find.text('RECENT'));
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    final origin = _opened[RouteNames.hermesConversations];
    expect(origin, isA<HermezMorphOrigin>());
    final rect = (origin! as HermezMorphOrigin).resolve();
    // The origin is the block (header and rows), not the small label.
    expect(rect.top, lessThanOrEqualTo(block.top));
    expect(rect.height, greaterThan(block.height * 3));
  });

  testWidgets('All teams grows the Teams block into Teams', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.text('All teams'));
    await tester.pumpAndSettle();
    expect(_opened[RouteNames.hermesTeams], isA<HermezMorphOrigin>());
  });

  testWidgets('Attention and Artifacts are objects that open with an '
      'origin', (tester) async {
    await _pumpHome(tester);
    expect(find.text('ATTENTION'), findsOneWidget);
    expect(find.text('Needs your input'), findsOneWidget);
    await tester.tap(find.text('ATTENTION'));
    await tester.pumpAndSettle();
    expect(_opened[RouteNames.hermesAttention], isA<HermezMorphOrigin>());

    await _pumpHome(tester);
    await tester.tap(find.text('ARTIFACTS'));
    await tester.pumpAndSettle();
    expect(_opened[RouteNames.hermesArtifacts], isA<HermezMorphOrigin>());
  });

  testWidgets('the + turns into a bot menu; choosing closes it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpHome(tester);
    await tester.tap(find.byTooltip('New Hermes chat'));
    await tester.pumpAndSettle();
    // The plus-to-menu morph, not a sheet from the bottom edge.
    expect(find.byType(HermezPanelMorph), findsOneWidget);
    expect(find.byType(HermezModalSheet), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('NEW CONVERSATION'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Start a conversation with Kai')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('^Start a conversation with Local')),
      findsOneWidget,
    );

    await tester.tap(
      find.bySemanticsLabel(RegExp('^Start a conversation with Kai')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HermezPanelMorph), findsNothing);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  group('Conversations page', () {
    Future<void> pumpConversations(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermesApiServiceProvider.overrideWithValue(null),
            hermesBotsProvider.overrideWith((ref) async => _bots),
            hermesSessionsProvider.overrideWith(_Sessions.new),
            hermesSessionTotalsProvider.overrideWith(
              (ref) async => {'kai': 12, 'local': 1},
            ),
            hermesBotSessionsProvider.overrideWith(
              (ref, profile) async => [
                for (var i = 0; i < 7; i++)
                  HermesSessionSummary(
                    id: '$profile-$i',
                    title: '$profile chat $i',
                    profile: profile,
                  ),
              ],
            ),
          ],
          child: const MaterialApp(home: HermesConversationsPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('groups conversations by bot and carries no side-navigation '
        'entries', (tester) async {
      await pumpConversations(tester);
      expect(find.text('KAI  12'), findsOneWidget);
      expect(find.text('LOCAL  1'), findsOneWidget);
      expect(find.text('Inventory migration'), findsOneWidget);
      expect(find.text('Umbrel setup'), findsOneWidget);
      for (final entry in ['Hermes Home', 'Kanban', 'Scheduled agents']) {
        expect(find.text(entry), findsNothing, reason: entry);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bot filter shows that bot\'s full list', (tester) async {
      await pumpConversations(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Kai'));
      await tester.pumpAndSettle();
      expect(find.text('kai chat 0'), findsOneWidget);
      expect(find.text('kai chat 6'), findsOneWidget);
      expect(find.text('Umbrel setup'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All bots'));
      await tester.pumpAndSettle();
      expect(find.text('Umbrel setup'), findsOneWidget);
    });

    testWidgets('See all on a bot group narrows to that bot', (tester) async {
      await pumpConversations(tester);
      await tester.tap(find.text('See all').first);
      await tester.pumpAndSettle();
      expect(find.text('kai chat 6'), findsOneWidget);
    });
  });
}
