import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/providers/chat_providers.dart';
import '../feedback/hermez_feedback.dart';
import '../models/hermes_config.dart';
import '../models/hermes_todo.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../widgets/hermes_plan_view.dart';
import '../widgets/hermez_action_pills.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_live.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermez_modal_sheet.dart';

/// How a piece of direction reached Hermes.
enum HermesDirectionOutcome {
  /// The live run took it now.
  steered,

  /// Hermes holds it for the next turn.
  queued,

  /// Nothing is running: it waits in the composer for the user to send.
  drafted,
  failed,
}

/// Sends direction for a session's work: a steer while its run is live,
/// otherwise text in the composer the user sends themselves.
Future<HermesDirectionOutcome> deliverHermesDirection(
  WidgetRef ref, {
  required String sessionId,
  required String text,
}) async {
  final message = text.trim();
  if (message.isEmpty) return HermesDirectionOutcome.failed;
  final service = ref.read(hermesApiServiceProvider);
  final running =
      service is HermesDesktopApiService &&
      service.turnStateFor(sessionId) == HermesDesktopTurnState.running;
  if (!running) {
    // It waits beside the send button; the keyboard stays down so the
    // user sees the draft before sending it.
    ref
        .read(composerTextInsertionProvider.notifier)
        .insert(targetId: chatComposerTextInsertionTargetId, text: message);
    return HermesDirectionOutcome.drafted;
  }
  try {
    final steered = await service.steer(sessionId, message);
    HermezFeedback.play(HermezFeedbackCue.approvalAccepted);
    return steered
        ? HermesDirectionOutcome.steered
        : HermesDirectionOutcome.queued;
  } catch (_) {
    HermezFeedback.play(HermezFeedbackCue.runFailed);
    return HermesDirectionOutcome.failed;
  }
}

String hermesDirectionNotice(HermesDirectionOutcome outcome) =>
    switch (outcome) {
      HermesDirectionOutcome.steered => 'Sent. Hermes is adjusting.',
      HermesDirectionOutcome.queued => 'Hermes will see this next turn.',
      HermesDirectionOutcome.drafted => 'Added to your message. Send it.',
      HermesDirectionOutcome.failed => 'Could not reach Hermes.',
    };

/// The whole plan: every step, nested, live while open. A step can be
/// discussed, changed, extended or cancelled; the plan can be redone.
/// Everything is ordinary direction to the agent, never a hidden edit.
Future<void> showHermesPlanSheet(
  BuildContext context, {
  required String sessionId,
  HermezMorphOrigin? origin,
}) => pushHermezSheetRoute<void>(
  context,
  origin: origin,
  heightFactor: 0.86,
  builder: (_) => _HermesPlanSheet(sessionId: sessionId),
);

class _HermesPlanSheet extends ConsumerStatefulWidget {
  const _HermesPlanSheet({required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<_HermesPlanSheet> createState() => _HermesPlanSheetState();
}

class _HermesPlanSheetState extends ConsumerState<_HermesPlanSheet> {
  String? _selected;
  bool _sending = false;
  String? _notice;
  bool _failed = false;

  void _select(HermesTodoItem item) {
    HermezFeedback.play(HermezFeedbackCue.controlSelect);
    setState(() => _selected = _selected == item.id ? null : item.id);
  }

  /// Delivers [text]; true when it reached Hermes or the composer.
  Future<bool> _send(String text) async {
    if (_sending) return false;
    setState(() => _sending = true);
    final outcome = await deliverHermesDirection(
      ref,
      sessionId: widget.sessionId,
      text: text,
    );
    if (!mounted) return false;
    final delivered = outcome != HermesDirectionOutcome.failed;
    setState(() {
      _sending = false;
      _notice = hermesDirectionNotice(outcome);
      _failed = !delivered;
      if (delivered) _selected = null;
    });
    if (outcome == HermesDirectionOutcome.drafted) {
      // The draft is in the composer; close the sheet over it. A plain pop:
      // the field that sent it is still open, and its Back handling would
      // fold it instead of closing the sheet.
      Navigator.of(context).pop();
    }
    return delivered;
  }

  static String _quote(String content) {
    final line = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.length > 160 ? '${line.substring(0, 159)}…' : line;
  }

  List<HermezPillAction> _stepActions(HermesTodoItem step) {
    final quote = _quote(step.content);
    return [
      HermezPillAction(
        label: 'Comment',
        icon: Icons.mode_comment_outlined,
        hint: 'Your note on this step',
        onSubmit: (words) => _send('About the plan step "$quote": $words'),
      ),
      HermezPillAction(
        label: 'Add after',
        icon: Icons.playlist_add_rounded,
        hint: 'The new step',
        onSubmit: (words) =>
            _send('Please add a step to the plan after "$quote": $words'),
      ),
      if (step.status.isOpen) ...[
        HermezPillAction(
          label: 'Change',
          icon: Icons.edit_outlined,
          hint: 'What this step should be',
          onSubmit: (words) =>
              _send('Please change the plan step "$quote" to: $words'),
        ),
        HermezPillAction(
          label: 'Cancel step',
          icon: Icons.remove_circle_outline_rounded,
          quiet: true,
          busy: _sending,
          onTap: _sending
              ? null
              : () => unawaited(
                  _send(
                    'Please cancel the plan step "$quote" and update the plan.',
                  ),
                ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final state = ref.watch(hermesAgenticStateProvider(widget.sessionId));
    final turn = ref.watch(hermesSessionTurnStateProvider(widget.sessionId));
    final running = turn.value == HermesDesktopTurnState.running;
    final plan = state.value?.todo;
    final rows = plan?.outline ?? const <HermesTodoRow>[];
    return HermezModalSheet(
      eyebrow: plan == null
          ? 'PLAN'
          : hermesPlanStatus(plan, running: running).toUpperCase(),
      title: 'Plan',
      subtitle: plan == null
          ? Text(
              'Hermes has not made a plan in this chat yet.',
              style: HermezType.meta(palette),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 10, right: 8),
              child: HermezPlanBar(
                snapshot: plan,
                height: 5,
                paused: !running && plan.hasActiveWork,
              ),
            ),
      body: plan == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in rows) ...[
                  HermesPlanRow(
                    key: ValueKey('plan-${row.item.id}'),
                    item: row.item,
                    depth: row.depth,
                    live:
                        running &&
                        row.item.status == HermesTodoStatus.inProgress,
                    selected: row.item.id == _selected,
                    onTap: () => _select(row.item),
                  ),
                  // The step's actions open in place under it; a field grows
                  // out of its own pill, like Steer.
                  HermezReveal(
                    visible: row.item.id == _selected,
                    revealKey: ValueKey('plan-tray-${row.item.id}'),
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: 40 + row.depth * 20.0,
                        end: 6,
                        top: 2,
                        bottom: 12,
                      ),
                      child: HermezActionPills(
                        key: ValueKey('plan-actions-${row.item.id}'),
                        actions: _stepActions(row.item),
                      ),
                    ),
                  ),
                ],
              ],
            ),
      footer: plan == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HermezReveal(
                  visible: _notice != null,
                  revealKey: ValueKey('plan-notice-$_notice'),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        HermezLiveDot(
                          state: _failed
                              ? HermezLiveState.failed
                              : HermezLiveState.done,
                          size: 6,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _notice ?? '',
                            style: HermezType.meta(palette),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                HermezActionPills(
                  actions: [
                    if (!running && plan.hasActiveWork)
                      HermezPillAction(
                        label: 'Continue plan',
                        icon: Icons.play_arrow_rounded,
                        emphasized: true,
                        busy: _sending,
                        onTap: _sending
                            ? null
                            : () => unawaited(
                                _send('Please continue with the plan.'),
                              ),
                      ),
                    HermezPillAction(
                      label: 'Replan',
                      icon: Icons.alt_route_rounded,
                      hint: 'What should change?',
                      emptyText: 'start again from where you are.',
                      onSubmit: (words) =>
                          _send('Please revise the plan: $words'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
