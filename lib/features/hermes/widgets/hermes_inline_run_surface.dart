import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../motion/hermez_motion.dart';
import '../models/hermes_config.dart';
import '../providers/hermes_live_run_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_live_activity.dart';
import '../services/hermes_pending_decision_store.dart';
import '../services/hermes_steel_viewer.dart';
import '../sheets/hermes_attention_resolution_sheet.dart';
import 'hermes_live_activity_disclosure.dart';
import 'hermes_run_action_dialogs.dart';
import 'hermes_run_actions.dart';
import 'hermes_steel_live_view.dart';
import 'hermez_chat_palette.dart';
import '../feedback/hermez_feedback.dart';

/// One session-owned run control surface in the transcript's live footer.
/// Browser viewing is lazy and watch-only; Hermes owns the active run.
class HermesInlineRunSurface extends ConsumerStatefulWidget {
  const HermesInlineRunSurface({
    super.key,
    required this.service,
    required this.sessionId,
    required this.turnState,
    this.activityStream,
    this.steerRun,
    this.interruptRun,
  });

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
    if (!await confirmHermesStop(context) || !mounted) return;
    final sessionId = widget.sessionId;
    setState(() {
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
    final browserAvailable = working && parseSteelViewerUrl(viewerUrl) != null;
    final run = HermesRunSummary.latest(_events, running: working);
    final finished =
        !attention &&
        widget.turnState == HermesDesktopTurnState.idle &&
        !run.isEmpty;
    final title = attention
        ? 'Input needed'
        : finished
        ? (run.failed ? 'Run failed' : 'Done')
        : switch (widget.turnState) {
            HermesDesktopTurnState.running => 'Hermes is working',
            HermesDesktopTurnState.reconnecting => 'Reconnecting to Hermes',
            HermesDesktopTurnState.synchronizing => 'Recovering the run',
            HermesDesktopTurnState.idle => 'Hermes needs your attention',
            HermesDesktopTurnState.unsupportedGateway =>
              'Live activity unavailable',
          };
    final latest = _events.isEmpty ? null : _events.last;
    final elapsed = run.elapsed(
      startedAt: working || finished ? _runStartedAt : null,
    );
    final steps = run.steps;
    final tools = run.tools;
    final details = <String>[
      if (working && latest != null) latest.title,
      if (finished && elapsed != null) formatHermesRunDuration(elapsed),
      if (steps > 0) steps == 1 ? '1 step' : '$steps steps',
      if (working && elapsed != null) formatHermesRunDuration(elapsed),
      if (finished && tools.isNotEmpty)
        tools.take(2).map((tool) => tool.name).join(', '),
    ].join(' · ');
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
      builder: (context, edge, child) => DecoratedBox(
        key: _surfaceKey,
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
                  onTap: () => setState(() {
                    _expanded = !_expanded;
                    if (!_expanded) _showBrowser = false;
                  }),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        HermezIconSwap(
                          icon: attention
                              ? Icons.priority_high_rounded
                              : finished
                              ? (run.failed
                                    ? Icons.error_outline_rounded
                                    : Icons.check_circle_rounded)
                              : Icons.radio_button_checked_rounded,
                          color: attention || working || run.failed
                              ? palette.accent
                              : finished
                              ? palette.ink
                              : palette.muted,
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
                              Text(
                                attention
                                    ? 'Review the request below'
                                    : details.isNotEmpty
                                    ? details
                                    : latest?.title ?? 'Live activity',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 12,
                                ),
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
                  visible: attention,
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
                      const SizedBox(height: 10),
                      Text(
                        'Recent activity',
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_events.isEmpty)
                        Text(
                          'Waiting for the first tool update…',
                          style: TextStyle(color: palette.muted),
                        )
                      else
                        SizedBox(
                          height: 190,
                          child: HermesLiveActivityTimeline(
                            // This run only; earlier runs are in the
                            // transcript.
                            events: run.isEmpty ? _events : run.events,
                            running: working,
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
                              onTap: !_busy ? _stop : null,
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
