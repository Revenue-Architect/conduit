part of 'hermes_desktop_api_service.dart';

/// The models a chat can switch to: its profile's connected providers.
final class HermesModelCatalog {
  const HermesModelCatalog({
    required this.options,
    this.currentModel,
    this.currentProvider,
    this.providerNames = const {},
  });

  final List<HermesDesktopModelOption> options;

  /// Provider slug -> the name Hermes shows for it ("OpenAI Codex").
  final Map<String, String> providerNames;

  String providerLabel(String slug) => providerNames[slug] ?? slug;

  /// What the profile (or the live session) runs on now.
  final String? currentModel;
  final String? currentProvider;
}

/// How a model switch landed.
enum HermesModelSwitchOutcome {
  /// The session runs on it from now on.
  applied,

  /// A reply is streaming; Hermes switches when the next one starts.
  nextTurn,

  /// Kept for this chat; it is applied when the chat first sends.
  pending,
}

/// What one team member is doing in its room session, read from Hermes'
/// live session list and its replay buffer. Read-only: Conduit never
/// resumes, steers or interrupts a room's sessions.
@immutable
final class HermesTeamMemberLive {
  const HermesTeamMemberLive({
    required this.profile,
    required this.status,
    this.preview,
    this.thinking,
    this.activity = const [],
    this.todo,
  });

  final String profile;

  /// `working`, `waiting`, `starting` or `idle`.
  final String status;

  /// The reply as it is being written (Hermes caps it at 160 characters).
  final String? preview;

  /// The latest reasoning Hermes surfaced, when the profile shows it.
  final String? thinking;

  /// This turn's tool activity, oldest first.
  final List<HermesLiveActivityEvent> activity;
  final HermesTodoSnapshot? todo;

  bool get working =>
      status == 'working' || status == 'starting' || status == 'waiting';
}

/// A session that is live on this Hermes right now, from any client or
/// profile (a chat, a scheduled run, another device).
@immutable
final class HermesLiveSession {
  const HermesLiveSession({
    required this.runtimeId,
    required this.storedId,
    required this.title,
    required this.status,
    this.preview,
    this.model,
    this.lastActive,
  });

  final String runtimeId;
  final String storedId;
  final String title;

  /// `working`, `waiting` (needs the user), `starting` or `idle`.
  final String status;
  final String? preview;
  final String? model;
  final DateTime? lastActive;

  bool get needsYou => status == 'waiting';
  bool get working => status == 'working' || status == 'starting';

  /// Needs you first, then working, then starting, newest first within.
  int get rank => switch (status) {
    'waiting' => 0,
    'working' => 1,
    'starting' => 2,
    _ => 3,
  };
}

final class _RoomSessionCursor {
  _RoomSessionCursor(this.storedId);

  final String storedId;
  String? runtimeId;
  int lastSeen = 0;
  String? epoch;
  final List<HermesLiveActivityEvent> activity = [];
  String? thinking;
  HermesTodoSnapshot? todo;
}

extension _HermesDesktopAgentic on HermesDesktopApiService {
  // -- models -----------------------------------------------------------------

  Future<HermesModelCatalog> _modelCatalog({
    String? storedId,
    String? profile,
  }) async {
    await _ensureConnected();
    final binding = storedId == null ? null : _bindings[storedId];
    final live =
        binding != null &&
        _bindingSocketGenerations[storedId] == _rpc.socketGeneration;
    final scope = storedId != null
        ? _sessionScope(storedId)
        : {'profile': profile ?? config.desktopProfile};
    final result = _object(
      await _rpc.request<Object?>(
        'model.options',
        params: {
          'explicit_only': true,
          // Probe configured proxies (including LiteLLM), not just the
          // cache-only row that can contain only the profile's current model.
          'refresh': true,
          if (live) 'session_id': binding.runtimeId,
          ...scope,
        },
        timeout: const Duration(seconds: 20),
      ),
    );
    final options = parseHermesDesktopConfiguredModels(result)
        .map(HermesDesktopModelOption.fromJson)
        .where((model) => model.id.isNotEmpty)
        .take(1000)
        .toList(growable: false);
    final names = <String, String>{};
    final providers = result['providers'];
    if (providers is List) {
      for (final raw in providers.take(200)) {
        if (raw is! Map) continue;
        final slug = validateHermesBoundedString(
          raw['slug'],
          maxCharacters: 128,
        );
        final name = validateHermesBoundedString(
          raw['name'],
          maxCharacters: 80,
        );
        if (slug != null && name != null) names[slug] = name;
      }
    }
    return HermesModelCatalog(
      options: options,
      providerNames: names,
      currentModel: validateHermesBoundedString(
        result['model'],
        maxCharacters: 512,
      ),
      currentProvider: validateHermesBoundedString(
        result['provider'],
        maxCharacters: 128,
      ),
    );
  }

  /// Switches [storedId] to [choice] right away when the session is live
  /// on this connection, else keeps it for the chat's next send.
  Future<HermesModelSwitchOutcome> _switchSessionModel(
    String storedId,
    HermesSessionModelChoice choice, {
    bool resumeIfNeeded = true,
  }) async {
    final merged = (_choiceFor(storedId) ?? choice).copyWith(
      model: choice.model,
      provider: choice.provider,
      reasoningEffort: choice.reasoningEffort,
      fast: choice.fast,
    );
    _rememberChoice(storedId, merged);
    if (!resumeIfNeeded && _bindings[storedId] == null) {
      return HermesModelSwitchOutcome.pending;
    }
    final binding = await _resume(storedId);
    final scope = _sessionScope(binding.storedId);
    var deferred = false;
    final selection = hermesDesktopSessionModelSelection(
      choice.model,
      choice.provider,
    );
    if (selection.model != null) {
      final result = _object(
        await _rpc.request<Object?>(
          'config.set',
          params: {
            'session_id': binding.runtimeId,
            'key': 'model',
            'value':
                '${selection.model}${selection.provider == null ? '' : ' --provider ${selection.provider}'} --session',
            ...scope,
          },
        ),
      );
      if (result['confirm_required'] == true) {
        final message = validateHermesBoundedString(
          result['confirm_message'] ?? result['warning'],
          maxCharacters: 400,
        );
        throw HermesModelSwitchNeedsConfirmation(
          message ?? 'This model needs confirmation before switching.',
        );
      }
      deferred = result['deferred'] == true;
    }
    final effort = choice.reasoningEffort?.trim();
    if (effort != null && effort.isNotEmpty) {
      await _rpc.request<Object?>(
        'config.set',
        params: {
          'session_id': binding.runtimeId,
          'key': 'reasoning',
          'value': effort,
          ...scope,
        },
      );
    }
    if (choice.fast != null) {
      await _rpc.request<Object?>(
        'config.set',
        params: {
          'session_id': binding.runtimeId,
          'key': 'fast',
          'value': choice.fast! ? 'fast' : 'normal',
          ...scope,
        },
      );
    }
    // The next send must not undo the switch with the composer's defaults.
    _appliedSessionOptions.remove(binding.storedId);
    // Show the pick at once; Hermes' next session.info confirms it.
    final known = _agentic.snapshotFor(binding.storedId).info;
    _agentic.applySessionInfo(binding.storedId, {
      'model': selection.model ?? known?.model,
      'provider': selection.model != null
          ? selection.provider
          : known?.provider,
      'reasoning_effort': (effort?.isNotEmpty ?? false)
          ? effort
          : known?.reasoningEffort,
      'fast': choice.fast ?? known?.fast ?? false,
      'running': known?.running,
    });
    return deferred
        ? HermesModelSwitchOutcome.nextTurn
        : HermesModelSwitchOutcome.applied;
  }

  // -- inspector --------------------------------------------------------------

  /// The stored messages that hold [toolId]'s call and result. Read from the
  /// REST transcript, which keeps tool-call ids (the socket history a
  /// profile chat loads from drops them), newest pages first, stopping once
  /// both halves are found. Oldest first in the result.
  Future<List<Map<String, dynamic>>> _toolCallMessages(
    String storedId,
    String toolId, {
    CancelToken? cancelToken,
  }) async {
    final scope = _sessionScope(storedId);
    final found = <Map<String, dynamic>>[];
    const page = 200;
    for (var index = 0; index < 5; index++) {
      final rows = _objects(
        await _requestJson(
          'GET',
          '/api/sessions/${Uri.encodeComponent(storedId)}/messages',
          query: {
            'limit': page,
            'offset': index * page,
            'order': 'latest',
            'include_compacted': true,
            ...scope,
          },
          cancelToken: cancelToken,
        ),
        'messages',
      );
      found.addAll(rows);
      final result = found.any((row) => row['tool_call_id'] == toolId);
      final call = found.any(
        (row) => row['tool_calls']?.toString().contains(toolId) ?? false,
      );
      if ((result && call) || rows.length < page) break;
    }
    return List.unmodifiable(found);
  }

  // -- plan recovery ----------------------------------------------------------

  /// When Hermes has not sent a plan for a session being shown (a compute
  /// host owns the live todo store, so a resume carries none), the latest
  /// stored `todo_list` result is the plan: read it once per session from
  /// the REST transcript, in the background.
  void _restorePlanFromTranscript(String storedId) {
    if (!HermesDesktopApiService._planRecoveryTried.add(
      '$_origin\u0000$storedId',
    )) {
      return;
    }
    if (_agentic.snapshotFor(storedId).todo != null) return;
    unawaited(() async {
      try {
        final rows = _objects(
          await _requestJson(
            'GET',
            '/api/sessions/${Uri.encodeComponent(storedId)}/messages',
            query: {
              'limit': 120,
              'offset': 0,
              'order': 'latest',
              'include_compacted': true,
              ..._sessionScope(storedId),
            },
          ),
          'messages',
        );
        // The latest page is in time order: the newest result is last.
        for (final row in rows.reversed) {
          if (row['role'] != 'tool') continue;
          final name = row['tool_name'];
          if (name != 'todo_list' && name != 'todo') continue;
          final content = row['content'];
          if (content is! String || content.length > 512000) continue;
          Object? json;
          try {
            json = jsonDecode(content);
          } catch (_) {
            continue;
          }
          if (_agentic.applyTodo(storedId, json)) return;
          if (HermesTodoSnapshot.fromJson(json) != null) return;
        }
      } catch (_) {
        // Recovery is best effort; the next todo.updated replaces it anyway.
      }
    }());
  }

  // -- delegates --------------------------------------------------------------

  Future<bool> _steerSubagent(
    String storedId,
    String subagentId,
    String text,
  ) async {
    final id = validateHermesOpaqueIdentifier(subagentId);
    final message = text.trim();
    if (id == null || message.isEmpty) return false;
    final binding = await _resume(storedId);
    final result = _object(
      await _rpc.request<Object?>(
        'subagent.steer',
        params: {
          'session_id': binding.runtimeId,
          'subagent_id': id,
          'text': message.length > 4000 ? message.substring(0, 4000) : message,
          ..._sessionScope(binding.storedId),
        },
      ),
    );
    return result['status'] == 'queued';
  }

  Future<bool> _stopSubagent(String storedId, String subagentId) async {
    final id = validateHermesOpaqueIdentifier(subagentId);
    if (id == null) return false;
    final binding = await _resume(storedId);
    final result = _object(
      await _rpc.request<Object?>(
        'subagent.interrupt',
        params: {
          'session_id': binding.runtimeId,
          'subagent_id': id,
          ..._sessionScope(binding.storedId),
        },
      ),
    );
    return result['found'] == true;
  }

  // -- active work ------------------------------------------------------------

  Future<List<HermesLiveSession>> _activeSessions() async {
    await _ensureConnected();
    final rows = _objects(
      await _rpc.request<Object?>(
        'session.active_list',
        timeout: const Duration(seconds: 15),
      ),
      'sessions',
    );
    final out = <HermesLiveSession>[];
    for (final row in rows.take(200)) {
      final runtimeId = validateHermesOpaqueIdentifier(row['id']);
      final storedId = validateHermesOpaqueIdentifier(
        row['session_key'] ?? row['id'],
      );
      if (runtimeId == null || storedId == null) continue;
      final title =
          validateHermesBoundedString(row['title'], maxCharacters: 200) ?? '';
      // A team room's plumbing session is shown inside its room.
      if (title.startsWith('Group: ')) continue;
      final status = switch (row['status']) {
        'working' ||
        'waiting' ||
        'starting' ||
        'idle' => row['status'] as String,
        _ => 'idle',
      };
      final last = row['last_active'];
      out.add(
        HermesLiveSession(
          runtimeId: runtimeId,
          storedId: storedId,
          title: title.isEmpty ? 'Untitled chat' : title,
          status: status,
          preview: HermesActivityPresenter.clean(
            row['preview']?.toString(),
            sensitiveValues: config.sensitiveValues,
            max: 160,
          ),
          model: validateHermesBoundedString(row['model'], maxCharacters: 200),
          lastActive: last is num && last.isFinite
              ? DateTime.fromMillisecondsSinceEpoch(
                  (last * 1000).round(),
                  isUtc: true,
                )
              : null,
        ),
      );
    }
    out.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      return (b.lastActive ?? DateTime(0)).compareTo(
        a.lastActive ?? DateTime(0),
      );
    });
    return out;
  }

  // -- teams ------------------------------------------------------------------

  /// The live state of each member's room session. Members whose room
  /// session does not exist yet (no turn so far) are absent.
  Future<Map<String, HermesTeamMemberLive>> _teamMembersLive(
    String roomId,
    List<HermesTeamMember> members,
  ) async {
    if (!isValidHermesTeamId(roomId)) throw ArgumentError.value(roomId);
    await _ensureConnected();
    final title = 'Group: $roomId';
    final now = DateTime.now();
    for (final member in members.take(16)) {
      final key = '$roomId\u0000${member.profile}';
      if (_roomSessions.containsKey(key)) continue;
      final checked = _roomSessionChecks[key];
      // The driver creates a member's room session when its first turn
      // starts, so look again soon: a short turn is over in seconds.
      if (checked != null &&
          now.difference(checked) < const Duration(seconds: 2)) {
        continue;
      }
      _roomSessionChecks[key] = now;
      if (!HermesConfig.isValidDesktopProfile(member.profile)) continue;
      final rows = _objects(
        await _rpc.request<Object?>(
          'session.list',
          params: {
            'profile': member.profile,
            'title': title,
            'include_hidden': true,
          },
          timeout: const Duration(seconds: 15),
        ),
        'sessions',
      );
      if (rows.isEmpty) continue;
      final storedId = validateHermesOpaqueIdentifier(
        rows.first['resolved_id'] ?? rows.first['id'],
      );
      if (storedId != null) _roomSessions[key] = _RoomSessionCursor(storedId);
    }
    final cursors = <String, _RoomSessionCursor>{
      for (final member in members)
        member.profile: ?_roomSessions['$roomId\u0000${member.profile}'],
    };
    if (cursors.isEmpty) return const {};
    final live = _objects(
      await _rpc.request<Object?>(
        'session.active_list',
        timeout: const Duration(seconds: 15),
      ),
      'sessions',
    );
    final out = <String, HermesTeamMemberLive>{};
    for (final entry in cursors.entries) {
      final cursor = entry.value;
      final row = live
          .where((row) => row['session_key'] == cursor.storedId)
          .firstOrNull;
      if (row == null) {
        out[entry.key] = HermesTeamMemberLive(
          profile: entry.key,
          status: 'idle',
          activity: List.unmodifiable(cursor.activity),
          todo: cursor.todo,
        );
        continue;
      }
      final runtimeId = validateHermesOpaqueIdentifier(row['id']);
      final status = switch (row['status']) {
        'working' ||
        'waiting' ||
        'starting' ||
        'idle' => row['status'] as String,
        _ => 'idle',
      };
      if (runtimeId != null && runtimeId != cursor.runtimeId) {
        cursor
          ..runtimeId = runtimeId
          ..lastSeen = 0
          ..epoch = null;
      }
      if (runtimeId != null && status != 'idle') {
        await _pullRoomEvents(cursor, runtimeId);
      }
      out[entry.key] = HermesTeamMemberLive(
        profile: entry.key,
        status: status,
        preview: HermesActivityPresenter.clean(
          row['preview']?.toString(),
          sensitiveValues: config.sensitiveValues,
          max: 200,
        ),
        thinking: cursor.thinking,
        activity: List.unmodifiable(cursor.activity),
        todo: cursor.todo,
      );
    }
    return out;
  }

  Future<void> _pullRoomEvents(
    _RoomSessionCursor cursor,
    String runtimeId,
  ) async {
    final result = _object(
      await _rpc.request<Object?>(
        'session.events.since',
        params: {'session_id': runtimeId, 'last_seen': cursor.lastSeen},
        timeout: const Duration(seconds: 15),
      ),
    );
    final epoch = result['epoch']?.toString();
    if (cursor.epoch != null && epoch != cursor.epoch) {
      // Hermes restarted: its numbering started over.
      cursor
        ..lastSeen = 0
        ..activity.clear()
        ..thinking = null;
    }
    cursor.epoch = epoch;
    if (result['truncated'] == true) cursor.activity.clear();
    final events = _objects(result['events']);
    for (final raw in events.take(512)) {
      final seq = raw['seq'];
      if (seq is int && seq > cursor.lastSeen) cursor.lastSeen = seq;
      final type = raw['type'];
      if (type is! String) continue;
      final payload = raw['payload'] is Map
          ? Map<String, dynamic>.from(raw['payload'] as Map)
          : <String, dynamic>{};
      switch (type) {
        case 'message.start':
          // A new turn: this member's earlier steps are in the room log.
          cursor.activity.clear();
          cursor.thinking = null;
        case 'reasoning.available':
          cursor.thinking = HermesActivityPresenter.clean(
            payload['text']?.toString(),
            sensitiveValues: config.sensitiveValues,
            max: 280,
          );
        case 'todo.updated':
          final todo = HermesTodoSnapshot.fromJson(payload);
          if (todo != null &&
              (cursor.todo == null || todo.revision >= cursor.todo!.revision)) {
            cursor.todo = todo;
          }
        default:
          final recorded = _projectActivity(
            HermesDesktopEvent(type: type, payload: payload),
            storedId: cursor.storedId,
          );
          if (recorded != null) cursor.activity.add(recorded);
      }
    }
    final latest = result['latest_seq'];
    if (latest is int && latest > cursor.lastSeen && events.isEmpty) {
      cursor.lastSeen = latest;
    }
    if (cursor.activity.length > 60) {
      cursor.activity.removeRange(0, cursor.activity.length - 60);
    }
  }
}

/// Hermes refused a switch until the user confirms it (an expensive model).
final class HermesModelSwitchNeedsConfirmation implements Exception {
  const HermesModelSwitchNeedsConfirmation(this.message);
  final String message;
  @override
  String toString() => message;
}
