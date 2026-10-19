import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../hermes/views/hermes_page_chrome.dart';
import '../../hermes/widgets/hermez_chat_palette.dart';
import '../models/approval.dart';
import '../providers/push_providers.dart';
import '../services/push_gateway_client.dart';
import 'approval_formatting.dart';
import 'approval_widgets.dart';

/// One approval in full: what is asked, the registered parameters, who asked,
/// the timeline, and the decision controls while it is still pending.
class ApprovalDetailPage extends ConsumerStatefulWidget {
  const ApprovalDetailPage({super.key, required this.approvalId});

  final String approvalId;

  @override
  ConsumerState<ApprovalDetailPage> createState() => _ApprovalDetailPageState();
}

class _ApprovalDetailPageState extends ConsumerState<ApprovalDetailPage> {
  bool _busy = false;
  String? _resultMessage;
  bool _resultIsError = false;

  Future<void> _decide(Approval approval, ApprovalDecision decision) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _resultMessage = null;
    });
    final outcome = await ref
        .read(approvalDeciderProvider)
        .decide(approval, decision);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _resultMessage = outcome.message;
      _resultIsError = !outcome.succeeded;
    });
    showApprovalSnack(context, outcome.message, error: !outcome.succeeded);
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(Theme.of(context).brightness);
    final detail = ref.watch(approvalDetailProvider(widget.approvalId));
    return HermesPageChrome(
      title: 'Approval',
      subtitle: 'Review before you decide.',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () =>
              ref.invalidate(approvalDetailProvider(widget.approvalId)),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
          children: [
            HermesPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error is PushGatewayException
                        ? error.message
                        : 'Could not load this request.',
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(
                      approvalDetailProvider(widget.approvalId),
                    ),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ],
        ),
        data: (approval) => NowBuilder(
          builder: (context, now) => ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
            children: [
              HermesPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            approval.actionType,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        ApprovalStatusChip(
                          status: approval.status,
                          overdue: approval.isOverdue(now),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      approval.description,
                      style: const TextStyle(height: 1.4, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    _Meta('Requested by', approval.requestedBy, palette),
                    _Meta('Asked', formatWhen(approval.createdAt, now), palette),
                    if (approval.isPending)
                      _Meta('Answer by', pendingLine(approval, now).replaceFirst('Answer by ', ''), palette)
                    else
                      _Meta(
                        'Result',
                        '${describeResolution(approval)} · ${formatWhen(approval.resolvedAt ?? approval.expiresAt, now)}',
                        palette,
                      ),
                  ],
                ),
              ),
              if (approval.canDecide(now)) ...[
                const SizedBox(height: 14),
                ApprovalDecisionBar(
                  approval: approval,
                  busy: _busy,
                  onDecision: (decision) => _decide(approval, decision),
                ),
              ] else if (approval.isPending) ...[
                const SizedBox(height: 14),
                HermesPanel(
                  child: Text(
                    approval.isOverdue(now)
                        ? 'This request has expired or is about to. Refresh to see the result.'
                        : 'This request has no verification code yet, so it cannot be decided from the phone. Refresh in a moment.',
                    style: TextStyle(color: palette.muted),
                  ),
                ),
              ],
              if (_resultMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _resultMessage!,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _resultIsError
                        ? ApprovalColors.of(Theme.of(context).brightness).deny
                        : ApprovalColors.of(Theme.of(context).brightness).approve,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const HermesSectionTitle('Registered parameters'),
              const SizedBox(height: 8),
              HermesPanel(
                child: SelectableText(
                  prettyPayload(approval.payload),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
              if (approval.payloadDigest != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Verification code ${approval.payloadDigest!.substring(0, approval.payloadDigest!.length < 12 ? approval.payloadDigest!.length : 12)}…',
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
              ],
              if (approval.originSessionId != null) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => context.push(
                    '/profile/hermes/live/${Uri.encodeComponent(approval.originSessionId!)}?open=chat',
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Open the chat that asked'),
                ),
              ],
              if (approval.events.isNotEmpty) ...[
                const SizedBox(height: 20),
                const HermesSectionTitle('Timeline'),
                const SizedBox(height: 8),
                HermesPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final event in approval.events)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${formatWhen(event.createdAt, now)}  ${describeEvent(event)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value, this.palette);

  final String label;
  final String value;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: palette.muted),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13.5))),
      ],
    ),
  );
}
