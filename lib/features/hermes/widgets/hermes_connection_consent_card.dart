import 'dart:async';

import 'package:flutter/material.dart';

import '../models/hermes_connection_operation.dart';
import 'hermez_chat_palette.dart';
import 'hermez_decision_frame.dart';
import '../feedback/hermez_feedback.dart';

/// Native-style contract-8 consent card. Secret values live in controllers
/// only; callers persist [HermesConnectionOperation.safeJson] instead.
final class HermesConnectionConsentCard extends StatefulWidget {
  const HermesConnectionConsentCard({
    super.key,
    required this.operation,
    required this.onRespond,
    required this.onOpenAuthorization,
    required this.onWake,
  });

  final HermesConnectionOperation operation;
  final Future<bool> Function(
    List<Map<String, Object?>> targets,
    bool continueOperation,
  )
  onRespond;
  final Future<void> Function(String targetName) onOpenAuthorization;
  final Future<void> Function() onWake;

  @override
  State<HermesConnectionConsentCard> createState() =>
      _HermesConnectionConsentCardState();
}

final class _HermesConnectionConsentCardState
    extends State<HermesConnectionConsentCard>
    with WidgetsBindingObserver {
  final Map<String, TextEditingController> _values = {};
  final Map<String, bool> _include = {};
  bool _busy = false;
  bool _sent = false;
  String? _error;
  int _lastWakeSeq = -1;
  bool _authorizationOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncFields(widget.operation);
  }

  @override
  void didUpdateWidget(covariant HermesConnectionConsentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.operation.seq != widget.operation.seq) {
      _sent = false;
      _error = null;
      _authorizationOpened = false;
    }
    _syncFields(widget.operation);
  }

  void _syncFields(HermesConnectionOperation operation) {
    for (final target in operation.targets) {
      _include.putIfAbsent(target.name, () => true);
      for (final field in target.requiredEnv) {
        final key = '${target.name}\u0000${field.name}';
        _values.putIfAbsent(
          key,
          () => TextEditingController(text: field.defaultValue ?? ''),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        widget.operation.seq == _lastWakeSeq ||
        !(_authorizationOpened ||
            widget.operation.targets.any(
              (target) => target.state == HermesConnectionTargetState.initiated,
            ))) {
      return;
    }
    _lastWakeSeq = widget.operation.seq;
    unawaited(widget.onWake().catchError((_) {}));
  }

  Future<void> _submit({bool continueOperation = false}) async {
    if (_busy ||
        _sent ||
        widget.operation.settled ||
        !widget.operation.deadlineAt.isAfter(DateTime.now().toUtc())) {
      return;
    }
    final results = <Map<String, Object?>>[];
    for (final target in widget.operation.targets) {
      if (target.state != HermesConnectionTargetState.pending &&
          target.state != HermesConnectionTargetState.failed) {
        continue;
      }
      final approved = _include[target.name] ?? true;
      final env = <String, String>{};
      if (approved) {
        for (final field in target.requiredEnv) {
          final value = _values['${target.name}\u0000${field.name}']!.text;
          if (field.required && value.trim().isEmpty) {
            setState(
              () => _error = 'Complete required fields before continuing.',
            );
            return;
          }
          if (value.isNotEmpty) env[field.name] = value;
        }
      }
      results.add(<String, Object?>{
        'name': target.name,
        'status': approved ? 'approved' : 'skipped',
        if (env.isNotEmpty) 'env': env,
      });
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    HermezFeedback.play(HermezFeedbackCue.controlSelect);
    final accepted = await widget.onRespond(results, continueOperation);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = accepted;
      if (!accepted) _error = 'Hermes did not accept this response. Try again.';
    });
    HermezFeedback.play(
      accepted
          ? HermezFeedbackCue.approvalAccepted
          : HermezFeedbackCue.runFailed,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _values.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final operation = widget.operation;
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final expired = !operation.deadlineAt.isAfter(DateTime.now().toUtc());
    final enabled = !_busy && !_sent && !expired && !operation.settled;
    return HermezDecisionFrame(
      semanticsLabel: 'Connector consent',
      eyebrow: 'Connector access',
      status: operation.settled || _sent
          ? 'SENT'
          : expired
          ? 'EXPIRED'
          : _busy
          ? 'SENDING'
          : 'WAIT',
      busy: _busy,
      children: [
        for (final target in operation.targets) ...[
          Text(
            target.name,
            style: TextStyle(
              color: palette.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (target.detail?.isNotEmpty == true ||
              target.instructions?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                target.detail ?? target.instructions!,
                style: TextStyle(color: palette.muted),
              ),
            ),
          if (target.state == HermesConnectionTargetState.pending ||
              target.state == HermesConnectionTargetState.failed)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow this target'),
              value: _include[target.name] ?? true,
              onChanged: enabled
                  ? (value) => setState(() => _include[target.name] = value)
                  : null,
            )
          else
            Text(
              'Status: ${target.state.name}',
              style: TextStyle(color: palette.muted),
            ),
          if (_include[target.name] != false)
            for (final field in target.requiredEnv) ...[
              TextField(
                controller: _values['${target.name}\u0000${field.name}'],
                enabled: enabled,
                obscureText: field.secret,
                enableSuggestions: !field.secret,
                autocorrect: !field.secret,
                decoration: InputDecoration(
                  labelText: '${field.name}${field.required ? ' *' : ''}',
                  hintText: field.prompt,
                ),
              ),
            ],
          if (target.connectUrl != null &&
              (target.state == HermesConnectionTargetState.pending ||
                  target.state == HermesConnectionTargetState.initiated))
            TextButton.icon(
              onPressed: enabled
                  ? () async {
                      _authorizationOpened = true;
                      try {
                        await widget.onOpenAuthorization(target.name);
                      } catch (_) {}
                    }
                  : null,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open sign-in'),
            ),
          const SizedBox(height: 8),
        ],
        if (_sent) const Text('Response sent. Waiting for connector updates.'),
        if (expired) const Text('This connector request has expired.'),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!operation.settled && !expired) ...[
          const SizedBox(height: 8),
          FilledButton(
            onPressed: enabled ? () => _submit() : null,
            child: Text(_sent ? 'Response sent' : 'Submit choices'),
          ),
          TextButton(
            onPressed: enabled ? () => _submit(continueOperation: true) : null,
            child: const Text('Continue without waiting'),
          ),
        ],
      ],
    );
  }
}
