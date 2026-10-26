import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_pending_decision_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects a bot roster row', () {
    final bot = HermesBot.fromJson({
      'name': 'researcher',
      'description': 'Reads papers',
      'has_avatar': true,
      'ui_meta': {
        'hermes-bots': {
          'title': 'Research',
          'chat': 'session-7',
          'shape': 'cloud',
          'color': '#14B8A6',
          'imageKind': 'shape',
        },
      },
      'last_session': {
        'preview': 'Found three candidates',
        'last_active': 1700000000,
      },
    });

    check(bot).isNotNull();
    check(bot!.name).equals('researcher');
    check(bot.title).equals('Research');
    check(bot.chatSessionId).equals('session-7');
    check(bot.preview).equals('Found three candidates');
    check(bot.hasAvatar).isTrue();
    check(bot.avatarShape).equals('cloud');
    check(bot.avatarColor).equals('#14b8a6');
    check(bot.avatarImageKind).equals('shape');
    check(bot.lastActive).isNotNull();
  });

  test('the canonical Bot Chat comes from the roster, not a legacy pin', () {
    // Hermes 0.22 names each bot's forever chat by title and reports it as
    // canonical_session; ui_meta['hermes-bots'].chat pins were removed.
    final bot = HermesBot.fromJson({
      'name': 'default',
      'ui_meta': {
        'hermes-bots': {'imageKind': 'photo'},
      },
      'canonical_session': {
        'id': 'local-74f799c6f9f1',
        'resolved_id': 'local-74f799c6f9f2',
      },
      'last_session': {'id': 'webhook-session', 'preview': '[SILENT]'},
    });
    check(bot!.chatSessionId).equals('local-74f799c6f9f2'); // the live tip
    // The pinned row describes the Bot Chat itself, not the newest chat.
    check(bot.preview).isNull();
    final durable = HermesBot.fromJson({
      'name': 'kai',
      'canonical_session': {
        'id': 'local-kai-chat',
        'preview': 'Scope memo is ready.',
        'last_active': 1793028341,
      },
      'last_session': {
        'preview': 'Process email #3',
        'last_active': 1793029000,
      },
    });
    check(durable!.chatSessionId).equals('local-kai-chat');
    check(durable.preview).equals('Scope memo is ready.');
    check(durable.chatLastActive?.millisecondsSinceEpoch).equals(1793028341000);
  });

  test('falls back to the profile name and tolerates missing meta', () {
    final bot = HermesBot.fromJson({'name': 'default'});

    check(bot).isNotNull();
    check(bot!.title).equals('Chief'); // the default profile reads as Chief
    check(bot.chatSessionId).isNull();
    check(bot.preview).isNull();
    check(bot.hasAvatar).isFalse();
  });

  test('rejects rows that cannot scope an RPC profile', () {
    // The name is interpolated into `profile` params; only valid profile ids
    // may become a bot.
    check(HermesBot.fromJson({'name': '../escape'})).isNull();
    check(HermesBot.fromJson({'name': 'Upper'})).isNull();
    check(HermesBot.fromJson({'name': ''})).isNull();
    check(HermesBot.fromJson(const {})).isNull();
  });

  test('falls back from invalid avatar metadata', () {
    final bot = HermesBot.fromJson({
      'name': 'bot',
      'ui_meta': {
        'hermes-bots': {
          'shape': '<script>',
          'color': 'red',
          'imageKind': 'remote-url',
        },
      },
    })!;

    check(bot.avatarShape).equals('squircle');
    check(bot.avatarColor).equals('#8b5cf6');
    check(bot.avatarImageKind).isNull();
  });

  test('ignores a hostile pinned chat id instead of routing to it', () {
    final bot = HermesBot.fromJson({
      'name': 'bot',
      'ui_meta': {
        'hermes-bots': {'chat': '../../etc/passwd'},
      },
    });

    check(bot).isNotNull();
    check(bot!.chatSessionId).isNull();
  });

  test('parses a real pre-Bot-Mode profiles.list row (Hermes 0.20.1)', () {
    // Captured verbatim from a live gateway that predates Bot Mode: no
    // ui_meta, no bot_mode_protocol flag. The row still has to parse, because
    // the same shape is what a Bot-Mode gateway returns for an un-themed bot.
    final bot = HermesBot.fromJson({
      'name': 'default',
      'path': '/data/.hermes',
      'is_default': true,
      'model': 'openai/gpt-5.5',
      'provider': 'auto',
      'description': '',
      'skill_count': 36,
      'last_session': {
        'id': '20260818_064357_f15a11',
        'title': 'Show approval prompt',
        'preview': 'Can you show me an approval prompt',
        'started_at': 1787035437.2407894,
        'last_active': 1787035453.3102949,
        'message_count': 4,
      },
      'has_avatar': false,
    });

    check(bot).isNotNull();
    check(bot!.name).equals('default');
    check(bot.title).equals('Chief');
    check(bot.description).isNull();
    check(bot.chatSessionId).isNull();
    check(bot.preview).equals('Can you show me an approval prompt');
    check(bot.hasAvatar).isFalse();
    check(bot.lastActive).isNotNull();
  });

  test('sorting an unmodifiable roster does not throw', () {
    // The Bot-Mode-off path returns `const []`; sorting that in place throws
    // UnsupportedError, which the provider's catch would mask as "no bots".
    check(sortHermesBotsByRecency(const <HermesBot>[])).isEmpty();
    check(
      sortHermesBotsByRecency(
        List<HermesBot>.unmodifiable([
          HermesBot(name: 'a', title: 'A'),
          HermesBot(name: 'b', title: 'B'),
        ]),
      ),
    ).length.equals(2);
  });

  test('roster is ordered most recently active first', () {
    final sorted = sortHermesBotsByRecency([
      HermesBot(
        name: 'stale',
        title: 'Stale',
        lastActive: DateTime(2026, 1, 1),
      ),
      const HermesBot(name: 'never', title: 'Never'),
      HermesBot(
        name: 'fresh',
        title: 'Fresh',
        lastActive: DateTime(2026, 8, 1),
      ),
    ]);

    check(sorted.map((bot) => bot.name).toList())
        .deepEquals(['fresh', 'stale', 'never']);
  });

  test('prefers the caller-pinned session over the newest one', () {
    final bot = HermesBot.fromJson({
      'name': 'bot',
      'preferred_session': {'preview': 'pinned chat'},
      'last_session': {'preview': 'some other chat'},
    });

    check(bot!.preview).equals('pinned chat');
  });

  test('a persisted decision keeps its bot profile across a restart', () {
    // `_sessionProfiles` is in-memory only. A decision that outlives the
    // process must carry its own profile, or the restored response targets a
    // same-id decision in the CONNECTION profile.
    final stored = HermesPendingDesktopDecision(
      origin: 'https://hermes.example',
      storedSessionId: 'stored-bot',
      runtimeId: 'runtime-bot',
      requestId: 'req-1',
      kind: HermesPendingDesktopDecisionKind.approval,
      expiresAt: DateTime.utc(2030),
      profile: 'researcher',
    ).toStorage();

    final restored = HermesPendingDesktopDecision.fromStorage(stored);
    check(restored).isNotNull();
    check(restored!.profile).equals('researcher');
  });

  test('a tampered profile cannot redirect a restored decision', () {
    String withProfile(Object? value) => jsonEncode({
      'origin': 'https://hermes.example',
      'stored_session_id': 'stored-bot',
      'runtime_id': 'runtime-bot',
      'request_id': 'req-1',
      'kind': 'approval',
      'expires_at': DateTime.utc(2030).toIso8601String(),
      'profile': value,
    });

    // Same validation the RPC layer applies before a profile may scope a call.
    for (final hostile in <Object?>[
      '../../etc/passwd',
      'Upper',
      '',
      {'not': 'a string'},
    ]) {
      final restored = HermesPendingDesktopDecision.fromStorage(
        withProfile(hostile),
      );
      check(restored).isNotNull();
      check(
        restored!.profile,
        because: 'accepted hostile profile: $hostile',
      ).isNull();
    }
  });
}
