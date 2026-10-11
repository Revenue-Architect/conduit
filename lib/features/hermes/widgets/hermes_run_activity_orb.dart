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
    final summary = hermesActivityLabel(
      HermesActivityPresenter.rows(run.events, running: running),
      statuses,
      running: running,
      fallback: hermesStatusSummary(context, statuses, running: running),
    );
    final failed =
        messages.any((message) => message.error != null) || run.failed;
    // A plain answer with no tools, plan or request has nothing to open: show
    // no activity control rather than a "Done" that leads to an empty sheet.
    // Only the current answer's activity is known here; an older answer's
    // saved run loads when opened, so it always keeps its entry point.
    if (currentAnswer &&
        state == HermesDesktopTurnState.idle &&
        !attention &&
        !failed &&
        // Lifecycle events (started, completed) alone are not activity.
        run.subagents == 0 &&
        HermesActivityPresenter.rows(run.events, running: false).isEmpty &&
        statuses.where((s) => s.hidden != true).isEmpty) {
      return const SizedBox.shrink();
    }
    final toolCount = run.tools.fold<int>(0, (n, t) => n + t.count);
    return HermesRunActivityOrb(
      sessionId: sessionId,
      state: state,
      attention: attention,
      events: run.events,
      summary: summary,
      toolCount: toolCount,
      failed: failed,
      answerMessages: messages,
      currentAnswer: currentAnswer,
    );
  }
}

/// The run's label in plain words: "Ran code 4 times", "Read web page and 2
/// more". Raw tool names ("Explored execute_code (4)") never reach the chat.
String hermesActivityLabel(
  List<HermesActivityRow> rows,
  List<ChatStatusUpdate> statuses, {
  required bool running,
  String fallback = '',
}) {
  final steps = <({String verb, int count})>[
    for (final row in rows) (verb: row.verb, count: row.count),
  ];
  if (steps.isEmpty) {
    // Saved answers carry status updates, not live events.
    final counts = <String, int>{};
    for (final status in statuses) {
      if (status.hidden == true) continue;
      final name = hermesStatusToolName(status);
      if (name == null || name.isEmpty) continue;
      final verb = HermesActivityPresenter.verb(name, running: running);
      counts[verb] = (counts[verb] ?? 0) + 1;
    }
    steps.addAll([
      for (final entry in counts.entries) (verb: entry.key, count: entry.value),
    ]);
  }
  if (steps.isEmpty) return fallback;
  // While running, say what is happening now; afterwards, what happened.
  final lead = running ? steps.last : steps.first;
  if (steps.length == 1) {
    return lead.count > 1 ? '${lead.verb} ${lead.count} times' : lead.verb;
  }
  return '${lead.verb} and ${steps.length - 1} more';
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
    this.toolCount = 0,
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

  /// Tool calls in this run, for the quiet finished label.
  final int toolCount;
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
    // Finished: say what happened in plain words, not raw tool names.
    final finishedLabel = widget.failed
        ? 'Run failed'
        : widget.summary.isNotEmpty
        ? widget.summary
        : widget.toolCount > 0
        ? 'Used ${widget.toolCount} tool${widget.toolCount == 1 ? '' : 's'}'
        : 'Run details';
    final label = done
        ? finishedLabel
        : (widget.summary.isNotEmpty ? widget.summary : title);
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
                SizedBox(
                  width: done ? 28 : 40,
                  height: 48,
                  child: Center(
                    child: done
                        // Finished is the quietest state: a small muted mark,
                        // not a filled disc that outweighs the answer.
                        ? Icon(
                            widget.failed
                                ? Icons.error_outline_rounded
                                : Icons.check_rounded,
                            size: 16,
                            color: widget.failed
                                ? Theme.of(context).colorScheme.error
                                : palette.muted,
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
                    key: const ValueKey('hermes-run-orb-label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.attention ? palette.accent : palette.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                // Opens a sheet: a forward chevron, not an inline-expand one.
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: palette.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
