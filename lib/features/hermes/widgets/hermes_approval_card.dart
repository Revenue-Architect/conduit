import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../feedback/hermez_feedback.dart';
import 'hermez_chat_palette.dart';
import 'hermez_decision_frame.dart';
import 'hermez_expandable_section.dart';

/// Resolution state of a Hermes approval gate, mirrored from the assistant
/// message's `metadata['hermesApproval']['state']`.
enum HermesApprovalState { pending, resolving, approved, denied }

/// Inline prompt shown when a Hermes run pauses for human approval.
///
/// Presentational only: [onDecision] / [onChoice] is invoked with the user's
/// choice; the caller performs the request and updates the message metadata.
/// Only the choices Hermes sent are offered. The first approving choice and
/// Deny are the primary options; any other policies (allow for the session,
/// always allow) sit in a More options compartment. One answer per pending
/// request: a second tap before the state changes does nothing.
class HermesApprovalCard extends StatefulWidget {
  const HermesApprovalCard({
    super.key,
    required this.state,
    required this.onDecision,
    this.summary,
    this.choices = const <String>[],
    this.onChoice,
  });

  final HermesApprovalState state;
  final String? summary;
  final void Function(bool approved) onDecision;
  final List<String> choices;
  final void Function(String choice)? onChoice;

  @override
  State<HermesApprovalCard> createState() => _HermesApprovalCardState();
}

class _HermesApprovalCardState extends State<HermesApprovalCard> {
  bool _sent = false;
  bool _more = false;

  @override
  void didUpdateWidget(HermesApprovalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Back to pending (a failed request): it may be answered again.
    if (oldWidget.state != widget.state) _sent = false;
  }

  void _answer(VoidCallback send) {
    if (_sent || widget.state != HermesApprovalState.pending) return;
    _sent = true;
    HermezFeedback.play(HermezFeedbackCue.controlSelect);
    send();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final state = widget.state;
    final resolved =
        state == HermesApprovalState.approved ||
        state == HermesApprovalState.denied;
    final enabled = state == HermesApprovalState.pending && !_sent;

    String label(String choice) => switch (choice) {
      'once' => l10n.hermesApprovalAllowOnce,
      'session' => l10n.hermesApprovalAllowSession,
      'always' => l10n.hermesApprovalAlwaysAllow,
      'deny' => l10n.hermesApprovalDenyAction,
      _ => choice,
    };
    String detail(String choice) => switch (choice) {
      'once' => 'Continue this action once',
      'session' => 'Allow it for the rest of this session',
      'always' => 'Allow it from now on',
      'deny' => 'Do not run',
      _ => 'Send this answer to Hermes',
    };

    final choices = widget.choices;
    final onChoice = widget.onChoice;
    final List<Widget> primary;
    final List<Widget> secondary;
    if (choices.isNotEmpty && onChoice != null) {
      final approving = choices.where((c) => c != 'deny').toList();
      final first = approving.contains('once')
          ? 'once'
          : (approving.isEmpty ? null : approving.first);
      final main = [?first, if (choices.contains('deny')) 'deny'];
      primary = [
        for (final choice in main)
          HermezDecisionOption(
            title: label(choice),
            detail: detail(choice),
            destructive: choice == 'deny',
            enabled: enabled,
            onTap: () => _answer(() => onChoice(choice)),
          ),
      ];
      secondary = [
        for (final choice in choices)
          if (!main.contains(choice))
            HermezDecisionOption(
              title: label(choice),
              detail: detail(choice),
              enabled: enabled,
              onTap: () => _answer(() => onChoice(choice)),
            ),
      ];
    } else {
      primary = [
        HermezDecisionOption(
          title: l10n.hermesApprovalApproveAction,
          detail: detail('once'),
          enabled: enabled,
          onTap: () => _answer(() => widget.onDecision(true)),
        ),
        HermezDecisionOption(
          title: l10n.hermesApprovalDenyAction,
          detail: detail('deny'),
          destructive: true,
          enabled: enabled,
          onTap: () => _answer(() => widget.onDecision(false)),
        ),
      ];
      secondary = const [];
    }

    return HermezDecisionFrame(
      semanticsLabel: l10n.hermesApprovalRequired,
      eyebrow: l10n.hermesApprovalRequired,
      status: switch (state) {
        HermesApprovalState.pending => _sent ? 'SENDING' : 'WAIT',
        HermesApprovalState.resolving => 'SENDING',
        HermesApprovalState.approved => 'APPROVED',
        HermesApprovalState.denied => 'DENIED',
      },
      busy: state == HermesApprovalState.resolving || (_sent && !resolved),
      children: [
        HermezCommandBlock(text: widget.summary ?? l10n.hermesApprovalFallback),
        const SizedBox(height: 10),
        if (resolved)
          Text(
            state == HermesApprovalState.approved
                ? l10n.hermesApprovalApproved
                : l10n.hermesApprovalDenied,
            style: TextStyle(
              color: state == HermesApprovalState.approved
                  ? palette.ink
                  : Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          )
        else ...[
          Text(
            'Hermes is paused until you decide.',
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final option in primary) ...[option, const SizedBox(height: 8)],
          if (secondary.isNotEmpty)
            HermezExpandableSection(
              expanded: _more,
              onExpansionChanged: (open) => setState(() => _more = open),
              semanticLabel: 'More options',
              openFeedback: HermezFeedbackCue.compartmentOpen,
              closeFeedback: HermezFeedbackCue.compartmentClose,
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              childPadding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              header: Text(
                'More options',
                style: TextStyle(
                  color: palette.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final option in secondary) ...[
                    option,
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }
}
