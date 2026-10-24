import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/models/hermes_job.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart'
    show HermesLiveSession;
import 'package:conduit/features/hermes/widgets/hermes_home_inbox.dart';
import 'package:conduit/features/hermes/widgets/hermes_home_lines.dart';
import 'package:conduit/features/hermes/widgets/hermes_home_working.dart';
import 'package:conduit/features/hermes/widgets/hermes_session_tile.dart'
    show hermesInboxTimeLabel;
import 'package:flutter_test/flutter_test.dart';

HermesSessionSummary _session(
  String id, {
  String? profile = 'kai',
  String? source,
  String? preview,
}) => HermesSessionSummary(
  id: id,
  title: 'Chat $id',
  profile: profile,
  source: source,
  preview: preview,
);

HermesLiveSession _live(
  String id, {
  String status = 'working',
  String? preview,
}) => HermesLiveSession(
  runtimeId: 'rt-$id',
  storedId: id,
  title: 'Chat $id',
  status: status,
  preview: preview,
);

void main() {
  group('buildHermesInbox', () {
    test('pins the canonical Chief chat first, once', () {
      final rows = buildHermesInbox(
        sessions: [
          _session('s1'),
          _session('chief-chat', profile: 'default'),
          _session('s2'),
        ],
        bots: const [
          HermesBot(name: 'kai', title: 'Kai'),
          HermesBot(
            name: 'default',
            title: 'Default',
            chatSessionId: 'chief-chat',
          ),
        ],
      );
      expect(rows.map((row) => row.session.id), ['chief-chat', 's1', 's2']);
      expect(rows.first.pinned, isTrue);
      expect(rows.first.name, 'Chief');
      expect(rows.first.listed, isTrue);
      expect(rows.skip(1).any((row) => row.pinned), isFalse);
    });

    test('draws Chief from the bot when its canonical chat is not listed', () {
      final last = DateTime(2026, 10, 24, 9);
      final rows = buildHermesInbox(
        sessions: [_session('s1')],
        bots: [
          HermesBot(
            name: 'default',
            title: 'Chief',
            chatSessionId: 'hidden-chief',
            preview: 'Asked Scout.',
            lastActive: last,
          ),
        ],
      );
      expect(rows.first.session.id, 'hidden-chief');
      expect(rows.first.session.preview, 'Asked Scout.');
      expect(rows.first.session.updatedAt, last);
      // A hidden chat is not one to fork, rename or delete from a row.
      expect(rows.first.listed, isFalse);
      expect(rows.map((row) => row.session.id), ['hidden-chief', 's1']);
    });

    test('falls back to the newest Chief conversation, else none', () {
      final withChief = buildHermesInbox(
        sessions: [
          _session('s1'),
          _session('c1', profile: 'default'),
          _session('c2', profile: 'default'),
        ],
        bots: const [HermesBot(name: 'default', title: 'Chief')],
      );
      expect(withChief.first.session.id, 'c1');
      expect(withChief.first.name, 'Chief');
      expect(withChief.map((row) => row.session.id), ['c1', 's1', 'c2']);

      final without = buildHermesInbox(
        sessions: [_session('s1'), _session('s2')],
        bots: const [HermesBot(name: 'default', title: 'Chief')],
      );
      expect(without.map((row) => row.session.id), ['s1', 's2']);
      expect(without.any((row) => row.pinned), isFalse);
    });

    test(
      'leaves background sessions out: workers, routines, one-off checks',
      () {
        final rows = buildHermesInbox(
          sessions: [
            _session('s1'),
            _session('child', source: 'subagent'),
            _session('s2', source: 'cron'),
            _session('s3', source: 'mobile'),
          ],
        );
        expect(rows.map((row) => row.session.id), ['s1', 's3']);
      },
    );

    test('shows at most eight rows, Chief among them', () {
      final rows = buildHermesInbox(
        sessions: [for (var i = 0; i < 12; i++) _session('s$i')],
        bots: const [
          HermesBot(name: 'default', title: 'Chief', chatSessionId: 'chief'),
        ],
      );
      expect(rows, hasLength(hermesInboxVisibleRows));
      expect(rows.first.session.id, 'chief');
    });

    test('carries only the live state it is given', () {
      final rows = buildHermesInbox(
        sessions: [_session('s1'), _session('s2'), _session('s3')],
        workingLines: const {'s2': 'checking service logs…'},
        needsYouIds: const {'s3'},
      );
      expect(rows[0].liveLine, isNull);
      expect(rows[0].needsYou, isFalse);
      expect(rows[1].liveLine, 'checking service logs…');
      expect(rows[2].needsYou, isTrue);

      final stale = buildHermesInbox(sessions: [_session('s2')]);
      expect(stale.single.liveLine, isNull);
    });
  });

  group('hermesWorkingAgents', () {
    String? profileOf(String id) => {'a': 'kai', 'b': 'ops', 'c': 'kai'}[id];

    test('lists working agents once per bot, in Hermes\' order', () {
      final agents = hermesWorkingAgents([
        _live('a', preview: 'reading the logs'),
        _live('b', status: 'starting'),
        _live('c'),
      ], profileOf: profileOf);
      expect(agents.map((agent) => agent.profile), ['kai', 'ops']);
      expect(agents[0].line, 'reading the logs');
      expect(agents[1].line, 'Starting…');
    });

    test('a session waiting on the owner or idle is not working', () {
      final agents = hermesWorkingAgents([
        _live('a', status: 'waiting'),
        _live('b', status: 'idle'),
      ], profileOf: profileOf);
      expect(agents, isEmpty);
    });

    test('says Working… when Hermes has said nothing yet', () {
      expect(
        hermesWorkingAgents([_live('a')], profileOf: profileOf).single.line,
        'Working…',
      );
    });

    test('claims nothing from stale data or a session it cannot place', () {
      expect(
        hermesWorkingAgents([_live('a')], profileOf: profileOf, stale: true),
        isEmpty,
      );
      expect(
        hermesWorkingAgents([_live('zzz')], profileOf: profileOf),
        isEmpty,
      );
    });
  });

  group('hermesProfileOfSession', () {
    test('uses the session list, then the bot whose chat it is', () {
      const bots = [
        HermesBot(name: 'default', title: 'Chief', chatSessionId: 'chief'),
      ];
      final sessions = [_session('s1', profile: 'ops')];
      expect(
        hermesProfileOfSession('s1', sessions: sessions, bots: bots),
        'ops',
      );
      expect(
        hermesProfileOfSession('chief', sessions: sessions, bots: bots),
        'default',
      );
      expect(
        hermesProfileOfSession('other', sessions: sessions, bots: bots),
        isNull,
      );
    });
  });

  group('hermesInboxTimeLabel', () {
    final now = DateTime(2026, 10, 24, 15, 30);
    test('reads as a messenger does', () {
      expect(hermesInboxTimeLabel(now, now: now), 'now');
      expect(
        hermesInboxTimeLabel(
          now.subtract(const Duration(minutes: 12)),
          now: now,
        ),
        '12m',
      );
      expect(
        hermesInboxTimeLabel(DateTime(2026, 10, 24, 9, 5), now: now),
        '9:05 AM',
      );
      expect(
        hermesInboxTimeLabel(DateTime(2026, 10, 23, 22), now: now),
        'Yesterday',
      );
      // 2026-10-21 is a Wednesday.
      expect(hermesInboxTimeLabel(DateTime(2026, 10, 21, 8), now: now), 'Wed');
      expect(hermesInboxTimeLabel(DateTime(2026, 10, 3, 8), now: now), 'Oct 3');
    });

    test('a time slightly ahead of the clock reads as now', () {
      expect(
        hermesInboxTimeLabel(now.add(const Duration(seconds: 20)), now: now),
        'now',
      );
    });
  });

  group('Later today', () {
    final now = DateTime(2026, 10, 24, 12);
    HermesJob job(String id, {DateTime? next, bool enabled = true}) =>
        HermesJob(
          id: id,
          prompt: 'p',
          schedule: '* * * * *',
          enabled: enabled,
          nextRun: next,
        );

    test('counts enabled routines whose next run is still to come today', () {
      final jobs = [
        ('kai', job('later', next: DateTime(2026, 10, 24, 18))),
        ('kai', job('passed', next: DateTime(2026, 10, 24, 8))),
        ('kai', job('tomorrow', next: DateTime(2026, 10, 25, 9))),
        (
          'ops',
          job('paused', next: DateTime(2026, 10, 24, 20), enabled: false),
        ),
        ('ops', job('unscheduled')),
      ];
      expect(hermesRoutinesLaterToday(jobs, now).map((item) => item.$2.id), [
        'later',
      ]);
    });

    test('words the count', () {
      expect(hermesLaterTodayLabel(1), 'Later today · 1 routine');
      expect(hermesLaterTodayLabel(2), 'Later today · 2 routines');
    });
  });
}
