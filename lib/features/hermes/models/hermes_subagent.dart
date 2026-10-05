import 'package:flutter/foundation.dart';

/// A delegated worker's lifecycle, as Hermes' `subagent.*` events report it.
enum HermesSubagentStatus {
  queued,
  running,
  completed,
  failed,
  interrupted,
  timeout,
  unknown;

  bool get isTerminal => switch (this) {
    completed || failed || interrupted || timeout => true,
    queued || running || unknown => false,
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
    }
    if (terminalEvent) return HermesSubagentStatus.failed;
    return value == 'queued'
        ? HermesSubagentStatus.queued
        : HermesSubagentStatus.running;
  }
}

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

  /// The latest thing it reported, for a one-line glance.
  String? get latest => lines.isEmpty ? null : lines.last.text;

  /// The id Hermes uses for steering, or null for a placeholder row that
  /// only has a derived id.
  String? get steerableId => id.startsWith('~') ? null : id;

  /// Applies one `subagent.*` event. A finished worker stays finished: late
  /// progress for it is ignored.
  static HermesSubagentState? reduce(
    HermesSubagentState? previous,
    String type,
    Map<String, Object?> payload, {
    required DateTime now,
    Iterable<String> sensitiveValues = const [],
  }) {
    if (previous != null && previous.status.isTerminal) return previous;
    String text(Object? value, [int max = _previewCharacters]) =>
        _compact(_redact(value is String ? value : '', sensitiveValues), max);
    final id = _id(payload) ?? previous?.id;
    if (id == null) return null;
    final terminal = type == 'subagent.complete';
    final status = switch (type) {
      'subagent.spawn_requested' when payload['status'] == null =>
        HermesSubagentStatus.queued,
      _ => HermesSubagentStatus.parse(
        payload['status'],
        terminalEvent: terminal,
      ),
    };
    final tool = text(payload['tool_name'], 64);
    final preview = text(payload['tool_preview']).isNotEmpty
        ? text(payload['tool_preview'])
        : text(payload['text']);
    final added = <HermesSubagentLine>[
      for (final tail in _tail(payload['output_tail']))
        (
          text: tail.tool == null
              ? text(tail.preview)
              : _toolLine(tail.tool!, text(tail.preview, 96)),
          tool: tail.tool != null,
          error: tail.error,
        ),
      if (tool.isNotEmpty)
        (
          text: _toolLine(
            tool,
            preview.length > 96 ? '${preview.substring(0, 95)}…' : preview,
          ),
          tool: true,
          error: payload['error'] != null,
        ),
      if ((type == 'subagent.progress' || type == 'subagent.thinking') &&
          tool.isEmpty &&
          preview.isNotEmpty)
        (text: preview, tool: false, error: payload['error'] != null),
    ];
    final seconds = _double(payload['duration_seconds']);
    final rawSummary = text(payload['summary']).isNotEmpty
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
      startedAt: previous?.startedAt ?? now,
      updatedAt: now,
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
    );
  }

  static String? _id(Map<String, Object?> payload) {
    final id = _string(payload['subagent_id'], 128);
    if (id != null) return id;
    final goal = _string(payload['goal'], 400);
    if (goal == null) return null;
    return '~${_string(payload['parent_id'], 128) ?? 'root'}:'
        '${_int(payload['task_index']) ?? 0}:${goal.hashCode}';
  }

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
    var out = value;
    for (final secret in secrets) {
      if (secret.length >= 4 && out.contains(secret)) {
        out = out.replaceAll(secret, '••••');
      }
    }
    return out;
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
