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
import '../widgets/hermez_chat_palette.dart';
import 'hermes_page_chrome.dart';

class HermesLiveRunPage extends ConsumerStatefulWidget {
  const HermesLiveRunPage({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<HermesLiveRunPage> createState() => _HermesLiveRunPageState();
}

class _HermesLiveRunPageState extends ConsumerState<HermesLiveRunPage> {
  bool _busy = false;
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

  Future<void> _steer(HermesDesktopApiService service) async {
    final text = await promptHermesSteer(context);
    if (!mounted || text == null || text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final accepted = await service.steer(widget.sessionId, text);
      if (mounted && !accepted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This run cannot be steered right now.'),
          ),
        );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not steer this run.')),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop(HermesDesktopApiService service) async {
    final confirm = await confirmHermesStop(context);
    if (!confirm || !mounted) return;
    setState(() => _busy = true);
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
    final current =
        session ??
        HermesSessionSummary(id: widget.sessionId, title: 'Hermes run');
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
                      HermesPanel(
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                running
                                    ? '●  RUNNING'
                                    : state ==
                                          HermesDesktopTurnState.reconnecting
                                    ? '●  RECONNECTING'
                                    : '●  NOT RUNNING',
                                style: TextStyle(
                                  color: running
                                      ? palette.accent
                                      : palette.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: 215,
                              height: 215,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: palette.ink,
                                      border: Border.all(
                                        color: palette.border,
                                        width: 9,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 178,
                                    height: 178,
                                    child: CircularProgressIndicator(
                                      value: running ? null : 0,
                                      strokeWidth: 7,
                                      color: palette.accent,
                                      backgroundColor: palette.muted.withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        running ? 'EXECUTING' : 'STATUS',
                                        style: TextStyle(
                                          color: palette.surface,
                                          fontSize: 11,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      SizedBox(
                                        width: 145,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            running
                                                ? 'LIVE'
                                                : state.name.toUpperCase(),
                                            style: TextStyle(
                                              color: palette.surface,
                                              fontSize: 28,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              running ? 'Hermes is working in the background.' : 'Open the conversation for the latest result.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const HermesSectionTitle('Activity'),
                      const SizedBox(height: 8),
                      HermesPanel(
                        child: (activity.data ?? const []).isEmpty
                            ? const Text(
                                'Live events will appear here while Hermes works.',
                              )
                            : Column(
                                children: [
                                  for (final event
                                      in (activity.data ?? const []).reversed
                                          .take(30))
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      leading: Icon(
                                        _icon(event.kind),
                                        color:
                                            event.kind ==
                                                HermesLiveActivityKind.failed
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .error
                                            : palette.accent,
                                      ),
                                      title: Text(event.title),
                                      subtitle: Text(
                                        '${event.timestamp.toLocal().hour.toString().padLeft(2, '0')}:${event.timestamp.toLocal().minute.toString().padLeft(2, '0')}',
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                openHermesSession(context, ref, current),
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: const Text('View chat'),
                          ),
                          if (running) ...[
                            OutlinedButton(
                              onPressed: _busy ? null : () => _steer(service),
                              child: const Text('Steer'),
                            ),
                            OutlinedButton(
                              onPressed: _busy ? null : () => _stop(service),
                              child: const Text('Stop'),
                            ),
                          ],
                        ],
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
                                    ListTile(
                                      title: Text(
                                        decision.prompt ?? 'Hermes needs input',
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_right_rounded,
                                      ),
                                      onTap: () async {
                                        final resolved =
                                            await showHermesAttentionResolutionSheet(
                                              context,
                                              decision,
                                            );
                                        if (resolved == true && mounted) {
                                          setState(
                                            () => _pendingFuture = _loadPending(
                                              service,
                                            ),
                                          );
                                        }
                                      },
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

  static IconData _icon(HermesLiveActivityKind kind) => switch (kind) {
    HermesLiveActivityKind.toolCompleted ||
    HermesLiveActivityKind.subagentCompleted ||
    HermesLiveActivityKind.completed => Icons.check_circle_outline_rounded,
    HermesLiveActivityKind.failed => Icons.error_outline_rounded,
    HermesLiveActivityKind.waitingForInput => Icons.pan_tool_alt_outlined,
    HermesLiveActivityKind.review => Icons.rate_review_outlined,
    _ => Icons.radio_button_checked_rounded,
  };
}
