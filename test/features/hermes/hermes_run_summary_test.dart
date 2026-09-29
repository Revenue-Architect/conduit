import 'package:conduit/features/hermes/services/hermes_live_activity.dart';
import 'package:conduit/features/hermes/widgets/hermes_bot_knowledge.dart';
import 'package:flutter_test/flutter_test.dart';

HermesLiveActivityEvent _event(
  HermesLiveActivityKind kind,
  int second, {
  String? detail,
}) => HermesLiveActivityEvent(
  sessionId: 's',
  kind: kind,
  title: kind.name,
  timestamp: DateTime.utc(2026, 9, 28, 12, 0, second),
  detail: detail,
);

void main() {
  final history = [
    _event(HermesLiveActivityKind.toolStarted, 0, detail: 'old_tool'),
    _event(HermesLiveActivityKind.completed, 2),
    _event(HermesLiveActivityKind.toolStarted, 10, detail: 'web_search'),
    _event(HermesLiveActivityKind.toolCompleted, 14, detail: 'web_search'),
    _event(HermesLiveActivityKind.toolStarted, 15, detail: 'web_search'),
    _event(HermesLiveActivityKind.toolCompleted, 18, detail: 'web_search'),
    _event(HermesLiveActivityKind.toolStarted, 20, detail: 'browser'),
    _event(HermesLiveActivityKind.subagentStarted, 21),
    _event(HermesLiveActivityKind.toolCompleted, 30, detail: 'browser'),
    _event(HermesLiveActivityKind.completed, 42),
  ];

  test('a finished run is the events that ended with it', () {
    final run = HermesRunSummary.latest(history, running: false);
    expect(run.events.first.detail, 'web_search');
    expect(run.completed, isTrue);
    expect(run.failed, isFalse);
    expect(run.steps, 3);
    expect(run.subagents, 1);
    expect(run.tools, [
      (name: 'web_search', count: 2),
      (name: 'browser', count: 1),
    ]);
    expect(run.elapsed(), const Duration(seconds: 32));
    // The recorded turn start counts when it is earlier than the first tool.
    expect(
      run.elapsed(startedAt: DateTime.utc(2026, 9, 28, 12, 0, 8)),
      const Duration(seconds: 34),
    );
  });

  test('a run in progress is everything after the last one ended', () {
    final run = HermesRunSummary.latest(history.sublist(0, 6), running: true);
    expect(run.events, hasLength(4));
    expect(run.steps, 2);
    expect(run.completed, isFalse);
  });

  test('a failed run reports failure', () {
    final run = HermesRunSummary.latest([
      _event(HermesLiveActivityKind.toolStarted, 0, detail: 'shell'),
      _event(HermesLiveActivityKind.failed, 5),
    ], running: false);
    expect(run.failed, isTrue);
    // No finished tool: started ones count as steps.
    expect(run.steps, 1);
  });

  test('durations read naturally', () {
    expect(formatHermesRunDuration(const Duration(seconds: 42)), '42s');
    expect(formatHermesRunDuration(const Duration(seconds: 185)), '3m 05s');
    expect(formatHermesRunDuration(const Duration(minutes: 72)), '1h 12m');
  });

  test('the learning graph splits memory and keeps learned skills', () {
    final knowledge = HermesBotKnowledge.fromGraph({
      'memory': [
        {'source': 'memory', 'title': 'Store runs on Shopify', 'body': 'x'},
        {'source': 'profile', 'title': 'Prefers markdown', 'body': 'y'},
        {'source': 'profile', 'title': 'Blank', 'body': '   '},
        'not a row',
      ],
      'nodes': [
        {'kind': 'skill', 'label': 'price-audit', 'useCount': 2},
        {
          'kind': 'skill',
          'label': 'weekly-brief',
          'useCount': 9,
          'createdBy': 'agent',
          'category': 'reports',
        },
        {'kind': 'memory', 'label': 'memory:memory:0'},
      ],
    });
    expect(knowledge.notes.single.title, 'Store runs on Shopify');
    expect(knowledge.aboutUser.single.title, 'Prefers markdown');
    expect(knowledge.skills.map((skill) => skill.name), [
      'weekly-brief',
      'price-audit',
    ]);
    expect(knowledge.skills.first.writtenByBot, isTrue);
    expect(HermesBotKnowledge.fromGraph(const {}).isEmpty, isTrue);
  });
}
