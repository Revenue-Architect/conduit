import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../models/hermes_completed_run_snapshot.dart';
import '../models/hermes_config.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_live_activity.dart';
import '../services/hermes_media_parser.dart';
import '../services/hermes_pending_decision_store.dart';
import '../sheets/hermes_attention_resolution_sheet.dart';
import '../sheets/hermes_completed_run_sheet.dart';
import '../widgets/hermes_session_tile.dart';
import '../widgets/hermes_run_action_dialogs.dart';
import '../widgets/hermes_run_actions.dart';
import '../widgets/hermez_chat_palette.dart';
import '../motion/hermez_morph_origin.dart';
import '../motion/hermez_motion_route.dart' show HermezRouteExits;
import 'hermes_page_chrome.dart';
import '../providers/hermes_agentic_providers.dart';
import '../services/hermes_activity_presenter.dart';
import '../services/hermes_agentic_state.dart';
import '../sheets/hermes_delegates_sheet.dart';
import '../sheets/hermes_plan_sheet.dart';
import '../sheets/hermes_tool_inspector_sheet.dart';
import '../widgets/hermes_activity_view.dart';
import '../widgets/hermes_plan_view.dart';
import '../widgets/hermez_live.dart';
import '../widgets/hermez_technical_background.dart';
import '../widgets/hermez_surfaces.dart';
import '../motion/hermez_motion_surface.dart';
import '../motion/hermez_motion_tokens.dart';

class HermesLiveRunPage extends ConsumerStatefulWidget {
  const HermesLiveRunPage({
    super.key,
    required this.sessionId,
    this.openChat = false,
  });
  final String sessionId;

  /// Opened from a "finished" notification: go straight on to the
  /// conversation, showing the run's status while its transcript loads.
  final bool openChat;

  @override
  ConsumerState<HermesLiveRunPage> createState() => _HermesLiveRunPageState();
}

class _HermesLiveRunPageState extends ConsumerState<HermesLiveRunPage> {
  bool _busy = false;
  bool _chatOpened = false;
  bool _openChatFailed = false;

  /// The Stop guard is open under the run's controls.
  bool _confirmingStop = false;
  bool _sawRunning = false;
  bool _completionPresented = false;
  DateTime? _startedAt;
  HermesDesktopApiService? _pendingService;
  Future<List<HermesPendingDesktopDecision>>? _pendingFuture;

  Future<List<HermesPendingDesktopDecision>> _loadPending(
    HermesDesktopApiService service,
  ) async {
    try {
      return await service.pendingDecisionsForSession(widget.sessionId);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _presentCompletion(
    HermesDesktopApiService service,
    HermesSessionSummary session,
  ) async {
    try {
      final messages = await service.getSessionMessages(widget.sessionId);
      if (!mounted) return;
      String finalText = '';
      for (final message in messages.reversed) {
        if (message['role'] == 'assistant' && message['content'] is String) {
          finalText = message['content'] as String;
          break;
        }
      }
      final parsed = parseHermesMedia(finalText);
      final action = await showHermesCompletedRunSheet(
        context,
        HermesCompletedRunSnapshot(
          sessionId: widget.sessionId,
          title: session.title,
          profile: session.profile,
          startedAt: _startedAt,
          completedAt: DateTime.now(),
          finalText: parsed.cleanText,
          activity: service.activitySnapshotFor(widget.sessionId),
          artifacts: parsed.artifacts,
        ),
      );
      if (!mounted) return;
      if (action == HermesCompletedRunAction.conversation) {
        await openHermesSession(context, ref, session);
      } else if (action == HermesCompletedRunAction.artifacts) {
        context.pushNamed(RouteNames.hermesArtifacts);
      }
    } catch (_) {
      // The live page remains usable if a completed transcript cannot load.
    }
  }

  Future<bool> _steer(HermesDesktopApiService service, String text) async {
    setState(() => _busy = true);
    try {
      final accepted = await service.steer(widget.sessionId, text);
      if (mounted && !accepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This run cannot be steered right now.'),
          ),
        );
      }
      return accepted;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not steer this run.')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop(HermesDesktopApiService service) async {
    if (_busy) return;
    setState(() {
      _confirmingStop = false;
      _busy = true;
    });
    try {
      await service.interrupt(widget.sessionId);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not stop this run.')),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens this run's conversation once Hermes is ready. After a cold launch
  /// from a notification the connection and the session list are still
  /// loading, and the bot (profile) is only known from that list, so wait for
  /// both, for a few seconds. If the chat cannot be opened, show the live page
  /// instead of a blank screen.
  Future<void> _openChatWhenReady() async {
    HermesSessionSummary? row;
    try {
      final sessions = await ref
          .read(hermesSessionsProvider.future)
          .timeout(const Duration(seconds: 6));
      for (final candidate in sessions) {
        if (candidate.id == widget.sessionId) row = candidate;
      }
    } catch (_) {}
    for (var i = 0; i < 40 && mounted; i++) {
      final service = ref.read(hermesApiServiceProvider);
      if (service is HermesDesktopApiService) {
        HermezRouteExits.leaveForAnotherDestination();
        await openHermesSession(
          context,
          ref,
          row ??
              HermesSessionSummary(
                id: widget.sessionId,
                title: 'Hermes run',
                profile: service.boundProfileFor(widget.sessionId),
              ),
        );
        // Opening replaces this page; if it is still here, it did not open.
        if (!mounted ||
            ref.read(hermesActiveSessionProvider) == widget.sessionId) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (mounted) setState(() => _openChatFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(hermesApiServiceProvider);
    if (service is HermesDesktopApiService &&
        !identical(_pendingService, service)) {
      _pendingService = service;
      _pendingFuture = _loadPending(service);
    }
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final sessions =
        ref.watch(hermesSessionsProvider).asData?.value ??
        const <HermesSessionSummary>[];
    HermesSessionSummary? session;
    for (final row in sessions) {
      if (row.id == widget.sessionId) {
        session = row;
        break;
      }
    }
    // A conversation too new for the session list still has its bot from the
    // desktop service's binding.
    final current =
        session ??
        HermesSessionSummary(
          id: widget.sessionId,
          title: 'Hermes run',
          profile: service is HermesDesktopApiService
              ? service.boundProfileFor(widget.sessionId)
              : null,
        );
    if (widget.openChat && !_chatOpened) {
      _chatOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openChatWhenReady());
      });
    }
    if (widget.openChat && !_openChatFailed) {
      // On its way to the conversation: only the page's own background,
      // until the chat replaces it.
      return ColoredBox(color: palette.canvas, child: const SizedBox.expand());
    }
    return HermesPageChrome(
      title: current.title,
      subtitle: 'LIVE ACTIVITY · ${current.profile ?? 'Hermes'}',
      child: service is! HermesDesktopApiService
          ? const Center(child: Text('Live run is unavailable.'))
          : StreamBuilder<HermesDesktopTurnState>(
              stream: service.turnStatesFor(widget.sessionId),
              initialData: service.turnStateFor(widget.sessionId),
              builder: (context, turn) {
                final state = turn.data ?? HermesDesktopTurnState.idle;
                final running = state == HermesDesktopTurnState.running;
                if (running) {
                  if (!_sawRunning) {
                    _startedAt = DateTime.now();
                    _completionPresented = false;
                  }
                  _sawRunning = true;
                } else if (_sawRunning &&
                    state == HermesDesktopTurnState.idle &&
                    !_completionPresented) {
                  _completionPresented = true;
                  _sawRunning = false;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _presentCompletion(service, current);
                  });
                }
                return StreamBuilder<List<HermesLiveActivityEvent>>(
                  stream: service.activityFor(widget.sessionId),
                  initialData: service.activitySnapshotFor(widget.sessionId),
                  builder: (context, activity) => ListView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 34),
                    children: [
                      _LiveHero(
                        sessionId: widget.sessionId,
                        state: state,
                        events: activity.data ?? const [],
                        startedAt: _startedAt,
                      ),
                      const SizedBox(height: 18),
                      const HermesSectionTitle('Activity'),
                      const SizedBox(height: 8),
                      HermesPanel(
                        child: Builder(
                          builder: (context) {
                            final events = activity.data ?? const [];
                            final run = HermesRunSummary.latest(
                              events,
                              running: running,
                            );
                            final rows = HermesActivityPresenter.rows(
                              run.isEmpty ? events : run.events,
                              running: running,
                            );
                            if (rows.isEmpty) {
                              return const Text(
                                'Steps appear here while Hermes works.',
                              );
                            }
                            return HermesActivityList(
                              rows: rows,
                              visible: 30,
                              onInspect: (row, origin) =>
                                  showHermesToolInspector(
                                    context,
                                    sessionId: widget.sessionId,
                                    row: row,
                                    origin: origin,
                                  ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      HermesRunActions(
                        showSteer: running,
                        onSteer: running
                            ? (text) => _steer(service, text)
                            : null,
                        leading: [
                          HermezRunPill(
                            label: 'View chat',
                            icon: Icons.chat_bubble_outline_rounded,
                            onTap: () =>
                                openHermesSession(context, ref, current),
                          ),
                        ],
                        trailing: [
                          if (running)
                            HermezRunPill(
                              label: 'Stop',
                              icon: Icons.stop_circle_outlined,
                              onTap: _busy
                                  ? null
                                  : () => setState(
                                      () => _confirmingStop = !_confirmingStop,
                                    ),
                            ),
                        ],
                      ),
                      HermesStopGuard(
                        open: _confirmingStop && running,
                        onKeepRunning: () =>
                            setState(() => _confirmingStop = false),
                        onStop: () => _stop(service),
                      ),
                      FutureBuilder<List<HermesPendingDesktopDecision>>(
                        future: _pendingFuture,
                        builder: (context, pending) {
                          final decisions =
                              pending.data ??
                              const <HermesPendingDesktopDecision>[];
                          if (decisions.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: HermesPanel(
                              child: Column(
                                children: [
                                  for (final decision in decisions)
                                    Builder(
                                      builder: (rowContext) => RepaintBoundary(
                                        child: ListTile(
                                          title: Text(
                                            decision.prompt ??
                                                'Hermes needs input',
                                          ),
                                          trailing: const Icon(
                                            Icons.chevron_right_rounded,
                                          ),
                                          onTap: () async {
                                            final resolved =
                                                await showHermesAttentionResolutionSheet(
                                                  context,
                                                  decision,
                                                  origin: HermezMorphOrigin.of(
                                                    rowContext,
                                                    radius: 18,
                                                    color: palette.surface,
                                                  ),
                                                );
                                            if (resolved == true && mounted) {
                                              setState(
                                                () => _pendingFuture =
                                                    _loadPending(service),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// The run, honestly: whether it is working, for how long, what it is
/// doing now, and its plan and delegates when it has them.
class _LiveHero extends ConsumerWidget {
  const _LiveHero({
    required this.sessionId,
    required this.state,
    required this.events,
    required this.startedAt,
  });

  final String sessionId;
  final HermesDesktopTurnState state;
  final List<HermesLiveActivityEvent> events;
  final DateTime? startedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final running = state == HermesDesktopTurnState.running;
    final run = HermesRunSummary.latest(events, running: running);
    final rows = HermesActivityPresenter.rows(
      run.isEmpty ? events : run.events,
      running: running,
    );
    final agentic =
        ref.watch(hermesAgenticStateProvider(sessionId)).value ??
        HermesAgenticSnapshot.empty;
    final plan = agentic.hasPlan ? agentic.todo : null;
    final workers = agentic.subagents;
    final current = rows.reversed
        .where((row) => row.state == HermesActivityRowState.running)
        .firstOrNull;
    final elapsed = run.elapsed(startedAt: running ? startedAt?.toUtc() : null);
    final status = switch (state) {
      HermesDesktopTurnState.running => 'Working',
      HermesDesktopTurnState.reconnecting => 'Reconnecting',
      HermesDesktopTurnState.synchronizing => 'Recovering the run',
      _ when run.failed => 'Run failed',
      _ when plan != null && plan.hasActiveWork => 'Plan paused',
      _ when !run.isEmpty => 'Done',
      _ => 'Not running',
    };
    final headline =
        current?.verb ??
        (running
            ? 'Thinking'
            : run.failed
            ? 'Stopped with an error'
            : run.isEmpty
            ? 'Nothing running'
            : 'Finished');
    return HermesPanel(
      // Mechanical linework only while the run is actually working.
      backgroundVariant: running ? HermezBackgroundVariant.mechanical : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              HermezLiveDot(
                state: running
                    ? HermezLiveState.working
                    : run.failed
                    ? HermezLiveState.failed
                    : run.isEmpty
                    ? HermezLiveState.idle
                    : HermezLiveState.done,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  status.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HermezType.technical(
                    running ? palette.accent : palette.muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (elapsed != null)
                Text(
                  formatHermesRunDuration(elapsed),
                  style: HermezType.meta(palette).copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          HermezLiveText(
            headline,
            live: running,
            maxLines: 2,
            style: HermezType.display(palette).copyWith(fontSize: 30),
          ),
          if (current?.object != null) ...[
            const SizedBox(height: 6),
            Text(
              current!.object!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: HermezType.body(palette).copyWith(color: palette.muted),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _Stat(label: 'steps', value: '${run.steps}'),
              _Stat(label: 'tools', value: '${run.tools.length}'),
              if (workers.isNotEmpty)
                _Stat(label: 'delegates', value: '${workers.length}'),
            ],
          ),
          if (plan != null) ...[
            const SizedBox(height: 14),
            HermesPlanPreview(
              plan: plan,
              running: running,
              onOpen: (origin) => showHermesPlanSheet(
                context,
                sessionId: sessionId,
                origin: origin,
              ),
            ),
          ],
          if (workers.isNotEmpty) ...[
            const SizedBox(height: 6),
            HermezMotionSurface(
              weight: HermezMotionWeight.light,
              semanticLabel: '${hermesDelegatesSummary(workers)}. Open',
              originRadius: 14,
              onOpen: (origin) => showHermesDelegatesSheet(
                context,
                sessionId: sessionId,
                origin: origin,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.call_split_rounded, color: palette.ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hermesDelegatesSummary(workers),
                        style: HermezType.body(palette)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: palette.muted),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        HermezRollingCount(
          value: value,
          style: HermezType.section(palette).copyWith(fontSize: 18),
        ),
        const SizedBox(width: 4),
        Text(label, style: HermezType.meta(palette)),
      ],
    );
  }
}
