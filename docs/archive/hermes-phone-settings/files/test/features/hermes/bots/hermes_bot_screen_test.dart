import 'package:conduit/features/hermes/bots/hermes_bot_screen.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/settings/pages/hermes_bot_editor_extras.dart';
import 'package:conduit/features/hermes/settings/pages/hermes_bot_editor_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a bot name becomes a valid id, and taken or reserved ids are refused',
    () {
      expect(hermesBotIdFor('My Bot'), 'my-bot');
      expect(hermesBotIdFor('  Ops & Research!  '), 'ops--research');
      expect(hermesBotIdProblem('default', const []), contains('reserved'));
      expect(
        hermesBotIdProblem('ops', const ['ops']),
        contains('already exists'),
      );
      expect(hermesBotIdProblem('', const []), isNotNull);
      expect(hermesBotIdProblem('scout', const ['ops']), isNull);
    },
  );

  test('live state comes from the bot chat in Active Work', () {
    final bot = HermesBot.fromJson({
      'name': 'ops',
      'ui_meta': {
        'hermes-bots': {'chat': 's1'},
      },
    })!;
    HermesLiveSession session(String status) => HermesLiveSession(
      runtimeId: 'r1',
      storedId: 's1',
      title: 'Bot Chat',
      status: status,
    );
    expect(
      hermesBotLiveState(bot, AsyncData([session('waiting')])),
      HermesBotLiveState.needsYou,
    );
    expect(
      hermesBotLiveState(bot, AsyncData([session('working')])),
      HermesBotLiveState.working,
    );
    expect(
      hermesBotLiveState(bot, const AsyncData([])),
      HermesBotLiveState.idle,
    );
    expect(
      hermesBotLiveState(bot, const AsyncLoading()),
      HermesBotLiveState.unknown,
    );
  });

  test('avatar uploads accept only PNG, JPEG and WebP', () {
    expect(hermesAvatarMime('me.JPG'), 'image/jpeg');
    expect(hermesAvatarMime('me.webp'), 'image/webp');
    expect(hermesAvatarMime('me.gif'), isNull);
  });
}
