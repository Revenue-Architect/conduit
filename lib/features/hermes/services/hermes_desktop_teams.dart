part of 'hermes_desktop_api_service.dart';

/// Hermes Group Chat (`groups.*`) over the Desktop connection. Hermes owns
/// the rooms and runs the discussion; nothing here schedules bot turns.
extension _HermesDesktopTeams on HermesDesktopApiService {
  static const _timeout = Duration(seconds: 30);

  Future<Map<String, dynamic>> _teams(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    await _ensureConnected();
    return _object(
      await _rpc.request<Object?>(method, params: params, timeout: _timeout),
    );
  }

  Future<Map<String, dynamic>> _teamCapabilities() =>
      _teams('groups.capabilities');

  Future<List<HermesTeam>> _listTeams() async {
    final result = await _teams('groups.list', const {'limit': 100});
    final rooms = result['rooms'];
    if (rooms is! List) return const [];
    final teams = <HermesTeam>[
      for (final row in rooms.take(100))
        if (HermesTeam.fromJson(row) case final team? when !team.disbanded)
          team,
    ];
    final epoch = DateTime.utc(1970);
    teams.sort(
      (a, b) => (b.updatedAt ?? epoch).compareTo(a.updatedAt ?? epoch),
    );
    return teams;
  }

  Future<HermesTeam> _createTeam({
    required String name,
    required List<Map<String, Object?>> members,
  }) async {
    final result = await _teams('groups.create', {
      'room_id': newHermesTeamId('team'),
      'name': name,
      'members': members,
    });
    final team = HermesTeam.fromJson(result['room']);
    if (team == null) {
      throw StateError('Hermes did not return the new team.');
    }
    return team;
  }

  Future<({HermesTeam team, HermesTeamStatus status})> _teamState(
    String roomId,
  ) async {
    _requireTeamId(roomId);
    final result = await _teams('groups.state', {'room_id': roomId});
    final team = HermesTeam.fromJson(result['room']);
    if (team == null) throw StateError('Hermes did not return the team.');
    return (
      team: team,
      status: HermesTeamStatus.fromJson(result['driver_status']),
    );
  }

  Future<({List<HermesTeamEvent> events, int cursor, bool hasMore})> _teamLog(
    String roomId, {
    int sinceSeq = 0,
    int limit = 200,
  }) async {
    _requireTeamId(roomId);
    final result = await _teams('groups.log', {
      'room_id': roomId,
      'since_seq': sinceSeq,
      'limit': limit,
    });
    final rows = result['events'];
    final events = <HermesTeamEvent>[
      if (rows is List)
        for (final row in rows.take(500))
          if (HermesTeamEvent.fromJson(row) case final event?) event,
    ];
    final cursor = result['cursor'];
    return (
      events: events,
      cursor: cursor is num
          ? cursor.toInt()
          : events.isEmpty
          ? sinceSeq
          : events.last.seq,
      hasMore: result['has_more'] == true,
    );
  }

  /// Hermes accepts exactly `{text, thread_id}` for a user message and keeps
  /// one discussion history per thread. The room is one conversation, so its
  /// own id is the thread: every message continues the same discussion.
  Future<void> _sendToTeam(String roomId, String text) async {
    _requireTeamId(roomId);
    await _teams('groups.send', {
      'room_id': roomId,
      'event_id': newHermesTeamId('u'),
      'payload': {'text': text, 'thread_id': roomId},
    });
  }

  Future<void> _stopTeam(String roomId) async {
    _requireTeamId(roomId);
    await _teams('groups.stop', {'room_id': roomId});
  }

  Future<void> _answerTeamApproval(
    String roomId,
    HermesTeamApproval approval, {
    required bool allow,
  }) async {
    _requireTeamId(roomId);
    await _teams('groups.approve', {
      'room_id': roomId,
      'member_id': approval.memberId,
      'task_id': approval.taskId,
      'execution_generation': approval.executionGeneration,
      'choice': allow ? 'once' : 'deny',
      'request_id': approval.requestId,
    });
  }

  Future<void> _retryTeamTask(String roomId, String taskId) async {
    _requireTeamId(roomId);
    await _teams('groups.retry', {'room_id': roomId, 'task_id': taskId});
  }

  Future<void> _disbandTeam(String roomId) async {
    _requireTeamId(roomId);
    await _teams('groups.disband', {'room_id': roomId});
  }

  void _requireTeamId(String roomId) {
    if (!isValidHermesTeamId(roomId)) {
      throw ArgumentError.value(roomId, 'roomId');
    }
  }
}
