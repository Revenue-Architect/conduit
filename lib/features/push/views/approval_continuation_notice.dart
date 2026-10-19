import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';

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

class ApprovalContinuationNotifier extends Notifier<ApprovalContinuation?> {
  @override
  ApprovalContinuation? build() => null;
  void show(Approval approval, Object owner) =>
      state = ApprovalContinuation(approval, owner);
  void dismiss() => state = null;
}

final approvalContinuationProvider =
    NotifierProvider<ApprovalContinuationNotifier, ApprovalContinuation?>(
      ApprovalContinuationNotifier.new,
    );

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
class ApprovalContinuationNotice extends ConsumerWidget {
  const ApprovalContinuationNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final continuation = ref.watch(approvalContinuationProvider);
    final service = ref.watch(hermesApiServiceProvider);
    final sid = ref.watch(hermesActiveSessionProvider);
    final conversation = ref.watch(activeConversationProvider);
    if (continuation == null ||
        conversation?.metadata['backend'] != 'hermes' ||
        conversation?.metadata['hermesSessionId'] != sid ||
        !identical(service, continuation.owner) ||
        sid != continuation.approval.originSessionId ||
        service is! HermesDesktopApiService ||
        service.boundProfileFor(sid!) != continuation.approval.originProfile) {
      return const SizedBox.shrink();
    }
    final detail = ref.watch(approvalDetailProvider(continuation.approval.id));
    final approval = detail.asData?.value;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                approval?.continuationMessage ??
                    (detail.hasError
                        ? 'Could not check continuation. Open the request to retry.'
                        : 'Checking continuation…'),
              ),
            ),
            TextButton(
              onPressed: () => context.push(
                '/profile/hermes/approvals/${Uri.encodeComponent(continuation.approval.id)}',
              ),
              child: const Text('Request'),
            ),
            IconButton(
              tooltip: 'Dismiss continuation status',
              onPressed: () =>
                  ref.read(approvalContinuationProvider.notifier).dismiss(),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
