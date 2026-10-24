import 'package:conduit/features/hermes/models/hermes_job.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/services/hermes_pending_decision_store.dart';
import 'package:conduit/features/hermes/widgets/hermes_home_needs_you.dart';
import 'package:conduit/features/push/models/approval.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 24, 12);

HermesPendingDesktopDecision _decision(
  String request, {
  String session = 'session-1',
  HermesPendingDesktopDecisionKind kind =
      HermesPendingDesktopDecisionKind.clarification,
  String? prompt,
  String? profile,
  DateTime? askedAt,
}) => HermesPendingDesktopDecision(
  origin: 'https://hermes.example',
  storedSessionId: session,
  runtimeId: 'runtime-$session',
  requestId: request,
  kind: kind,
  // The store holds a decision for its ttl from the last time it was asked.
  expiresAt: (askedAt ?? _now).toUtc().add(HermesPendingDecisionStore.ttl),
  prompt: prompt,
  profile: profile,
);

Approval _approval(
  String id, {
  String description = 'Send the follow-up',
  DateTime? createdAt,
  DateTime? expiresAt,
  String? profile,
  String requestedBy = 'unknown',
  ApprovalStatus status = ApprovalStatus.pending,
}) => Approval(
  id: id,
  actionType: 'send_email',
  description: description,
  status: status,
  createdAt: createdAt ?? _now.subtract(const Duration(minutes: 5)),
  expiresAt: expiresAt ?? _now.add(const Duration(minutes: 30)),
  requestedBy: requestedBy,
  originProfile: profile,
);

HermesJob _failedJob(String id, {DateTime? lastRun}) => HermesJob(
  id: id,
  name: 'Nightly report $id',
  prompt: 'Report',
  schedule: '0 2 * * *',
  lastError: 'boom',
  lastRun: lastRun,
);

void main() {
  group('mergeHermesNeedsYou', () {
    test('is empty when nothing waits', () {
      expect(mergeHermesNeedsYou(now: _now), isEmpty);
    });

    test('merges every source into one list with a stable id each', () {
      final items = mergeHermesNeedsYou(
        now: _now,
        decisions: [_decision('r1', prompt: 'Which account?')],
        approvals: [_approval('a1', profile: 'kai')],
        prepared: const [
          HermesSessionSummary(
            id: 'initiative-0123456789abcdef01234567',
            title: 'Weekly plan',
            profile: 'default',
          ),
        ],
        failedJobs: [('ops', _failedJob('j1'))],
        botNames: const {'kai': 'Kai', 'ops': 'Ops'},
      );
      expect(items.map((item) => item.id).toSet(), {
        'decision:session-1:r1',
        'approval:a1',
        'prepared:initiative-0123456789abcdef01234567',
        'job:ops:j1',
      });
      expect(items, hasLength(4));
    });

    test('words the source line as who and what they want', () {
      final items = mergeHermesNeedsYou(
        now: _now,
        decisions: [
          _decision('q', prompt: 'Which account?', profile: 'kai'),
          _decision(
            's',
            session: 'session-2',
            kind: HermesPendingDesktopDecisionKind.sudo,
          ),
        ],
        approvals: [_approval('a1', profile: 'kai')],
        prepared: const [
          HermesSessionSummary(
            id: 'p1',
            title: 'Weekly plan',
            profile: 'default',
          ),
        ],
        failedJobs: [('ops', _failedJob('j1'))],
        botNames: const {'kai': 'Kai', 'ops': 'Ops'},
      );
      String source(String id) => items.firstWhere((i) => i.id == id).source;
      expect(source('decision:session-1:q'), 'Kai · has a question');
      // A decision with no recorded bot belongs to the connection's own: Chief.
      expect(source('decision:session-2:s'), 'Chief · needs admin access');
      expect(source('approval:a1'), 'Kai · approval');
      expect(source('prepared:p1'), 'Chief · ready for review');
      expect(source('job:ops:j1'), 'Ops · run failed');
    });

    test('a decision shows its prompt, else a plain title for its kind', () {
      final items = mergeHermesNeedsYou(
        now: _now,
        decisions: [
          _decision('r1', prompt: '  Which   account\nto use? '),
          _decision(
            'r2',
            session: 'session-2',
            kind: HermesPendingDesktopDecisionKind.approval,
          ),
        ],
      );
      String title(String id) => items.firstWhere((i) => i.id == id).title;
      expect(title('decision:session-1:r1'), 'Which account to use?');
      expect(title('decision:session-2:r2'), 'Tool approval requested');
    });

    test('deduplicates a repeated decision, approval and failed run', () {
      final items = mergeHermesNeedsYou(
        now: _now,
        decisions: [_decision('r1'), _decision('r1')],
        approvals: [_approval('a1'), _approval('a1')],
        failedJobs: [('ops', _failedJob('j1')), ('ops', _failedJob('j1'))],
      );
      expect(items, hasLength(3));
    });

    test('the same request id in two chats is two decisions', () {
      final items = mergeHermesNeedsYou(
        now: _now,
        decisions: [
          _decision('1'),
          _decision('1', session: 'session-2'),
        ],
      );
      expect(items, hasLength(2));
    });

    test('an approval and a decision with one id are one request, shown '
        'as the approval', () {
      final items = mergeHermesNeedsYou(
        now: _now,
        decisions: [_decision('shared')],
        approvals: [_approval('shared')],
      );
      expect(items.map((item) => item.id), ['approval:shared']);
    });

    test('prepared work in a chat that holds a decision is not repeated', () {
      final items = mergeHermesNeedsYou(
        now: _now,
        decisions: [_decision('r1', session: 'initiative-a')],
        prepared: const [
          HermesSessionSummary(id: 'initiative-a', title: 'Plan'),
          HermesSessionSummary(id: 'initiative-b', title: 'Other plan'),
        ],
      );
      expect(items.map((item) => item.id), [
        'decision:initiative-a:r1',
        'prepared:initiative-b',
      ]);
    });

    test('drops an approval that is no longer pending or is past its '
        'expiry', () {
      final items = mergeHermesNeedsYou(
        now: _now,
        approvals: [
          _approval('live'),
          _approval('done', status: ApprovalStatus.approved),
          _approval(
            'late',
            expiresAt: _now.subtract(const Duration(seconds: 1)),
          ),
        ],
      );
      expect(items.map((item) => item.id), ['approval:live']);
    });

    test('actionable rows come first, then newest first within each', () {
      final items = mergeHermesNeedsYou(
        now: _now,
        decisions: [
          _decision('old', askedAt: _now.subtract(const Duration(hours: 3))),
        ],
        approvals: [
          _approval(
            'new',
            createdAt: _now.subtract(const Duration(minutes: 1)),
          ),
        ],
        prepared: [
          HermesSessionSummary(
            id: 'p-new',
            title: 'New prep',
            updatedAt: _now.subtract(const Duration(minutes: 2)),
          ),
          HermesSessionSummary(
            id: 'p-old',
            title: 'Old prep',
            updatedAt: _now.subtract(const Duration(days: 1)),
          ),
        ],
        failedJobs: [
          (
            'ops',
            _failedJob('j', lastRun: _now.subtract(const Duration(hours: 5))),
          ),
        ],
      );
      expect(items.map((item) => item.id), [
        'approval:new',
        'decision:session-1:old',
        'prepared:p-new',
        'job:ops:j',
        'prepared:p-old',
      ]);
      expect(items.take(2).every((item) => item.actionable), isTrue);
      expect(items.skip(2).any((item) => item.actionable), isFalse);
    });

    test('an approval names the bot that asked, when the gateway knows', () {
      final items = mergeHermesNeedsYou(
        now: _now,
        approvals: [
          _approval('a1', requestedBy: 'scout'),
          _approval('a2', requestedBy: 'unknown'),
          _approval('a3', requestedBy: 'conduit:phone'),
        ],
        botNames: const {'scout': 'Scout'},
      );
      String source(String id) => items.firstWhere((i) => i.id == id).source;
      expect(source('approval:a1'), 'Scout · approval');
      expect(source('approval:a2'), 'Hermes · approval');
      expect(source('approval:a3'), 'Hermes · approval');
    });

    test('untitled prepared work reads as Prepared work', () {
      final items = mergeHermesNeedsYou(
        now: _now,
        prepared: const [
          HermesSessionSummary(id: 'p1', title: 'Untitled session'),
        ],
      );
      expect(items.single.title, 'Prepared work');
    });
  });
}
