import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../models/hermes_run_event.dart';
import '../feedback/hermez_feedback.dart';
import 'hermez_chat_palette.dart';
import 'hermez_decision_frame.dart';

final class HermesDecisionCard extends StatefulWidget {
  const HermesDecisionCard({
    super.key,
    required this.kind,
    required this.onSubmit,
    this.prompt,
    this.mcpServer,
    this.mcpAction,
    this.choices = const <String>[],
    this.multiSelect = false,
  });

  final HermesDecisionKind kind;
  final String? prompt;
  final String? mcpServer;
  final String? mcpAction;
  final List<String> choices;
  final bool multiSelect;
  final Future<bool> Function(String value) onSubmit;

  @override
  State<HermesDecisionCard> createState() => _HermesDecisionCardState();
}

final class _HermesDecisionCardState extends State<HermesDecisionCard> {
  final _controller = TextEditingController();
  bool _submitting = false;
  bool _resolved = false;
  final Set<String> _selectedChoices = <String>{};

  bool get _sensitive =>
      widget.kind == HermesDecisionKind.sudo ||
      widget.kind == HermesDecisionKind.secret;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit([String? override]) async {
    final value = override ?? _controller.text;
    if (value.trim().isEmpty || _submitting) return;
    setState(() => _submitting = true);
    // Sensory cues are presentation only: sent, then the backend's answer.
    HermezFeedback.play(HermezFeedbackCue.controlSelect);
    final resolved = await widget.onSubmit(value);
    HermezFeedback.play(
      resolved
          ? HermezFeedbackCue.approvalAccepted
          : HermezFeedbackCue.runFailed,
    );
    if (!mounted) return;
    if (resolved) _controller.clear();
    setState(() {
      _submitting = false;
      _resolved = resolved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final title = switch (widget.kind) {
      HermesDecisionKind.clarification => l10n.hermesClarificationTitle,
      HermesDecisionKind.sudo => l10n.hermesSudoTitle,
      HermesDecisionKind.secret => l10n.hermesSecretTitle,
      HermesDecisionKind.mcpSetup => l10n.hermesMcpSetupTitle,
    };
    final enabled = !_submitting && !_resolved;
    return HermezDecisionFrame(
      semanticsLabel: title,
      eyebrow: title,
      status: _resolved
          ? 'SENT'
          : _submitting
          ? 'SENDING'
          : 'WAIT',
      busy: _submitting,
      children: [
        if (widget.prompt?.trim().isNotEmpty == true) ...[
          Text(
            widget.prompt!,
            style: TextStyle(
              color: palette.ink,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_resolved)
          Text(
            l10n.hermesResponseSent,
            style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
          )
        else if (widget.kind == HermesDecisionKind.mcpSetup) ...[
          HermezCommandBlock(
            text:
                '${widget.mcpAction ?? 'Set up'} ${widget.mcpServer ?? 'MCP server'}',
          ),
          const SizedBox(height: 12),
          HermezDecisionOption(
            title: l10n.hermesSetUp,
            enabled: enabled,
            onTap: () => _submit('approve'),
          ),
          const SizedBox(height: 8),
          HermezDecisionOption(
            title: l10n.hermesNotNow,
            enabled: enabled,
            onTap: () => _submit('decline'),
          ),
        ] else ...[
          // Hermes's own choices, as a single or multiple choice list.
          for (final choice in widget.choices) ...[
            HermezDecisionOption(
              title: choice,
              enabled: enabled,
              selected: _selectedChoices.contains(choice),
              marker: widget.multiSelect
                  ? (_selectedChoices.contains(choice)
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded)
                  : (_selectedChoices.contains(choice)
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded),
              onTap: () => setState(() {
                final selected = !_selectedChoices.contains(choice);
                if (!widget.multiSelect && selected) {
                  _selectedChoices.clear();
                }
                selected
                    ? _selectedChoices.add(choice)
                    : _selectedChoices.remove(choice);
              }),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.choices.isNotEmpty) const SizedBox(height: 4),
          // The field and button come from material_ui, whose Material is
          // not the Flutter one the Hermez frame provides.
          Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _controller,
                  enabled: enabled,
                  obscureText: _sensitive,
                  enableSuggestions: !_sensitive,
                  autocorrect: !_sensitive,
                  enableIMEPersonalizedLearning: !_sensitive,
                  decoration: InputDecoration(
                    labelText: _sensitive
                        ? l10n.hermesSensitiveResponse
                        : widget.choices.isEmpty
                        ? l10n.hermesResponse
                        : 'Or type your answer',
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ConduitButton(
                    text: l10n.hermesSendResponse,
                    isCompact: true,
                    isLoading: _submitting,
                    onPressed: _submitting
                        ? null
                        : () => _submit(
                            _selectedChoices.isEmpty
                                ? null
                                : widget.multiSelect
                                ? jsonEncode(_selectedChoices.toList())
                                : _selectedChoices.single,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
