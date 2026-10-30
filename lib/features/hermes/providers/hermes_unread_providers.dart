import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../../../core/providers/app_providers.dart'
    show activeConversationProvider;
import '../../../core/services/navigation_service.dart';
import '../../chat/providers/chat_providers.dart'
    show chatMessagesProvider, isChatStreamingProvider;
import '../../navigation/widgets/responsive_drawer_layout.dart'
    show ResponsiveDrawerLayoutState;
import '../models/hermes_bot.dart';
import '../models/hermes_session.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_identifier.dart';
import '../widgets/hermes_home_inbox.dart'
    show hermesChiefProfile, hermesIsBackgroundSession;
import 'hermes_providers.dart';

// Unread conversations. Hermes keeps the read state itself: a per-session
// watermark (`sessions.last_read_at`) that the session list turns into
// `unread`, and that Hermes Desktop's sidebar uses too. Conduit stamps it when
// the owner has the chat on screen with its newest message, and keeps a small
// record on the phone of what it read through, so the badge clears at once,
// holds offline and survives a restart. Both sides are timestamps, so a
// message delivered twice (push, then the reconnect replay) cannot count twice.

/// Bumped when unread state may have moved: Hermes' `sessions.changed`, a
/// foreground push, the app coming back.
class HermesUnreadRefresh extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final hermesUnreadRefreshProvider = NotifierProvider<HermesUnreadRefresh, int>(
  HermesUnreadRefresh.new,
);

/// Session id to the server time (epoch seconds) this phone read it through.
class HermesReadMarks extends Notifier<Map<String, double>> {
  static const storageKey = 'hermes_read_marks_v1';
  static const _keep = 300;

  @override
  Map<String, double> build() {
    try {
      final raw = PreferencesStore.getString(storageKey);
      if (raw == null) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toDouble(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Records that [sessionId] was read through [through]. Never moves back.
  void mark(String sessionId, double through) {
    if ((state[sessionId] ?? double.negativeInfinity) >= through) return;
    final next = {...state, sessionId: through};
    if (next.length > _keep) {
      final oldest = next.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final entry in oldest.take(next.length - _keep)) {
        next.remove(entry.key);
      }
    }
    state = next;
    unawaited(PreferencesStore.put(storageKey, jsonEncode(next)));
  }
}

final hermesReadMarksProvider =
    NotifierProvider<HermesReadMarks, Map<String, double>>(HermesReadMarks.new);

/// The Hermes chat the owner is looking at right now (app in front, chat page
/// on screen), or null.
class HermesVisibleChat extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? sessionId) {
    if (state != sessionId) state = sessionId;
  }
}

final hermesVisibleChatProvider = NotifierProvider<HermesVisibleChat, String?>(
  HermesVisibleChat.new,
);

/// Hermes' watermark for one session, read from the row itself (a bot's
/// canonical chat is hidden from the session list).
final hermesSessionReadStateProvider = FutureProvider.autoDispose
    .family<HermesSessionReadState?, String>((ref, sessionId) async {
      final service = ref.watch(hermesApiServiceProvider);
      if (service is! HermesDesktopApiService) return null;
      ref.watch(hermesUnreadRefreshProvider);
      try {
        return await service.sessionReadState(sessionId);
      } catch (_) {
        return null;
      }
    });

double? _epochSeconds(DateTime? time) =>
    time == null ? null : time.millisecondsSinceEpoch / 1000;

/// True when Hermes counts [sessionId] unread at [lastActive] and this phone
/// has not read through that activity since.
bool _unreadAfterMarks(
  Map<String, double> marks,
  String sessionId, {
  required bool serverUnread,
  required double? lastActive,
}) {
  if (!serverUnread) return false;
  final mark = marks[sessionId];
  // Timestamps parsed into DateTime keep milliseconds; allow for the cut.
  return mark == null || lastActive == null || lastActive > mark + 0.001;
}

/// The conversations with something the owner has not seen: Chief's Bot Chat
/// and the chats Home's inbox lists. The chat on screen is never unread.
final hermesUnreadSessionIdsProvider = Provider<Set<String>>((ref) {
  final sessions =
      ref.watch(hermesSessionsProvider).value ?? const <HermesSessionSummary>[];
  final bots = ref.watch(hermesBotsProvider).value ?? const <HermesBot>[];
  final marks = ref.watch(hermesReadMarksProvider);
  final visible = ref.watch(hermesVisibleChatProvider);
  final unread = <String>{};
  for (final session in sessions) {
    if (session.id == visible || hermesIsBackgroundSession(session)) continue;
    if (_unreadAfterMarks(
      marks,
      session.id,
      serverUnread: session.unread == true,
      lastActive: _epochSeconds(session.updatedAt),
    )) {
      unread.add(session.id);
    }
  }
  final chief = bots.where((bot) => bot.name == hermesChiefProfile).firstOrNull;
  final chat = chief?.chatSessionId;
  if (chat != null &&
      chat != visible &&
      !sessions.any((session) => session.id == chat)) {
    final state = ref.watch(hermesSessionReadStateProvider(chat)).value;
    if (state != null &&
        _unreadAfterMarks(
          marks,
          chat,
          serverUnread: state.unread,
          lastActive: state.lastActive,
        )) {
      unread.add(chat);
    }
  }
  return unread;
});

/// Keeps unread state current and marks chats read. Read once from app
/// startup (`ref.read(hermesUnreadSyncProvider)`).
///
/// A chat is read when the app is in front, the chat page is the one on
/// screen, its transcript is loaded and nothing is streaming into it: then its
/// newest message is what the owner sees. Each new newest message marks it
/// again, so a reply that lands while the chat is open never shows as unread.
final hermesUnreadSyncProvider = Provider<void>((ref) {
  var disposed = false;
  Timer? settle;
  Timer? throttle;
  var pendingRefresh = false;
  String? markedKey;
  StreamSubscription<void>? changes;

  void refresh() {
    if (disposed) return;
    // Hermes broadcasts at most every 2 s, and busy agents keep it firing; one
    // re-read of the lists per 10 s keeps badges current without the churn.
    if (throttle != null) {
      pendingRefresh = true;
      return;
    }
    ref.read(hermesUnreadRefreshProvider.notifier).bump();
    ref.invalidate(hermesSessionsProvider);
    // Chief's row shows the Bot Chat's own preview and time from the roster.
    ref.invalidate(hermesBotsProvider);
    throttle = Timer(const Duration(seconds: 10), () {
      throttle = null;
      if (pendingRefresh) {
        pendingRefresh = false;
        refresh();
      }
    });
  }

  String? visibleSession() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return null;
    }
    final location = NavigationService.currentRoute;
    final path = location == null ? null : Uri.tryParse(location)?.path;
    if (path != Routes.chat ||
        ResponsiveDrawerLayoutState.mobileDrawerShowing.value) {
      return null;
    }
    final active = ref.read(activeConversationProvider);
    if (active?.metadata['backend'] != 'hermes') return null;
    return validateHermesOpaqueIdentifier(active?.metadata['hermesSessionId']);
  }

  Future<void> markRead(String sessionId) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    final marks = ref.read(hermesReadMarksProvider.notifier);
    // At once, from what the lists already say, so the badge clears now.
    final known = [
      for (final session in ref.read(hermesSessionsProvider).value ?? const [])
        if (session.id == sessionId) _epochSeconds(session.updatedAt),
      ref.read(hermesSessionReadStateProvider(sessionId)).value?.lastActive,
    ].whereType<double>();
    if (known.isNotEmpty) {
      marks.mark(sessionId, known.reduce((a, b) => a > b ? a : b));
    }
    try {
      await service.markSessionRead(sessionId);
      // Hermes' own stamp, in its clock, covers whatever landed meanwhile.
      final readAt = (await service.sessionReadState(sessionId)).lastReadAt;
      if (!disposed && readAt != null) marks.mark(sessionId, readAt);
    } catch (error) {
      // Offline or an older gateway: the mark on the phone still holds, and
      // the next look at the chat tells Hermes again.
      final detail = error is DioException
          ? '${error.response?.statusCode} '
                '${'${error.response?.data}'.characters.take(160)}'
          : '$error'.characters.take(160).toString();
      debugPrint('hermes-unread: mark read failed $detail');
      markedKey = null;
    }
  }

  void evaluate() {
    if (disposed) return;
    final sessionId = visibleSession();
    ref.read(hermesVisibleChatProvider.notifier).set(sessionId);
    settle?.cancel();
    if (sessionId == null) {
      markedKey = null;
      return;
    }
    final messages = ref.read(chatMessagesProvider);
    if (messages.isEmpty || ref.read(isChatStreamingProvider)) return;
    final key = '$sessionId|${messages.length}|${messages.last.id}';
    if (key == markedKey) return;
    // Let the transcript settle (a reload replaces it in steps).
    settle = Timer(const Duration(milliseconds: 600), () {
      if (disposed || visibleSession() != sessionId) return;
      markedKey = key;
      unawaited(markRead(sessionId));
    });
  }

  void bindService() {
    unawaited(changes?.cancel());
    changes = null;
    final service = ref.read(hermesApiServiceProvider);
    if (service is HermesDesktopApiService) {
      changes = service.sessionStoreChanges.listen((_) => refresh());
    }
  }

  bindService();
  ref.listen(hermesApiServiceProvider, (_, _) => bindService());
  ref.listen(activeConversationProvider, (_, _) => evaluate());
  ref.listen(chatMessagesProvider, (_, _) => evaluate());
  ref.listen(isChatStreamingProvider, (_, _) => evaluate());
  NavigationService.addRouteListener(evaluate);
  ResponsiveDrawerLayoutState.mobileDrawerShowing.addListener(evaluate);
  final lifecycle = AppLifecycleListener(
    onResume: () {
      refresh();
      evaluate();
    },
    onInactive: evaluate,
    onHide: evaluate,
  );
  ref.onDispose(() {
    disposed = true;
    settle?.cancel();
    throttle?.cancel();
    unawaited(changes?.cancel());
    NavigationService.removeRouteListener(evaluate);
    ResponsiveDrawerLayoutState.mobileDrawerShowing.removeListener(evaluate);
    lifecycle.dispose();
  });
});

/// For a foreground push: a new message may have landed somewhere.
void refreshHermesUnread(Ref ref) {
  ref.read(hermesUnreadRefreshProvider.notifier).bump();
  ref.invalidate(hermesSessionsProvider);
  ref.invalidate(hermesBotsProvider);
}
