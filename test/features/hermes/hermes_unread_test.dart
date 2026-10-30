import 'package:conduit/core/persistence/preferences_store.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/providers/hermes_unread_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chat = 'local-74f799c6f9f1';

DateTime _at(double seconds) =>
    DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());

List<HermesSessionSummary> _rows = const [];

class _Sessions extends HermesSessionsController {
  @override
  Future<List<HermesSessionSummary>> build() async => _rows;
}

Future<ProviderContainer> _container({
  List<HermesSessionSummary> sessions = const [],
  HermesSessionReadState? chiefChat,
}) async {
  _rows = sessions;
  final container = ProviderContainer(
    overrides: [
      hermesApiServiceProvider.overrideWithValue(null),
      hermesSessionsProvider.overrideWith(_Sessions.new),
      hermesBotsProvider.overrideWith(
        (ref) async => const [
          HermesBot(name: 'default', title: 'Chief', chatSessionId: _chat),
        ],
      ),
      hermesSessionReadStateProvider(_chat)
          .overrideWith((ref) async => chiefChat),
    ],
  );
  addTearDown(container.dispose);
  container.listen(hermesUnreadSessionIdsProvider, (_, _) {});
  await container.read(hermesSessionsProvider.future);
  await container.read(hermesBotsProvider.future);
  await container.read(hermesSessionReadStateProvider(_chat).future);
  return container;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PreferencesStore.debugReset();
    await PreferencesStore.ensureInitialized();
  });

  group('HermesSessionReadState', () {
    test('a session Hermes never tracked reads as read', () {
      final state = HermesSessionReadState.fromJson({
        'last_read_at': null,
        'last_activity_at': 200.0,
      });
      expect(state.unread, isFalse);
    });

    test('activity after the watermark is unread, using the freshest time', () {
      final state = HermesSessionReadState.fromJson({
        'last_read_at': 150.0,
        'started_at': 100.0,
        'last_activity_at': 160.5,
      });
      expect(state.lastActive, 160.5);
      expect(state.unread, isTrue);
      expect(
        HermesSessionReadState.fromJson({
          'last_read_at': 170.0,
          'last_activity_at': 160.5,
        }).unread,
        isFalse,
      );
    });

    test('the session list carries Hermes\' unread flag', () {
      final row = HermesSessionSummary.fromJson({
        'id': 's1',
        'title': 'Plan',
        'unread': true,
      });
      expect(row!.unread, isTrue);
      expect(HermesSessionSummary.fromJson({'id': 's2'})!.unread, isNull);
    });
  });

  group('hermesUnreadSessionIdsProvider', () {
    test('a new Bot Chat turn is unread until the phone reads it', () async {
      final container = await _container(
        chiefChat: const HermesSessionReadState(
          lastReadAt: 100,
          lastActive: 120,
        ),
      );
      expect(container.read(hermesUnreadSessionIdsProvider), {_chat});

      container.read(hermesReadMarksProvider.notifier).mark(_chat, 120);
      expect(container.read(hermesUnreadSessionIdsProvider), isEmpty);
    });

    test('the chat on screen is never unread', () async {
      final container = await _container(
        chiefChat: const HermesSessionReadState(
          lastReadAt: 100,
          lastActive: 120,
        ),
      );
      container.read(hermesVisibleChatProvider.notifier).set(_chat);
      expect(container.read(hermesUnreadSessionIdsProvider), isEmpty);
    });

    test('a listed conversation follows the list flag and the marks', () async {
      final container = await _container(
        sessions: [
          HermesSessionSummary(
            id: 'conv',
            title: 'Supplier call',
            unread: true,
            updatedAt: _at(300.25),
          ),
          HermesSessionSummary(
            id: 'cron-run',
            title: 'Morning brief',
            source: 'cron',
            unread: true,
            updatedAt: _at(300),
          ),
          HermesSessionSummary(id: 'quiet', title: 'Old', unread: false),
        ],
      );
      // Background runs are not conversations the inbox shows.
      expect(container.read(hermesUnreadSessionIdsProvider), {'conv'});

      container.read(hermesReadMarksProvider.notifier).mark('conv', 300.25);
      expect(container.read(hermesUnreadSessionIdsProvider), isEmpty);
    });

    test('the same message delivered twice counts once, a newer one counts '
        'again', () async {
      final container = await _container(
        chiefChat: const HermesSessionReadState(
          lastReadAt: 100,
          lastActive: 120,
        ),
      );
      container.read(hermesReadMarksProvider.notifier).mark(_chat, 120);
      // Push, then the reconnect replay: same activity time, still read.
      container.read(hermesUnreadRefreshProvider.notifier).bump();
      await container.pump();
      expect(container.read(hermesUnreadSessionIdsProvider), isEmpty);

      // A later cron turn moves Hermes' activity past the phone's mark.
      final later = await _container(
        chiefChat: const HermesSessionReadState(
          lastReadAt: 100,
          lastActive: 130,
        ),
      );
      expect(later.read(hermesUnreadSessionIdsProvider), {_chat});
    });
  });

  group('HermesReadMarks', () {
    test('survive a restart and never move back', () async {
      final first = ProviderContainer();
      first.read(hermesReadMarksProvider.notifier)
        ..mark(_chat, 120)
        ..mark(_chat, 90);
      expect(first.read(hermesReadMarksProvider)[_chat], 120);
      first.dispose();
      await Future<void>.delayed(Duration.zero);

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      expect(restarted.read(hermesReadMarksProvider)[_chat], 120);
    });
  });
}
