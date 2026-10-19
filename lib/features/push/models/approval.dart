import 'package:flutter/foundation.dart';

enum ApprovalStatus {
  pending,
  approved,
  denied,
  expired,
  cancelled,
  unknown;

  static ApprovalStatus parse(Object? value) {
    switch (value) {
      case 'pending':
        return ApprovalStatus.pending;
      case 'approved':
        return ApprovalStatus.approved;
      case 'denied':
      case 'rejected':
        return ApprovalStatus.denied;
      case 'expired':
        return ApprovalStatus.expired;
      case 'cancelled':
      case 'canceled':
        return ApprovalStatus.cancelled;
    }
    return ApprovalStatus.unknown;
  }

  String get label => switch (this) {
    ApprovalStatus.pending => 'Pending',
    ApprovalStatus.approved => 'Approved',
    ApprovalStatus.denied => 'Denied',
    ApprovalStatus.expired => 'Expired',
    ApprovalStatus.cancelled => 'Cancelled',
    ApprovalStatus.unknown => 'Unknown',
  };
}

enum ApprovalDecision {
  approve,
  deny;

  String get wire => name;
}

@immutable
class ApprovalEvent {
  const ApprovalEvent({
    required this.type,
    required this.createdAt,
    this.actor,
    this.details = const {},
  });

  final String type;
  final DateTime createdAt;
  final String? actor;
  final Map<String, dynamic> details;

  static ApprovalEvent? fromJson(Object? value) {
    if (value is! Map) return null;
    final type = value['type'] ?? value['event_type'];
    final createdAt = DateTime.tryParse('${value['created_at'] ?? ''}');
    if (type is! String || createdAt == null) return null;
    final details = value['details'];
    return ApprovalEvent(
      type: type,
      createdAt: createdAt.toLocal(),
      actor: value['actor'] is String ? value['actor'] as String : null,
      details: details is Map ? Map<String, dynamic>.from(details) : const {},
    );
  }
}

/// A V2 approval request as the phone gateway returns it (spec 5.3 / 5.8).
@immutable
class Approval {
  const Approval({
    required this.id,
    required this.actionType,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.requestedBy,
    this.resolvedAt,
    this.resolvedBy,
    this.decidedVia,
    this.payload,
    this.payloadDigest,
    this.originSessionId,
    this.events = const [],
  });

  final String id;
  final String actionType;
  final String description;
  final ApprovalStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String requestedBy;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? decidedVia;
  final Map<String, dynamic>? payload;
  final String? payloadDigest;
  final String? originSessionId;
  final List<ApprovalEvent> events;

  bool get isPending => status == ApprovalStatus.pending;

  /// Pending but past its expiry (the server expires it within seconds).
  bool isOverdue(DateTime now) => isPending && !expiresAt.isAfter(now);

  /// Whether the phone can still send a decision for this request.
  bool canDecide(DateTime now) =>
      isPending && !isOverdue(now) && payloadDigest != null;

  /// Parses one row. Returns null when required fields are missing, so one
  /// malformed row never breaks the whole list.
  static Approval? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final actionType = value['action_type'];
    final createdAt = DateTime.tryParse('${value['created_at'] ?? ''}');
    final expiresAt = DateTime.tryParse('${value['expires_at'] ?? ''}');
    if (id is! String ||
        id.isEmpty ||
        actionType is! String ||
        createdAt == null ||
        expiresAt == null) {
      return null;
    }
    final origin = value['origin'];
    final payload = value['payload'];
    final events = value['events'];
    return Approval(
      id: id,
      actionType: actionType,
      description: value['description'] is String
          ? value['description'] as String
          : '',
      status: ApprovalStatus.parse(value['status']),
      createdAt: createdAt.toLocal(),
      expiresAt: expiresAt.toLocal(),
      requestedBy: value['requested_by'] is String
          ? value['requested_by'] as String
          : 'unknown',
      resolvedAt: DateTime.tryParse('${value['resolved_at'] ?? ''}')?.toLocal(),
      resolvedBy: value['resolved_by'] is String
          ? value['resolved_by'] as String
          : null,
      decidedVia: value['decided_via'] is String
          ? value['decided_via'] as String
          : null,
      payload: payload is Map ? Map<String, dynamic>.from(payload) : null,
      payloadDigest: value['payload_digest'] is String
          ? value['payload_digest'] as String
          : null,
      originSessionId: origin is Map && origin['session_id'] is String
          ? origin['session_id'] as String
          : null,
      events: events is List
          ? events.map(ApprovalEvent.fromJson).whereType<ApprovalEvent>().toList()
          : const [],
    );
  }
}

/// One page of approvals plus the cursor for the next (older) page.
@immutable
class ApprovalPage {
  const ApprovalPage({required this.items, this.nextBefore});

  final List<Approval> items;
  final String? nextBefore;

  static ApprovalPage fromJson(Object? value) {
    final map = value is Map ? value : const {};
    final rows = map['items'] ?? map['approvals'];
    final items = rows is List
        ? rows.map(Approval.fromJson).whereType<Approval>().toList()
        : <Approval>[];
    final next = map['next_before'];
    return ApprovalPage(
      items: items,
      nextBefore: next is String && next.isNotEmpty ? next : null,
    );
  }
}
