import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';

import '../../chat/providers/chat_providers.dart' show chatMessagesProvider;
import '../../hermes/models/hermes_config.dart';
import '../../hermes/providers/hermes_providers.dart';
import '../../hermes/services/hermes_desktop_api_service.dart';
import '../../hermes/services/hermes_identifier.dart';
import '../models/approval.dart';
import '../providers/push_providers.dart';
import 'approval_widgets.dart';

class ApprovalContinuation {
  const ApprovalContinuation(this.approval, this.owner);
  final Approval approval;
  final Object owner;
}

/// Holds the one approval whose resume status the open chat is showing.
/// Finished or dismissed approvals are remembered so the notice never comes
/// back for them when the chat is reopened.
class ApprovalContinuationNotifier extends Notifier<ApprovalContinuation?> {
  final Set<String> _finished = <String>{};

  @override
  ApprovalContinuation? build() => null;

  void show(Approval approval, Object owner) {
    if (_finished.contains(approval.id)) return;
    final resolved = approval.resolvedAt;
    // Opening an old, already-settled request's chat is plain navigation.
    if (!approval.isPending &&
        resolved != null &&
        DateTime.now().difference(resolved) > approvalNoticeMaxAge) {
      return;
    }
    state = ApprovalContinuation(approval, owner);
  }

  void dismiss() {
    final current = state;
    if (current != null) _finished.add(current.approval.id);
    state = null;
  }
}

final approvalContinuationProvider =
    NotifierProvider<ApprovalContinuationNotifier, ApprovalContinuation?>(
      ApprovalContinuationNotifier.new,
    );

/// A notice older than this is not worth showing again.
const approvalNoticeMaxAge = Duration(minutes: 10);

/// How long the phone waits for the agent's reply after the wake was sent.
const approvalResumeGrace = Duration(seconds: 90);

enum ApprovalResumePhase {
  /// Still waiting for a decision.
  awaitingDecision,

  /// Decision recorded; the server has not woken the agent yet.
  recording,

  /// Wake dispatched; nothing visible in the chat yet.
  requested,

  /// The automated notice is in the chat; the agent is composing its answer.
  working,

  /// The agent's answer is in the chat.
  resumed,

  /// Decision recorded; this request does not resume the chat.
  recordedOnly,

  /// Request cancelled.
  cancelled,

  /// Could not resume (server says so).
  failed,

  /// Dispatched, but no reply within the grace period.
  stalled;

  bool get inProgress =>
      this == awaitingDecision ||
      this == recording ||
      this == requested ||
      this == working;

  /// Finished fine: the notice may close itself.
  bool get autoCloses =>
      this == resumed || this == recordedOnly || this == cancelled;

  bool get isProblem => this == failed || this == stalled;
}

/// Pure mapping from server state and what the chat shows to a phase.
ApprovalResumePhase approvalResumePhase(
  Approval approval, {
  required bool wakeMessageVisible,
  required bool replyVisible,
  required DateTime now,
}) {
  if (approval.isPending) return ApprovalResumePhase.awaitingDecision;
  if (approval.status == ApprovalStatus.cancelled) {
    return ApprovalResumePhase.cancelled;
  }
  if (approval.wakeMode != 'resume') return ApprovalResumePhase.recordedOnly;
  final resolved = approval.resolvedAt;
  switch (approval.wakeState) {
    case 'pending' || 'retry':
      if (resolved != null &&
          now.difference(resolved) >= const Duration(minutes: 2)) {
        return ApprovalResumePhase.stalled;
      }
      return ApprovalResumePhase.recording;
    case 'sent':
      if (replyVisible) return ApprovalResumePhase.resumed;
      final sent = approval.wakeSentAt ?? resolved;
      if (sent != null && now.difference(sent) >= approvalResumeGrace) {
        return ApprovalResumePhase.stalled;
      }
      return wakeMessageVisible
          ? ApprovalResumePhase.working
          : ApprovalResumePhase.requested;
    case 'gone' || 'failed':
      return ApprovalResumePhase.failed;
    default:
      return ApprovalResumePhase.recordedOnly;
  }
}

String approvalResumeText(Approval approval, ApprovalResumePhase phase) {
  final word = approval.decisionWord;
  return switch (phase) {
    ApprovalResumePhase.awaitingDecision => 'Waiting for your decision.',
    ApprovalResumePhase.recording => '$word. Telling the agent…',
    ApprovalResumePhase.requested => '$word. Waking the agent…',
    ApprovalResumePhase.working => '$word. The agent is replying…',
    ApprovalResumePhase.resumed => '$word. The agent has continued below.',
    ApprovalResumePhase.recordedOnly =>
      '$word. This request does not continue the chat.',
    ApprovalResumePhase.cancelled => 'This request was cancelled.',
    ApprovalResumePhase.failed =>
      'Couldn\u2019t continue this chat. Your decision was recorded.',
    ApprovalResumePhase.stalled =>
      '$word, but the agent has not replied yet. Your decision was recorded.',
  };
}

String? approvalConversationRoute(Approval approval) {
  final sid = validateHermesOpaqueIdentifier(approval.originSessionId);
  final profile = approval.originProfile;
  if (sid == null ||
      profile == null ||
      !HermesConfig.isValidDesktopProfile(profile)) {
    return null;
  }
  return '/profile/hermes/live/${Uri.encodeComponent(sid)}?${Uri(queryParameters: {'open': 'chat', 'profile': profile}).query}';
}

bool openApprovalConversation(
  BuildContext context,
  WidgetRef ref,
  Approval approval, {
  bool replace = false,
}) {
  final route = approvalConversationRoute(approval);
  final service = ref.read(hermesApiServiceProvider);
  if (route == null || service is! HermesDesktopApiService) {
    showApprovalSnack(
      context,
      'The originating chat or bot is unavailable. Your decision is unchanged.',
      error: true,
    );
    return false;
  }
  ref.read(approvalContinuationProvider.notifier).show(approval, service);
  if (replace) {
    context.pushReplacement(route);
  } else {
    unawaited(context.push<void>(route));
  }
  return true;
}

/// Kept above the chat composer only for the exact session and service opened
/// from an approval. The phone never sends its own continuation message.
///
/// The notice follows the real outcome: it polls the request (and nudges the
/// open transcript to reload, because a wake runs outside this chat's own
/// event stream) while work is in progress, turns green when the agent has
/// answered, closes itself shortly after, and is red only for real failures.
class ApprovalContinuationNotice extends ConsumerStatefulWidget {
  const ApprovalContinuationNotice({super.key});

  @override
  ConsumerState<ApprovalContinuationNotice> createState() =>
      _ApprovalContinuationNoticeState();
}

class _ApprovalContinuationNoticeState
    extends ConsumerState<ApprovalContinuationNotice> {
  Timer? _poll;
  Timer? _close;
  String? _pollingFor;
  final Map<String, DateTime> _discovered = <String, DateTime>{};

  /// Opening a chat by any route (notification, history, drawer) should show
  /// the resume status of a decision made in the last few minutes for that
  /// chat, not only when the approval screen opened it.
  Future<void> _discover(String sid, HermesDesktopApiService service) async {
    final last = _discovered[sid];
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 20)) {
      return;
    }
    _discovered[sid] = DateTime.now();
    final client = ref.read(pushGatewayClientProvider);
    if (client == null) return;
    try {
      final page = await client.listApprovals(status: 'all', limit: 6);
      final cutoff = DateTime.now().subtract(approvalNoticeMaxAge);
      for (final item in page.items) {
        final resolved = item.resolvedAt;
        if (item.isPending || resolved == null || resolved.isBefore(cutoff)) {
          continue;
        }
        final full = await client.getApproval(item.id);
        if (!mounted) return;
        if (full.originSessionId == sid && full.wakeMode == 'resume') {
          ref.read(approvalContinuationProvider.notifier).show(full, service);
          return;
        }
      }
    } catch (_) {
      // Purely informational; the chat itself is unaffected.
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _close?.cancel();
    super.dispose();
  }

  void _syncTimers(
    ApprovalContinuation continuation,
    HermesDesktopApiService service,
    ApprovalResumePhase phase,
  ) {
    final id = continuation.approval.id;
    if (phase.inProgress) {
      _close?.cancel();
      _close = null;
      if (_pollingFor != id || _poll == null) {
        _poll?.cancel();
        _pollingFor = id;
        _poll = Timer.periodic(const Duration(seconds: 2), (_) {
          if (!mounted) return;
          ref.invalidate(approvalDetailProvider(id));
          if (continuation.approval.wakeState == 'sent' ||
              ref.read(approvalDetailProvider(id)).value?.wakeState == 'sent') {
            service.requestTranscriptRefresh(
              continuation.approval.originSessionId!,
            );
          }
        });
      }
      return;
    }
    _poll?.cancel();
    _poll = null;
    _pollingFor = null;
    if (phase == ApprovalResumePhase.resumed) {
      // One last reload so the final answer is complete, then close.
      service.requestTranscriptRefresh(continuation.approval.originSessionId!);
    }
    if (phase.autoCloses) {
      _close ??= Timer(const Duration(seconds: 4), () {
        if (mounted) ref.read(approvalContinuationProvider.notifier).dismiss();
      });
    } else {
      _close?.cancel();
      _close = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final continuation = ref.watch(approvalContinuationProvider);
    final service = ref.watch(hermesApiServiceProvider);
    final sid = ref.watch(hermesActiveSessionProvider);
    final conversation = ref.watch(activeConversationProvider);
    if (continuation == null &&
        sid != null &&
        service is HermesDesktopApiService &&
        conversation?.metadata['backend'] == 'hermes' &&
        conversation?.metadata['hermesSessionId'] == sid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_discover(sid, service));
      });
    }
    if (continuation == null ||
        conversation?.metadata['backend'] != 'hermes' ||
        conversation?.metadata['hermesSessionId'] != sid ||
        !identical(service, continuation.owner) ||
        sid != continuation.approval.originSessionId ||
        service is! HermesDesktopApiService ||
        service.boundProfileFor(sid!) != continuation.approval.originProfile) {
      return const SizedBox.shrink();
    }
    final messages = ref.watch(chatMessagesProvider);
    final detail = ref.watch(approvalDetailProvider(continuation.approval.id));
    final approval = detail.value ?? continuation.approval;
    final now = DateTime.now();
    final wakeIndex = messages.lastIndexWhere(
      (m) => m.role == 'user' && m.content.contains(approval.id),
    );
    final replyVisible =
        wakeIndex >= 0 &&
        messages
            .skip(wakeIndex + 1)
            .any(
              (m) =>
                  m.role == 'assistant' &&
                  !m.isStreaming &&
                  m.content.trim().isNotEmpty,
            );
    final phase = approvalResumePhase(
      approval,
      wakeMessageVisible: wakeIndex >= 0,
      replyVisible: replyVisible,
      now: now,
    );
    final resolved = approval.resolvedAt;
    final stale =
        !approval.isPending &&
        resolved != null &&
        now.difference(resolved) > approvalNoticeMaxAge &&
        !phase.inProgress;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (stale) {
        ref.read(approvalContinuationProvider.notifier).dismiss();
        return;
      }
      _syncTimers(continuation, service, phase);
    });
    if (stale) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final colors = ApprovalColors.of(Theme.of(context).brightness);
    final failed = phase.isProblem;
    final ok = phase == ApprovalResumePhase.resumed;
    final background = failed
        ? scheme.errorContainer
        : ok
        ? colors.approve.withValues(alpha: 0.16)
        : scheme.surfaceContainerHigh;
    final foreground = failed
        ? scheme.onErrorContainer
        : scheme.onSurface;
    final leading = phase.inProgress
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            failed
                ? Icons.error_outline_rounded
                : ok
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            size: 18,
            color: ok ? colors.approve : foreground,
          );
    return Semantics(
      liveRegion: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  approvalResumeText(approval, phase),
                  style: TextStyle(color: foreground),
                ),
              ),
              if (phase.isProblem)
                TextButton(
                  onPressed: () => context.push(
                    '/profile/hermes/approvals/${Uri.encodeComponent(continuation.approval.id)}',
                  ),
                  child: const Text('Details'),
                ),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: () =>
                    ref.read(approvalContinuationProvider.notifier).dismiss(),
                icon: Icon(Icons.close_rounded, size: 18, color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
