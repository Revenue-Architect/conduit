import 'package:flutter_test/flutter_test.dart';
import 'package:conduit/features/hermes/models/hermes_subagent.dart';
import 'package:conduit/features/hermes/services/hermes_agentic_state.dart';

void main() {
  final now = DateTime.utc(2026, 10, 23);
  HermesSubagentState reduce(
    HermesSubagentState? previous,
    String type,
    Map<String, Object?> payload,
  ) => HermesSubagentState.reduce(previous, type, payload, now: now)!;
  test('batch children keep independent server identities', () {
    final first = reduce(null, 'subagent.start', {
      'subagent_id': 'a',
      'delegation_id': 'batch',
    });
    final second = reduce(null, 'subagent.start', {
      'subagent_id': 'b',
      'delegation_id': 'batch',
    });
    expect(first.id, 'a');
    expect(second.id, 'b');
  });
  test(
    'late start enriches a terminal worker without changing origin or status',
    () {
      final done = reduce(null, 'subagent.complete', {
        'subagent_id': 'a',
        'status': 'completed',
        'parent_turn_id': 'turn-1',
        'summary': 'Actual result',
      });
      final late = reduce(done, 'subagent.start', {
        'subagent_id': 'a',
        'status': 'running',
        'parent_turn_id': 'turn-2',
        'child_session_id': 'real-child',
        'child_profile': 'kai',
      });
      expect(late.status, HermesSubagentStatus.completed);
      expect(late.parentTurnId, 'turn-1');
      expect(late.summary, 'Actual result');
      expect(late.childSessionId, 'real-child');
      expect(late.childProfile, 'kai');
    },
  );
  test('new turns retain historical workers and repeated events do not duplicate cards', () async {
    final store = HermesAgenticStateStore(clock: () => now);
    addTearDown(store.close);
    const payload = {
      'subagent_id': 'a',
      'parent_turn_id': 'turn-1',
      'status': 'completed',
    };
    store.applySubagentEvent('p', 'subagent.complete', payload);
    store.applySubagentEvent('p', 'subagent.complete', payload);
    store.pruneFinishedSubagents('p');
    expect(store.snapshotFor('p').subagents.length, 1);
    expect(store.snapshotFor('p').subagents.single.parentTurnId, 'turn-1');
  });
  test('source call promotes a provisional worker without replacing its UI identity', () {
    final store = HermesAgenticStateStore(clock: () => now);
    addTearDown(store.close);
    store.applySubagentEvent('p', 'subagent.spawn_requested', {
      'source_tool_call_id': 'call',
      'parent_turn_id': 'turn',
      'task_index': 0,
    });
    final id = store.snapshotFor('p').subagents.single.id;
    store.applySubagentEvent('p', 'subagent.start', {
      'source_tool_call_id': 'call',
      'subagent_id': 'reported-id',
      'task_index': 0,
    });
    expect(store.snapshotFor('p').subagents.length, 1);
    expect(store.snapshotFor('p').subagents.single.id, id);
    expect(store.snapshotFor('p').subagents.single.steerableId, 'reported-id');
  });
  test('parallel specialists in one terminal call remain separate', () {
    final store = HermesAgenticStateStore(clock: () => now);
    addTearDown(store.close);
    for (final profile in ['kai', 'ops']) {
      store.applySubagentEvent('p', 'delegation.progress', {
        'delegation_id': 'specialist:$profile',
        'worker_kind': 'specialist',
        'source_tool_call_id': 'shared-terminal-call',
        'child_profile': profile,
        'status': 'running',
      });
    }
    expect(
      store.snapshotFor('p').subagents.map((w) => w.childProfile),
      unorderedEquals(['kai', 'ops']),
    );
  });
  test('Kanban run enriches queued identity and retries remain distinct', () {
    final store = HermesAgenticStateStore(clock: () => now);
    addTearDown(store.close);
    void event(String id, String? run, String status) =>
        store.applySubagentEvent('p', 'delegation.progress', {
          'delegation_id': id,
          'worker_kind': 'kanban',
          'task_id': 'task',
          'run_id': run,
          'status': status,
          'source_tool_call_id': 'creation-call',
        });
    event('queued', null, 'queued');
    event('run-1', '1', 'completed');
    expect(store.snapshotFor('p').subagents.single.id, 'queued');
    event('run-2', '2', 'running');
    expect(store.snapshotFor('p').subagents.length, 2);
    expect(
      store.snapshotFor('p').subagents.last.status,
      HermesSubagentStatus.running,
    );
  });
  test(
    'thinking, tool arguments and raw outputs never enter public activity',
    () {
      var worker = reduce(null, 'subagent.thinking', {
        'subagent_id': 'a',
        'text': 'private thoughts',
      });
      expect(worker.lines, isEmpty);
      worker = reduce(worker, 'subagent.tool', {
        'subagent_id': 'a',
        'tool_name': 'read_file',
        'tool_preview': 'password=verysecret',
        'text': 'raw output',
        'output_tail': [
          {'preview': 'private thoughts'},
          {'tool': 'terminal', 'preview': 'token=secret'},
        ],
      });
      expect(worker.lines.map((l) => l.text).join(' '), 'Terminal Read File');
    },
  );
  test('specialists and Kanban never inherit native control authority', () {
    for (final kind in ['specialist', 'kanban']) {
      final worker = reduce(null, 'delegation.progress', {
        'delegation_id': 'real-id',
        'worker_kind': kind,
        'status': 'running',
      });
      expect(worker.supportsNativeControl, isFalse);
      expect(worker.steerableId, isNull);
    }
  });
  test('unknown status does not animate and missing origin does not invent identity', () {
    expect(HermesSubagentStatus.parse('disconnected').isLive, isFalse);
    expect(
      HermesSubagentState.reduce(null, 'subagent.start', {
        'goal': 'same goal',
      }, now: now),
      isNull,
    );
  });
  test(
    'buffered runtime alias merges workers instead of discarding one side',
    () {
      final store = HermesAgenticStateStore(clock: () => now);
      addTearDown(store.close);
      store.applySubagentEvent('runtime', 'subagent.start', {
        'subagent_id': 'a',
      });
      store.applySubagentEvent('stored', 'subagent.start', {
        'subagent_id': 'b',
      });
      store.alias('runtime', 'stored');
      expect(
        store.snapshotFor('stored').subagents.map((w) => w.id),
        unorderedEquals(['a', 'b']),
      );
    },
  );
}
