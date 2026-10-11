import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thinking_orbs/thinking_orbs.dart';

import '../../../core/models/chat_message.dart';
import '../../chat/widgets/streaming_status_widget.dart';
import '../models/hermes_config.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_live_run_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_activity_presenter.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_identifier.dart';
import '../services/hermes_live_activity.dart';
import 'hermes_inline_run_surface.dart' show hermesThinkingOrbState;
import 'hermes_run_details_button.dart';
import 'hermez_chat_palette.dart';
import 'hermez_live.dart';
import 'hermez_status_morph.dart';

/// One answer's activity entry, beside its bot mark. Old answers never subscribe
/// to a new turn's controls or pending requests. The existing sheet owns details.
class HermesMessageActivity extends ConsumerWidget {
  const HermesMessageActivity({
    super.key,
    required this.messages,
    required this.currentAnswer,
  });
  final List<ChatMessage> messages;
  final bool currentAnswer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (messages.isEmpty) return const SizedBox.shrink();
    final sessionId = validateHermesOpaqueIdentifier(
      messages.first.metadata?['hermesSessionId'],
    );
    final service = ref.watch(hermesApiServiceProvider);
    if (sessionId == null || service is! HermesDesktopApiService) {
      return const SizedBox.shrink();
    }
    final state = currentAnswer
        ? ref.watch(hermesSessionTurnStateProvider(sessionId)).value ??
              service.turnStateFor(sessionId)
        : HermesDesktopTurnState.idle;
    final events = currentAnswer
        ? ref.watch(hermesSessionActivityProvider(sessionId)).value ??
              service.activitySnapshotFor(sessionId)
        : const <HermesLiveActivityEvent>[];
    final attention =
        currentAnswer &&
        (ref
                .watch(hermesPendingSessionDecisionsProvider(sessionId))
                .value
                ?.isNotEmpty ??
            false);
    final statuses = [for (final message in messages) ...message.statusHistory];
    final running = state == HermesDesktopTurnState.running;
    final run = HermesRunSummary.latest(events, running: running);
    final summary = hermesStatusSummary(context, statuses, running: running);
    return HermesRunActivityOrb(
      sessionId: sessionId,
      state: state,
      attention: attention,
      events: run.events,
      summary: summary,
      failed: messages.any((message) => message.error != null) || run.failed,
      answerMessages: messages,
      currentAnswer: currentAnswer,
    );
  }
}

/// The orb and its label are one touch target and one morph origin. It remains
/// quiet and still after completion; no separate activity or Run details button.
class HermesRunActivityOrb extends StatefulWidget {
  const HermesRunActivityOrb({
    super.key,
    required this.sessionId,
    required this.state,
    this.attention = false,
    this.failed = false,
    this.summary = '',
    this.events = const [],
    this.answerMessages,
    this.currentAnswer = false,
    this.detailsBuilder,
  });
  final String sessionId;
  final HermesDesktopTurnState state;
  final bool attention;
  final bool failed;
  final String summary;
  final List<HermesLiveActivityEvent> events;
  final List<ChatMessage>? answerMessages;
  final bool currentAnswer;
  final WidgetBuilder? detailsBuilder;

  @override
  State<HermesRunActivityOrb> createState() => _HermesRunActivityOrbState();
}

class _HermesRunActivityOrbState extends State<HermesRunActivityOrb>
    with WidgetsBindingObserver {
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final done =
        widget.state == HermesDesktopTurnState.idle && !widget.attention;
    final title = widget.attention
        ? 'Input needed'
        : done
        ? (widget.failed ? 'Run failed' : 'Done')
        : switch (widget.state) {
            HermesDesktopTurnState.running => 'Hermes is working',
            HermesDesktopTurnState.reconnecting => 'Reconnecting',
            _ => 'Recovering the run',
          };
    final rows = HermesActivityPresenter.rows(
      widget.events,
      running: widget.state == HermesDesktopTurnState.running,
    );
    final label = widget.summary.isNotEmpty ? widget.summary : title;
    return HermesRunDetailsButton(
      key: ValueKey('run-activity-${widget.sessionId}'),
      sessionId: widget.sessionId,
      answerMessages: widget.answerMessages,
      currentAnswer: widget.currentAnswer,
      detailsBuilder: widget.detailsBuilder,
      faceBuilder: (context, onOpen) => Tooltip(
        message: '$title. $label. Open run activity',
        child: HermezMotionSurface(
          key: const ValueKey('hermes-run-orb-toggle'),
          semanticLabel: '$title. $label. Open run activity',
          weight: HermezMotionWeight.light,
          originRadius: 24,
          originColor: palette.surface,
          originBorderColor: palette.border,
          onOpen: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: done
                        ? HermezStatusMorph(
                            size: 20,
                            state: widget.failed
                                ? HermezMorphState.failed
                                : HermezMorphState.done,
                          )
                        : ThinkingOrb(
                            size: OrbSize.size20,
                            state: hermesThinkingOrbState(
                              turnState: widget.state,
                              attention: widget.attention,
                              rows: rows,
                            ),
                            semanticLabel: title,
                            color: widget.attention
                                ? palette.accent
                                : palette.muted,
                            paused:
                                !_foreground || !HermezLiveMotion.on(context),
                          ),
                  ),
                ),
                Flexible(
                  child: Text(
                    widget.attention ? 'Input needed' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.attention ? palette.accent : palette.muted,
                    ),
                  ),
                ),
                Icon(Icons.expand_more_rounded, size: 16, color: palette.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
