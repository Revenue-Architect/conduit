import 'package:checks/checks.dart';
import 'package:conduit/features/push/models/approval.dart';
import 'package:conduit/features/push/views/approval_formatting.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({String id = 'a-1', String status = 'pending'}) => {
  'id': id,
  'action_type': 'restart_container',
  'description': 'Restart the changedetection container',
  'status': status,
  'created_at': '2026-10-19T15:00:00+00:00',
  'expires_at': '2026-10-19T15:40:00+00:00',
  'requested_by': 'chief',
};

void main() {
  group('Approval.fromJson', () {
    test('reads a list row', () {
      final a = Approval.fromJson(_row())!;
      check(a.id).equals('a-1');
      check(a.status).equals(ApprovalStatus.pending);
      check(a.isPending).isTrue();
      check(a.payloadDigest).isNull();
      check(a.requestedBy).equals('chief');
    });

    test('reads the detail fields', () {
      final a = Approval.fromJson({
        ..._row(status: 'approved'),
        'payload': {'name': 'cd'},
        'payload_digest': 'abc123',
        'resolved_at': '2026-10-19T15:10:00+00:00',
        'resolved_by': 'conduit:dev-1',
        'decided_via': 'conduit',
        'origin': {'session_id': 'sess-9'},
        'events': [
          {'type': 'CREATED', 'created_at': '2026-10-19T15:00:00+00:00', 'actor': 'chief'},
          {'type': 'APPROVED', 'created_at': '2026-10-19T15:10:00+00:00'},
          {'bad': true},
        ],
      })!;
      check(a.status).equals(ApprovalStatus.approved);
      check(a.payload).isNotNull().deepEquals({'name': 'cd'});
      check(a.originSessionId).equals('sess-9');
      check(a.events).length.equals(2);
      check(a.decidedVia).equals('conduit');
    });

    test('a malformed row is null, not an exception', () {
      check(Approval.fromJson(null)).isNull();
      check(Approval.fromJson({'id': 'x'})).isNull();
      check(Approval.fromJson({..._row(), 'expires_at': 'soon'})).isNull();
    });

    test('unknown status parses as unknown', () {
      check(ApprovalStatus.parse('weird')).equals(ApprovalStatus.unknown);
      check(ApprovalStatus.parse('rejected')).equals(ApprovalStatus.denied);
    });

    test('canDecide needs pending, not overdue and a digest', () {
      final a = Approval.fromJson({..._row(), 'payload_digest': 'd'})!;
      final inside = a.expiresAt.subtract(const Duration(minutes: 5));
      final after = a.expiresAt.add(const Duration(seconds: 1));
      check(a.canDecide(inside)).isTrue();
      check(a.canDecide(after)).isFalse();
      check(a.isOverdue(after)).isTrue();
      check(Approval.fromJson(_row())!.canDecide(inside)).isFalse();
      check(
        Approval.fromJson({..._row(status: 'denied'), 'payload_digest': 'd'})!
            .canDecide(inside),
      ).isFalse();
    });
  });

  group('ApprovalPage', () {
    test('reads items and the cursor, skipping bad rows', () {
      final page = ApprovalPage.fromJson({
        'items': [_row(), {'id': 'broken'}, _row(id: 'a-2')],
        'next_before': '2026-10-18T00:00:00+00:00',
      });
      check(page.items).length.equals(2);
      check(page.nextBefore).equals('2026-10-18T00:00:00+00:00');
    });

    test('accepts an approvals key and no cursor', () {
      final page = ApprovalPage.fromJson({'approvals': [_row()]});
      check(page.items).length.equals(1);
      check(page.nextBefore).isNull();
      check(ApprovalPage.fromJson(null).items).isEmpty();
    });
  });

  group('formatting', () {
    final now = DateTime(2026, 10, 19, 15, 0, 0);

    test('time left rounds up and reads naturally', () {
      check(formatTimeLeft(now.add(const Duration(seconds: 20)), now))
          .equals('Under 1 min left');
      check(formatTimeLeft(now.add(const Duration(seconds: 61)), now))
          .equals('2 min left');
      check(formatTimeLeft(now.add(const Duration(minutes: 12)), now))
          .equals('12 min left');
      check(formatTimeLeft(now.add(const Duration(minutes: 65)), now))
          .equals('1 h 5 min left');
      check(formatTimeLeft(now.add(const Duration(hours: 3)), now))
          .equals('3 h left');
      check(formatTimeLeft(now.add(const Duration(days: 2)), now))
          .equals('2 days left');
      check(formatTimeLeft(now.subtract(const Duration(seconds: 1)), now))
          .equals('Expired');
    });

    test('12-hour clock', () {
      check(formatClock(DateTime(2026, 1, 1, 0, 5))).equals('12:05 AM');
      check(formatClock(DateTime(2026, 1, 1, 12, 0))).equals('12:00 PM');
      check(formatClock(DateTime(2026, 1, 1, 15, 40))).equals('3:40 PM');
      check(formatClock(DateTime(2026, 1, 1, 9, 7))).equals('9:07 AM');
    });

    test('relative day labels', () {
      check(formatWhen(DateTime(2026, 10, 19, 9, 5), now)).equals('Today 9:05 AM');
      check(formatWhen(DateTime(2026, 10, 18, 21, 0), now)).equals('Yesterday 9:00 PM');
      check(formatWhen(DateTime(2026, 10, 3, 8, 30), now)).equals('Oct 3, 8:30 AM');
    });

    test('resolution wording', () {
      final approved = Approval.fromJson({
        ..._row(status: 'approved'),
        'resolved_by': 'conduit:dev-1',
        'decided_via': 'conduit',
      })!;
      check(describeResolution(approved)).equals('Approved by you in Hermez');
      final expired = Approval.fromJson({
        ..._row(status: 'expired'),
        'resolved_by': 'system',
      })!;
      check(describeResolution(expired)).equals('Expired unanswered');
      final denied = Approval.fromJson({
        ..._row(status: 'denied'),
        'resolved_by': 'ntfy-button',
        'decided_via': 'ntfy',
      })!;
      check(describeResolution(denied)).equals('Denied by you from the ntfy button');
    });

    test('payload and event wording', () {
      check(prettyPayload(null)).equals('None');
      check(prettyPayload({})).equals('None');
      check(prettyPayload({'a': 1})).equals('{\n  "a": 1\n}');
      final e = ApprovalEvent(type: 'WAKE_GONE', createdAt: now);
      check(describeEvent(e)).equals('The requesting chat is gone');
      check(describeEvent(ApprovalEvent(type: 'CUSTOM_THING', createdAt: now)))
          .equals('Custom thing');
      check(describeEvent(ApprovalEvent(type: '', createdAt: now))).equals('Event');
    });
  });
}
