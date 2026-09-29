enum HermesLiveActivityKind {
  toolStarted,
  toolProgress,
  toolCompleted,
  subagentStarted,
  subagentProgress,
  subagentCompleted,
  review,
  waitingForInput,
  completed,
  failed,
}

final class HermesLiveActivityEvent {
  const HermesLiveActivityEvent({
    required this.sessionId,
    required this.kind,
    required this.title,
    required this.timestamp,
    this.detail,
  });

  final String sessionId;
  final HermesLiveActivityKind kind;
  final String title;
  final DateTime timestamp;

  /// The tool name for tool events, when Hermes reported a safe one.
  final String? detail;

  bool get isTerminal =>
      kind == HermesLiveActivityKind.completed ||
      kind == HermesLiveActivityKind.failed;
}

/// One run out of a session's activity history: the events after the
/// previous run ended, up to and including the end of this one.
final class HermesRunSummary {
  const HermesRunSummary._(this.events, {required this.running});

  /// The latest run in [history]. While [running], that is everything after
  /// the last completed or failed event; afterwards, the events that ended
  /// with it.
  factory HermesRunSummary.latest(
    List<HermesLiveActivityEvent> history, {
    required bool running,
  }) {
    if (history.isEmpty) return HermesRunSummary._(const [], running: running);
    if (running) {
      final start = history.lastIndexWhere((event) => event.isTerminal) + 1;
      return HermesRunSummary._(history.sublist(start), running: true);
    }
    final last = history.lastIndexWhere((event) => event.isTerminal);
    if (last < 0) return HermesRunSummary._(history, running: false);
    final previous = history
        .sublist(0, last)
        .lastIndexWhere((event) => event.isTerminal);
    return HermesRunSummary._(
      history.sublist(previous + 1, last + 1),
      running: false,
    );
  }

  final List<HermesLiveActivityEvent> events;
  final bool running;

  bool get isEmpty => events.isEmpty;

  bool get failed =>
      events.isNotEmpty && events.last.kind == HermesLiveActivityKind.failed;

  bool get completed =>
      events.isNotEmpty && events.last.kind == HermesLiveActivityKind.completed;

  /// Finished tool calls, or started ones when Hermes reported no finish.
  int get steps {
    final done = events
        .where((event) => event.kind == HermesLiveActivityKind.toolCompleted)
        .length;
    return done > 0
        ? done
        : events
              .where(
                (event) => event.kind == HermesLiveActivityKind.toolStarted,
              )
              .length;
  }

  int get subagents => events
      .where((event) => event.kind == HermesLiveActivityKind.subagentStarted)
      .length;

  /// Tool names in first-use order with how often each ran.
  List<({String name, int count})> get tools {
    final counts = <String, int>{};
    for (final event in events) {
      final name = event.detail;
      if (name == null || name.isEmpty) continue;
      if (event.kind == HermesLiveActivityKind.toolStarted) {
        counts[name] = (counts[name] ?? 0) + 1;
      } else if (event.kind == HermesLiveActivityKind.toolCompleted) {
        counts.putIfAbsent(name, () => 1);
      }
    }
    return [
      for (final entry in counts.entries) (name: entry.key, count: entry.value),
    ];
  }

  /// Time from [startedAt] (or the first event) to the last event.
  Duration? elapsed({DateTime? startedAt, DateTime? now}) {
    if (events.isEmpty && startedAt == null) return null;
    final first = events.isEmpty
        ? startedAt!
        : startedAt != null && startedAt.isBefore(events.first.timestamp)
        ? startedAt
        : events.first.timestamp;
    final end = running || events.isEmpty
        ? (now ?? DateTime.now().toUtc())
        : events.last.timestamp;
    final value = end.difference(first);
    return value.isNegative ? Duration.zero : value;
  }
}

/// "42s", "3m 05s", "1h 12m".
String formatHermesRunDuration(Duration value) {
  final seconds = value.inSeconds;
  if (seconds < 60) return '${seconds}s';
  final minutes = value.inMinutes;
  if (minutes < 60) {
    return '${minutes}m ${(seconds % 60).toString().padLeft(2, '0')}s';
  }
  return '${value.inHours}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}
