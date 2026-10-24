import 'dart:collection';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thinking_orbs/thinking_orbs.dart';

import '../../../core/models/chat_message.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../chat/providers/chat_providers.dart'
    show chatMessageByIdProvider, chatMessagesProvider;
import '../../chat/widgets/streaming_status_widget.dart';
import '../models/hermes_config.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_live_run_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_activity_presenter.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_identifier.dart';
import '../services/hermes_inline_ui_capability.dart'
    show hermesIsDelegationResultNotice;
import '../services/hermes_live_activity.dart';
import '../services/hermes_run_transport.dart' show kHermesProviderWaitAction;
import '../services/hermes_steel_viewer.dart';
import '../sheets/hermes_tool_inspector_sheet.dart';
import 'hermes_inline_run_surface.dart'
    show hermesRunUsedBrowser, hermesThinkingOrbState;
import '../../../l10n/app_localizations.dart';
import '../../../l10n/conduit_localizations.dart';
import '../views/hermes_live_run_page.dart';
import 'hermes_steel_live_view.dart' show HermesRunBrowserSection;
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
    if (this.messages.isEmpty) return const SizedBox.shrink();
    // The whole turn, not just this row's group: a delegated run continues
    // after Hermes' hidden "[ASYNC DELEGATION …]" wake-up, and its tools and
    // thinking belong to the same answer. Only the turn's first line shows.
    final anchor = this.messages.first.id;
    final span = ref.watch(
      chatMessagesProvider.select((all) => hermesTurnSpanKey(all, anchor)),
    );
    if (span.leadsElsewhere) return const SizedBox.shrink();
    final messages = span.ids.isEmpty
        ? this.messages
        : [for (final id in span.ids) ?ref.watch(chatMessageByIdProvider(id))];
    final currentAnswer = this.currentAnswer || span.latest;
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
    // A stalled provider is said plainly rather than left as endless working.
    final summary =
        (running ? hermesProviderWaitLabel(statuses) : null) ??
        hermesActivityLabel(
          HermesActivityPresenter.rows(run.events, running: running),
          statuses,
          running: running,
          fallback: hermesStatusSummary(context, statuses, running: running),
        );
    final failed =
        messages.any((message) => message.error != null) || run.failed;
    final thought = hermesThoughtLines(statuses);
    // A plain answer with no tools, thinking, plan or request has nothing to
    // open: the line rolls away once the turn ends rather than leaving a
    // "Done" over nothing. Only the current answer's activity is known here;
    // an older answer's saved run loads when opened, so it keeps its entry.
    final empty =
        currentAnswer &&
        state == HermesDesktopTurnState.idle &&
        !attention &&
        !failed &&
        // Lifecycle events (started, completed) alone are not activity.
        run.subagents == 0 &&
        HermesActivityPresenter.rows(run.events, running: false).isEmpty &&
        statuses.where((s) => s.hidden != true).isEmpty;
    final toolCount = run.tools.fold<int>(0, (n, t) => n + t.count);
    // The run's facts in one line: the run sheet's hero, without the box.
    // Only Hermes' reported model: a message's `model` can be the profile.
    // Read from what this connection already holds: subscribing here would
    // start a fetch for every answer on screen.
    final model = currentAnswer
        ? service.agenticSnapshotFor(sessionId).info?.model
        : null;
    final elapsed = running ? null : run.elapsed();
    final meta = [
      ?model,
      if (elapsed != null && elapsed.inSeconds > 0)
        formatHermesRunDuration(elapsed),
      if (run.steps > 0) run.steps == 1 ? '1 step' : '${run.steps} steps',
    ].join(' · ');
    // Watch-only Steel player, offered while a browsing run is under way.
    final viewerUrl = ref.watch(hermesSteelViewerUrlProvider);
    final browser =
        running &&
            parseSteelViewerUrl(viewerUrl) != null &&
            hermesRunUsedBrowser(run)
        ? HermesRunBrowserSection(viewerUrl: viewerUrl, sessionId: sessionId)
        : null;
    return HermezReveal(
      visible: !empty,
      revealKey: ValueKey('message-activity-$sessionId'),
      child: HermesRunActivityOrb(
        sessionId: sessionId,
        state: state,
        attention: attention,
        events: run.events,
        statuses: statuses,
        summary: summary,
        thought: thought,
        meta: meta,
        browser: browser,
        toolCount: toolCount,
        failed: failed,
        answerMessages: messages,
        currentAnswer: currentAnswer,
      ),
    );
  }
}

/// Where an answer's turn lies in the conversation, as comparable values so a
/// streaming token elsewhere does not rebuild every answer's line.
typedef HermesTurnSpan = ({List<String> ids, bool leadsElsewhere, bool latest});

/// The assistant messages of the turn holding [anchorId]: from the owner's
/// prompt to the next one, across Hermes' hidden delegation wake-ups.
/// [HermesTurnSpan.leadsElsewhere] is true when an earlier message of the same
/// turn already shows text, so that line, above, speaks for the turn.
HermesTurnSpan hermesTurnSpanKey(List<ChatMessage> all, String anchorId) {
  final at = all.indexWhere((message) => message.id == anchorId);
  if (at < 0) return (ids: const [], leadsElsewhere: false, latest: false);
  bool inTurn(ChatMessage message) =>
      message.role == 'assistant' ||
      (message.role == 'user' &&
          hermesIsDelegationResultNotice(message.content));
  var start = at;
  while (start > 0 && inTurn(all[start - 1])) {
    start--;
  }
  var end = at;
  while (end < all.length - 1 && inTurn(all[end + 1])) {
    end++;
  }
  final turn = [
    for (var i = start; i <= end; i++)
      if (all[i].role == 'assistant') all[i],
  ];
  final leadsElsewhere = all
      .sublist(start, at)
      .any(
        (message) =>
            message.role == 'assistant' && message.content.trim().isNotEmpty,
      );
  return (
    ids: _HermesIds([for (final message in turn) message.id]),
    leadsElsewhere: leadsElsewhere,
    latest: end == all.length - 1,
  );
}

/// A list of ids that compares by value, for provider selection.
final class _HermesIds extends ListBase<String> {
  _HermesIds(this._ids);
  final List<String> _ids;

  @override
  int get length => _ids.length;
  @override
  set length(int value) => throw UnsupportedError('read-only');
  @override
  String operator [](int index) => _ids[index];
  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('read-only');
  @override
  bool operator ==(Object other) =>
      other is _HermesIds && listEquals(other._ids, _ids);
  @override
  int get hashCode => Object.hashAll(_ids);
}

/// The model's thinking for this answer as short lines ("Validating card
/// layout"), in order. Each message keeps one `reasoning` status, updated in
/// place while it streams, so every message's latest text counts once.
List<String> hermesThoughtLines(List<ChatStatusUpdate> statuses) {
  final lines = <String>[];
  for (final status in statuses) {
    if (status.action != 'reasoning') continue;
    final text = (status.description ?? '').replaceFirst(
      RegExp(r'^Thinking…\s*'),
      '',
    );
    for (final line in text.split('\n')) {
      final clean = line.replaceAll('*', '').trim();
      if (clean.isNotEmpty && !lines.contains(clean)) lines.add(clean);
    }
  }
  return lines;
}

/// Hermes' open "waiting on the model" notice in plain words, or null when the
/// provider is answering. No second count: Hermes only rewrites the notice
/// when its phase changes, so a number here would go stale.
String? hermesProviderWaitLabel(List<ChatStatusUpdate> statuses) {
  ChatStatusUpdate? wait;
  for (final status in statuses) {
    if (status.action == kHermesProviderWaitAction) wait = status;
  }
  if (wait == null || wait.done == true) return null;
  final text = wait.description ?? '';
  final model = RegExp(r'waiting on (\S+)').firstMatch(text)?.group(1);
  final who = model ?? 'The model';
  return text.contains('still waiting')
      ? '$who is slow to reply · retrying soon'
      : '$who is slow to reply';
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
    this.statuses = const [],
    this.thought = const [],
    this.meta,
    this.browser,
    this.answerMessages,
    this.currentAnswer = false,
    this.detailsBuilder,
  });

  /// One quiet line over the unfolded steps: model, time, step count.
  final String? meta;

  /// The watch-only browser line, while a browsing run can be watched.
  final Widget? browser;

  /// A saved answer's recorded tool steps, for when no live events remain.
  final List<ChatStatusUpdate> statuses;

  /// The model's thinking, as [hermesThoughtLines] reads it.
  final List<String> thought;
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
  bool _expanded = false;

  /// The full run details are unfolded under the steps.
  bool _details = false;
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
  void didUpdateWidget(HermesRunActivityOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the run settles, its open steps fold back into the one line.
    if (oldWidget.state != HermesDesktopTurnState.idle &&
        widget.state == HermesDesktopTurnState.idle) {
      _expanded = false;
      _details = false;
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
    // Finished: say what happened in plain words, not raw tool names. Live
    // thinking reads as its current thought; once done it folds to "Thought"
    // and the thoughts themselves unfold under it.
    final thoughtLine = widget.thought.isEmpty ? null : widget.thought.last;
    final finishedLabel = widget.failed
        ? 'Run failed'
        : widget.summary.isNotEmpty
        ? widget.summary
        : widget.toolCount > 0
        ? 'Used ${widget.toolCount} tool${widget.toolCount == 1 ? '' : 's'}'
        : thoughtLine != null
        ? 'Thought'
        : 'Run details';
    final label = done
        ? finishedLabel
        : (widget.summary.isNotEmpty ? widget.summary : thoughtLine ?? title);
    final List<HermesRunStep> steps = [
      for (final line in widget.thought)
        (text: line, state: HermesActivityRowState.note, row: null),
      ...hermesRunSteps(rows, widget.statuses),
    ];
    final verb = _expanded ? 'Hide' : 'Show';
    Widget face({
      VoidCallback? onTap,
      ValueChanged<HermezMorphOrigin?>? onOpen,
    }) => Tooltip(
      message: '$title. $label. $verb the steps',
      child: HermezMotionSurface(
        key: const ValueKey('hermes-run-orb-toggle'),
        semanticLabel: '$title. $label. $verb the steps',
        semanticsExpanded: _expanded,
        weight: HermezMotionWeight.light,
        originRadius: 24,
        originColor: palette.canvas,
        onTap: onTap,
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
                          paused: !_foreground || !HermezLiveMotion.on(context),
                        ),
                ),
              ),
              Flexible(
                // Each new line rises in as the old one leaves; a working
                // line carries the shimmer.
                child: AnimatedSwitcher(
                  duration: context.reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.45),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(widget.attention ? 'Input needed' : label),
                    child: Builder(
                      builder: (context) {
                        final text = widget.attention ? 'Input needed' : label;
                        final style = TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: widget.attention
                              ? palette.accent
                              : palette.muted,
                        );
                        return KeyedSubtree(
                          key: const ValueKey('hermes-run-orb-label'),
                          child: !done && !widget.attention
                              ? HermezShimmerText(text, style: style)
                              : Text(
                                  text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: style,
                                ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              // Unfolds in place: the chevron turns down with it.
              AnimatedRotation(
                turns: _expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Waiting on the owner opens the steps by itself: the question is
    // answered in the run's own details, unfolded right here.
    final open = _expanded || widget.attention;
    return Column(
      key: ValueKey('run-activity-${widget.sessionId}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        face(onTap: () => setState(() => _expanded = !open)),
        HermezReveal(
          visible: open,
          revealKey: ValueKey('run-steps-${widget.sessionId}'),
          child: _RunSteps(
            steps: steps,
            showSteps: !(_details || widget.attention),
            meta: widget.meta,
            browser: widget.browser,
            sessionId: widget.sessionId,
            details: _FullRunDetails(
              sessionId: widget.sessionId,
              open: _details || widget.attention,
              onToggle: () => setState(() => _details = !_details),
              builder:
                  widget.detailsBuilder ??
                  (context) => HermesLiveRunPage(
                    key: ValueKey('inline-run-${widget.sessionId}'),
                    sessionId: widget.sessionId,
                    inline: true,
                    answerMessages: widget.answerMessages,
                    currentAnswer: widget.currentAnswer,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The run's full details, unfolded in place under its steps: the same view
/// the run sheet had, laid on the rail instead of in a sheet.
class _FullRunDetails extends StatelessWidget {
  const _FullRunDetails({
    required this.sessionId,
    required this.open,
    required this.onToggle,
    required this.builder,
  });

  final String sessionId;
  final bool open;
  final VoidCallback onToggle;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: HermezMotionSurface(
            key: const ValueKey('hermes-run-full-details'),
            semanticLabel: open ? 'Hide full run details' : 'Full run details',
            semanticsExpanded: open,
            weight: HermezMotionWeight.light,
            originRadius: 12,
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Full run details',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        HermezReveal(
          visible: open,
          revealKey: ValueKey('run-details-$sessionId'),
          // The detail view carries Material widgets; chat itself does not
          // always provide their localizations.
          child: Localizations.override(
            context: context,
            delegates: [
              ...conduitLocalizationsDelegates,
              ...AppLocalizations.localizationsDelegates,
            ],
            // Its buttons and folds ink on the chat's own canvas.
            child: Material(
              type: MaterialType.transparency,
              child: Builder(builder: builder),
            ),
          ),
        ),
      ],
    );
  }
}

/// One step of a run as the conversation shows it. [row] is the live tool row
/// behind it, when there is one to inspect.
typedef HermesRunStep = ({
  String text,
  HermesActivityRowState state,
  HermesActivityRow? row,
});

/// A run's steps in plain words: the live activity rows while they exist,
/// else the tool steps the saved answer recorded. Repeats fold into a count.
List<HermesRunStep> hermesRunSteps(
  List<HermesActivityRow> rows,
  List<ChatStatusUpdate> statuses,
) {
  if (rows.isNotEmpty) {
    return [
      for (final row in rows)
        (
          text: [
            row.verb,
            if (row.object != null && row.object!.trim().isNotEmpty)
              row.object!.trim(),
            if (row.count > 1) '×${row.count}',
          ].join(' '),
          state: row.state,
          row: row,
        ),
    ];
  }
  final steps = <HermesRunStep>[];
  String? last;
  var count = 0;
  void flush() {
    final verb = last;
    if (verb == null) return;
    steps.add((
      text: count > 1 ? '$verb ×$count' : verb,
      state: HermesActivityRowState.done,
      row: null,
    ));
  }

  for (final status in statuses) {
    if (status.hidden == true) continue;
    final name = hermesStatusToolName(status);
    if (name == null || name.isEmpty) continue;
    final verb = HermesActivityPresenter.verb(name);
    if (verb == last) {
      count++;
      continue;
    }
    flush();
    last = verb;
    count = 1;
  }
  flush();
  return steps;
}

/// The unfolded steps: a quiet list on a thin rail, then the way into the full
/// run. No box: it reads as part of the answer it belongs to.
class _RunSteps extends StatelessWidget {
  const _RunSteps({
    required this.steps,
    required this.details,
    this.meta,
    this.browser,
    this.sessionId,
    this.showSteps = true,
  });

  final List<HermesRunStep> steps;
  final Widget details;
  final String? meta;
  final Widget? browser;

  /// Lets a tool step unfold its input and result in place.
  final String? sessionId;

  /// False while the full details are open: their timeline has every step.
  final bool showSteps;

  static const int _shown = 8;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final shown = steps.take(_shown).toList(growable: false);
    final rest = steps.length - shown.length;
    final meta = TextStyle(fontSize: 12.5, height: 1.3, color: palette.ink);
    Widget mark(HermesActivityRowState state) => switch (state) {
      HermesActivityRowState.running => const HermezLiveDot(
        state: HermezLiveState.working,
        size: 6,
      ),
      HermesActivityRowState.failed => Icon(
        Icons.close_rounded,
        size: 14,
        color: Theme.of(context).colorScheme.error,
      ),
      HermesActivityRowState.waiting => Icon(
        Icons.hourglass_empty_rounded,
        size: 13,
        color: palette.accent,
      ),
      HermesActivityRowState.note => Icon(
        Icons.notes_rounded,
        size: 13,
        color: palette.muted,
      ),
      HermesActivityRowState.done => Icon(
        Icons.check_rounded,
        size: 14,
        color: palette.muted,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(left: 13, bottom: 6),
      child: CustomPaint(
        painter: _StepRail(palette.muted.withValues(alpha: 0.35)),
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (this.meta case final line? when line.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Text(
                    line,
                    key: const ValueKey('hermes-run-meta'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta.copyWith(
                      fontSize: 11.5,
                      color: palette.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              if (showSteps && shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'No steps recorded for this answer.',
                    style: meta.copyWith(color: palette.muted),
                  ),
                ),
              if (showSteps)
                for (final (i, step) in shown.indexed)
                  _StepLine(
                    key: ValueKey('step-$i-${step.text}'),
                    step: step,
                    mark: mark(step.state),
                    style: meta,
                    sessionId: sessionId,
                  ),
              if (showSteps && rest > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 24),
                  child: Text(
                    '$rest more in the full run',
                    style: meta.copyWith(color: palette.muted),
                  ),
                ),
              ?browser,
              details,
            ],
          ),
        ),
      ),
    );
  }
}

/// A step's line. A tool step the transcript can show up close unfolds its
/// input and result right under itself; the rest are plain text. A step
/// arrives with a short rise into place, and the one running shimmers.
class _StepLine extends StatefulWidget {
  const _StepLine({
    super.key,
    required this.step,
    required this.mark,
    required this.style,
    required this.sessionId,
  });

  final HermesRunStep step;
  final Widget mark;
  final TextStyle style;
  final String? sessionId;

  @override
  State<_StepLine> createState() => _StepLineState();
}

class _StepLineState extends State<_StepLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final step = widget.step;
    final row = step.row;
    final sessionId = widget.sessionId;
    final inspectable = row != null && row.inspectable && sessionId != null;
    final quiet =
        step.state == HermesActivityRowState.done ||
        step.state == HermesActivityRowState.note;
    final style = quiet
        ? widget.style.copyWith(color: palette.muted)
        : widget.style;
    final running = step.state == HermesActivityRowState.running;
    final line = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 16, height: 16, child: Center(child: widget.mark)),
          const SizedBox(width: 8),
          Expanded(
            child: running
                ? HermezShimmerText(step.text, style: style, maxLines: 2)
                : Text(
                    step.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
          ),
          if (inspectable)
            AnimatedRotation(
              turns: _open ? 0.25 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 15,
                color: palette.muted,
              ),
            ),
        ],
      ),
    );
    final body = !inspectable
        ? line
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              HermezMotionSurface(
                weight: HermezMotionWeight.light,
                semanticLabel:
                    '${step.text}. ${_open ? 'Hide' : 'Show'} details',
                semanticsExpanded: _open,
                originRadius: 10,
                onTap: () => setState(() => _open = !_open),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: line,
                ),
              ),
              HermezReveal(
                visible: _open,
                revealKey: ValueKey('tool-${row.key}'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 2, 0, 10),
                  child: HermesToolInspectorInline(
                    sessionId: sessionId,
                    row: row,
                  ),
                ),
              ),
            ],
          );
    // Arrives once: a short rise and fade, never again on rebuilds.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: context.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - t)),
          child: child,
        ),
      ),
      child: body,
    );
  }
}

class _StepRail extends CustomPainter {
  const _StepRail(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawLine(
    const Offset(1, 2),
    Offset(1, size.height - 8),
    Paint()
      ..color = color
      ..strokeWidth = 1,
  );

  @override
  bool shouldRepaint(_StepRail oldDelegate) => oldDelegate.color != color;
}
