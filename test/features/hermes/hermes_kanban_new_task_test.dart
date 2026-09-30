import 'dart:async';
import 'dart:convert';

import 'package:conduit/features/hermes/feedback/hermez_feedback.dart';
import 'package:conduit/features/hermes/kanban/hermes_kanban_client.dart';
import 'package:conduit/features/hermes/kanban/hermes_kanban_page.dart';
import 'package:conduit/features/hermes/motion/hermez_motion_surface.dart';
import 'package:conduit/features/hermes/motion/hermez_panel_morph.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _config = HermesConfig(
  enabled: true,
  mode: HermesBackendMode.desktopGateway,
  baseUrl: 'https://example.test/v1',
  desktopAuthKind: HermesDesktopAuthKind.dashboardCookie,
);

const _notice =
    'Ready tasks assigned to a bot may start agent work '
    'immediately.';

class _Sound implements HermezSoundBackend {
  final List<String> played = [];

  @override
  Future<void> start(Iterable<String> assets) async {}

  @override
  void play(String asset, {required double volume, required double speed}) =>
      played.add(asset.split('/').last);
}

/// A Kanban board with one Ready task (so the Ready lane and its plus button
/// are on screen) that records every task the app creates.
class _Board {
  _Board({this.holdCreate});

  /// When set, task creation waits for this to complete.
  final Completer<void>? holdCreate;
  final List<Map<String, Object?>> created = [];

  HermesKanbanClient client() => HermesKanbanClient(
    _config,
    request: (method, uri, {body}) async {
      final path = uri.path;
      if (path.endsWith('/boards')) {
        return (
          status: 200,
          body: '{"boards":[{"slug":"qa","name":"QA board"}]}',
        );
      }
      if (path.endsWith('/profiles')) {
        return (
          status: 200,
          body: '{"profiles":[{"name":"kai","description":"General agent"}]}',
        );
      }
      if (method == 'POST' && path.endsWith('/tasks')) {
        await holdCreate?.future;
        created.add((jsonDecode(body!) as Map).cast<String, Object?>());
        return (status: 200, body: '{}');
      }
      return (
        status: 200,
        body: jsonEncode({
          'columns': [
            {
              'name': 'ready',
              'tasks': [
                {'id': 't-1', 'title': 'Existing task', 'status': 'ready'},
              ],
            },
          ],
        }),
      );
    },
  );
}

Future<void> _pumpBoard(
  WidgetTester tester,
  _Board board, {
  Size size = const Size(412, 900),
  double textScale = 1,
  bool reduceMotion = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: HermesKanbanPage(client: board.client()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openNewTask(WidgetTester tester) async {
  await tester.tap(find.text('New task'));
  await tester.pumpAndSettle();
}

double _y(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

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

  Finder fabSurface() => find.ancestor(
    of: find.text('New task'),
    matching: find.byType(HermezMotionSurface),
  );

  bool triggerVisible(WidgetTester tester, Finder surface) => tester
      .widget<Visibility>(
        find.ancestor(of: surface, matching: find.byType(Visibility)).first,
      )
      .visible;

  testWidgets('the New task button turns into the panel and comes home', (
    tester,
  ) async {
    await _pumpBoard(tester, _Board());
    final button = tester.getRect(fabSurface());
    expect(triggerVisible(tester, fabSurface()), isTrue);

    await tester.tap(find.text('New task'));
    await tester.pump();
    final morph = tester.renderObject<RenderHermezPanelMorph>(
      find.byType(HermezPanelMorph),
    );
    // It grows out of exactly where the button is, and the real button is
    // held back (still in its place) while the panel stands in for it.
    expect(morph.originRect, button);
    expect(triggerVisible(tester, fabSurface()), isFalse);
    await tester.pump(const Duration(milliseconds: 80));
    expect(morph.apertureRect.height, greaterThan(button.height));
    expect(morph.apertureRect.height, lessThan(morph.panelRect.height));

    await tester.pumpAndSettle();
    expect(morph.apertureRect, morph.panelRect);
    expect(find.text('Title *'), findsOneWidget);
    expect(triggerVisible(tester, fabSurface()), isFalse);

    // Cancel runs it home; the button is only shown again once it has
    // finished contracting into it.
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(triggerVisible(tester, fabSurface()), isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(HermezPanelMorph), findsNothing);
    expect(triggerVisible(tester, fabSurface()), isTrue);
    expect(tester.getRect(fabSurface()), button);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a keyboard does not move the New task button', (tester) async {
    await _pumpBoard(tester, _Board());
    final before = tester.getRect(fabSurface());
    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(tester.getRect(fabSurface()), before);
  });

  testWidgets('a lane plus opens the same panel from its own position', (
    tester,
  ) async {
    await _pumpBoard(tester, _Board());
    final plus = find.byTooltip('New Ready task');
    final plusRect = tester.getRect(
      find.ancestor(of: plus, matching: find.byType(HermezMotionSurface)),
    );

    await tester.tap(plus);
    await tester.pump();
    final morph = tester.renderObject<RenderHermezPanelMorph>(
      find.byType(HermezPanelMorph),
    );
    expect(morph.originRect, plusRect);
    // Only the tapped plus is held back; the floating button stays.
    expect(triggerVisible(tester, fabSurface()), isTrue);

    await tester.pumpAndSettle();
    expect(find.text('Ready · No bot · Priority 0'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(HermezPanelMorph), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping outside closes the panel without creating anything', (
    tester,
  ) async {
    final board = _Board();
    await _pumpBoard(tester, board);
    await _openNewTask(tester);
    await tester.enterText(find.byType(TextField).first, 'Draft');
    await tester.tapAt(const Offset(200, 880));
    await tester.pumpAndSettle();
    expect(find.byType(HermezPanelMorph), findsNothing);
    expect(board.created, isEmpty);
    expect(triggerVisible(tester, fabSurface()), isTrue);
  });

  testWidgets('starts closed: primary fields and the Create button are '
      'visible, the options show their real values', (tester) async {
    await _pumpBoard(tester, _Board());
    await _openNewTask(tester);

    expect(find.text('Title *'), findsOneWidget);
    expect(find.text('Details / instructions'), findsOneWidget);
    expect(find.text('Create task'), findsOneWidget);
    expect(find.text('OPTIONS'), findsOneWidget);
    expect(find.text('Triage · No bot · Priority 0'), findsOneWidget);
    // The controls are not built while the compartment is closed.
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.text('Assign a bot (optional)'), findsNothing);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
  });

  testWidgets('opening pushes the actions down and closes the keyboard; '
      'closing brings them back', (tester) async {
    await _pumpBoard(tester, _Board());
    await _openNewTask(tester);
    // Opening the panel does not raise the keyboard; typing a title does.
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    double gap() =>
        _y(tester, find.text('Create task')) - _y(tester, find.text('OPTIONS'));
    final closedGap = gap();

    await tester.tap(find.text('OPTIONS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midGap = gap();
    await tester.pumpAndSettle();
    final openGap = gap();

    expect(midGap, greaterThan(closedGap));
    expect(openGap, greaterThan(midGap));
    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    expect(find.text('Assign a bot (optional)'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.text('OPTIONS'));
    await tester.pumpAndSettle();
    expect((gap() - closedGap).abs(), lessThan(0.5));
    expect(find.byType(SegmentedButton<bool>), findsNothing);
  });

  testWidgets('choices update the header, the warning stays visible with the '
      'options closed, and the created task carries them', (tester) async {
    final board = _Board();
    await _pumpBoard(tester, board);
    await _openNewTask(tester);

    await tester.enterText(find.byType(TextField).first, 'Ship the route');
    await tester.enterText(find.byType(TextField).last, 'Details here');
    await tester.tap(find.text('OPTIONS'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ready').last);
    await tester.pumpAndSettle();
    expect(find.text('Ready · No bot · Priority 0'), findsOneWidget);
    // Ready with no bot: no warning yet.
    expect(find.text(_notice), findsNothing);

    await tester.tap(find.text('Assign a bot (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('kai'));
    await tester.pumpAndSettle();
    expect(find.text('Ready · kai · Priority 0'), findsOneWidget);
    expect(find.text(_notice), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Priority 2').last);
    await tester.pumpAndSettle();
    expect(find.text('Ready · kai · Priority 2'), findsOneWidget);

    // Close the options: the summary and the warning are still on screen.
    await tester.tap(find.text('OPTIONS'));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.text('Ready · kai · Priority 2'), findsOneWidget);
    expect(find.text(_notice), findsOneWidget);

    await tester.tap(find.text('Create task'));
    await tester.pumpAndSettle();
    expect(board.created, hasLength(1));
    expect(board.created.single['title'], 'Ship the route');
    expect(board.created.single['body'], 'Details here');
    expect(board.created.single['triage'], false);
    expect(board.created.single['assignee'], 'kai');
    expect(board.created.single['priority'], 2);
    expect(find.text('New task'), findsOneWidget); // the button, dialog gone
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing title shows its error with the options closed and '
      'sends nothing', (tester) async {
    final board = _Board();
    await _pumpBoard(tester, board);
    await _openNewTask(tester);

    await tester.tap(find.text('Create task'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a task title.'), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(board.created, isEmpty);
  });

  testWidgets('the Ready lane plus button opens with Ready already shown', (
    tester,
  ) async {
    await _pumpBoard(tester, _Board());
    await tester.tap(find.byTooltip('New Ready task'));
    await tester.pumpAndSettle();
    expect(find.text('Ready · No bot · Priority 0'), findsOneWidget);
  });

  testWidgets('the compartment cues play once per real header tap', (
    tester,
  ) async {
    await _pumpBoard(tester, _Board());
    await _openNewTask(tester);
    final before = sound.played.length;

    await tester.tap(find.text('OPTIONS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OPTIONS'));
    await tester.pumpAndSettle();

    expect(sound.played.sublist(before), [
      'object_open.wav',
      'object_close.wav',
    ]);
  });

  testWidgets('semantics: the header announces its state and values', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpBoard(tester, _Board());
    await _openNewTask(tester);

    final header = find.bySemanticsLabel(
      RegExp('^Task options. Triage, no bot assigned, priority 0'),
    );
    expect(header, findsOneWidget);
    expect(
      tester.getSemantics(header),
      matchesSemantics(
        isButton: true,
        hasExpandedState: true,
        isExpanded: false,
        hasTapAction: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('reduced motion opens the options at once', (tester) async {
    await _pumpBoard(tester, _Board(), reduceMotion: true);
    await _openNewTask(tester);
    final closedGap =
        _y(tester, find.text('Create task')) - _y(tester, find.text('OPTIONS'));

    await tester.tap(find.text('OPTIONS'));
    await tester.pump();
    final openGap =
        _y(tester, find.text('Create task')) - _y(tester, find.text('OPTIONS'));
    expect(openGap, greaterThan(closedGap + 100));
    await tester.pumpAndSettle();
    expect(
      _y(tester, find.text('Create task')) - _y(tester, find.text('OPTIONS')),
      openGap,
    );
  });

  testWidgets('the options are disabled while the task is being saved', (
    tester,
  ) async {
    final hold = Completer<void>();
    final board = _Board(holdCreate: hold);
    await _pumpBoard(tester, board);
    await _openNewTask(tester);
    await tester.enterText(find.byType(TextField).first, 'Slow one');
    await tester.tap(find.text('OPTIONS'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create task'));
    await tester.pump();
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .onSelectionChanged,
      isNull,
    );

    hold.complete();
    await tester.pumpAndSettle();
    expect(board.created, hasLength(1));
  });

  for (final width in <double>[320, 412]) {
    testWidgets('no overflow at $width dp and 200% text, closed or open', (
      tester,
    ) async {
      await _pumpBoard(tester, _Board(), size: Size(width, 700), textScale: 2);
      await _openNewTask(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('OPTIONS'), findsOneWidget);

      // With large text the panel scrolls its own content, like a dialog.
      await tester.ensureVisible(find.text('OPTIONS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OPTIONS'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    });
  }
}
