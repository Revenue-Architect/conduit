import '../models/hermes_session.dart';
import '../sky/hermez_sky.dart';

/// Today's two sentences (docs/app-design-2026-10-30/SPEC.md, copy matrix):
/// what got done, then what needs the owner. Never a greeting.
({String done, String needs}) hermesTodayHeadline({
  required int done,
  required int needs,
  required DateTime now,
  required HermezSkyPhase phase,
}) {
  final morning = now.hour < 12;
  final String first;
  if (done == 0) {
    first = phase == HermezSkyPhase.night
        ? 'Quiet night.'
        : morning
        ? 'Quiet morning.'
        : 'Quiet day.';
  } else {
    first = '$done done ${morning ? 'overnight' : 'today'}.';
  }
  final String second;
  if (needs == 0) {
    second = 'Nothing needs you.';
  } else if (!morning && done > 0) {
    second = '$needs still ${needs == 1 ? 'needs' : 'need'} you.';
  } else {
    second = '$needs ${needs == 1 ? 'needs' : 'need'} you.';
  }
  return (done: first, needs: second);
}

/// Where "done" starts counting: 20:00 yesterday in the morning (so it reads
/// as overnight), midnight after noon.
DateTime hermesTodayDoneSince(DateTime now) {
  final midnight = DateTime(now.year, now.month, now.day);
  return now.hour < 12 ? midnight.subtract(const Duration(hours: 4)) : midnight;
}

/// What Today counts as done: conversations that moved since [since] and
/// are not still working, newest first. A routine's runs (cron, webhook,
/// subagent) and empty sessions are left out: an hourly run is the
/// routine's history, not something finished for the owner, and opening
/// one showed an empty chat.
List<HermesSessionSummary> hermesTodayDoneSessions(
  Iterable<HermesSessionSummary> sessions, {
  required DateTime since,
  Set<String> working = const {},
}) =>
    sessions
        .where(
          (s) =>
              s.updatedAt != null &&
              s.updatedAt!.isAfter(since) &&
              !working.contains(s.id) &&
              !s.isAutomated &&
              s.messageCount != 0,
        )
        .toList()
      ..sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
