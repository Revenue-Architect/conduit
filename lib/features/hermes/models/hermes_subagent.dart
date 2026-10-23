import 'package:flutter/foundation.dart';

/// A delegated worker's lifecycle, as Hermes' `subagent.*` events report it.
enum HermesSubagentStatus {
  queued,
  running,
  waiting,
  completed,
  failed,
  interrupted,
  timeout,
  unknown;

  bool get isTerminal => switch (this) {
    completed || failed || interrupted || timeout => true,
    queued || running || waiting || unknown => false,
  };

  bool get isLive => this == queued || this == running;

  bool get isProblem => this == failed || this == timeout;

  /// [terminalEvent]: a `subagent.complete` is terminal by definition, so a
  /// missing or still-active status there fails closed instead of leaving a
  /// finished worker spinning forever.
  static HermesSubagentStatus parse(
    Object? value, {
    bool terminalEvent = false,
  }) {
    switch (value) {
      case 'completed' || 'complete' || 'success' || 'done':
        return HermesSubagentStatus.completed;
      case 'failed' || 'error':
        return HermesSubagentStatus.failed;
      case 'interrupted' || 'cancelled' || 'canceled':
        return HermesSubagentStatus.interrupted;
      case 'timeout' || 'timed_out':
        return HermesSubagentStatus.timeout;
      case 'waiting' || 'blocked' || 'waiting_for_approval':
        return HermesSubagentStatus.waiting;
      case 'unknown' || 'disconnected' || 'unavailable':
        return HermesSubagentStatus.unknown;
    }
    if (terminalEvent) return HermesSubagentStatus.failed;
    return switch (value) {
      'queued' || 'pending' => HermesSubagentStatus.queued,
      'running' ||
      'working' ||
      'started' ||
      null => HermesSubagentStatus.running,
      _ => HermesSubagentStatus.unknown,
    };
  }
}

enum HermesDelegationKind { native, specialist, kanban }

/// One line of what a worker did, newest last.
typedef HermesSubagentLine = ({String text, bool tool, bool error});

/// Everything Conduit knows about one delegated worker. Built only from what
/// Hermes reported: no invented progress, no guessed durations.
@immutable
final class HermesSubagentState {
  const HermesSubagentState({
    required this.id,
    required this.goal,
    required this.status,
    required this.startedAt,
    required this.updatedAt,
    this.parentId,
    this.childSessionId,
    this.model,
    this.taskIndex = 0,
    this.taskCount = 1,
    this.depth = 0,
    this.toolCount,
    this.currentTool,
    this.summary,
    this.durationSeconds,
    this.inputTokens,
    this.outputTokens,
    this.filesRead = 0,
    this.filesWritten = 0,
    this.lines = const [],
    this.kind = HermesDelegationKind.native,
    this.parentSessionId,
    this.parentTurnId,
    this.parentMessageId,
    this.parentProfile,
    this.childProfile,
    this.sourceToolCallId,
    this.taskId,
    this.runId,
    this.name,
    this.artifacts = const [],
    this.reportedStart = false,
    this.nativeControlId,
    this.boardSlug,
  });

  static const int maxLines = 24;
  static const int _previewCharacters = 220;

  final String id;
  final String goal;
  final HermesSubagentStatus status;
  final DateTime startedAt;
  final DateTime updatedAt;
  final String? parentId;
  final String? childSessionId;
  final String? model;
  final int taskIndex;
  final int taskCount;
  final int depth;
  final int? toolCount;

  /// The tool it is running now; cleared once it finishes.
  final String? currentTool;
  final String? summary;

  /// Hermes' own measurement, when it sent one.
  final double? durationSeconds;
  final int? inputTokens;
  final int? outputTokens;
  final int filesRead;
  final int filesWritten;
  final List<HermesSubagentLine> lines;
  final HermesDelegationKind kind;
  final String? parentSessionId;
  final String? parentTurnId;
  final String? parentMessageId;
  final String? parentProfile;
  final String? childProfile;
  final String? sourceToolCallId;
  final String? taskId;
  final String? runId;
  final String? name;
  final List<String> artifacts;
  final bool reportedStart;
  final String? nativeControlId;
  final String? boardSlug;

  String get displayName => name ?? childProfile ?? 'Delegate';
  bool get supportsNativeControl => kind == HermesDelegationKind.native;

  /// The latest thing it reported, for a one-line glance.
  String? get latest => lines.isEmpty ? null : lines.last.text;

  /// The id Hermes uses for steering, or null for a placeholder row that
  /// only has a derived id.
  String? get steerableId => !supportsNativeControl
      ? null
      : nativeControlId ?? (id.startsWith('~') ? null : id);

  /// Applies one `subagent.*` event. A finished worker stays finished: late
  /// progress for it is ignored.
  static HermesSubagentState? reduce(
    HermesSubagentState? previous,
    String type,
    Map<String, Object?> payload, {
    required DateTime now,
    Iterable<String> sensitiveValues = const [],
  }) {
    final settled = previous?.status.isTerminal ?? false;
    String text(Object? value, [int max = _previewCharacters]) =>
        _compact(_redact(value is String ? value : '', sensitiveValues), max);
    final id = previous?.id ?? _id(payload);
    if (id == null) return null;
    final terminal = type.endsWith('.complete') || type.endsWith('.completed');
    final status = settled
        ? previous!.status
        : switch (type) {
            'subagent.spawn_requested' when payload['status'] == null =>
              HermesSubagentStatus.queued,
            _ => HermesSubagentStatus.parse(
              payload['status'],
              terminalEvent: terminal,
            ),
          };
    final tool = settled ? '' : text(payload['tool_name'], 64);
    // Tool arguments, raw outputs and thinking are not a public activity feed.
    final preview = text(payload['status_summary']);
    final added = <HermesSubagentLine>[
      for (final tail
          in settled
              ? const <({String? tool, String preview, bool error})>[]
              : _tail(payload['output_tail']))
        (
          text: tail.tool == null ? '' : _toolLine(tail.tool!, ''),
          tool: tail.tool != null,
          error: tail.error,
        ),
      if (tool.isNotEmpty)
        (
          text: _toolLine(tool, ''),
          tool: true,
          error: payload['error'] != null,
        ),
      if (!settled &&
          type.endsWith('.progress') &&
          tool.isEmpty &&
          preview.isNotEmpty)
        (text: preview, tool: false, error: payload['error'] != null),
    ];
    final seconds = _double(payload['duration_seconds']);
    final rawSummary = settled
        ? ''
        : text(payload['summary']).isNotEmpty
        ? text(payload['summary'])
        : status == HermesSubagentStatus.timeout
        ? 'Timed out after ${seconds?.round() ?? '?'}s'
        : terminal
        ? text(payload['text'])
        : '';
    var lines = previous?.lines ?? const <HermesSubagentLine>[];
    for (final line in added) {
      if (line.text.isEmpty) continue;
      final last = lines.isEmpty ? null : lines.last;
      if (last != null && last.text == line.text && last.error == line.error) {
        continue;
      }
      lines = [...lines, line];
    }
    if (lines.length > maxLines) lines = lines.sublist(lines.length - maxLines);
    final goal = text(payload['goal'], 400);
    return HermesSubagentState(
      id: id,
      goal: goal.isNotEmpty ? goal : previous?.goal ?? 'Delegated task',
      status: status,
      startedAt:
          previous?.startedAt ??
          _time(payload['started_at']) ??
          _time(payload['timestamp']) ??
          now,
      updatedAt: settled
          ? previous!.updatedAt
          : _time(payload['updated_at']) ?? _time(payload['timestamp']) ?? now,
      parentId: _string(payload['parent_id']) ?? previous?.parentId,
      childSessionId:
          _string(payload['child_session_id']) ?? previous?.childSessionId,
      model: _string(payload['model'], 128) ?? previous?.model,
      taskIndex: _int(payload['task_index']) ?? previous?.taskIndex ?? 0,
      taskCount: _int(payload['task_count']) ?? previous?.taskCount ?? 1,
      depth: _int(payload['depth']) ?? previous?.depth ?? 0,
      toolCount: _int(payload['tool_count']) ?? previous?.toolCount,
      currentTool: status.isTerminal
          ? null
          : (tool.isNotEmpty ? tool : previous?.currentTool),
      summary: rawSummary.isNotEmpty ? rawSummary : previous?.summary,
      durationSeconds: seconds ?? previous?.durationSeconds,
      inputTokens: _int(payload['input_tokens']) ?? previous?.inputTokens,
      outputTokens: _int(payload['output_tokens']) ?? previous?.outputTokens,
      filesRead: _count(payload['files_read']) ?? previous?.filesRead ?? 0,
      filesWritten:
          _count(payload['files_written']) ?? previous?.filesWritten ?? 0,
      lines: lines,
      kind:
          previous?.kind ??
          switch (payload['worker_kind'] ?? payload['kind']) {
            'specialist' => HermesDelegationKind.specialist,
            'kanban' => HermesDelegationKind.kanban,
            _ => HermesDelegationKind.native,
          },
      parentSessionId:
          previous?.parentSessionId ?? _string(payload['parent_session_id']),
      parentTurnId:
          previous?.parentTurnId ?? _string(payload['parent_turn_id']),
      parentMessageId:
          previous?.parentMessageId ?? _string(payload['parent_message_id']),
      parentProfile:
          previous?.parentProfile ?? _string(payload['parent_profile']),
      childProfile: previous?.childProfile ?? _string(payload['child_profile']),
      sourceToolCallId:
          previous?.sourceToolCallId ?? _string(payload['source_tool_call_id']),
      taskId: _string(payload['task_id']) ?? previous?.taskId,
      runId: _string(payload['run_id']) ?? previous?.runId,
      boardSlug: _string(payload['board_slug']) ?? previous?.boardSlug,
      name: _string(payload['name'], 128) ?? previous?.name,
      artifacts: payload['artifacts'] is List
          ? List.unmodifiable(
              (payload['artifacts'] as List)
                  .whereType<String>()
                  .where((v) => v.length <= 2048)
                  .take(12),
            )
          : previous?.artifacts ?? const [],
      reportedStart:
          previous?.reportedStart == true ||
          _time(payload['started_at']) != null ||
          _time(payload['timestamp']) != null,
      nativeControlId:
          _string(payload['subagent_id']) ?? previous?.nativeControlId,
    );
  }

  static String? _id(Map<String, Object?> payload) {
    // A delegation may be a batch: each native child has its own subagent id.
    final id =
        _string(payload['subagent_id'], 128) ??
        _string(payload['delegation_id'], 256);
    if (id != null) return id;
    final call = _string(payload['source_tool_call_id']);
    if (call == null) return null;
    return '~${_string(payload['parent_turn_id']) ?? 'turn'}:$call:${_int(payload['task_index']) ?? 0}';
  }

  static DateTime? _time(Object? value) => switch (value) {
    final num seconds when seconds.isFinite && seconds > 0 =>
      DateTime.fromMillisecondsSinceEpoch(
        (seconds * 1000).round(),
        isUtc: true,
      ),
    final String text => DateTime.tryParse(text),
    _ => null,
  };

  static String _toolLine(String tool, String preview) {
    final label = tool
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
    return preview.isEmpty ? label : '$label · $preview';
  }

  static Iterable<({String? tool, String preview, bool error})> _tail(
    Object? value,
  ) sync* {
    if (value is! List) return;
    for (final row in value.take(8)) {
      if (row is! Map) continue;
      final tool = row['tool'];
      final preview = row['preview'];
      yield (
        tool: tool is String && tool.trim().isNotEmpty ? tool.trim() : null,
        preview: preview is String ? preview : '',
        error: row['is_error'] == true,
      );
    }
  }

  static String _compact(String value, int max) {
    final line = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.length > max ? '${line.substring(0, max - 1)}…' : line;
  }

  static String _redact(String value, Iterable<String> secrets) {
    var out = value.replaceAll(
      RegExp(
        r'<(?:think|thinking|analysis)>.*?(?:</(?:think|thinking|analysis)>|$)',
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    );
    for (final secret in secrets) {
      if (secret.length >= 4 && out.contains(secret)) {
        out = out.replaceAll(secret, '••••');
      }
    }
    return out.replaceAll(
      RegExp(
        r'\b(?:sk-[\w-]{12,}|Bearer\s+[\w.=-]{12,}|(?:api[_-]?key|token|password|secret)\s*[:=]\s*\S+)',
        caseSensitive: false,
      ),
      '[redacted]',
    );
  }

  static String? _string(Object? value, [int max = 256]) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > max) return null;
    return trimmed;
  }

  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final double number when number.isFinite => number.round(),
    _ => null,
  };

  static double? _double(Object? value) => switch (value) {
    final num number when number.isFinite && number >= 0 => number.toDouble(),
    _ => null,
  };

  static int? _count(Object? value) => value is List ? value.length : null;
}

/// A session's workers at a glance.
extension HermesSubagentRoster on Iterable<HermesSubagentState> {
  int get live => where((worker) => worker.status.isLive).length;
  int get problems => where((worker) => worker.status.isProblem).length;
  int get finished => where((worker) => worker.status.isTerminal).length;
}
