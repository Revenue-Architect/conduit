import 'dart:convert';

import '../models/approval.dart';

/// "12 min left", "1 h 5 min left", "Expired". Rounds up so the last minute
/// still reads "1 min left".
String formatTimeLeft(DateTime expiresAt, DateTime now) {
  final left = expiresAt.difference(now);
  if (left.inSeconds <= 0) return 'Expired';
  if (left.inMinutes < 1) return 'Under 1 min left';
  final minutes = (left.inSeconds / 60).ceil();
  if (minutes < 60) return '$minutes min left';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours < 24) return rest == 0 ? '$hours h left' : '$hours h $rest min left';
  final days = hours ~/ 24;
  return days == 1 ? '1 day left' : '$days days left';
}

/// 12-hour clock, no leading zero: "3:40 PM".
String formatClock(DateTime time) {
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = time.hour >= 12 ? 'PM' : 'AM';
  return '$hour12:$minute $suffix';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Today 3:40 PM", "Yesterday 9:05 AM", or "Oct 17, 3:40 PM".
String formatWhen(DateTime time, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  final clock = formatClock(time);
  if (diff == 0) return 'Today $clock';
  if (diff == 1) return 'Yesterday $clock';
  return '${_months[time.month - 1]} ${time.day}, $clock';
}

/// Short phrase for the history list: "Approved by you via Conduit".
String describeResolution(Approval approval) {
  final who = switch (approval.resolvedBy) {
    null => null,
    final value when value.startsWith('conduit:') => 'you',
    'system' => 'the system',
    final value when value == 'ntfy-button' || value.startsWith('ntfy') => 'you',
    final value => value,
  };
  final via = switch (approval.decidedVia) {
    'conduit' => 'in Hermez',
    'ntfy' => 'from the ntfy button',
    'operator' => 'by the operator',
    'system' => null,
    _ => null,
  };
  final base = switch (approval.status) {
    ApprovalStatus.approved => 'Approved',
    ApprovalStatus.denied => 'Denied',
    ApprovalStatus.expired => 'Expired unanswered',
    ApprovalStatus.cancelled => 'Cancelled',
    ApprovalStatus.pending => 'Pending',
    ApprovalStatus.unknown => 'Unknown',
  };
  final parts = [
    base,
    if (who != null &&
        approval.status != ApprovalStatus.expired &&
        approval.status != ApprovalStatus.cancelled)
      'by $who',
    ?via,
  ];
  return parts.join(' ');
}

/// Pretty-printed payload for the detail page; "None" for an empty one.
String prettyPayload(Map<String, dynamic>? payload) {
  if (payload == null || payload.isEmpty) return 'None';
  try {
    return const JsonEncoder.withIndent('  ').convert(payload);
  } catch (_) {
    return payload.toString();
  }
}

/// Human wording for event types in the timeline.
String describeEvent(ApprovalEvent event) => switch (event.type) {
  'CREATED' => 'Requested',
  'NOTIFIED' || 'NOTIFY_SENT' => 'You were notified',
  'APPROVED' => 'Approved',
  'DENIED' => 'Denied',
  'EXPIRED' => 'Expired',
  'CANCELLED' => 'Cancelled',
  'REPLAY_REJECTED' => 'A repeated answer was ignored',
  'WAKE_SENT' => 'The requesting chat was told',
  'WAKE_RETRY' => 'Telling the requesting chat again',
  'WAKE_GONE' => 'The requesting chat is gone',
  'WAKE_FAILED' => 'Could not tell the requesting chat',
  'NOTIFY_STATUS_SENT' => 'Status notification sent',
  final other => other.isEmpty
      ? 'Event'
      : other[0] + other.substring(1).toLowerCase().replaceAll('_', ' '),
};
