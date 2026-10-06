import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/persistence_keys.dart';
import '../../../core/persistence/preferences_store.dart';
import '../../../core/services/background_streaming_handler.dart';
import '../../../core/providers/app_providers.dart'
    show activeConversationProvider;
import '../../../core/utils/debug_logger.dart';
import '../../chat/providers/chat_providers.dart'
    show chatMessagesProvider, isChatStreamingProvider;
import '../../notifications/models/app_notification.dart';
import '../../notifications/providers/notification_center.dart'
    show notificationRouterProvider;
import '../../notifications/services/notification_router.dart';
import '../models/hermes_config.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import 'hermes_backend_service.dart';
import 'hermes_desktop_api_service.dart';
import 'hermes_live_activity.dart';
import 'hermes_pending_decision_store.dart';
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

  /// Per armed run: when it started and the tools it used, for the finished
  /// notification's facts line.
  final Map<String, DateTime> _started = {};
  final Map<String, List<String>> _tools = {};
  bool _leased = false;
  AppLifecycleState? _lifecycle;
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
    _lifecycle = state;
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

  /// Feeds one activity event as the Desktop connection would. For tests.
  @visibleForTesting
  void debugActivity(HermesLiveActivityEvent event) => _onActivity(event);

  void _onTurnState(HermesDesktopTurnState state) {
    switch (state) {
      case HermesDesktopTurnState.running:
        final active = _ref.read(hermesActiveSessionProvider);
        if (active != null) {
          _armed.add(active);
          _started.putIfAbsent(active, DateTime.now);
        }
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
        _trace('waiting', sessionId);
        unawaited(_notifyWaiting(event));
      case HermesLiveActivityKind.completed:
      case HermesLiveActivityKind.failed:
        final kindName = event.kind == HermesLiveActivityKind.failed
            ? 'failed'
            : 'completed';
        _trace(kindName, sessionId);
        if (!_armed.remove(sessionId)) {
          // A replayed or unseen completion: suppressed on purpose.
          _trace('$kindName-suppressed-unarmed', sessionId);
          return;
        }
        unawaited(
          _notifyFinished(
            event,
            failed: event.kind == HermesLiveActivityKind.failed,
            started: _started.remove(sessionId),
            tools: _tools.remove(sessionId) ?? const <String>[],
          ),
        );
      default:
        _armed.add(sessionId);
        _started.putIfAbsent(sessionId, () => event.timestamp);
        final tool = event.detail;
        if (event.kind == HermesLiveActivityKind.toolStarted &&
            tool != null &&
            tool.isNotEmpty) {
          (_tools[sessionId] ??= <String>[]).add(tool);
        }
    }
  }

  /// "kai needs you" with what it is asking: the command waiting for
  /// approval, the question, or which secret or setup it needs.
  Future<void> _notifyWaiting(HermesLiveActivityEvent event) async {
    final sessionId = event.sessionId;
    final bot = _botLabel(sessionId);
    HermesPendingDesktopDecision? decision;
    final service = _ref.read(hermesApiServiceProvider);
    if (service is HermesDesktopApiService) {
      try {
        final pending = await service
            .pendingStoredDecisionsForSession(sessionId)
            .timeout(const Duration(seconds: 2));
        if (pending.isNotEmpty) decision = pending.last;
      } catch (_) {}
    }
    final ask = decision == null ? null : hermesDecisionAsk(decision);
    final title = _sessionTitle(sessionId);
    _route(
      AppNotification(
        kind: NotificationKind.hermesAttention,
        title: '$bot needs you',
        body: [ask ?? 'Open to review the request.', ?title].join('\n'),
        sourceId: sessionId,
        dedupKey:
            'hermes-attention:$sessionId:'
            '${event.detail ?? event.timestamp.millisecondsSinceEpoch ~/ 60000}',
      ),
    );
  }

  /// "fast finished" with the start of the reply, then the conversation,
  /// the tools it used, and how long it took.
  Future<void> _notifyFinished(
    HermesLiveActivityEvent event, {
    required bool failed,
    required DateTime? started,
    required List<String> tools,
  }) async {
    final sessionId = event.sessionId;
    final bot = _botLabel(sessionId);
    final reply = failed ? null : await _replySnippet(sessionId);
    final facts = hermesRunFacts(
      tools: tools,
      elapsed: started == null ? null : event.timestamp.difference(started),
    );
    final title = _sessionTitle(sessionId);
    final lead =
        reply ??
        (failed ? 'The run stopped with an error.' : title) ??
        'Tap to see what it did.';
    final second = [if (title != null && title != lead) title, ?facts];
    _route(
      AppNotification(
        kind: NotificationKind.hermesRun,
        title: failed ? '$bot hit a problem' : '$bot finished',
        body: [lead, if (second.isNotEmpty) second.join(' · ')].join('\n'),
        sourceId: sessionId,
        dedupKey:
            'hermes-run:$sessionId:${event.timestamp.millisecondsSinceEpoch}',
      ),
    );
  }

  /// The start of the run's answer: from the open chat when it is this
  /// session, else the session's stored transcript (bounded wait).
  Future<String?> _replySnippet(String sessionId) async {
    final active = _ref.read(activeConversationProvider);
    if (active?.metadata['hermesSessionId'] == sessionId) {
      // The completed event can land before the answer has finished
      // streaming into the chat; let the stream settle (bounded).
      for (var i = 0; i < 20 && _ref.read(isChatStreamingProvider); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      final messages = _ref.read(chatMessagesProvider);
      for (final message in messages.reversed) {
        if (message.role == 'assistant' && message.content.trim().isNotEmpty) {
          return hermesNotificationSnippet(message.content);
        }
      }
    }
    final service = _ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return null;
    try {
      final messages = await service
          .getSessionMessages(sessionId)
          .timeout(const Duration(seconds: 4));
      for (final message in messages.reversed) {
        final content = message['content'];
        if (message['role'] == 'assistant' &&
            content is String &&
            content.trim().isNotEmpty) {
          return hermesNotificationSnippet(content);
        }
      }
    } catch (_) {}
    return null;
  }

  /// One line per notification-relevant event, for device debugging. Never
  /// includes prompts, answers, secrets, or payloads. Off in release builds.
  void _trace(String event, String sessionId, [Map<String, Object?>? more]) {
    if (kReleaseMode) return;
    final fields = <String, Object?>{
      'event': event,
      'session': sessionId.length > 8 ? sessionId.substring(0, 8) : sessionId,
      'profile': _profile(sessionId) ?? '?',
      'armed': _armed.contains(sessionId),
      'lifecycle':
          (_lifecycle ?? WidgetsBinding.instance.lifecycleState)?.name ??
          'unknown',
      ...?more,
    };
    debugPrint(
      'hermes/notifications ${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
    );
  }

  HermesSessionSummary? _session(String id) {
    final sessions = _ref.read(hermesSessionsProvider).asData?.value;
    if (sessions == null) return null;
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  /// The session's bot: from the session list, else from the binding the
  /// desktop service made when it started the conversation (a brand-new
  /// chat is not in the list until the next refresh).
  String? _profile(String sessionId) {
    final listed = _session(sessionId)?.profile;
    if (listed != null && listed.isNotEmpty) return listed;
    final service = _ref.read(hermesApiServiceProvider);
    return service is HermesDesktopApiService
        ? service.boundProfileFor(sessionId)
        : null;
  }

  String _botLabel(String sessionId) {
    final profile = _profile(sessionId);
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
      _ref
          .read(notificationRouterProvider)
          .route(notification)
          .then((surface) {
            _trace('routed', notification.sourceId, {
              'kind': notification.kind.name,
              'surface': surface.name,
              'system_attempted': surface == NotificationSurface.system,
            });
            return surface;
          })
          .catchError((Object error, StackTrace stackTrace) {
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

/// Plain, one-paragraph text for a notification: markdown marks, code
/// fences and extra whitespace removed, cut at a word near [max].
@visibleForTesting
String? hermesNotificationSnippet(String text, {int max = 220}) {
  // Lead with the answer: skip a short narration paragraph ("…so let me
  // check live conditions.") and parenthetical asides ("(Saved to …)").
  final narration = RegExp(
    r"\b(let me|i'll|i will|i'm going to|i am going to)\b",
    caseSensitive: false,
  );
  final paragraphs = text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .split(RegExp(r'\n\s*\n'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  final answer = paragraphs.where(
    (part) =>
        !part.startsWith('(') &&
        !part.startsWith('#') &&
        !(part.length < 200 && narration.hasMatch(part)),
  );
  if (paragraphs.length > 1 && answer.isNotEmpty) text = answer.first;
  var plain = text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAllMapped(
        RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
        (match) => match.group(1) ?? '',
      )
      .replaceAll(
        RegExp(r'^\s{0,3}(#{1,6}|[-*+>]|\d+\.)\s+', multiLine: true),
        '',
      )
      .replaceAll(RegExp(r'[*_`~]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (plain.isEmpty) return null;
  if (plain.length <= max) return plain;
  plain = plain.substring(0, max);
  final space = plain.lastIndexOf(' ');
  if (space > max * 0.6) plain = plain.substring(0, space);
  return '${plain.trimRight()}…';
}

/// "Used web search, terminal · 42s": what a finished run did.
@visibleForTesting
String? hermesRunFacts({required List<String> tools, Duration? elapsed}) {
  final names = {for (final tool in tools) tool.replaceAll('_', ' ')}.toList();
  final parts = <String>[
    if (names.isNotEmpty)
      names.length <= 3
          ? 'Used ${names.join(', ')}'
          : 'Used ${names.take(2).join(', ')} +${names.length - 2} more',
    if (elapsed != null && elapsed.inSeconds > 0)
      elapsed.inMinutes >= 1
          ? '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s'
          : '${elapsed.inSeconds}s',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// What a waiting bot is asking, in a line.
@visibleForTesting
String hermesDecisionAsk(HermesPendingDesktopDecision decision) {
  final prompt = decision.prompt == null
      ? null
      : hermesNotificationSnippet(decision.prompt!, max: 160);
  return switch (decision.kind) {
    HermesPendingDesktopDecisionKind.approval =>
      prompt == null ? 'Approve an action to continue.' : 'Approve: $prompt',
    HermesPendingDesktopDecisionKind.clarification =>
      prompt ?? 'Answer a question to continue.',
    HermesPendingDesktopDecisionKind.sudo =>
      'Needs an administrator password to continue.',
    HermesPendingDesktopDecisionKind.secret =>
      prompt == null
          ? 'Needs a secret to continue.'
          : 'Needs a secret: $prompt',
    HermesPendingDesktopDecisionKind.mcpSetup =>
      'Set up ${decision.mcpServer ?? 'an MCP server'} to continue.',
    HermesPendingDesktopDecisionKind.connectorOperation =>
      'Review connector access to continue.',
  };
}
