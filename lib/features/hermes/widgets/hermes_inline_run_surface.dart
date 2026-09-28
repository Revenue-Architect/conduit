import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../models/hermes_config.dart';
import '../providers/hermes_live_run_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_live_activity.dart';
import '../services/hermes_pending_decision_store.dart';
import '../services/hermes_steel_viewer.dart';
import '../sheets/hermes_attention_resolution_sheet.dart';
import 'hermes_live_activity_disclosure.dart';
import 'hermes_run_action_dialogs.dart';
import 'hermes_steel_live_view.dart';
import 'hermez_chat_palette.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindActivity();
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
    final subscription = _activitySubscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  Future<void> _steer() async {
    if (_busy || widget.turnState != HermesDesktopTurnState.running) return;
    final text = await promptHermesSteer(context);
    if (!mounted || text == null || text.isEmpty) return;
    final sessionId = widget.sessionId;
    setState(() => _busy = true);
    try {
      final accepted =
          await (widget.steerRun?.call(sessionId, text) ??
              widget.service.steer(sessionId, text));
      if (!mounted || widget.sessionId != sessionId) return;
      if (!accepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This run cannot be steered right now.'),
          ),
        );
      }
    } catch (_) {
      if (mounted && widget.sessionId == sessionId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not steer this run.')),
        );
      }
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
    setState(() => _busy = true);
    try {
      await (widget.interruptRun?.call(sessionId) ??
          widget.service.interrupt(sessionId));
    } catch (_) {
      if (mounted && widget.sessionId == sessionId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not stop this run.')),
        );
      }
    } finally {
      if (mounted && widget.sessionId == sessionId) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _review(HermesPendingDesktopDecision decision) async {
    if (decision.storedSessionId != widget.sessionId) return;
    final sessionId = widget.sessionId;
    final resolved = await showHermesAttentionResolutionSheet(
      context,
      decision,
    );
    if (resolved == true && mounted && widget.sessionId == sessionId) {
      ref.invalidate(hermesPendingSessionDecisionsProvider(sessionId));
    }
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
    final title = attention
        ? 'Input needed'
        : switch (widget.turnState) {
            HermesDesktopTurnState.running => 'Hermes is working',
            HermesDesktopTurnState.reconnecting => 'Reconnecting to Hermes',
            HermesDesktopTurnState.synchronizing => 'Recovering the run',
            HermesDesktopTurnState.idle => 'Hermes needs your attention',
            HermesDesktopTurnState.unsupportedGateway =>
              'Live activity unavailable',
          };
    final latest = _events.isEmpty ? null : _events.last;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: palette.border),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        curve: Curves.easeOutCubic,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => setState(() {
                  _expanded = !_expanded;
                  if (!_expanded) _showBrowser = false;
                }),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Icon(
                        attention
                            ? Icons.priority_high_rounded
                            : Icons.radio_button_checked_rounded,
                        color: attention || working
                            ? palette.accent
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
                              latest?.title ??
                                  (attention
                                      ? 'Review the request below'
                                      : 'Live activity'),
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
                      if (_events.isNotEmpty)
                        Text(
                          '${_events.length}',
                          style: TextStyle(color: palette.muted),
                        ),
                      const SizedBox(width: 6),
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: palette.ink,
                      ),
                    ],
                  ),
                ),
              ),
              if (attention) ...[
                const SizedBox(height: 10),
                Text(
                  decisions.length == 1
                      ? decisions.first.prompt ?? 'Hermes needs your response.'
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
                      OutlinedButton(
                        onPressed: () => _review(decision),
                        child: Text(
                          decisions.length == 1 ? 'Review' : 'Review request',
                        ),
                      ),
                  ],
                ),
              ] else if (pending.hasError) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(
                    hermesPendingSessionDecisionsProvider(widget.sessionId),
                  ),
                  child: const Text('Could not load requests · Retry'),
                ),
              ],
              if (_expanded) ...[
                const SizedBox(height: 12),
                if (browserAvailable) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _showBrowser = !_showBrowser),
                        icon: const Icon(Icons.visibility_outlined),
                        label: Text(
                          _showBrowser ? 'Close browser' : 'Watch browser',
                        ),
                      ),
                      if (_showBrowser)
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => HermesSteelFullScreenPage(
                                viewerUrl: viewerUrl,
                                sessionId: widget.sessionId,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.open_in_full),
                          label: const Text('Expand'),
                        ),
                    ],
                  ),
                  if (_showBrowser) ...[
                    const SizedBox(height: 8),
                    SizedBox(
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
                      events: _events,
                      running: working,
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: working && !_busy ? _steer : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Steer'),
                    ),
                    OutlinedButton.icon(
                      onPressed: working && !_busy ? _stop : null,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Stop'),
                    ),
                    TextButton(
                      onPressed: () => context.pushNamed(
                        RouteNames.hermesLiveRun,
                        pathParameters: {'sessionId': widget.sessionId},
                      ),
                      child: const Text('Full activity'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
