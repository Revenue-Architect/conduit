import 'package:conduit/core/providers/backend_mode_providers.dart';
import 'package:conduit/features/hermes/sheets/hermes_connect_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The rule (owner: "don't disconnect the current connection"): connecting
  // Hermes from the card makes it the app's backend only on a first run;
  // with a backend already chosen it is saved and turned on beside it.
  Future<List<String>> connect(PreferredBackend backend) async {
    final calls = <String>[];
    final ok = await connectHermesKeepingCurrent(
      backend: backend,
      finishOnboarding: () async {
        calls.add('onboard');
        return true;
      },
      testConnection: () async {
        calls.add('test');
        return true;
      },
      save: () async {
        calls.add('save');
        return true;
      },
      enable: () async => calls.add('enable'),
    );
    expect(ok, isTrue);
    return calls;
  }

  test('Hermes joins an existing connection without replacing it', () async {
    expect(await connect(PreferredBackend.owui), ['test', 'save', 'enable']);
    expect(await connect(PreferredBackend.direct), ['test', 'save', 'enable']);
    expect(await connect(PreferredBackend.unset), ['onboard']);
  });
}
