import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../motion/hermez_motion.dart';
import '../models/hermes_config.dart';
import '../models/hermes_subagent.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_live_run_providers.dart';
import '../services/hermes_activity_presenter.dart';
import '../services/hermes_agentic_state.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_live_activity.dart';
import '../services/hermes_pending_decision_store.dart';
import '../services/hermes_steel_viewer.dart';
import '../sheets/hermes_attention_resolution_sheet.dart';
import '../sheets/hermes_delegates_sheet.dart';
import '../sheets/hermes_plan_sheet.dart';
import '../sheets/hermes_tool_inspector_sheet.dart';
import 'hermes_activity_view.dart';
import 'hermes_plan_view.dart';
import 'hermes_run_action_dialogs.dart';
import 'hermes_run_actions.dart';
import 'hermes_steel_live_view.dart';
import 'hermez_chat_palette.dart';
import 'hermez_live.dart';
import 'hermez_skeleton.dart';
import 'hermez_status_morph.dart';
import 'hermez_surfaces.dart';
import '../feedback/hermez_feedback.dart';

/// One session-owned run control surface in the transcript's live footer.
/// Browser viewing is lazy and watch-only; Hermes owns the active run.
/// Whether the run has started a browser (Steel) tool.
@visibleForTesting
bool hermesRunUsedBrowser(HermesRunSummary run) => run.tools.any(
  (tool) => RegExp('browser|steel', caseSensitive: false).hasMatch(tool.name),
);

class HermesInlineRunSurface extends ConsumerStatefulWidget {
  const HermesInlineRunSurface({
    super.key,
    required this.service,
    required this.sessionId,
    required this.turnState,
    this.activityStream,
    this.steerRun,
    this.interruptRun,
    this.requestShownBelow = false,
  });

  /// The pending request is already on screen as the composer's prompt card.
  /// The surface then says only that input is needed, and does not repeat the
  /// request text or a Review button for the same question.
  final bool requestShownBelow;

  final HermesDesktopApiService service;
  final String sessionId;
  final HermesDesktopTurnState turnState;

  /// Small test seam; production listens to the existing Desktop event stream.
  final Stream<List<HermesLiveActivityEvent>>? activityStream;
  final Future<bool> Function(String sessionId, String text)? steerRun;
  final Future<void> Function(String sessionId)? interruptRun;

  @override
  ConsumerState<HermesInlineRunSurface> createState() =>
      _HermesInlineRunSurfaceState();
}

class _HermesInlineRunSurfaceState extends ConsumerState<HermesInlineRunSurface>
    with WidgetsBindingObserver {
  StreamSubscription<List<HermesLiveActivityEvent>>? _activitySubscription;
  List<HermesLiveActivityEvent> _events = const [];
  String? _lastWaitingMarker;
  bool _expanded = false;
  bool _showBrowser = false;
  bool _busy = false;
  bool _stopping = false;

  /// The Stop guard is open under the run's controls.
  bool _confirmingStop = false;
  DateTime? _runStartedAt;
  Timer? _clock;
  final GlobalKey _surfaceKey = GlobalKey();
  final GlobalKey _apertureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindActivity();
    if (widget.turnState == HermesDesktopTurnState.running) _runStarted();
  }

  /// A run began: time it, and tick the elapsed time once a second.
  void _runStarted() {
    _runStartedAt = DateTime.now().toUtc();
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _bindActivity() {
    _events = widget.service.activitySnapshotFor(widget.sessionId);
    _activitySubscription =
        (widget.activityStream ?? widget.service.activityFor(widget.sessionId))
            .listen((events) {
              if (!mounted) return;
              for (final event in events.reversed) {
                if (event.kind != HermesLiveActivityKind.waitingForInput) {
                  continue;
                }
                final marker =
                    '${event.sessionId}:${event.timestamp.toIso8601String()}';
                if (_lastWaitingMarker != marker &&
                    event.sessionId == widget.sessionId) {
                  _lastWaitingMarker = marker;
                  ref.invalidate(
                    hermesPendingSessionDecisionsProvider(widget.sessionId),
                  );
                }
                break;
              }
              setState(() => _events = events);
            });
  }

  @override
  void didUpdateWidget(covariant HermesInlineRunSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        !identical(oldWidget.service, widget.service) ||
        oldWidget.activityStream != widget.activityStream) {
      final previous = _activitySubscription;
      if (previous != null) unawaited(previous.cancel());
      _lastWaitingMarker = null;
      _expanded = false;
      _showBrowser = false;
      _busy = false;
      _bindActivity();
      _refreshPendingAfterFrame();
    } else if (oldWidget.turnState != widget.turnState) {
      _refreshPendingAfterFrame();
      final wasRunning = oldWidget.turnState == HermesDesktopTurnState.running;
      final running = widget.turnState == HermesDesktopTurnState.running;
      if (running && !wasRunning) {
        _runStarted();
      } else if (wasRunning && !running) {
        // The run ended: shrink to its summary instead of disappearing.
        _clock?.cancel();
        _clock = null;
        _expanded = false;
        _showBrowser = false;
      }
    }
  }

  void _refreshPendingAfterFrame() {
    final sessionId = widget.sessionId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.sessionId == sessionId) {
        ref.invalidate(hermesPendingSessionDecisionsProvider(sessionId));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(hermesPendingSessionDecisionsProvider(widget.sessionId));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    final subscription = _activitySubscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  /// Sends a steer typed into the inline field. The field closes only when
  /// Hermes accepted it.
  Future<bool> _steer(String text) async {
    if (_busy || widget.turnState != HermesDesktopTurnState.running) {
      return false;
    }
    final sessionId = widget.sessionId;
    setState(() => _busy = true);
    // Sensory cues are presentation only: sent, then Hermes' answer.
    HermezFeedback.play(HermezFeedbackCue.controlSelect);
    try {
      final accepted =
          await (widget.steerRun?.call(sessionId, text) ??
              widget.service.steer(sessionId, text));
      HermezFeedback.play(
        accepted
            ? HermezFeedbackCue.approvalAccepted
            : HermezFeedbackCue.runFailed,
      );
      if (!mounted || widget.sessionId != sessionId) return false;
      if (!accepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This run cannot be steered right now.'),
          ),
        );
      }
      return accepted;
    } catch (_) {
      HermezFeedback.play(HermezFeedbackCue.runFailed);
      if (mounted && widget.sessionId == sessionId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not steer this run.')),
        );
      }
      return false;
    } finally {
      if (mounted && widget.sessionId == sessionId) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stop() async {
    if (_busy || widget.turnState != HermesDesktopTurnState.running) return;
    final sessionId = widget.sessionId;
    setState(() {
      _confirmingStop = false;
      _busy = true;
      _stopping = true;
    });
    HermezFeedback.play(HermezFeedbackCue.controlSelect);
    try {
      await (widget.interruptRun?.call(sessionId) ??
          widget.service.interrupt(sessionId));
      HermezFeedback.play(HermezFeedbackCue.objectClose);
    } catch (_) {
      HermezFeedback.play(HermezFeedbackCue.runFailed);
      if (mounted && widget.sessionId == sessionId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not stop this run.')),
        );
      }
    } finally {
      if (mounted && widget.sessionId == sessionId) {
        setState(() {
          _busy = false;
          _stopping = false;
        });
      }
    }
  }

  Future<void> _review(HermesPendingDesktopDecision decision) async {
    if (decision.storedSessionId != widget.sessionId) return;
    final sessionId = widget.sessionId;
    final surface = _surfaceKey.currentContext;
    final resolved = await showHermesAttentionResolutionSheet(
      context,
      decision,
      origin: surface == null
          ? null
          : HermezMorphOrigin.of(
              surface,
              radius: 20,
              color: HermezChatPalette.forBrightness(
                Theme.of(context).brightness,
              ).surface,
            ),
    );
    if (resolved == true && mounted && widget.sessionId == sessionId) {
      ref.invalidate(hermesPendingSessionDecisionsProvider(sessionId));
    }
  }

  /// The inline browser aperture grows into the full-screen viewer and
  /// contracts back into it on Back.
  void _openBrowser(String viewerUrl) {
    final aperture = _apertureKey.currentContext;
    Navigator.of(context).push(
      HermezRoute<void>(
        motion: HermezRouteMotion.expand,
        reducedMotion: context.reduceMotion,
        origin: aperture == null
            ? null
            : HermezMorphOrigin.of(
                aperture,
                radius: 16,
                color: HermezChatPalette.forBrightness(
                  Theme.of(context).brightness,
                ).canvas,
              ),
        builder: (_) => HermesSteelFullScreenPage(
          viewerUrl: viewerUrl,
          sessionId: widget.sessionId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final pending = ref.watch(
      hermesPendingSessionDecisionsProvider(widget.sessionId),
    );
    final decisions =
        pending.asData?.value ?? const <HermesPendingDesktopDecision>[];
    final attention = decisions.isNotEmpty;
    final working = widget.turnState == HermesDesktopTurnState.running;
    final viewerUrl = ref.watch(hermesSteelViewerUrlProvider);
    final run = HermesRunSummary.latest(_events, running: working);
    final agentic =
        ref.watch(hermesAgenticStateProvider(widget.sessionId)).value ??
        HermesAgenticSnapshot.empty;
    final plan = agentic.hasPlan ? agentic.todo : null;
    final workers = agentic.subagents;
    final rows = HermesActivityPresenter.rows(
      run.isEmpty ? _events : run.events,
      running: working,
    );
    final nowLine = working ? HermesActivityPresenter.now(rows) : null;
    // Offered once the run has used a browser tool: a run that only searched
    // or ran a command has nothing to watch.
    final browserAvailable =
        working &&
        parseSteelViewerUrl(viewerUrl) != null &&
        hermesRunUsedBrowser(run);
    final finished =
        !attention &&
        widget.turnState == HermesDesktopTurnState.idle &&
        !run.isEmpty;
    final title = attention
        ? 'Input needed'
        : finished
        ? (run.failed
              ? 'Run failed'
              : plan != null && plan.hasActiveWork
              ? hermesPlanStatus(plan, running: false)
              : 'Done')
        : switch (widget.turnState) {
            HermesDesktopTurnState.running => 'Hermes is working',
            HermesDesktopTurnState.reconnecting => 'Reconnecting to Hermes',
            HermesDesktopTurnState.synchronizing => 'Recovering the run',
            HermesDesktopTurnState.idle => 'Hermes needs your attention',
            HermesDesktopTurnState.unsupportedGateway =>
              'Live activity unavailable',
          };
    final elapsed = run.elapsed(
      startedAt: working || finished ? _runStartedAt : null,
    );
    final steps = run.steps;
    final tools = run.tools;
    // Between steps, the step that just finished, in words.
    final lastRow = rows.isEmpty ? null : rows.last;
    final lastLine = lastRow == null
        ? null
        : lastRow.object == null
        ? lastRow.verb
        : '${lastRow.verb} · ${lastRow.object}';
    final details = <String>[
      if (working) nowLine ?? lastLine ?? 'Thinking',
      if (finished && elapsed != null) formatHermesRunDuration(elapsed),
      if (steps > 0) steps == 1 ? '1 step' : '$steps steps',
      if (finished && tools.isNotEmpty)
        HermesActivityPresenter.headline(tools)
            .map(HermesActivityPresenter.verb)
            .join(', '),
    ].join(' · ');
    final clock = working && elapsed != null
        ? formatHermesRunDuration(elapsed)
        : null;
    final reduced = context.reduceMotion;
    final settle = reduced
        ? Duration.zero
        : HermezMotion.settleFor(HermezMotionWeight.medium);
    // One surface. Its edge and status mark change with the run's state;
    // everything else unrolls inside it.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(
        end: attention
            ? palette.accent.withValues(alpha: 0.55)
            : palette.border,
      ),
      duration: settle,
      curve: HermezMotion.curveMedium,
      // Its own layer, edge included: a review sheet grows out of this card's
      // face and dissolves back into it.
      builder: (context, edge, child) => RepaintBoundary(
        key: _surfaceKey,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: edge ?? palette.border,
              width: attention ? 1.5 : 1,
            ),
          ),
          child: child,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          type: MaterialType.transparency,
          // No size animation here: every section inside unrolls and rolls
          // away on its own, and a second animated size around them trailed
          // behind and settled late.
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                HermezMotionSurface(
                  weight: HermezMotionWeight.light,
                  semanticLabel: _expanded
                      ? '$title. Collapse activity'
                      : '$title. Expand activity',
                  // The same grammar as HermezExpandableSection: an
                  // in-place compartment with its own quiet latch.
                  semanticsExpanded: _expanded,
                  feedbackCue: _expanded
                      ? HermezFeedbackCue.compartmentClose
                      : HermezFeedbackCue.compartmentOpen,
                  onTap: () => setState(() {
                    _expanded = !_expanded;
                    if (!_expanded) _showBrowser = false;
                  }),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        // One object from working to its outcome: the arc
                        // spins, closes, floods and draws its mark.
                        HermezStatusMorph(
                          state: attention
                              ? HermezMorphState.attention
                              : finished
                              ? (run.failed
                                    ? HermezMorphState.failed
                                    : HermezMorphState.done)
                              : working
                              ? HermezMorphState.working
                              : HermezMorphState.idle,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: palette.ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    // A light band runs through the line
                                    // while Hermes works.
                                    child: HermezSheen(
                                      active: working && !attention,
                                      child: HermezLiveText(
                                        attention
                                            ? 'Review the request below'
                                            : details.isNotEmpty
                                            ? details
                                            : 'Live activity',
                                        live: working && !attention,
                                        style: TextStyle(
                                          color: working
                                              ? palette.ink
                                              : palette.muted,
                                          fontSize: 12.5,
                                          fontWeight: working
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (clock != null && !attention) ...[
                                    const SizedBox(width: 8),
                                    // Ticks in place: a clock, not news.
                                    Text(
                                      clock,
                                      style: TextStyle(
                                        color: palette.muted,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: settle,
                          curve: HermezMotion.curveMedium,
                          child: Icon(
                            Icons.expand_more_rounded,
                            color: palette.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                HermezReveal(
                  visible: plan != null && !_expanded,
                  revealKey: const ValueKey('inline-plan-bar'),
                  child: plan == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 2),
                          child: HermezPlanBar(
                            snapshot: plan,
                            height: 3,
                            paused: !working && plan.hasActiveWork,
                          ),
                        ),
                ),
                HermezReveal(
                  visible: attention && !widget.requestShownBelow,
                  weight: HermezMotionWeight.medium,
                  revealKey: const ValueKey('inline-attention'),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          decisions.length == 1
                              ? decisions.first.prompt ??
                                    'Hermes needs your response.'
                              : 'Hermes needs your attention · ${decisions.length} requests',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: palette.ink),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final decision in decisions.take(3))
                              HermezRunPill(
                                label: decisions.length == 1
                                    ? 'Review'
                                    : 'Review request',
                                icon: Icons.arrow_outward_rounded,
                                emphasized: true,
                                onTap: () => _review(decision),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                HermezReveal(
                  visible: !attention && pending.hasError,
                  revealKey: const ValueKey('inline-pending-error'),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => ref.invalidate(
                        hermesPendingSessionDecisionsProvider(widget.sessionId),
                      ),
                      child: const Text('Could not load requests · Retry'),
                    ),
                  ),
                ),
                // Browser watch stays exactly as before: plain presence and
                // no animated clip or transform around the platform WebView,
                // which can render blank inside one.
                if (browserAvailable) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _showBrowser = !_showBrowser;
                          if (_showBrowser) _expanded = true;
                        }),
                        icon: const Icon(Icons.visibility_outlined),
                        label: Text(
                          _showBrowser ? 'Close browser' : 'Watch browser',
                        ),
                      ),
                      if (_showBrowser)
                        TextButton.icon(
                          onPressed: () => _openBrowser(viewerUrl),
                          icon: const Icon(Icons.open_in_full),
                          label: const Text('Expand'),
                        ),
                    ],
                  ),
                  if (_showBrowser) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      key: _apertureKey,
                      height: 260,
                      child: HermesSteelLiveView(viewerUrl: viewerUrl),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Watch only · Hermes controls this browser.',
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                HermezReveal(
                  visible: _expanded,
                  weight: HermezMotionWeight.medium,
                  revealKey: const ValueKey('inline-expanded'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (plan != null) ...[
                        const SizedBox(height: 8),
                        HermesPlanPreview(
                          plan: plan,
                          running: working,
                          onOpen: (origin) => showHermesPlanSheet(
                            context,
                            sessionId: widget.sessionId,
                            origin: origin,
                          ),
                        ),
                      ],
                      if (workers.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _DelegatesRow(
                          workers: workers,
                          onOpen: (origin) => showHermesDelegatesSheet(
                            context,
                            sessionId: widget.sessionId,
                            origin: origin,
                          ),
                        ),
                      ],
                      if (!run.isEmpty) ...[
                        const SizedBox(height: 10),
                        _RunStats(
                          palette: palette,
                          elapsed: elapsed,
                          steps: steps,
                          tools: tools,
                          subagents: run.subagents,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'ACTIVITY',
                        style: HermezType.technical(palette.muted),
                      ),
                      const SizedBox(height: 4),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: HermezLiveText(
                            working
                                ? 'Waiting for the first step…'
                                : 'No steps in this run.',
                            live: working,
                            style: TextStyle(color: palette.muted),
                          ),
                        )
                      else
                        // This run only; earlier runs are in the transcript.
                        HermesActivityList(
                          rows: rows,
                          onInspect: (row, origin) => showHermesToolInspector(
                            context,
                            sessionId: widget.sessionId,
                            row: row,
                            origin: origin,
                          ),
                        ),
                      const SizedBox(height: 10),
                      HermesRunActions(
                        // Steer grows into an inline field in place; no
                        // dialog. Sending does not depend on [_busy] so the
                        // field stays open while its own send runs.
                        onSteer: working ? _steer : null,
                        showSteer: working,
                        trailing: [
                          if (working)
                            HermezRunPill(
                              label: _stopping ? 'Stopping…' : 'Stop',
                              icon: Icons.stop_circle_outlined,
                              busy: _stopping,
                              onTap: !_busy
                                  ? () => setState(
                                      () => _confirmingStop = !_confirmingStop,
                                    )
                                  : null,
                            ),
                          HermezRunPill(
                            label: 'Full activity',
                            icon: Icons.chevron_right_rounded,
                            quiet: true,
                            onTap: () => context.pushNamed(
                              RouteNames.hermesLiveRun,
                              pathParameters: {'sessionId': widget.sessionId},
                            ),
                          ),
                        ],
                      ),
                      HermesStopGuard(
                        open: _confirmingStop && working,
                        onKeepRunning: () =>
                            setState(() => _confirmingStop = false),
                        onStop: _stop,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The run at a glance: how long, how many steps, and which tools.
class _RunStats extends StatelessWidget {
  const _RunStats({
    required this.palette,
    required this.elapsed,
    required this.steps,
    required this.tools,
    required this.subagents,
  });

  final HermezChatPalette palette;
  final Duration? elapsed;
  final int steps;
  final List<({String name, int count})> tools;
  final int subagents;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            stat(
              'Time',
              elapsed == null ? '—' : formatHermesRunDuration(elapsed!),
            ),
            stat('Steps', '$steps'),
            stat('Tools', '${tools.length}'),
            if (subagents > 0) stat('Subagents', '$subagents'),
          ],
        ),
        if (tools.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tool in tools.take(8))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: palette.canvas,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    tool.count > 1 ? '${tool.name} ×${tool.count}' : tool.name,
                    style: TextStyle(color: palette.ink, fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// "2 delegates working · 1 done", opening the delegates sheet.
class _DelegatesRow extends StatelessWidget {
  const _DelegatesRow({required this.workers, required this.onOpen});

  final List<HermesSubagentState> workers;
  final ValueChanged<HermezMorphOrigin?> onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final live = workers.live;
    final latest = workers
        .where((worker) => worker.status.isLive)
        .map((worker) => worker.latest ?? worker.goal)
        .firstOrNull;
    return HermezMotionSurface(
      weight: HermezMotionWeight.light,
      semanticLabel: '${hermesDelegatesSummary(workers)}. Open delegates',
      originRadius: 14,
      onOpen: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: palette.ink.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: live > 0
                    ? const HermezLiveDot(
                        state: HermezLiveState.working,
                        size: 6,
                      )
                    : Icon(
                        Icons.call_split_rounded,
                        size: 17,
                        color: palette.ink,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hermesDelegatesSummary(workers),
                    style: HermezType.body(palette).copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (latest != null)
                    HermezLiveText(
                      latest,
                      live: live > 0,
                      style: HermezType.meta(palette).copyWith(fontSize: 12),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: palette.muted),
          ],
        ),
      ),
    );
  }
}
