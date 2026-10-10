import 'package:conduit/features/hermes/services/hermes_activity_presenter.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/services/hermes_live_activity.dart';
import 'package:conduit/features/hermes/widgets/hermes_inline_run_surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thinking_orbs/thinking_orbs.dart';

void main() {
  OrbState select(
    List<HermesLiveActivityEvent> events, {
    bool attention = false,
    HermesDesktopTurnState state = HermesDesktopTurnState.running,
  }) => hermesThinkingOrbState(
    turnState: state,
    attention: attention,
    rows: HermesActivityPresenter.rows(events),
  );
  HermesLiveActivityEvent event(
    String tool, {
    HermesLiveActivityKind kind = HermesLiveActivityKind.toolStarted,
  }) => HermesLiveActivityEvent(
    sessionId: 'session-1',
    kind: kind,
    title: 'Untrusted title mentioning search, writing and browser',
    detail: tool,
    toolId: tool,
    timestamp: DateTime.utc(2026, 10, 10),
  );

  test('all nine modes are reachable from grounded activity', () {
    final modes = {
      select([]),
      select([], attention: true),
      select([], state: HermesDesktopTurnState.reconnecting),
      select([event('web_search')]),
      select([event('execute_code')]),
      select([event('delegate_task')]),
      select([event('write_file')]),
      select([event('todo_list')]),
      select([event('web_search', kind: HermesLiveActivityKind.toolCompleted)]),
    };
    expect(modes, OrbState.values.toSet());
  });

  for (final entry in {
    'read_file': OrbState.searching,
    'search_files': OrbState.searching,
    'web_fetch': OrbState.searching,
    'tool_search': OrbState.searching,
    'spaces_read_page': OrbState.searching,
    'spaces_create_page': OrbState.composing,
    'spaces_edit_page': OrbState.composing,
    'edit_file': OrbState.composing,
    'send_message': OrbState.composing,
    'memory': OrbState.weaving,
    'terminal': OrbState.solving,
    'review': OrbState.solving,
    'image_generate': OrbState.shaping,
    'cronjob': OrbState.shaping,
    'browser_navigate': OrbState.connecting,
    'clarify': OrbState.listening,
    'unknown_tool': OrbState.working,
  }.entries) {
    test('${entry.key} uses ${entry.value.name}', () {
      expect(select([event(entry.key)]), entry.value);
    });
  }

  test('attention and recovery override outstanding tools', () {
    final events = [event('web_search')];
    expect(select(events, attention: true), OrbState.listening);
    expect(
      select(events, state: HermesDesktopTurnState.synchronizing),
      OrbState.connecting,
    );
  });

  test('closed calls no longer claim their tool mode', () {
    expect(
      select([
        event('web_search'),
        event('web_search', kind: HermesLiveActivityKind.toolCompleted),
      ]),
      OrbState.breathing,
    );
  });

  test('most recently opened active tool wins', () {
    expect(
      select([event('web_search'), event('write_file')]),
      OrbState.composing,
    );
  });
}
