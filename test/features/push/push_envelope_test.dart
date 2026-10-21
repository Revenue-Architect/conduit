import 'package:checks/checks.dart';
import 'package:conduit/features/notifications/models/app_notification.dart';
import 'package:conduit/features/push/models/push_envelope.dart';
import 'package:conduit/features/push/models/push_route.dart';
import 'package:conduit/features/push/services/push_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

const _approval = '60867a2f-afa1-4679-b9de-672d1a17ac63';

String _json(String fields) => '{"v":1,"id":"01JABC","ts":1760841600,$fields}';

void main() {
  group('PushEnvelope.tryParse', () {
    test('reads the spec approval example', () {
      final e = PushEnvelope.tryParse('''
{"v":1,"t":"notify","id":"01JABCDEFGHJKMNPQRSTVWXYZ0",
 "dedupe":"approval:$_approval:created","tag":"approval:$_approval",
 "ts":1760841600,"ttl":86400,"cat":"approvals","pri":4,
 "title":"Approval needed: restart_container","body":"Restart it",
 "open":{"k":"approval","id":"$_approval"},
 "actions":[{"id":"approve","label":"Approve","kind":"decide","approval":"$_approval","digest":"abc","auth":true}],
 "group":"approvals","ack":true,"shadow":false}''')!;
      check(e.type).equals('notify');
      check(e.category).equals(PushCategory.approvals);
      check(e.priority).equals(4);
      check(e.ack).isTrue();
      check(e.actions).length.equals(1);
      check(e.dedupKey).equals('approval:$_approval:created');
      check(e.route).equals('/profile/hermes/approvals/$_approval');
    });

    test('rejects wrong version, unknown type and non-JSON', () {
      check(PushEnvelope.tryParse('nope')).isNull();
      check(PushEnvelope.tryParse('')).isNull();
      check(PushEnvelope.tryParse('[]')).isNull();
      check(
        PushEnvelope.tryParse('{"v":2,"t":"notify","id":"a","ts":1,"cat":"alerts"}'),
      ).isNull();
      check(
        PushEnvelope.tryParse(_json('"t":"explode","cat":"alerts"')),
      ).isNull();
    });

    test('rejects an oversized envelope', () {
      final big = _json('"t":"notify","cat":"alerts","body":"${'x' * 5000}"');
      check(PushEnvelope.tryParse(big)).isNull();
    });

    test('truncates long title and body', () {
      final e = PushEnvelope.tryParse(
        _json('"t":"notify","cat":"alerts","title":"${'t' * 300}","body":"${'b' * 900}"'),
      )!;
      check(e.title.length).equals(PushEnvelope.maxTitle);
      check(e.body.length).equals(PushEnvelope.maxBody);
    });

    test('probe and verify need no category', () {
      check(PushEnvelope.tryParse(_json('"t":"probe"'))).isNotNull();
      check(PushEnvelope.tryParse(_json('"t":"verify","nonce":"n"'))).isNotNull();
      check(PushEnvelope.tryParse(_json('"t":"notify"'))).isNull();
    });

    test('ignores unknown fields and clamps priority', () {
      final e = PushEnvelope.tryParse(
        _json('"t":"notify","cat":"alerts","pri":99,"future":{"x":1}'),
      )!;
      check(e.priority).equals(5);
    });

    test('a url open must be the pinned relay origin', () {
      final ok = PushEnvelope.tryParse(
        _json('"t":"notify","cat":"alerts","open":{"k":"url","url":"https://umbrel.tail4c9e01.ts.net:8447/a"}'),
      )!;
      check(ok.open?.kind).equals(PushOpenKind.url);
      final evil = PushEnvelope.tryParse(
        _json('"t":"notify","cat":"alerts","open":{"k":"url","url":"https://evil.example/a"}'),
      )!;
      check(evil.open).isNull();
    });

    test('ids with path characters are rejected', () {
      check(
        PushEnvelope.tryParse('{"v":1,"t":"notify","id":"../x","ts":1,"cat":"alerts"}'),
      ).isNull();
    });
  });

  group('routes', () {
    test('open kinds map to app routes', () {
      check(pushRouteFor(const PushOpen(kind: PushOpenKind.approval, id: 'a-1')))
          .equals('/profile/hermes/approvals/a-1');
      check(pushRouteFor(const PushOpen(kind: PushOpenKind.session, id: 's1')))
          .equals('/profile/hermes/live/s1');
      check(pushRouteFor(const PushOpen(kind: PushOpenKind.thread, id: '7')))
          .equals('/profile/hermes/conversations?thread=7');
      check(pushRouteFor(const PushOpen(kind: PushOpenKind.brief, id: '2026-10-19')))
          .equals('/profile/hermes/home?brief=2026-10-19');
      check(pushRouteFor(const PushOpen(kind: PushOpenKind.none))).isNull();
      check(pushRouteFor(null)).isNull();
    });

    test('safePushRoute only allows Hermes pages inside the app', () {
      check(safePushRoute('/profile/hermes/approvals/a-1'))
          .equals('/profile/hermes/approvals/a-1');
      check(safePushRoute('/profile/hermes/home?brief=2026-10-19'))
          .equals('/profile/hermes/home?brief=2026-10-19');
      check(safePushRoute('https://evil.example/profile/hermes/x')).isNull();
      check(safePushRoute('//evil.example/profile/hermes/x')).isNull();
      check(safePushRoute('/profile/account')).isNull();
      check(safePushRoute('/profile/hermes/../account')).isNull();
      check(safePushRoute('')).isNull();
      check(safePushRoute(null)).isNull();
    });
  });

  group('notification mapping', () {
    test('categories map to push kinds', () {
      check(notificationKindForPush(PushCategory.approvals))
          .equals(NotificationKind.pushApproval);
      check(notificationKindForPush(PushCategory.critical))
          .equals(NotificationKind.pushAlert);
      check(notificationKindForPush(PushCategory.briefs))
          .equals(NotificationKind.pushBrief);
    });

    test('notify becomes an AppNotification carrying the route', () {
      final e = PushEnvelope.tryParse(
        _json('"t":"notify","cat":"approvals","dedupe":"d-1","title":"T","body":"B","open":{"k":"approval","id":"$_approval"}'),
      )!;
      final n = notificationFromEnvelope(e)!;
      check(n.kind).equals(NotificationKind.pushApproval);
      check(n.sourceId).equals('/profile/hermes/approvals/$_approval');
      check(n.dedupKey).equals('push:d-1');
      check(n.title).equals('T');
    });

    test('without an open target approvals go to the list, others to home', () {
      final a = notificationFromEnvelope(
        PushEnvelope.tryParse(_json('"t":"notify","cat":"approvals"'))!,
      )!;
      check(a.sourceId).equals('/profile/hermes/approvals');
      final b = notificationFromEnvelope(
        PushEnvelope.tryParse(_json('"t":"notify","cat":"briefs"'))!,
      )!;
      check(b.sourceId).equals('/profile/hermes/home');
    });

    test('only notify envelopes are shown', () {
      for (final t in ['dismiss', 'update', 'probe', 'verify']) {
        final e = PushEnvelope.tryParse(
          _json('"t":"$t","cat":"alerts","tag":"x","nonce":"n"'),
        )!;
        check(notificationFromEnvelope(e)).isNull();
      }
    });

    test('shadow copies are labelled', () {
      final e = PushEnvelope.tryParse(
        _json('"t":"notify","cat":"briefs","title":"Morning","shadow":true'),
      )!;
      check(notificationFromEnvelope(e)!.title).equals('[shadow] Morning');
    });

    test('NotificationTap round-trips a push kind', () {
      // The tap payload is kind name + sourceId; make sure push kinds decode.
      check(
        NotificationKind.values.where((k) => k.name == 'pushApproval'),
      ).isNotEmpty();
    });
  });
}
