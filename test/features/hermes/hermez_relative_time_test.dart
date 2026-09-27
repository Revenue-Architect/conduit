import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/widgets/hermez_bot_mark.dart';
import 'package:conduit/features/hermes/widgets/hermez_relative_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 27, 15, 0);

  test('relative labels never dump a raw timestamp', () {
    expect(
      hermezRelativeLabel(DateTime(2026, 9, 27, 12, 39), now: now),
      'Today, 12:39 PM',
    );
    expect(
      hermezRelativeLabel(DateTime(2026, 9, 26, 9, 0), now: now),
      'Yesterday, 9:00 AM',
    );
    expect(
      hermezRelativeLabel(DateTime(2026, 9, 27, 13, 40), now: now),
      '1h ago',
    );
    expect(
      hermezWhen(DateTime(2026, 9, 25, 6), now: now, prefix: 'Next'),
      isNot(contains('2026-09-25')),
    );
    expect(
      hermezRelativeLabel(DateTime(2026, 9, 27, 12, 39, 58, 814), now: now),
      isNot(contains('.814')),
    );
  });

  test('bot marks follow the profile name', () {
    HermesBot bot(String name) => HermesBot(name: name, title: name);
    expect(hermezIdentityForBot(bot('kai')), HermezBotIdentity.kai);
    expect(hermezIdentityForBot(bot('local')), HermezBotIdentity.local);
    expect(hermezIdentityForBot(bot('fast')), HermezBotIdentity.fast);
    expect(hermezIdentityForBot(bot('strong')), HermezBotIdentity.strong);
    expect(hermezIdentityForBot(bot('autopilot')), HermezBotIdentity.autopilot);
    expect(hermezIdentityForBot(bot('default')), HermezBotIdentity.neutral);
    expect(
      hermezIdentityForBot(
        const HermesBot(name: 'default', title: 'Fast research assistant'),
      ),
      HermezBotIdentity.neutral,
    );
  });
}
