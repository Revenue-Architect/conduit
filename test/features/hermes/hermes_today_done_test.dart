import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/views/hermes_today_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // On the S25 the done-today card listed every hourly routine run as an
  // "Untitled session", and opening one showed an empty chat. Done today is
  // conversations; a routine's runs belong to the routine.
  test('done today leaves out routine runs and empty sessions', () {
    final since = DateTime(2026, 10, 31);
    final at = DateTime(2026, 10, 31, 16, 15);
    final done = hermesTodayDoneSessions(
      [
        HermesSessionSummary(
          id: 'chat',
          title: 'Check barber jacks availability',
          source: 'api_server',
          updatedAt: at,
          messageCount: 6,
        ),
        HermesSessionSummary(
          id: 'run',
          title: 'Untitled session',
          source: 'cron',
          updatedAt: at,
          messageCount: 3,
        ),
        HermesSessionSummary(
          id: 'empty',
          title: 'Untitled session',
          source: 'api_server',
          updatedAt: at,
          messageCount: 0,
        ),
      ],
      since: since,
    );
    expect(done.map((s) => s.id), ['chat']);
  });
}
