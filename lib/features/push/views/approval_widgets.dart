import 'dart:async';

import 'package:flutter/material.dart';

import '../../hermes/widgets/hermez_chat_palette.dart';
import '../models/approval.dart';
import 'approval_formatting.dart';
import 'hold_to_confirm_button.dart';

/// Colours for the two decisions, readable in light and dark.
class ApprovalColors {
  const ApprovalColors._(this.approve, this.onApprove, this.deny);

  final Color approve;
  final Color onApprove;
  final Color deny;

  static ApprovalColors of(Brightness brightness) =>
      brightness == Brightness.dark
      ? const ApprovalColors._(
          Color(0xFF3FBF76),
          Color(0xFF0B1F14),
          Color(0xFFFF7A70),
        )
      : const ApprovalColors._(
          Color(0xFF1A7F45),
          Color(0xFFFFFFFF),
          Color(0xFFB3261E),
        );
}

/// A ticking "now" so countdowns update without rebuilding whole pages.
class NowBuilder extends StatefulWidget {
  const NowBuilder({
    super.key,
    required this.builder,
    this.interval = const Duration(seconds: 20),
  });

  final Widget Function(BuildContext context, DateTime now) builder;
  final Duration interval;

  @override
  State<NowBuilder> createState() => _NowBuilderState();
}

class _NowBuilderState extends State<NowBuilder> {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}

/// Small pill showing a request's state.
class ApprovalStatusChip extends StatelessWidget {
  const ApprovalStatusChip({
    super.key,
    required this.status,
    this.overdue = false,
  });

  final ApprovalStatus status;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final palette = HermezChatPalette.forBrightness(brightness);
    final colors = ApprovalColors.of(brightness);
    final (label, color) = overdue
        ? ('Expiring', palette.muted)
        : switch (status) {
            ApprovalStatus.pending => ('Pending', palette.accent),
            ApprovalStatus.approved => ('Approved', colors.approve),
            ApprovalStatus.denied => ('Denied', colors.deny),
            ApprovalStatus.expired => ('Expired', palette.muted),
            ApprovalStatus.cancelled => ('Cancelled', palette.muted),
            ApprovalStatus.unknown => ('Unknown', palette.muted),
          };
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// Approve (press and hold) and Deny (tap, then confirm) for one request.
class ApprovalDecisionBar extends StatelessWidget {
  const ApprovalDecisionBar({
    super.key,
    required this.approval,
    required this.busy,
    required this.onDecision,
  });

  final Approval approval;
  final bool busy;
  final Future<void> Function(ApprovalDecision decision) onDecision;

  Future<void> _confirmDeny(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deny this request?'),
        content: Text(
          '${approval.actionType}\n\n${approval.description}',
          maxLines: 8,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Deny'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onDecision(ApprovalDecision.deny);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ApprovalColors.of(Theme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoldToConfirmButton(
          label: 'Hold to approve',
          icon: Icons.check_rounded,
          color: colors.approve,
          foreground: colors.onApprove,
          busy: busy,
          onConfirmed: () => onDecision(ApprovalDecision.approve),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: busy ? null : () => _confirmDeny(context),
            icon: Icon(Icons.close_rounded, color: colors.deny),
            label: Text(
              'Deny',
              style: TextStyle(color: colors.deny, fontWeight: FontWeight.w800),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colors.deny.withValues(alpha: 0.6)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows the result of a decision. Errors stay until dismissed.
void showApprovalSnack(
  BuildContext context,
  String message, {
  bool error = false,
  VoidCallback? onOpenChat,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: error ? 6 : 3),
        action: onOpenChat == null
            ? null
            : SnackBarAction(label: 'Open chat', onPressed: onOpenChat),
      ),
    );
}

/// "Answer by 3:40 PM · 12 min left" for a pending request.
String pendingLine(Approval approval, DateTime now) =>
    'Answer by ${formatClock(approval.expiresAt)} · ${formatTimeLeft(approval.expiresAt, now)}';
