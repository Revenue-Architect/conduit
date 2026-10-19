import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../../hermes/views/hermes_page_chrome.dart';
import '../../hermes/widgets/hermez_chat_palette.dart';
import '../models/approval.dart';
import '../providers/push_providers.dart';
import '../services/push_gateway_client.dart';
import 'approval_formatting.dart';
import 'approval_widgets.dart';

/// Pending requests (decide here) and history. Built on the phone gateway's
/// `/approvals` routes; nothing here talks to V2 directly.
class ApprovalsPage extends ConsumerStatefulWidget {
  const ApprovalsPage({super.key});

  @override
  ConsumerState<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends ConsumerState<ApprovalsPage> {
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    // Fresh history each visit; pending refreshes through its own provider.
    Future.microtask(() {
      if (mounted) unawaited(ref.read(approvalsHistoryProvider.notifier).refresh());
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(approvalsPendingProvider);
    unawaited(ref.read(approvalsHistoryProvider.notifier).refresh());
    try {
      await ref.read(approvalsPendingProvider.future);
    } catch (_) {
      // The error shows in the list.
    }
  }

  Future<void> _decide(Approval approval, ApprovalDecision decision) async {
    if (_busy.contains(approval.id)) return;
    setState(() => _busy.add(approval.id));
    final outcome = await ref
        .read(approvalDeciderProvider)
        .decide(approval, decision);
    if (!mounted) return;
    setState(() => _busy.remove(approval.id));
    showApprovalSnack(context, outcome.message, error: !outcome.succeeded);
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(Theme.of(context).brightness);
    final pairing = ref.watch(pushPairingProvider);
    final pending = ref.watch(approvalsPendingProvider);
    final history = ref.watch(approvalsHistoryProvider);
    final paired = pairing.asData?.value != null;

    return HermesPageChrome(
      title: 'Approvals',
      subtitle: 'Decide what your agents may do.',
      actions: [
        IconButton(
          tooltip: 'Refresh approvals',
          onPressed: () => unawaited(_refresh()),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: NowBuilder(
          builder: (context, now) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
            children: [
              if (pairing.hasValue && !paired) _PairPrompt(palette: palette),
              if (paired) ...[
                _SummaryPanel(
                  palette: palette,
                  pending: pending.asData?.value.length,
                  loading: pending.isLoading,
                ),
                const SizedBox(height: 19),
                const HermesSectionTitle('Needs your decision'),
                const SizedBox(height: 8),
                ..._pendingSection(context, pending, now, palette),
                const SizedBox(height: 24),
                const HermesSectionTitle('History'),
                const SizedBox(height: 8),
                ..._historySection(context, history, now, palette),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _pendingSection(
    BuildContext context,
    AsyncValue<List<Approval>> pending,
    DateTime now,
    HermezChatPalette palette,
  ) {
    if (pending.hasError) {
      return [_ErrorPanel(error: pending.error, onRetry: _refresh)];
    }
    if (pending.isLoading && !pending.hasValue) {
      return const [LinearProgressIndicator(minHeight: 2)];
    }
    final items = pending.asData?.value ?? const <Approval>[];
    if (items.isEmpty) {
      return const [HermesPanel(child: Text('Nothing is waiting on you.'))];
    }
    return [
      for (final approval in items) ...[
        _PendingCard(
          approval: approval,
          now: now,
          palette: palette,
          busy: _busy.contains(approval.id),
          onOpen: () => context.push(approvalPath(approval.id)),
          onDecision: (decision) => _decide(approval, decision),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _historySection(
    BuildContext context,
    ApprovalsHistoryState history,
    DateTime now,
    HermezChatPalette palette,
  ) {
    if (history.error != null && history.items.isEmpty) {
      return [
        HermesPanel(
          child: Text(history.error!, style: TextStyle(color: palette.muted)),
        ),
      ];
    }
    if (!history.loaded) return const [LinearProgressIndicator(minHeight: 2)];
    if (history.items.isEmpty) {
      return const [HermesPanel(child: Text('No decided requests yet.'))];
    }
    return [
      for (final approval in history.items) ...[
        _HistoryRow(
          approval: approval,
          now: now,
          palette: palette,
          onOpen: () => context.push(approvalPath(approval.id)),
        ),
        const SizedBox(height: 8),
      ],
      if (history.hasMore)
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: history.loading
                ? null
                : () => unawaited(
                    ref.read(approvalsHistoryProvider.notifier).loadMore(),
                  ),
            child: Text(history.loading ? 'Loading…' : 'Load older'),
          ),
        ),
      if (history.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(history.error!, style: TextStyle(color: palette.muted)),
        ),
    ];
  }
}

/// The in-app path of one approval.
String approvalPath(String id) =>
    '/profile/hermes/approvals/${Uri.encodeComponent(id)}';

class _PairPrompt extends StatelessWidget {
  const _PairPrompt({required this.palette});

  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) => HermesPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pair this phone',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          'Approvals and push notifications go through a gateway on your '
          'Umbrel. Pair once with a code from the Umbrel to turn them on.',
          style: TextStyle(color: palette.muted, height: 1.35),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => context.push(Routes.hermesPushPairing),
          child: const Text('Enter pairing code'),
        ),
      ],
    ),
  );
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.palette,
    required this.pending,
    required this.loading,
  });

  final HermezChatPalette palette;
  final int? pending;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = loading && pending == null
        ? 'Checking…'
        : switch (pending ?? 0) {
            0 => 'All clear',
            1 => '1 request needs you',
            final n => '$n requests need you',
          };
    return HermesPanel(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: (pending ?? 0) > 0 ? palette.accent : palette.muted,
            radius: 11,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: () => context.push(Routes.notificationSettings),
            child: const Text('Push health'),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is PushGatewayException
        ? (error as PushGatewayException).message
        : 'Could not load approvals.';
    return HermesPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => unawaited(onRetry()),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.approval,
    required this.now,
    required this.palette,
    required this.busy,
    required this.onOpen,
    required this.onDecision,
  });

  final Approval approval;
  final DateTime now;
  final HermezChatPalette palette;
  final bool busy;
  final VoidCallback onOpen;
  final Future<void> Function(ApprovalDecision) onDecision;

  @override
  Widget build(BuildContext context) {
    final overdue = approval.isOverdue(now);
    return HermesPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(12),
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
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ApprovalStatusChip(status: approval.status, overdue: overdue),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  approval.description,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.35),
                ),
                const SizedBox(height: 8),
                Text(
                  'From ${approval.requestedBy} · ${pendingLine(approval, now)}',
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap for full details',
                  style: TextStyle(fontSize: 12, color: palette.accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (approval.canDecide(now))
            ApprovalDecisionBar(
              approval: approval,
              busy: busy,
              onDecision: onDecision,
            )
          else
            Text(
              overdue
                  ? 'This request is expiring. Refresh to see the result.'
                  : 'Open the request to review it before deciding.',
              style: TextStyle(color: palette.muted),
            ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.approval,
    required this.now,
    required this.palette,
    required this.onOpen,
  });

  final Approval approval;
  final DateTime now;
  final HermezChatPalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final when = approval.resolvedAt ?? approval.expiresAt;
    return HermesPanel(
      onTap: onOpen,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  approval.actionType,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  approval.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: palette.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  '${describeResolution(approval)} · ${formatWhen(when, now)}',
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ApprovalStatusChip(status: approval.status),
        ],
      ),
    );
  }
}
