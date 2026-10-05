import 'package:flutter/foundation.dart';

import 'hermes_live_activity.dart';

/// How an activity row reads at a glance.
enum HermesActivityRowState { running, done, failed, waiting, note }

/// The family a tool belongs to, for its icon.
enum HermesActivityFamily {
  command,
  code,
  file,
  search,
  web,
  browser,
  plan,
  delegate,
  page,
  memory,
  ask,
  image,
  schedule,
  message,
  tools,
  review,
  other,
}

/// One line of semantic activity: "Searched web · flutter springs · 1.2s".
@immutable
final class HermesActivityRow {
  const HermesActivityRow({
    required this.key,
    required this.verb,
    required this.state,
    required this.family,
    required this.at,
    this.object,
    this.count = 1,
    this.duration,
    this.summary,
    this.toolName,
    this.toolIds = const [],
    this.page,
  });

  /// Stable across rebuilds of the same run.
  final String key;
  final String verb;
  final HermesActivityRowState state;
  final HermesActivityFamily family;
  final DateTime at;
  final String? object;

  /// Adjacent identical successful calls folded into this row.
  final int count;
  final Duration? duration;
  final String? summary;
  final String? toolName;

  /// Every call in this row, oldest first; the inspector opens the last.
  final List<String> toolIds;
  final HermesActivityPageRef? page;

  bool get inspectable => toolIds.isNotEmpty;
  String? get toolId => toolIds.isEmpty ? null : toolIds.last;

  HermesActivityRow _merged(HermesActivityRow next) => HermesActivityRow(
    key: key,
    verb: verb,
    state: next.state,
    family: family,
    at: next.at,
    object: next.object ?? object,
    count: count + next.count,
    duration: duration == null && next.duration == null
        ? null
        : (duration ?? Duration.zero) + (next.duration ?? Duration.zero),
    summary: next.summary ?? summary,
    toolName: toolName,
    toolIds: [...toolIds, ...next.toolIds],
    page: next.page ?? page,
  );
}

/// Turns raw tool events into the words a person would use. Pure, so the
/// chat, the full activity page and Teams all say the same thing.
abstract final class HermesActivityPresenter {
  static const _bridgeCall = 'tool_call';

  /// A deferred tool runs through Hermes' `tool_call` bridge; the row should
  /// name the tool that actually ran.
  static ({String name, Map<String, Object?> args}) unwrap(
    String name,
    Object? args,
  ) {
    final map = args is Map
        ? Map<String, Object?>.from(args)
        : const <String, Object?>{};
    if (name == _bridgeCall) {
      final inner = map['name'];
      final innerArgs = map['arguments'];
      if (inner is String && inner.trim().isNotEmpty) {
        return (
          name: inner.trim(),
          args: innerArgs is Map
              ? Map<String, Object?>.from(innerArgs)
              : const <String, Object?>{},
        );
      }
    }
    return (name: name, args: map);
  }

  static HermesActivityFamily family(String tool) {
    final name = tool.toLowerCase();
    if (name.startsWith('spaces_')) return HermesActivityFamily.page;
    if (name.startsWith('browser') || name.contains('steel')) {
      return HermesActivityFamily.browser;
    }
    return switch (name) {
      'terminal' ||
      'process' ||
      'process_manage' ||
      'shell' => HermesActivityFamily.command,
      'execute_code' || 'code_execution' => HermesActivityFamily.code,
      'read_file' ||
      'write_file' ||
      'patch' ||
      'file_edit' ||
      'edit_file' ||
      'search_files' => HermesActivityFamily.file,
      'web_search' || 'session_search' => HermesActivityFamily.search,
      'web_extract' || 'web_fetch' => HermesActivityFamily.web,
      'todo_list' || 'todo' => HermesActivityFamily.plan,
      'delegate_task' => HermesActivityFamily.delegate,
      'memory' ||
      'skill_view' ||
      'skills_list' ||
      'skill_manage' => HermesActivityFamily.memory,
      'clarify' => HermesActivityFamily.ask,
      'image_generate' || 'vision_analyze' => HermesActivityFamily.image,
      'cronjob' || 'cronjob_manage' => HermesActivityFamily.schedule,
      'send_message' => HermesActivityFamily.message,
      'tool_search' || 'tool_describe' => HermesActivityFamily.tools,
      'review' => HermesActivityFamily.review,
      _ => HermesActivityFamily.other,
    };
  }

  /// "Searched web" once it finished, "Searching web" while it runs.
  static String verb(String tool, {bool running = false}) {
    final name = tool.toLowerCase();
    (String, String)? pair = switch (name) {
      'terminal' || 'shell' => ('Ran command', 'Running command'),
      'process' || 'process_manage' => ('Checked process', 'Checking process'),
      'execute_code' || 'code_execution' => ('Ran code', 'Running code'),
      'read_file' => ('Read file', 'Reading file'),
      'write_file' => ('Wrote file', 'Writing file'),
      'patch' || 'file_edit' || 'edit_file' => ('Edited file', 'Editing file'),
      'search_files' => ('Searched files', 'Searching files'),
      'web_search' => ('Searched web', 'Searching web'),
      'web_extract' || 'web_fetch' => ('Read web page', 'Reading web page'),
      'session_search' => ('Searched past chats', 'Searching past chats'),
      'todo_list' || 'todo' => ('Updated plan', 'Updating plan'),
      'delegate_task' => ('Delegated', 'Delegating'),
      'clarify' => ('Asked you', 'Asking you'),
      'memory' => ('Updated memory', 'Updating memory'),
      'skill_view' || 'skills_list' => ('Opened skill', 'Opening skill'),
      'skill_manage' => ('Updated skill', 'Updating skill'),
      'image_generate' => ('Made image', 'Making image'),
      'vision_analyze' => ('Looked at image', 'Looking at image'),
      'cronjob' || 'cronjob_manage' => ('Scheduled job', 'Scheduling job'),
      'send_message' => ('Sent message', 'Sending message'),
      'spaces_create_page' => ('Created Page', 'Creating Page'),
      'spaces_edit_page' => ('Edited Page', 'Editing Page'),
      'spaces_read_page' => ('Read Page', 'Reading Page'),
      'spaces_list_pages' ||
      'spaces_list_spaces' => ('Looked through Pages', 'Looking through Pages'),
      'tool_search' || 'tool_describe' => ('Found tool', 'Finding tool'),
      'review' => ('Reviewed', 'Reviewing'),
      _ => null,
    };
    if (pair == null && name.startsWith('browser')) {
      pair = ('Browsed', 'Browsing');
    }
    if (pair != null) return running ? pair.$2 : pair.$1;
    final label = _label(tool);
    return running ? 'Using $label' : 'Used $label';
  }

  /// "mcp_github_create_issue" -> "Github create issue".
  static String _label(String tool) {
    var name = tool.trim();
    if (name.startsWith('mcp_')) name = name.substring(4);
    name = name.replaceAll('__', ' ').replaceAll('_', ' ').trim();
    if (name.isEmpty) return 'a tool';
    return name[0].toUpperCase() + name.substring(1);
  }

  /// A short "what" for a call from its own arguments, used when Hermes did
  /// not send a preview.
  static String? objectFromArgs(String tool, Map<String, Object?> args) {
    String? pick(List<String> keys) {
      for (final key in keys) {
        final value = args[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    }

    return switch (tool.toLowerCase()) {
      'terminal' || 'shell' => pick(const ['command', 'cmd']),
      'web_search' ||
      'session_search' ||
      'search_files' ||
      'tool_search' => pick(const ['query', 'pattern', 'q']),
      'read_file' ||
      'write_file' ||
      'patch' ||
      'file_edit' ||
      'edit_file' => pick(const ['path', 'file_path', 'file']),
      'web_extract' ||
      'web_fetch' ||
      'browser_navigate' => pick(const ['url', 'urls']),
      'spaces_create_page' => pick(const ['title']),
      'delegate_task' => pick(const ['goal', 'task']),
      'skill_view' || 'skill_manage' => pick(const ['name']),
      _ => null,
    };
  }

  /// One line, no control characters, nothing that looks like a secret, and
  /// short enough for a row.
  static String? clean(
    String? value, {
    Iterable<String> sensitiveValues = const [],
    int max = 120,
  }) {
    if (value == null) return null;
    var text = value
        .replaceAll(RegExp(r'[\u0000-\u001f\u007f]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    for (final secret in sensitiveValues) {
      if (secret.length >= 4 && text.contains(secret)) {
        text = text.replaceAll(secret, '••••');
      }
    }
    text = text.replaceAll(
      RegExp(r'\b(?:sk|pk|rk|ghp|gho|xox[abpr]|AKIA)[-_A-Za-z0-9]{12,}\b'),
      '••••',
    );
    if (text.isEmpty) return null;
    return text.length > max ? '${text.substring(0, max - 1)}…' : text;
  }

  /// A Page the Spaces tools reported in their result.
  static HermesActivityPageRef? pageFromResult(String tool, Object? result) {
    if (!tool.startsWith('spaces_create_page') &&
        !tool.startsWith('spaces_edit_page')) {
      return null;
    }
    if (result is! Map || result['ok'] != true) return null;
    final page = result['page'];
    if (page is! Map) return null;
    final id = page['id'];
    final space = page['space_id'];
    final title = page['title'];
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (id is! String ||
        space is! String ||
        !uuid.hasMatch(id) ||
        !uuid.hasMatch(space)) {
      return null;
    }
    return (
      pageId: id,
      spaceId: space,
      title: title is String && title.trim().isNotEmpty
          ? (title.trim().length > 160
                ? title.trim().substring(0, 160)
                : title.trim())
          : 'Untitled',
    );
  }

  /// Whether a finished call reported failure in its own result.
  static bool resultFailed(Object? result) {
    if (result is! Map) return false;
    if (result['ok'] == false || result['success'] == false) return true;
    final error = result['error'];
    return error is String && error.trim().isNotEmpty;
  }

  /// The rows for one run, oldest first: starts paired with their finish,
  /// then adjacent identical successes folded together. Failures, waits,
  /// plan changes and delegate lifecycle are never folded.
  ///
  /// Only a start opens a row. `tool.generating` (the model is still writing
  /// the call, under its raw name and without an id) and `tool.progress`
  /// only add detail to a row that is already open. Once the run is no
  /// longer [running], a row it never closed is shown as finished.
  static List<HermesActivityRow> rows(
    List<HermesLiveActivityEvent> events, {
    bool running = true,
  }) {
    final rows = <HermesActivityRow>[];
    final byTool = <String, int>{};
    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      final tool = event.detail;
      switch (event.kind) {
        case HermesLiveActivityKind.toolProgress:
          final id = event.toolId;
          final open = id != null
              ? byTool[id]
              : rows.lastIndexWhere(
                  (row) =>
                      row.state == HermesActivityRowState.running &&
                      row.toolName == tool,
                );
          if (open == null || open < 0 || event.preview == null) continue;
          final row = rows[open];
          if (row.object == null) {
            rows[open] = HermesActivityRow(
              key: row.key,
              verb: row.verb,
              state: row.state,
              family: row.family,
              at: row.at,
              object: event.preview,
              toolName: row.toolName,
              toolIds: row.toolIds,
            );
          }
        case HermesLiveActivityKind.toolStarted:
          final id = event.toolId;
          final existing = id == null ? null : byTool[id];
          if (existing != null) {
            final row = rows[existing];
            if (row.object == null && event.preview != null) {
              rows[existing] = HermesActivityRow(
                key: row.key,
                verb: row.verb,
                state: row.state,
                family: row.family,
                at: row.at,
                object: event.preview,
                toolName: row.toolName,
                toolIds: row.toolIds,
              );
            }
            continue;
          }
          final name = tool ?? 'tool';
          rows.add(
            HermesActivityRow(
              key: id ?? 'e$index',
              verb: verb(name, running: true),
              state: HermesActivityRowState.running,
              family: family(name),
              at: event.timestamp,
              object: event.preview,
              toolName: tool,
              toolIds: [?id],
            ),
          );
          if (id != null) byTool[id] = rows.length - 1;
        case HermesLiveActivityKind.toolCompleted:
          final name = tool ?? 'tool';
          final id = event.toolId;
          final existing = id == null ? null : byTool[id];
          final started = existing == null ? null : rows[existing];
          final finished = HermesActivityRow(
            key: started?.key ?? id ?? 'e$index',
            verb: verb(name),
            state: event.failed
                ? HermesActivityRowState.failed
                : HermesActivityRowState.done,
            family: family(name),
            at: started?.at ?? event.timestamp,
            object: started?.object ?? event.preview,
            duration: event.duration,
            summary: event.summary,
            toolName: tool,
            toolIds: [?id],
            page: event.page,
          );
          if (existing != null) {
            rows[existing] = finished;
          } else {
            // Its start was missed (opened mid-run): close the newest
            // running row for the same tool, else add the finish on its own.
            final open = rows.lastIndexWhere(
              (row) =>
                  row.state == HermesActivityRowState.running &&
                  row.toolName == tool &&
                  row.toolIds.isEmpty,
            );
            if (open >= 0) {
              rows[open] = finished;
            } else {
              rows.add(finished);
            }
          }
        case HermesLiveActivityKind.subagentStarted:
        case HermesLiveActivityKind.subagentCompleted:
          rows.add(
            HermesActivityRow(
              key: 'e$index',
              verb: event.kind == HermesLiveActivityKind.subagentStarted
                  ? 'Started a delegate'
                  : 'Delegate finished',
              state: event.failed
                  ? HermesActivityRowState.failed
                  : HermesActivityRowState.note,
              family: HermesActivityFamily.delegate,
              at: event.timestamp,
              object: event.preview,
            ),
          );
        case HermesLiveActivityKind.subagentProgress:
          break;
        case HermesLiveActivityKind.review:
          rows.add(
            HermesActivityRow(
              key: 'e$index',
              verb: 'Review ready',
              state: HermesActivityRowState.note,
              family: HermesActivityFamily.review,
              at: event.timestamp,
              object: event.preview,
            ),
          );
        case HermesLiveActivityKind.waitingForInput:
          rows.add(
            HermesActivityRow(
              key: 'e$index',
              verb: 'Waiting for you',
              state: HermesActivityRowState.waiting,
              family: HermesActivityFamily.ask,
              at: event.timestamp,
            ),
          );
        case HermesLiveActivityKind.failed:
          rows.add(
            HermesActivityRow(
              key: 'e$index',
              verb: 'Run failed',
              state: HermesActivityRowState.failed,
              family: HermesActivityFamily.other,
              at: event.timestamp,
              object: event.preview,
            ),
          );
        case HermesLiveActivityKind.completed:
          break;
      }
    }
    if (!running) {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row.state != HermesActivityRowState.running) continue;
        final name = row.toolName ?? 'tool';
        rows[i] = HermesActivityRow(
          key: row.key,
          verb: verb(name),
          state: HermesActivityRowState.done,
          family: row.family,
          at: row.at,
          object: row.object,
          toolName: row.toolName,
          toolIds: row.toolIds,
          page: row.page,
        );
      }
    }
    return _fold(rows);
  }

  static bool _foldable(HermesActivityRow row) =>
      row.state == HermesActivityRowState.done &&
      row.page == null &&
      row.family != HermesActivityFamily.plan &&
      row.family != HermesActivityFamily.delegate &&
      row.family != HermesActivityFamily.ask;

  static List<HermesActivityRow> _fold(List<HermesActivityRow> rows) {
    final out = <HermesActivityRow>[];
    for (final row in rows) {
      final last = out.isEmpty ? null : out.last;
      if (last != null &&
          _foldable(last) &&
          _foldable(row) &&
          last.toolName == row.toolName &&
          last.verb == row.verb) {
        out[out.length - 1] = last._merged(row);
      } else {
        out.add(row);
      }
    }
    return out;
  }

  /// The newest [visible] rows and how many earlier ones are folded away.
  static ({List<HermesActivityRow> rows, int earlier}) recent(
    List<HermesActivityRow> rows, {
    int visible = 6,
  }) => rows.length <= visible
      ? (rows: rows, earlier: 0)
      : (
          rows: rows.sublist(rows.length - visible),
          earlier: rows.length - visible,
        );

  /// Up to [limit] tools that say what a finished run did, in first-use
  /// order. Finding tools, opening skills and keeping the plan are how it
  /// worked, not what it did: they only count when it did nothing else.
  static List<String> headline(
    List<({String name, int count})> tools, {
    int limit = 2,
  }) {
    bool housekeeping(String tool) => switch (family(tool)) {
      HermesActivityFamily.tools ||
      HermesActivityFamily.plan ||
      HermesActivityFamily.memory => true,
      _ => false,
    };
    final work = [
      for (final tool in tools)
        if (!housekeeping(tool.name)) tool.name,
    ];
    return (work.isEmpty ? [for (final tool in tools) tool.name] : work)
        .take(limit)
        .toList(growable: false);
  }

  /// The present-tense line for the run's header: what it is doing now.
  static String? now(List<HermesActivityRow> rows) {
    for (final row in rows.reversed) {
      if (row.state == HermesActivityRowState.running) {
        return row.object == null ? row.verb : '${row.verb} · ${row.object}';
      }
      if (row.state == HermesActivityRowState.waiting) return row.verb;
      break;
    }
    return null;
  }

  /// "1.2s", "42s", "3m 05s".
  static String formatDuration(Duration value) {
    final ms = value.inMilliseconds;
    if (ms < 1000) return '${(ms / 1000).toStringAsFixed(1)}s';
    if (ms < 10000) return '${(ms / 1000).toStringAsFixed(1)}s';
    final seconds = value.inSeconds;
    if (seconds < 60) return '${seconds}s';
    return '${value.inMinutes}m ${(seconds % 60).toString().padLeft(2, '0')}s';
  }
}
