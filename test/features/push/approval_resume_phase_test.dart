import 'package:checks/checks.dart';
import 'package:conduit/features/push/models/approval.dart';
import 'package:conduit/features/push/views/approval_continuation_notice.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 10, 19, 15, 0, 0);

Approval _approval({
  String status = 'approved',
  String wakeMode = 'resume',
  String? wakeState,
  DateTime? resolved,
  DateTime? wakeSent,
}) => Approval.fromJson({
  'id': 'a-1',
  'action_type': 'pairing_test',
  'description': 'x',
  'status': status,
  'created_at': _t0.toIso8601String(),
  'expires_at': _t0.add(const Duration(minutes: 10)).toIso8601String(),
  'requested_by': 'chief',
  'resolved_at': (resolved ?? _t0.add(const Duration(seconds: 20)))
      .toIso8601String(),
  'wake_mode': wakeMode,
  'wake_state': wakeState,
  'events': [
    if (wakeSent != null)
      {'type': 'WAKE_SENT', 'created_at': wakeSent.toIso8601String()},
  ],
})!;

ApprovalResumePhase _phase(
  Approval a, {
  bool wake = false,
  bool reply = false,
  Duration after = const Duration(seconds: 25),
}) => approvalResumePhase(
  a,
  wakeMessageVisible: wake,
  replyVisible: reply,
  now: _t0.add(after).toLocal(),
);

void main() {
  test('pending request waits for a decision', () {
    final a = _approval(status: 'pending', wakeState: 'none');
    check(_phase(a)).equals(ApprovalResumePhase.awaitingDecision);
  });

  test('wake not yet sent is "recording" and in progress', () {
    final a = _approval(wakeState: 'pending');
    check(_phase(a)).equals(ApprovalResumePhase.recording);
    check(_phase(a).inProgress).isTrue();
  });

  test('sent wake moves requested -> working -> resumed', () {
    final sent = _t0.add(const Duration(seconds: 50));
    final a = _approval(wakeState: 'sent', wakeSent: sent);
    const after = Duration(seconds: 55);
    check(_phase(a, after: after)).equals(ApprovalResumePhase.requested);
    check(_phase(a, wake: true, after: after)).equals(ApprovalResumePhase.working);
    final done = _phase(a, wake: true, reply: true, after: after);
    check(done).equals(ApprovalResumePhase.resumed);
    check(done.autoCloses).isTrue();
    check(done.isProblem).isFalse();
  });

  test('no reply within the grace period is stalled, not success', () {
    final sent = _t0.add(const Duration(seconds: 50));
    final a = _approval(wakeState: 'sent', wakeSent: sent);
    final p = _phase(a, after: const Duration(seconds: 50 + 95));
    check(p).equals(ApprovalResumePhase.stalled);
    check(p.isProblem).isTrue();
    check(p.autoCloses).isFalse();
  });

  test('server failure is the only hard failure', () {
    check(_phase(_approval(wakeState: 'gone'))).equals(ApprovalResumePhase.failed);
    check(_phase(_approval(wakeState: 'failed'))).equals(ApprovalResumePhase.failed);
    check(_phase(_approval(wakeMode: 'none', wakeState: 'none')))
        .equals(ApprovalResumePhase.recordedOnly);
    check(_phase(_approval(status: 'cancelled', wakeState: 'none')))
        .equals(ApprovalResumePhase.cancelled);
  });

  test('copy names the decision and is calm until it fails', () {
    final denied = _approval(status: 'denied', wakeState: 'sent');
    check(approvalResumeText(denied, ApprovalResumePhase.resumed))
        .startsWith('Denied.');
    check(approvalResumeText(denied, ApprovalResumePhase.requested))
        .contains('Waking');
    check(approvalResumeText(denied, ApprovalResumePhase.failed))
        .contains('decision was recorded');
  });
}
