import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_pending_decision_store.dart';
import '../views/hermes_page_chrome.dart';
import 'hermez_modal_sheet.dart';

/// Null/false means the sheet was dismissed or failed; dismissal never sends
/// a denial to Hermes. Only explicit actions resolve a pending request.
Future<bool?> showHermesAttentionResolutionSheet(
  BuildContext context,
  HermesPendingDesktopDecision decision,
) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _ResolutionSheet(decision: decision),
);

class _ResolutionSheet extends ConsumerStatefulWidget {
  const _ResolutionSheet({required this.decision});
  final HermesPendingDesktopDecision decision;

  @override
  ConsumerState<_ResolutionSheet> createState() => _ResolutionSheetState();
}

class _ResolutionSheetState extends ConsumerState<_ResolutionSheet> {
  final _answer = TextEditingController();
  final Set<String> _selected = {};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _send(String value) async {
    if (_busy || !widget.decision.expiresAt.isAfter(DateTime.now().toUtc()))
      return;
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final decision = widget.decision;
      if (decision.kind == HermesPendingDesktopDecisionKind.approval) {
        await service.resolveApprovalChoiceForSession(
          decision.storedSessionId,
          approvalId: decision.requestId,
          choice: value,
        );
      } else {
        final kind = decision.decisionKind;
        if (kind == null) throw StateError('Unsupported decision');
        await service.respondToDecision(
          runtimeId: decision.runtimeId,
          storedSessionId: decision.storedSessionId,
          requestId: decision.requestId,
          kind: kind,
          value: value,
          mcpServer: decision.mcpServer,
          mcpAction: decision.mcpAction,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Hermes did not accept the response. Retry or open the conversation.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final decision = widget.decision;
    final kind = decision.kind;
    final sensitive =
        kind == HermesPendingDesktopDecisionKind.secret ||
        kind == HermesPendingDesktopDecisionKind.sudo;
    final title = switch (kind) {
      HermesPendingDesktopDecisionKind.approval => 'Approve this action?',
      HermesPendingDesktopDecisionKind.clarification =>
        'Hermes needs your answer',
      HermesPendingDesktopDecisionKind.sudo => 'Administrator access required',
      HermesPendingDesktopDecisionKind.secret => 'Credential required',
      HermesPendingDesktopDecisionKind.mcpSetup =>
        'Connect ${decision.mcpServer ?? 'MCP server'}?',
    };
    return HermezModalSheet(
      title: title,
      eyebrow: 'Attention',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HermesPanel(
            child: Text(decision.prompt ?? 'Hermes is waiting for your input.'),
          ),
          if (kind == HermesPendingDesktopDecisionKind.mcpSetup) ...[
            const SizedBox(height: 12),
            Text('Requested action: ${decision.mcpAction ?? 'setup'}'),
          ],
          if (decision.choices.isNotEmpty) ...[
            const SizedBox(height: 15),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final choice in decision.choices)
                  ChoiceChip(
                    label: Text(choice),
                    selected: _selected.contains(choice),
                    onSelected: _busy
                        ? null
                        : (selected) => setState(() {
                            if (!decision.multiSelect) _selected.clear();
                            if (selected) {
                              _selected.add(choice);
                            } else {
                              _selected.remove(choice);
                            }
                          }),
                  ),
              ],
            ),
          ],
          if (kind == HermesPendingDesktopDecisionKind.clarification ||
              sensitive) ...[
            const SizedBox(height: 15),
            TextField(
              controller: _answer,
              obscureText: sensitive,
              enableSuggestions: !sensitive,
              autocorrect: !sensitive,
              enableIMEPersonalizedLearning: !sensitive,
              decoration: InputDecoration(
                labelText: sensitive ? 'Secure response' : 'Your answer',
              ),
            ),
          ],
          if (!decision.expiresAt.isAfter(DateTime.now().toUtc()))
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text('This request has expired. Reopen the conversation.'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      footer: Row(
        children: [
          if (kind == HermesPendingDesktopDecisionKind.approval ||
              kind == HermesPendingDesktopDecisionKind.mcpSetup) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _send(
                        kind == HermesPendingDesktopDecisionKind.approval
                            ? 'deny'
                            : 'decline',
                      ),
                child: Text(
                  kind == HermesPendingDesktopDecisionKind.approval
                      ? 'Deny'
                      : 'Not now',
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : () {
                      final value = switch (kind) {
                        HermesPendingDesktopDecisionKind.approval => 'once',
                        HermesPendingDesktopDecisionKind.mcpSetup => 'approve',
                        _ when _selected.isNotEmpty =>
                          decision.multiSelect
                              ? jsonEncode(_selected.toList())
                              : _selected.single,
                        _ => _answer.text.trim(),
                      };
                      if (value.isNotEmpty) _send(value);
                    },
              child: Text(switch (kind) {
                HermesPendingDesktopDecisionKind.approval => 'Approve once',
                HermesPendingDesktopDecisionKind.mcpSetup => 'Connect',
                _ => 'Send response',
              }),
            ),
          ),
        ],
      ),
    );
  }
}
