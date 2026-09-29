import 'package:flutter/foundation.dart';

import 'hermes_team.dart';

enum HermesTeamLineKind { user, member, note, problem }

/// One visible line in a team room.
@immutable
class HermesTeamLine {
  const HermesTeamLine({
    required this.key,
    required this.kind,
    required this.text,
    this.member,
    this.at,
  });

  /// Stable across polls: the room event id.
  final String key;
  final HermesTeamLineKind kind;
  final String text;

  /// The bot that spoke or that a note is about.
  final HermesTeamMember? member;
  final DateTime? at;
}

/// What a room's log looks like to the user, and who is still thinking.
@immutable
class HermesTeamTimeline {
  const HermesTeamTimeline({required this.lines, required this.thinking});

  final List<HermesTeamLine> lines;

  /// Bots whose turn has started and not yet ended, in turn order.
  final List<HermesTeamMember> thinking;

  static const _terminal = {
    'turn.settled',
    'turn.failed',
    'turn.cancelled',
    'turn.deferred',
  };

  /// Builds the timeline from a room log in sequence order.
  factory HermesTeamTimeline.from(
    List<HermesTeamEvent> events,
    HermesTeam team,
  ) {
    HermesTeamMember? who(HermesTeamEvent event) {
      final byPayload = team.memberById(event.memberId);
      if (byPayload != null) return byPayload;
      final byActor = team.memberById(event.actorId);
      if (byActor != null) return byActor;
      for (final member in team.members) {
        if (member.profile == event.actorProfile) return member;
      }
      return null;
    }

    String name(HermesTeamEvent event) =>
        who(event)?.label ?? event.actorName ?? event.actorProfile ?? 'A bot';

    final lines = <HermesTeamLine>[];
    final open = <String, HermesTeamMember>{};
    for (final event in events) {
      final turn = event.turnId;
      switch (event.kind) {
        case 'message.user':
          final text = event.text;
          if (text != null) {
            lines.add(
              HermesTeamLine(
                key: event.eventId,
                kind: HermesTeamLineKind.user,
                text: text,
                at: event.createdAt,
              ),
            );
          }
        case 'message.member':
          final text = event.text;
          if (turn != null) open.remove(turn);
          if (text != null) {
            lines.add(
              HermesTeamLine(
                key: event.eventId,
                kind: HermesTeamLineKind.member,
                text: text,
                member: who(event),
                at: event.createdAt,
              ),
            );
          }
        case 'turn.started':
          final member = who(event);
          if (turn != null && member != null) open[turn] = member;
        case 'turn.settled':
          if (turn != null) open.remove(turn);
          if (event.payload['passed'] == true) {
            lines.add(
              HermesTeamLine(
                key: event.eventId,
                kind: HermesTeamLineKind.note,
                text: '${name(event)} passed',
                member: who(event),
              ),
            );
          }
        case 'turn.failed':
          if (turn != null) open.remove(turn);
          final error = event.payload['error'];
          lines.add(
            HermesTeamLine(
              key: event.eventId,
              kind: HermesTeamLineKind.problem,
              text: error is String && error.trim().isNotEmpty
                  ? "${name(event)} couldn't reply: ${_short(error)}"
                  : "${name(event)} couldn't reply",
              member: who(event),
            ),
          );
        case 'member.unavailable':
          lines.add(
            HermesTeamLine(
              key: event.eventId,
              kind: HermesTeamLineKind.problem,
              text: '${name(event)} is unavailable',
              member: who(event),
            ),
          );
        case 'room.activity':
          final status = event.payload['status'];
          if (status == 'settled' || status == 'bounded') {
            open.clear();
            lines.add(
              HermesTeamLine(
                key: event.eventId,
                kind: HermesTeamLineKind.note,
                text: status == 'settled'
                    ? 'The team is done'
                    : 'The team reached its reply limit',
              ),
            );
          }
        case 'room.stop_requested':
          open.clear();
          lines.add(
            HermesTeamLine(
              key: event.eventId,
              kind: HermesTeamLineKind.note,
              text: 'Stopped',
            ),
          );
        case 'room.renamed':
          final renamed = event.payload['name'];
          if (renamed is String && renamed.trim().isNotEmpty) {
            lines.add(
              HermesTeamLine(
                key: event.eventId,
                kind: HermesTeamLineKind.note,
                text: 'Renamed to ${renamed.trim()}',
              ),
            );
          }
        default:
          if (_terminal.contains(event.kind) && turn != null) {
            open.remove(turn);
          }
      }
    }
    final seen = <String>{};
    return HermesTeamTimeline(
      lines: lines,
      thinking: [
        for (final member in open.values)
          if (seen.add(member.memberId)) member,
      ],
    );
  }

  static String _short(String value) {
    final line = value.trim().split('\n').first;
    return line.length > 140 ? '${line.substring(0, 140)}…' : line;
  }
}

/// Merges a new log page into what is already shown, in sequence order,
/// without duplicates. Pages can overlap after a retry.
List<HermesTeamEvent> mergeHermesTeamEvents(
  List<HermesTeamEvent> shown,
  List<HermesTeamEvent> page,
) {
  if (page.isEmpty) return shown;
  final byId = <String, HermesTeamEvent>{
    for (final event in shown) event.eventId: event,
    for (final event in page) event.eventId: event,
  };
  return byId.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));
}
