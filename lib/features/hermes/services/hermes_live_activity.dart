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
  });

  final String sessionId;
  final HermesLiveActivityKind kind;
  final String title;
  final DateTime timestamp;
}
