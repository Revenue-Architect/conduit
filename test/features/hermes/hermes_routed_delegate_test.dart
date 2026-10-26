import 'package:flutter_test/flutter_test.dart';
import 'package:conduit/features/hermes/services/hermes_agentic_state.dart';
import 'package:conduit/features/hermes/services/hermes_inline_ui_capability.dart';

void main() {
  final now = DateTime.utc(2026, 10, 24);

  test(
    'a returned background delegation is a notice, not an owner message',
    () {
      expect(
        hermesIsDelegationResultNotice(
          '[ASYNC DELEGATION BATCH COMPLETE — deleg_6b8f3a3d]\nA background…',
        ),
        isTrue,
      );
      expect(hermesIsDelegationResultNotice('Ask scout for a PONG'), isFalse);
      expect(
        hermesIsDelegationResultNotice('Why does [ASYNC DELEGATION show up?'),
        isFalse,
      );
    },
  );

  test('a turn Hermes started itself is not shown as the owner speaking', () {
    for (final text in [
      '[Cronjob "initiative-engine" output — scheduled job, not the user. Review it…',
      '[kanban] Task t_63502ffe completed.\nTitle: NetSuite wording',
      '[Umbrel incident from the hourly selftest, not the user. Investigate…',
    ]) {
      expect(hermesIsAutomationTurn(text), isTrue, reason: text);
    }
    expect(
      hermesIsAutomationTurn('Why did the [Cronjob "x" output appear?'),
      isFalse,
    );
    expect(hermesIsAutomationTurn('[kanban] is my board name'), isFalse);
    // A returned delegation continues its answer; it is a separate notice.
    expect(
      hermesIsAutomationTurn('[ASYNC DELEGATION BATCH COMPLETE — d]'),
      isFalse,
    );
  });

  test('the compaction handoff is a marker, not the owner speaking', () {
    expect(
      hermesIsCompactionHandoff(
        '[CONTEXT COMPACTION — REFERENCE ONLY] Earlier turns were compacted…',
      ),
      isTrue,
    );
    expect(hermesIsCompactionHandoff('What is [CONTEXT COMPACTION]?'), isFalse);
  });

  test('a profile-routed native worker takes its name from the projection', () {
    final store = HermesAgenticStateStore(clock: () => now);
    // Live events only know the parent's profile.
    store.applySubagentEvent('p', 'subagent.complete', {
      'subagent_id': 'sa-0-1e0dab43',
      'status': 'completed',
      'goal': 'Reply with PONG',
      'parent_session_id': 'p',
      'parent_profile': 'default',
      'child_profile': 'default',
    });
    // The server projection names the profile it ran as.
    store.applySubagentEvent('p', 'delegation.complete', {
      'delegation_id': 'sa-0-1e0dab43',
      'subagent_id': 'sa-0-1e0dab43',
      'worker_kind': 'native',
      'parent_session_id': 'p',
      'parent_profile': 'default',
      'child_profile': 'default',
      'name': 'scout',
      'child_session_id': 'child-1',
      'status': 'completed',
    });
    final workers = store.snapshotFor('p').subagents;
    expect(workers, hasLength(1));
    expect(workers.single.displayName, 'scout');
    expect(workers.single.childSessionId, 'child-1');
    expect(workers.single.childProfile, 'default');
  });
}
