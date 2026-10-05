import 'package:checks/checks.dart';
import 'package:conduit/features/hermes/models/hermes_subagent.dart';
import 'package:conduit/features/hermes/models/hermes_todo.dart';
import 'package:conduit/features/hermes/services/hermes_activity_presenter.dart';
import 'package:conduit/features/hermes/services/hermes_agentic_state.dart';
import 'package:conduit/features/hermes/services/hermes_live_activity.dart';
import 'package:conduit/features/hermes/services/hermes_tool_inspector_service.dart';
import 'package:flutter_test/flutter_test.dart';

HermesLiveActivityEvent _event(
  HermesLiveActivityKind kind, {
  String? tool,
  String? id,
  String? preview,
  Duration? duration,
  bool failed = false,
  HermesActivityPageRef? page,
  int second = 0,
}) => HermesLiveActivityEvent(
  sessionId: 's',
  kind: kind,
  title: 'x',
  timestamp: DateTime.utc(2026, 10, 4, 12, 0, second),
  detail: tool,
  toolId: id,
  preview: preview,
  duration: duration,
  failed: failed,
  page: page,
);

void main() {
  group('verbs', () {
    test('known tools read as plain past and present actions', () {
      check(HermesActivityPresenter.verb('terminal')).equals('Ran command');
      check(HermesActivityPresenter.verb('web_search', running: true))
          .equals('Searching web');
      check(HermesActivityPresenter.verb('patch')).equals('Edited file');
      check(HermesActivityPresenter.verb('browser_navigate')).equals('Browsed');
      check(HermesActivityPresenter.verb('todo_list')).equals('Updated plan');
      check(HermesActivityPresenter.verb('delegate_task')).equals('Delegated');
      check(HermesActivityPresenter.verb('spaces_create_page'))
          .equals('Created Page');
    });

    test('unknown tools fall back to "Used <tool>"', () {
      check(HermesActivityPresenter.verb('mcp_github_create_issue'))
          .equals('Used Github create issue');
    });
  });

  test('the bridge is unwrapped to the tool that ran', () {
    final call = HermesActivityPresenter.unwrap('tool_call', {
      'name': 'spaces_read_page',
      'arguments': {'page_id': 'p'},
    });
    check(call.name).equals('spaces_read_page');
    check(call.args['page_id']).equals('p');
    check(HermesActivityPresenter.unwrap('terminal', null).name)
        .equals('terminal');
  });

  test('a start and its finish make one row with the server duration', () {
    final rows = HermesActivityPresenter.rows([
      _event(
        HermesLiveActivityKind.toolStarted,
        tool: 'web_search',
        id: 't1',
        preview: 'springs',
      ),
      _event(
        HermesLiveActivityKind.toolCompleted,
        tool: 'web_search',
        id: 't1',
        duration: const Duration(milliseconds: 1200),
        second: 2,
      ),
    ]);
    check(rows).length.equals(1);
    check(rows.single.verb).equals('Searched web');
    check(rows.single.object).equals('springs');
    check(rows.single.duration).equals(const Duration(milliseconds: 1200));
    check(rows.single.state).equals(HermesActivityRowState.done);
  });

  test('adjacent identical successes fold; failures and plans never do', () {
    final rows = HermesActivityPresenter.rows([
      for (var i = 0; i < 3; i++) ...[
        _event(
          HermesLiveActivityKind.toolStarted,
          tool: 'web_search',
          id: 'w$i',
        ),
        _event(
          HermesLiveActivityKind.toolCompleted,
          tool: 'web_search',
          id: 'w$i',
          duration: const Duration(seconds: 1),
        ),
      ],
      _event(HermesLiveActivityKind.toolCompleted, tool: 'todo_list', id: 'p1'),
      _event(HermesLiveActivityKind.toolCompleted, tool: 'todo_list', id: 'p2'),
      _event(
        HermesLiveActivityKind.toolCompleted,
        tool: 'terminal',
        id: 'f1',
        failed: true,
      ),
      _event(
        HermesLiveActivityKind.toolCompleted,
        tool: 'terminal',
        id: 'f2',
        failed: true,
      ),
    ]);
    check(rows.map((row) => row.verb)).deepEquals([
      'Searched web',
      'Updated plan',
      'Updated plan',
      'Ran command',
      'Ran command',
    ]);
    check(rows.first.count).equals(3);
    check(rows.first.duration).equals(const Duration(seconds: 3));
    check(rows.first.toolIds).deepEquals(['w0', 'w1', 'w2']);
  });

  test('a call still being written never opens a row of its own', () {
    final rows = HermesActivityPresenter.rows([
      // tool.generating: raw bridge name, no id.
      _event(HermesLiveActivityKind.toolProgress, tool: 'tool_call'),
      _event(HermesLiveActivityKind.toolStarted, tool: 'todo_list', id: 't'),
      _event(HermesLiveActivityKind.toolCompleted, tool: 'todo_list', id: 't'),
    ]);
    check(rows.map((row) => row.verb)).deepEquals(['Updated plan']);
  });

  test('a finished run shows no step as still running', () {
    final events = [
      _event(HermesLiveActivityKind.toolStarted, tool: 'terminal', id: 'a'),
    ];
    check(HermesActivityPresenter.rows(events).single.state)
        .equals(HermesActivityRowState.running);
    final done = HermesActivityPresenter.rows(events, running: false).single;
    check(done.state).equals(HermesActivityRowState.done);
    check(done.verb).equals('Ran command');
  });

  test('the present-tense line names what is running now', () {
    final rows = HermesActivityPresenter.rows([
      _event(
        HermesLiveActivityKind.toolStarted,
        tool: 'terminal',
        id: 't',
        preview: 'flutter test',
      ),
    ]);
    check(HermesActivityPresenter.now(rows))
        .equals('Running command · flutter test');
  });

  test('a finished run is summed up by its work, not its housekeeping', () {
    check(
      HermesActivityPresenter.headline([
        (name: 'skill_view', count: 1),
        (name: 'tool_search', count: 1),
        (name: 'todo_list', count: 2),
        (name: 'terminal', count: 2),
        (name: 'search_files', count: 1),
      ]),
    ).deepEquals(['terminal', 'search_files']);
    // A run that only looked things up still says so.
    check(
      HermesActivityPresenter.headline([
        (name: 'skill_view', count: 1),
        (name: 'tool_search', count: 1),
        (name: 'todo_list', count: 1),
      ]),
    ).deepEquals(['skill_view', 'tool_search']);
  });

  test('older rows fold into "+N earlier"', () {
    final rows = [
      for (var i = 0; i < 9; i++)
        HermesActivityRow(
          key: '$i',
          verb: 'v$i',
          state: HermesActivityRowState.done,
          family: HermesActivityFamily.other,
          at: DateTime.utc(2026),
        ),
    ];
    final recent = HermesActivityPresenter.recent(rows, visible: 5);
    check(recent.earlier).equals(4);
    check(recent.rows.first.verb).equals('v4');
  });

  test('a created Page is linked only from a successful Spaces result', () {
    const page = {
      'id': '11111111-2222-4333-8444-555555555555',
      'space_id': '66666666-7777-4888-8999-aaaaaaaaaaaa',
      'title': 'Notes',
    };
    check(
      HermesActivityPresenter.pageFromResult('spaces_create_page', {
        'ok': true,
        'page': page,
      }),
    ).isNotNull().has((ref) => ref.title, 'title').equals('Notes');
    check(
      HermesActivityPresenter.pageFromResult('spaces_create_page', {
        'ok': false,
        'page': page,
      }),
    ).isNull();
    check(
      HermesActivityPresenter.pageFromResult('terminal', {
        'ok': true,
        'page': page,
      }),
    ).isNull();
  });

  test('previews never carry secrets or control characters', () {
    check(
      HermesActivityPresenter.clean(
        'curl -H "Bearer sk-abcdefghijklmnop1234" \u0007 x',
        sensitiveValues: const ['hunter2pass'],
      ),
    ).isNotNull().not((it) => it.contains('sk-abcdefghijklmnop1234'));
    check(
      HermesActivityPresenter.clean(
        'login hunter2pass now',
        sensitiveValues: const ['hunter2pass'],
      ),
    ).equals('login •••• now');
  });

  group('plan', () {
    test('preview puts the current step first, then what is next', () {
      final plan = HermesTodoSnapshot.fromJson({
        'revision': 2,
        'todos': [
          {'id': '1', 'content': 'One', 'status': 'completed'},
          {'id': '2', 'content': 'Two', 'status': 'pending'},
          {'id': '3', 'content': 'Three', 'status': 'in_progress'},
          {'id': '4', 'content': 'Four', 'status': 'cancelled'},
        ],
      })!;
      check(plan.preview().map((item) => item.id)).deepEquals(['3', '2', '1']);
      check(plan.total).equals(3);
      check(plan.hasActiveWork).isTrue();
    });

    test('an unused empty plan is not a plan, an emptied one is', () {
      check(HermesTodoSnapshot.fromJson({'revision': 0, 'todos': []})).isNull();
      check(HermesTodoSnapshot.fromJson({'revision': 4, 'todos': []}))
          .isNotNull()
          .has((plan) => plan.isEmpty, 'isEmpty')
          .isTrue();
    });

    test('nested steps follow their parent in the outline', () {
      final plan = HermesTodoSnapshot.fromJson({
        'revision': 1,
        'todos': [
          {'id': 'a', 'content': 'A', 'status': 'pending'},
          {'id': 'b', 'content': 'B', 'status': 'pending'},
          {'id': 'a1', 'content': 'A1', 'status': 'pending', 'parent': 'a'},
        ],
      })!;
      check(plan.outline.map((row) => '${row.item.id}:${row.depth}'))
          .deepEquals(['a:0', 'a1:1', 'b:0']);
    });
  });

  group('store', () {
    test('plans are revision-monotonic per session', () {
      final store = HermesAgenticStateStore();
      addTearDown(store.close);
      check(
        store.applyTodo('s', {
          'revision': 2,
          'todos': [
            {'id': 'a', 'content': 'A', 'status': 'pending'},
          ],
        }),
      ).isTrue();
      check(
        store.applyTodo('s', {
          'revision': 1,
          'todos': [
            {'id': 'b', 'content': 'B', 'status': 'pending'},
          ],
        }),
      ).isFalse();
      check(store.snapshotFor('s').todo!.items.single.id).equals('a');
    });

    test('a new turn drops finished delegates and keeps live ones', () {
      final store = HermesAgenticStateStore();
      addTearDown(store.close);
      store.applySubagentEvent('s', 'subagent.start', {
        'subagent_id': 'live',
        'goal': 'g',
      });
      store.applySubagentEvent('s', 'subagent.complete', {
        'subagent_id': 'done',
        'goal': 'g',
        'status': 'completed',
      });
      store.pruneFinishedSubagents('s');
      check(store.snapshotFor('s').subagents.map((worker) => worker.id))
          .deepEquals(['live']);
    });
  });

  test('a completion without a known status fails closed', () {
    final worker = HermesSubagentState.reduce(null, 'subagent.complete', {
      'subagent_id': 'x',
      'goal': 'g',
    }, now: DateTime.utc(2026))!;
    check(worker.status).equals(HermesSubagentStatus.failed);
  });

  test('the inspector finds a call and its result in the transcript', () {
    final record = findHermesToolCall([
      {
        'role': 'assistant',
        'tool_calls': [
          {
            'id': 'c1',
            'function': {
              'name': 'tool_call',
              'arguments':
                  '{"name": "spaces_read_page", "arguments": {"page_id": "p"}}',
            },
          },
        ],
      },
      {
        'role': 'tool',
        'tool_call_id': 'c1',
        'content': '{"ok": false, "error": "not_found"}',
      },
    ], 'c1')!;
    check(record.name).equals('spaces_read_page');
    check(record.input!).contains('"page_id": "p"');
    check(record.failed).isTrue();
    check(findHermesToolCall(const [], 'missing')).isNull();
  });

  test('the inspector reads calls stored as a JSON string', () {
    final record = findHermesToolCall([
      {
        'role': 'assistant',
        'tool_calls': '[{"id": "c9", "function": {"name": "terminal", "arguments": "{\\"command\\": \\"date\\"}"}}]',
      },
      {'role': 'tool', 'tool_call_id': 'c9', 'content': 'Mon Oct 5'},
    ], 'c9')!;
    check(record.name).equals('terminal');
    check(record.input!).contains('date');
    check(record.result).equals('Mon Oct 5');
  });
}
