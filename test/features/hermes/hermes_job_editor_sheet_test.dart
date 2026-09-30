import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/models/hermes_job.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_api_service.dart';
import 'package:conduit/features/hermes/views/hermes_jobs_page.dart';
import 'package:conduit/features/hermes/sheets/hermez_modal_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _calls = <String>[];

const _longError =
    'RuntimeError: Skipped to prevent unintended spend: global inference '
    'config drifted since this job was created, and this job is unpinned. '
    'No inference call was made. To run on the new config, pin it '
    'explicitly on the host. This alert is sent once.';

class _Service extends HermesApiService {
  _Service()
    : super(
        config: const HermesConfig(
          enabled: true,
          baseUrl: 'https://hermes.example',
          apiKey: 'test-key',
        ),
      );
}

class _Jobs extends HermesJobsController {
  @override
  Future<List<HermesJob>> build() async => [
    HermesJob(
      id: 'job-1',
      name: 'Daily digest',
      prompt: 'Summarize research',
      schedule: '0 9 * * *',
      enabled: true,
    ),
  ];

  @override
  Future<void> create({
    required String name,
    required String prompt,
    required String schedule,
  }) async => _calls.add('create:$name|$prompt|$schedule');

  @override
  Future<void> edit(
    String id, {
    String? name,
    String? prompt,
    String? schedule,
  }) async => _calls.add('edit:$id:$name|$prompt|$schedule');

  @override
  Future<void> delete(String id) async => _calls.add('delete:$id');
}

Future<void> _pumpJobs(WidgetTester tester) async {
  _calls.clear();
  await tester.binding.setSurfaceSize(const Size(412, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hermesApiServiceProvider.overrideWithValue(_Service()),
        hermesJobsProvider.overrideWith(_Jobs.new),
        hermesJobRunsProvider.overrideWith(
          (ref, id) async => const <HermesSessionSummary>[],
        ),
      ],
      child: const MaterialApp(home: HermesJobsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('New scheduled job opens the editor as a Hermez sheet and '
      'creates with the entered values', (tester) async {
    await _pumpJobs(tester);
    await tester.tap(find.text('New scheduled job'));
    await tester.pumpAndSettle();
    expect(find.byType(HermezModalSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);

    final fields = find.descendant(
      of: find.byType(HermezModalSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'Morning brief');
    await tester.enterText(fields.at(1), 'Brief me');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(_calls, ['create:Morning brief|Brief me|0 9 * * *']);
    expect(find.byType(HermezModalSheet), findsNothing);
  });

  testWidgets('invalid input keeps the editor open and sends nothing', (
    tester,
  ) async {
    await _pumpJobs(tester);
    await tester.tap(find.text('New scheduled job'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(HermezModalSheet), findsOneWidget);
    expect(_calls, isEmpty);
  });

  testWidgets('cancel closes the editor without a mutation', (tester) async {
    await _pumpJobs(tester);
    await tester.tap(find.text('New scheduled job'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(HermezModalSheet), findsNothing);
    expect(_calls, isEmpty);
  });

  testWidgets('edit opens the same editor, prefilled, and saves an edit', (
    tester,
  ) async {
    await _pumpJobs(tester);
    await tester.tap(find.byTooltip('Edit scheduled job'));
    await tester.pumpAndSettle();
    expect(find.byType(HermezModalSheet), findsOneWidget);
    expect(find.text('Edit job'), findsWidgets);
    expect(find.text('Summarize research'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(_calls, ['edit:job-1:Daily digest|Summarize research|0 9 * * *']);
  });

  testWidgets('delete opens a guard inside the card; Cancel closes it; '
      'Delete removes once', (tester) async {
    await _pumpJobs(tester);
    await tester.tap(find.byTooltip('Delete scheduled job'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text('This cannot be undone.', findRichText: true),
      findsNothing,
    );
    final guard = find.byWidgetPredicate(
      (w) => w is Semantics && (w.properties.liveRegion ?? false),
    );
    expect(guard, findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(guard, findsNothing);
    expect(_calls, isEmpty);

    await tester.tap(find.byTooltip('Delete scheduled job'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: guard, matching: find.text('Delete')));
    await tester.pumpAndSettle();
    expect(_calls, ['delete:job-1']);
  });

  testWidgets('a long run error shows two lines and opens in place', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: HermesJobError(text: _longError, color: Colors.red),
          ),
        ),
      ),
    );
    Text error() => tester.widget<Text>(find.text(_longError));
    expect(error().maxLines, 2);
    expect(find.text('Show full error'), findsOneWidget);
    expect(
      tester.getSize(find.byType(HermesJobError)).height,
      greaterThanOrEqualTo(44),
    );

    await tester.tap(find.text('Show full error'));
    await tester.pumpAndSettle();
    expect(error().maxLines, isNull);
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('a short run error is shown whole, with no toggle', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HermesJobError(text: 'Timed out', color: Colors.red),
        ),
      ),
    );
    expect(find.text('Timed out'), findsOneWidget);
    expect(find.text('Show full error'), findsNothing);
  });

  testWidgets('the page counts every bot and lists the schedules of the '
      'other bots', (tester) async {
    _calls.clear();
    await tester.binding.setSurfaceSize(const Size(412, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermesApiServiceProvider.overrideWithValue(_Service()),
          hermesJobsProvider.overrideWith(_Jobs.new),
          hermesHomeProfileJobsProvider.overrideWith(
            (ref) async => [
              (
                'kai',
                HermesJob(
                  id: 'kai-1',
                  name: 'Inventory sweep',
                  prompt: 'Sweep',
                  schedule: '0 7 * * *',
                  enabled: true,
                ),
              ),
              (
                'local',
                HermesJob(
                  id: 'local-1',
                  name: 'Nightly backup',
                  prompt: 'Back up',
                  schedule: '0 2 * * *',
                  enabled: false,
                ),
              ),
            ],
          ),
          hermesJobRunsProvider.overrideWith(
            (ref, id) async => const <HermesSessionSummary>[],
          ),
        ],
        child: const MaterialApp(home: HermesJobsPage()),
      ),
    );
    await tester.pumpAndSettle();
    // This profile's one job plus the two others, as Home counts them.
    expect(find.text('2 active · 3 total'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('OTHER BOTS  2'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Inventory sweep'), findsOneWidget);
    expect(find.text('Nightly backup'), findsOneWidget);
    expect(find.text('PAUSED'), findsWidgets);
  });
}
