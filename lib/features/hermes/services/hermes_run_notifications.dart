import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/persistence_keys.dart';
import '../../../core/persistence/preferences_store.dart';
import '../../../core/services/background_streaming_handler.dart';
import '../../../core/utils/debug_logger.dart';
import '../../notifications/models/app_notification.dart';
import '../../notifications/providers/notification_socket_listener.dart'
    show notificationRouterProvider;
import '../../notifications/services/notification_router.dart';
import '../models/hermes_config.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import 'hermes_backend_service.dart';
import 'hermes_desktop_api_service.dart';
import 'hermes_live_activity.dart';
import '../widgets/hermes_home_presence.dart' show hermesAwaySinceProvider;

/// Lets a Hermes bot reach the user first.
///
/// - When a run this app started finishes or fails, or a bot stops to wait
///   for an approval, a question, or a secret, it raises a notification
///   through the app's [NotificationRouter]. The router applies the usual
///   gates: the master toggle, de-duplication, and no alert for the chat the
///   user is looking at.
/// - While a run is working it holds a background lease on the existing
///   foreground service (the one Open WebUI streams use), so Android keeps
///   the connection alive long enough for the run to finish and reach the
///   user. The lease ends with the run, and after 45 minutes at most.
/// - It records when the app was last in use, for Home's "since you were
///   away" summary.
///
/// It only observes what the Desktop connection already receives; it never
/// opens another connection or polls.
final hermesRunNotifierProvider = Provider<HermesRunNotifier>((ref) {
  final notifier = HermesRunNotifier(ref);
  ref.onDispose(notifier.dispose);
  ref.listen<HermesBackendService?>(
    hermesApiServiceProvider,
    (_, next) => notifier.bind(next),
    fireImmediately: true,
  );
  return notifier;
});

class HermesRunNotifier with WidgetsBindingObserver {
  HermesRunNotifier(this._ref) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Ref _ref;

  static const leaseId = 'hermes-run';
  static const _leaseLimit = Duration(minutes: 45);

  HermesDesktopApiService? _service;
  StreamSubscription<HermesLiveActivityEvent>? _activity;
  StreamSubscription<HermesDesktopTurnState>? _turns;

  /// Sessions with a run in progress that this app saw start. A finish is
  /// announced only for these, so a replayed completion after a reconnect
  /// never notifies twice.
  final Set<String> _armed = {};
  bool _leased = false;
  Timer? _leaseCap;

  void bind(HermesBackendService? service) {
    if (identical(service, _service)) return;
    _unbind();
    if (service is! HermesDesktopApiService) return;
    _service = service;
    _activity = service.activityEvents.listen(_onActivity);
    _turns = service.turnStates.listen(_onTurnState);
  }

  void _unbind() {
    unawaited(_activity?.cancel());
    unawaited(_turns?.cancel());
    _activity = null;
    _turns = null;
    _service = null;
    _armed.clear();
    _release();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unbind();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ref.read(hermesAwaySinceProvider.notifier).returned();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(
        PreferencesStore.put(
          PreferenceKeys.hermesLastActiveAt,
          DateTime.now().toUtc().toIso8601String(),
        ),
      );
    }
  }

  void _onTurnState(HermesDesktopTurnState state) {
    switch (state) {
      case HermesDesktopTurnState.running:
        final active = _ref.read(hermesActiveSessionProvider);
        if (active != null) _armed.add(active);
        _hold();
      case HermesDesktopTurnState.idle:
      case HermesDesktopTurnState.unsupportedGateway:
        _release();
      case HermesDesktopTurnState.reconnecting:
      case HermesDesktopTurnState.synchronizing:
        // A run may still be going; keep whatever is held. The cap ends it.
        break;
    }
  }

  void _onActivity(HermesLiveActivityEvent event) {
    final sessionId = event.sessionId;
    switch (event.kind) {
      case HermesLiveActivityKind.waitingForInput:
        final bot = _botLabel(sessionId);
        _route(
          AppNotification(
            kind: NotificationKind.hermesAttention,
            title: '$bot needs you',
            body: _sessionTitle(sessionId) ?? 'Open to review the request.',
            sourceId: sessionId,
            dedupKey:
                'hermes-attention:$sessionId:'
                '${event.detail ?? event.timestamp.millisecondsSinceEpoch ~/ 60000}',
          ),
        );
      case HermesLiveActivityKind.completed:
      case HermesLiveActivityKind.failed:
        if (!_armed.remove(sessionId)) return;
        final bot = _botLabel(sessionId);
        final failed = event.kind == HermesLiveActivityKind.failed;
        _route(
          AppNotification(
            kind: NotificationKind.hermesRun,
            title: failed ? '$bot hit a problem' : '$bot finished',
            body:
                _sessionTitle(sessionId) ??
                (failed ? 'The run failed.' : 'Tap to see what it did.'),
            sourceId: sessionId,
            dedupKey:
                'hermes-run:$sessionId:${event.timestamp.millisecondsSinceEpoch}',
          ),
        );
      default:
        _armed.add(sessionId);
    }
  }

  HermesSessionSummary? _session(String id) {
    final sessions = _ref.read(hermesSessionsProvider).asData?.value;
    if (sessions == null) return null;
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  String _botLabel(String sessionId) {
    final profile = _session(sessionId)?.profile;
    return profile == null || profile.isEmpty || profile == 'default'
        ? 'Hermes'
        : profile;
  }

  String? _sessionTitle(String sessionId) {
    final title = _session(sessionId)?.title.trim();
    return title == null || title.isEmpty ? null : title;
  }

  void _route(AppNotification notification) {
    unawaited(
      _ref.read(notificationRouterProvider).route(notification).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        DebugLogger.error(
          'hermes notification routing failed',
          error: error,
          stackTrace: stackTrace,
          scope: 'hermes/notifications',
        );
        return NotificationSurface.suppressed;
      }),
    );
  }

  void _hold() {
    if (_leased) return;
    _leased = true;
    _leaseCap?.cancel();
    _leaseCap = Timer(_leaseLimit, _release);
    unawaited(
      BackgroundStreamingHandler.instance
          .startBackgroundExecution(const [leaseId])
          .catchError((Object error) {
            _leased = false;
            DebugLogger.error(
              'hermes background lease failed',
              error: error,
              scope: 'hermes/notifications',
            );
          }),
    );
  }

  void _release() {
    _leaseCap?.cancel();
    _leaseCap = null;
    if (!_leased) return;
    _leased = false;
    unawaited(
      BackgroundStreamingHandler.instance.stopBackgroundExecution(const [
        leaseId,
      ]),
    );
  }
}
