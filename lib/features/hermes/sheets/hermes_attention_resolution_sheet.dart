import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_pending_decision_store.dart';
import '../motion/hermez_motion.dart';
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_sheet_parts.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermez_modal_sheet.dart';

/// Null/false means the sheet was dismissed or failed; dismissal never sends
/// a denial to Hermes. Only explicit actions resolve a pending request.
Future<bool?> showHermesAttentionResolutionSheet(
  BuildContext context,
  HermesPendingDesktopDecision decision, {
  HermezMorphOrigin? origin,
}) => pushHermezSheetRoute<bool>(
  context,
  origin: origin,
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
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final decision = widget.decision;
    final kind = decision.kind;
    final sensitive =
        kind == HermesPendingDesktopDecisionKind.secret ||
        kind == HermesPendingDesktopDecisionKind.sudo;
    final expired = !decision.expiresAt.isAfter(DateTime.now().toUtc());
    final title = switch (kind) {
      HermesPendingDesktopDecisionKind.approval => 'Approve this action?',
      HermesPendingDesktopDecisionKind.clarification =>
        'Hermes needs your answer',
      HermesPendingDesktopDecisionKind.sudo => 'Administrator access required',
      HermesPendingDesktopDecisionKind.secret => 'Credential required',
      HermesPendingDesktopDecisionKind.mcpSetup =>
        'Connect ${decision.mcpServer ?? 'MCP server'}?',
    };
    final lead = switch (kind) {
      HermesPendingDesktopDecisionKind.approval =>
        'Hermes paused and is waiting for your approval before it continues.',
      HermesPendingDesktopDecisionKind.clarification =>
        'Hermes paused to ask you something.',
      HermesPendingDesktopDecisionKind.sudo =>
        'Hermes needs elevated access to continue.',
      HermesPendingDesktopDecisionKind.secret =>
        'Hermes needs a credential to continue. It is sent only to this run.',
      HermesPendingDesktopDecisionKind.mcpSetup =>
        'Hermes wants to connect a tool server.',
    };
    // Context: which bot asked, in which conversation, and what exactly.
    final profile = decision.profile;
    final botName = profile == null || profile.isEmpty ? 'Hermes' : profile;
    String? conversation;
    for (final session
        in ref.watch(hermesSessionsProvider).asData?.value ??
            const <HermesSessionSummary>[]) {
      if (session.id == decision.storedSessionId) {
        conversation = session.title;
        break;
      }
    }
    final asked = decision.prompt?.trim();
    final prompt = asked == null || asked.isEmpty
        ? 'Hermes did not send the question text with this request. Open '
              'the conversation to see what it asked, then answer here.'
        : asked;
    final remaining = decision.expiresAt.difference(DateTime.now().toUtc());
    return HermezModalSheet(
      title: title,
      eyebrow: 'Attention',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lead,
            style: HermezType.body(palette)
                .copyWith(color: palette.muted, fontSize: 15),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              HermezBotMark(
                identity: hermezIdentityForName(profile),
                size: 48,
                label: botName,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(botName, style: HermezType.section(palette)),
                    Text(
                      conversation == null || conversation.trim().isEmpty
                          ? 'Waiting for your response'
                          : 'In “${conversation.trim()}”',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HermezType.meta(palette),
                    ),
                  ],
                ),
              ),
              if (!expired && remaining.inMinutes < 24 * 60)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    remaining.inMinutes < 1
                        ? 'EXPIRES SOON'
                        : 'EXPIRES IN ${remaining.inMinutes} MIN',
                    style: HermezType.technical(palette.accent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(switch (kind) {
            HermesPendingDesktopDecisionKind.approval => 'COMMAND',
            HermesPendingDesktopDecisionKind.clarification => 'QUESTION',
            HermesPendingDesktopDecisionKind.mcpSetup => 'REASON',
            _ => 'REQUEST',
          }, style: HermezType.technical(palette.muted)),
          const SizedBox(height: 6),
          if (kind == HermesPendingDesktopDecisionKind.approval)
            _CommandBlock(text: prompt)
          else
            HermezSurface(
              kind: HermezSurfaceKind.utility,
              border: Border.all(color: palette.border.withValues(alpha: 0.75)),
              child: Text(
                prompt,
                style: asked == null || asked.isEmpty
                    ? HermezType.meta(palette)
                    : HermezType.body(palette),
              ),
            ),
          if (kind == HermesPendingDesktopDecisionKind.mcpSetup) ...[
            const SizedBox(height: 12),
            Text(
              'Requested action: ${decision.mcpAction ?? 'setup'}',
              style: HermezType.meta(palette),
            ),
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
          if (expired)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text('This request has expired. Reopen the conversation.'),
            ),
          HermezReveal(
            visible: _error != null,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                _error ?? '',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ],
      ),
      footer: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: HermezActionTile(
              primary: true,
              showChevron: false,
              icon: Icons.check_rounded,
              busy: _busy,
              title: switch (kind) {
                HermesPendingDesktopDecisionKind.approval => 'Approve once',
                HermesPendingDesktopDecisionKind.mcpSetup => 'Connect',
                _ => 'Send response',
              },
              subtitle: switch (kind) {
                HermesPendingDesktopDecisionKind.approval => 'Run this once',
                HermesPendingDesktopDecisionKind.mcpSetup =>
                  'Allow this server',
                _ => 'Hermes continues',
              },
              onTap: _busy
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
            ),
          ),
          if (kind == HermesPendingDesktopDecisionKind.approval ||
              kind == HermesPendingDesktopDecisionKind.mcpSetup) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: HermezActionTile(
                showChevron: false,
                icon: Icons.close_rounded,
                title: kind == HermesPendingDesktopDecisionKind.approval
                    ? 'Deny'
                    : 'Not now',
                subtitle: kind == HermesPendingDesktopDecisionKind.approval
                    ? "Don't run"
                    : 'Decline',
                onTap: _busy
                    ? null
                    : () => _send(
                        kind == HermesPendingDesktopDecisionKind.approval
                            ? 'deny'
                            : 'decline',
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The request text as the mockups show a command: monospace, on a quiet
/// panel, with a copy control. The text is exactly what Hermes sent.
class _CommandBlock extends StatelessWidget {
  const _CommandBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border.withValues(alpha: 0.75)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.border.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              '>_',
              style: TextStyle(
                color: palette.ink,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                text,
                style: TextStyle(
                  color: palette.ink,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)
                    ?.showSnackBar(const SnackBar(content: Text('Copied')));
              }
            },
            icon: Icon(Icons.copy_rounded, size: 20, color: palette.ink),
          ),
        ],
      ),
    );
  }
}
