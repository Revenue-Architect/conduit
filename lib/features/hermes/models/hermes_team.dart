import 'dart:math';

import 'package:flutter/foundation.dart';

/// Hermes Group Chat ("hosted rooms", `groups.*`): two to six bots in one
/// room. The user posts; the bots discuss it for up to three rounds, can pass,
/// and answer @mentions. Hermes runs the discussion; the app shows it.

String? _text(Object? value, {int max = 200}) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length > max ? trimmed.substring(0, max) : trimmed;
}

DateTime? _seconds(Object? value) => value is num
    ? DateTime.fromMillisecondsSinceEpoch((value * 1000).round(), isUtc: true)
    : null;

int? _int(Object? value) => value is num ? value.toInt() : null;

/// Identifier alphabet Hermes accepts for room, member, and event ids.
final RegExp _hermesTeamId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');

bool isValidHermesTeamId(String? value) =>
    value != null && _hermesTeamId.hasMatch(value);

@immutable
class HermesTeamMember {
  const HermesTeamMember({
    required this.memberId,
    required this.profile,
    required this.handle,
    this.displayName,
  });

  final String memberId;
  final String profile;
  final String handle;
  final String? displayName;

  String get label => displayName ?? profile;

  static HermesTeamMember? fromJson(Object? json) {
    if (json is! Map) return null;
    final memberId = _text(json['member_id'], max: 128);
    final profile = _text(json['profile'], max: 128);
    final handle = _text(json['handle'], max: 128) ?? profile;
    if (memberId == null || profile == null || handle == null) return null;
    return HermesTeamMember(
      memberId: memberId,
      profile: profile,
      handle: handle,
      displayName: _text(json['display_name']),
    );
  }

  /// The roster row `groups.create` expects for a bot on this gateway.
  static Map<String, Object?> rosterFor(String profile, {String? title}) => {
    'member_id': 'm-$profile',
    'profile': profile,
    'handle': profile,
    if (title != null && title.trim().isNotEmpty) 'display_name': title.trim(),
  };
}

@immutable
class HermesTeam {
  const HermesTeam({
    required this.roomId,
    required this.name,
    required this.members,
    this.updatedAt,
    this.latestSeq,
    this.disbanded = false,
  });

  final String roomId;
  final String name;
  final List<HermesTeamMember> members;
  final DateTime? updatedAt;
  final int? latestSeq;
  final bool disbanded;

  static HermesTeam? fromJson(Object? json) {
    if (json is! Map) return null;
    final roomId = _text(json['room_id'], max: 128);
    if (!isValidHermesTeamId(roomId)) return null;
    final members = <HermesTeamMember>[];
    final rows = json['members'];
    if (rows is List) {
      for (final row in rows.take(16)) {
        final member = HermesTeamMember.fromJson(row);
        if (member != null) members.add(member);
      }
    }
    return HermesTeam(
      roomId: roomId!,
      name: _text(json['name']) ?? 'Team',
      members: members,
      updatedAt: _seconds(json['updated_at']),
      latestSeq: _int(json['latest_seq']),
      disbanded: json['disbanded_at'] != null,
    );
  }

  HermesTeamMember? memberById(String? id) {
    for (final member in members) {
      if (member.memberId == id) return member;
    }
    return null;
  }
}

/// One entry in a room's log. The kinds the app shows are the user's and
/// bots' messages and the discussion's own milestones; the rest are kept for
/// ordering only.
@immutable
class HermesTeamEvent {
  const HermesTeamEvent({
    required this.seq,
    required this.eventId,
    required this.kind,
    required this.actorKind,
    required this.actorId,
    required this.payload,
    this.actorName,
    this.actorProfile,
    this.createdAt,
  });

  final int seq;
  final String eventId;
  final String kind;
  final String actorKind;
  final String actorId;
  final String? actorName;
  final String? actorProfile;
  final Map<String, Object?> payload;
  final DateTime? createdAt;

  String? get text => _text(payload['text'], max: 64 * 1024);
  String? get memberId => _text(payload['member_id'], max: 128);
  String? get turnId => _text(payload['turn_id'], max: 128);
  String? get discussionId => _text(payload['discussion_event_id'], max: 128);

  static HermesTeamEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final seq = _int(json['seq']);
    final eventId = _text(json['event_id'], max: 128);
    final kind = _text(json['kind'], max: 64);
    final actor = json['actor'];
    if (seq == null || eventId == null || kind == null || actor is! Map) {
      return null;
    }
    final payload = json['payload'];
    return HermesTeamEvent(
      seq: seq,
      eventId: eventId,
      kind: kind,
      actorKind: _text(actor['kind'], max: 32) ?? 'system',
      actorId: _text(actor['id'], max: 128) ?? '',
      actorName: _text(actor['display_name']),
      actorProfile: _text(actor['profile'], max: 128),
      payload: payload is Map
          ? Map<String, Object?>.from(payload)
          : const <String, Object?>{},
      createdAt: _seconds(json['created_at']),
    );
  }
}

/// A bot in the room asking to run something that needs the user's say.
@immutable
class HermesTeamApproval {
  const HermesTeamApproval({
    required this.memberId,
    required this.taskId,
    required this.executionGeneration,
    required this.requestId,
    required this.description,
  });

  final String memberId;
  final String taskId;
  final int executionGeneration;
  final String requestId;
  final String description;
}

/// The room's live driver state from `groups.state`.
@immutable
class HermesTeamStatus {
  const HermesTeamStatus({
    required this.running,
    required this.working,
    required this.blocked,
    required this.approvals,
    required this.retries,
  });

  static const idle = HermesTeamStatus(
    running: true,
    working: false,
    blocked: false,
    approvals: [],
    retries: [],
  );

  /// Whether Hermes' room worker is up at all.
  final bool running;
  final bool working;
  final bool blocked;
  final List<HermesTeamApproval> approvals;

  /// Task ids that did not finish cleanly and may be retried by the user.
  final List<String> retries;

  static HermesTeamStatus fromJson(Object? json) {
    if (json is! Map) return idle;
    final approvals = <HermesTeamApproval>[];
    final retries = <String>[];
    final actions = json['pending_actions'];
    if (actions is List) {
      for (final action in actions.take(32)) {
        if (action is! Map) continue;
        final taskId = _text(action['task_id'], max: 128);
        if (taskId == null) continue;
        if (action['kind'] == 'retry') {
          retries.add(taskId);
          continue;
        }
        if (action['kind'] != 'approval') continue;
        final memberId = _text(action['member_id'], max: 128);
        final requestId = _text(action['request_id'], max: 128);
        final generation = _int(action['execution_generation']);
        if (memberId == null || requestId == null || generation == null) {
          continue;
        }
        final approval = action['approval'];
        final description = approval is Map
            ? _text(approval['description'], max: 400) ??
                  _text(approval['command'], max: 400) ??
                  _text(approval['title'], max: 400)
            : null;
        approvals.add(
          HermesTeamApproval(
            memberId: memberId,
            taskId: taskId,
            executionGeneration: generation,
            requestId: requestId,
            description: description ?? 'An action that needs your approval',
          ),
        );
      }
    }
    return HermesTeamStatus(
      running: json['running'] != false,
      working: json['working'] == true,
      blocked: json['blocked'] == true,
      approvals: approvals,
      retries: retries,
    );
  }
}

/// A fresh identifier Hermes accepts, for a new room or a sent message.
String newHermesTeamId(String prefix) {
  final now = DateTime.now().toUtc().microsecondsSinceEpoch;
  final salt = _random.nextInt(1 << 32).toRadixString(36);
  return '$prefix-${now.toRadixString(36)}-$salt';
}

final Random _random = Random.secure();
