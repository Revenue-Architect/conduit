import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The rule: a new routine never starts running on save; it waits, paused,
  // until the owner turns it on.
  test('a routine created in Conduit is saved paused', () {
    final body = hermesNewRoutineBody(
      name: 'Storefront images',
      prompt: 'Check the storefront for broken images',
      schedule: 'every weekday 8am',
    );
    expect(body['paused'], isTrue);
    expect(body['schedule'], 'every weekday 8am');
  });
}
