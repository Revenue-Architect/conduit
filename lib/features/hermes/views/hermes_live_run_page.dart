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
import '../services/hermes_run_history.dart';
import '../services/hermes_media_parser.dart';
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
import '../widgets/hermes_plan_view.dart';
import '../widgets/hermez_live.dart';
import '../widgets/hermez_technical_background.dart';
import '../widgets/hermez_surfaces.dart';
import '../motion/hermez_motion_surface.dart';
import '../motion/hermez_motion_tokens.dart';
import '../../../core/models/chat_message.dart';
import '../../chat/widgets/streaming_status_widget.dart';
import '../services/hermes_message_mapper.dart';
import '../services/hermes_steel_viewer.dart';
import '../providers/hermes_live_run_providers.dart';
import '../widgets/hermes_steel_live_view.dart';
import '../widgets/hermes_unified_activity_timeline.dart';
import '../../chat/providers/chat_providers.dart' show chatMessagesProvider;

HermesSessionSummary? matchingOriginatingHermesSession(
  List<HermesSessionSummary> sessions,
  String sessionId,
  String? profile,
) {
  for (final candidate in sessions) {
    if (candidate.id == sessionId &&
        (profile == null || candidate.profile == profile)) {
      return candidate;
    }
  }
  return null;
}

class HermesLiveRunPage extends ConsumerStatefulWidget {
  const HermesLiveRunPage({
    super.key,
    required this.sessionId,
    this.openChat = false,
    this.profile,
    this.embedded = false,
    this.answerMessages,
    this.currentAnswer = false,
  });
  final String sessionId;

  /// Opened from a "finished" notification: go straight on to the
  /// conversation, showing the run's status while its transcript loads.
  final bool openChat;

  /// Profile supplied by a scoped originating-session link; never changes credentials.
  final String? profile;
  final bool embedded;
  final List<ChatMessage>? answerMessages;
  final bool currentAnswer;

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
  Future<List<Map<String, dynamic>>>? _historyFuture;

  @override
  void didUpdateWidget(covariant HermesLiveRunPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.profile != widget.profile) {
      _chatOpened = false;
      _openChatFailed = false;
      _pendingService = null;
      _historyFuture = null;
      _sawRunning = false;
      _completionPresented = false;
      _startedAt = null;
    }
  }

  Future<void> _presentCompletion(
    HermesDesktopApiService service,
    HermesSessionSummary session,
  ) async {
    try {
      final messages = await service.readRunDetailsMessages(widget.sessionId);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not stop this run.')),
        );
      }
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
      row = matchingOriginatingHermesSession(
        sessions,
        widget.sessionId,
        widget.profile,
      );
    } catch (_) {}
    for (var i = 0; i < 40 && mounted; i++) {
      final service = ref.read(hermesApiServiceProvider);
      if (service is HermesDesktopApiService) {
        if (!mounted) return;
        HermezRouteExits.leaveForAnotherDestination();
        await openHermesSession(
          context,
          ref,
          row ??
              HermesSessionSummary(
                id: widget.sessionId,
                title: 'Hermes run',
                profile:
                    widget.profile ?? service.boundProfileFor(widget.sessionId),
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
      _historyFuture = service.readRunDetailsMessages(widget.sessionId);
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
      // A new chat has no server title yet; never headline a placeholder.
      title: current.title == 'Untitled session'
          ? 'Run details'
          : current.title,
      subtitle: 'CONVERSATION ACTIVITY · ${current.profile ?? 'Hermes'}',
      leading: widget.embedded
          ? IconButton(
              tooltip: 'Close run details',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            )
          : null,
      child: service is! HermesDesktopApiService
          ? const Center(child: Text('Live run is unavailable.'))
          : StreamBuilder<HermesDesktopTurnState>(
              stream: service.turnStatesFor(widget.sessionId),
              initialData: service.turnStateFor(widget.sessionId),
              builder: (context, turn) {
                final state = turn.data ?? HermesDesktopTurnState.idle;
                final scoped = widget.answerMessages != null;
                final localMessages = scoped
                    ? ref.watch(chatMessagesProvider)
                    : const <ChatMessage>[];
                final liveAnswer = scoped && widget.currentAnswer
                    ? hermesCurrentAnswerMessages(
                        localMessages,
                        widget.answerMessages!,
                      )
                    : const <ChatMessage>[];
                final activeAnswer =
                    !scoped ||
                    (widget.currentAnswer &&
                        (localMessages.isEmpty || liveAnswer.isNotEmpty));
                final answerMessages = liveAnswer.isNotEmpty
                    ? liveAnswer
                    : widget.answerMessages;
                final running =
                    activeAnswer && state == HermesDesktopTurnState.running;
                if (running) {
                  if (!_sawRunning) {
                    _startedAt = DateTime.now();
                    _completionPresented = false;
                  }
                  _sawRunning = true;
                } else if (!activeAnswer) {
                  _sawRunning = false;
                } else if (_sawRunning &&
                    state == HermesDesktopTurnState.idle &&
                    !_completionPresented) {
                  _completionPresented = true;
                  _sawRunning = false;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(
                        () => _historyFuture = service.readRunDetailsMessages(
                          widget.sessionId,
                        ),
                      );
                      _presentCompletion(service, current);
                    }
                  });
                }
                return FutureBuilder<List<Map<String, dynamic>>>(
                  key: ValueKey('history-${widget.sessionId}'),
                  future: _historyFuture,
                  builder: (context, history) {
                    final messages =
                        history.data ?? const <Map<String, dynamic>>[];
                    final selected = scoped
                        ? hermesAnswerTranscript(messages, answerMessages!)
                        : messages;
                    final statuses = <ChatStatusUpdate>[];
                    // The stored mapper restores arguments/results into the
                    // same status contracts the old Explored sheet rendered.
                    for (final message in hermesMessagesToChatMessages(
                      selected,
                      sessionId: widget.sessionId,
                    )) {
                      statuses.addAll(message.statusHistory);
                    }
                    final localStatuses = [
                      for (final message
                          in answerMessages ?? const <ChatMessage>[])
                        ...message.statusHistory,
                    ];
                    if (activeAnswer && localStatuses.isNotEmpty) {
                      // A sheet left open during a turn receives new arguments
                      // and results from the existing chat state, not a snapshot.
                      statuses
                        ..clear()
                        ..addAll(localStatuses);
                    } else if (statuses.isEmpty) {
                      for (final message
                          in answerMessages ?? const <ChatMessage>[]) {
                        statuses.addAll(message.statusHistory);
                      }
                    }
                    final stored = hermesTranscriptActivity(
                      widget.sessionId,
                      selected,
                      sensitiveValues: service.config.sensitiveValues,
                    );
                    return StreamBuilder<List<HermesLiveActivityEvent>>(
                      key: ValueKey('activity-${widget.sessionId}'),
                      stream: service.activityFor(widget.sessionId),
                      initialData: service.activitySnapshotFor(
                        widget.sessionId,
                      ),
                      builder: (context, activity) {
                        final live = activeAnswer
                            ? HermesRunSummary.latest(
                                activity.data ?? const [],
                                running: running,
                              ).events
                            : const <HermesLiveActivityEvent>[];
                        final events = mergeHermesRunHistory(
                          stored,
                          scoped ? live : activity.data ?? const [],
                        );
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 34),
                          children: [
                            _LiveHero(
                              sessionId: widget.sessionId,
                              state: activeAnswer
                                  ? state
                                  : HermesDesktopTurnState.idle,
                              events: events,
                              startedAt: _startedAt,
                              showAgentic: activeAnswer,
                              model: hermesTranscriptModel(
                                selected,
                                sensitiveValues: service.config.sensitiveValues,
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (activeAnswer)
                              _PendingRunRequests(sessionId: widget.sessionId),
                            if (activeAnswer &&
                                running &&
                                parseSteelViewerUrl(
                                      ref.watch(hermesSteelViewerUrlProvider),
                                    ) !=
                                    null &&
                                HermesRunSummary.conversation(
                                  events,
                                  running: running,
                                ).tools.any(
                                  (tool) =>
                                      HermesActivityPresenter.family(
                                        tool.name,
                                      ) ==
                                      HermesActivityFamily.browser,
                                ))
                              HermesRunBrowserSection(
                                viewerUrl: ref.watch(
                                  hermesSteelViewerUrlProvider,
                                ),
                                sessionId: widget.sessionId,
                              ),
                            if (history.connectionState ==
                                ConnectionState.waiting)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Text(
                                  'Loading saved conversation activity…',
                                ),
                              ),
                            if (history.hasError)
                              HermesPanel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Saved activity is unavailable. Live activity is still shown.',
                                    ),
                                    TextButton(
                                      onPressed: () => setState(() {
                                        _historyFuture = service
                                            .readRunDetailsMessages(
                                              widget.sessionId,
                                            );
                                      }),
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            if (HermesActivityPresenter.rows(
                                  events,
                                  running: running,
                                ).isNotEmpty ||
                                statuses.isNotEmpty) ...[
                              const HermesSectionTitle('Activity'),
                              const SizedBox(height: 8),
                              HermesPanel(
                                child: Builder(
                                  builder: (context) {
                                    final rows = HermesActivityPresenter.rows(
                                      events,
                                      running: running,
                                    );
                                    if (rows.isEmpty && statuses.isEmpty) {
                                      return const Text(
                                        'No tool steps were recorded. Conversation responses are below.',
                                      );
                                    }
                                    return HermesUnifiedActivityTimeline(
                                      rows: rows,
                                      statuses: filterVisibleStatusUpdates(
                                        hermesSafeRunStatuses(
                                          statuses,
                                          service.config.sensitiveValues,
                                        ),
                                        isStreaming: running,
                                      ),
                                      running: running,
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
                            ],
                            for (final message
                                in answerMessages ?? const <ChatMessage>[])
                              if (message.error != null)
                                HermesPanel(
                                  child: Text(
                                    HermesActivityPresenter.clean(
                                          message.error?.content,
                                          sensitiveValues:
                                              service.config.sensitiveValues,
                                          max: 2048,
                                        ) ??
                                        'This run reported an error.',
                                  ),
                                ),
                            // Opened from an answer, the conversation is right
                            // behind this sheet; don't repeat it here.
                            if (messages.isNotEmpty && answerMessages == null)
                              _SavedConversationResults(
                                key: ValueKey('results-${widget.sessionId}'),
                                messages: messages,
                                sensitiveValues: service.config.sensitiveValues,
                              ),
                            HermesRunActions(
                              showSteer: running,
                              onSteer: running
                                  ? (text) => _steer(service, text)
                                  : null,
                              leading: [
                                if (!widget.embedded)
                                  HermezRunPill(
                                    label: 'View chat',
                                    icon: Icons.chat_bubble_outline_rounded,
                                    onTap: () => openHermesSession(
                                      context,
                                      ref,
                                      current,
                                    ),
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
                                            () => _confirmingStop =
                                                !_confirmingStop,
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
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _SavedConversationResults extends StatefulWidget {
  const _SavedConversationResults({
    super.key,
    required this.messages,
    required this.sensitiveValues,
  });
  final List<Map<String, dynamic>> messages;
  final Iterable<String> sensitiveValues;
  @override
  State<_SavedConversationResults> createState() =>
      _SavedConversationResultsState();
}

class _SavedConversationResultsState extends State<_SavedConversationResults> {
  bool _all = false;
  @override
  Widget build(BuildContext context) {
    final messages = widget.messages
        .where(
          (message) =>
              const {'user', 'assistant'}.contains(message['role']) &&
              message['content'] is String &&
              (message['content'] as String).trim().isNotEmpty,
        )
        .toList();
    final visible = _all
        ? messages
        : messages.skip((messages.length - 8).clamp(0, messages.length));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HermesSectionTitle('Conversation'),
        if (!_all && messages.length > 8)
          TextButton(
            onPressed: () => setState(() => _all = true),
            child: Text('Show ${messages.length - 8} earlier messages'),
          ),
        for (final message in visible)
          ExpansionTile(
            title: Text(message['role'] == 'user' ? 'You' : 'Hermes'),
            subtitle: Text(
              HermesActivityPresenter.clean(
                    message['content'] as String,
                    sensitiveValues: widget.sensitiveValues,
                  ) ??
                  'Saved response',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  HermesActivityPresenter.clean(
                        parseHermesMedia(message['content'] as String)
                            .cleanText,
                        sensitiveValues: widget.sensitiveValues,
                        max: 200000,
                      ) ??
                      '',
                ),
              ),
            ],
          ),
        const SizedBox(height: 14),
      ],
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
    this.showAgentic = true,
    this.model,
  });

  final String sessionId;
  final HermesDesktopTurnState state;
  final List<HermesLiveActivityEvent> events;
  final DateTime? startedAt;
  final bool showAgentic;
  final String? model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final running = state == HermesDesktopTurnState.running;
    final run = HermesRunSummary.conversation(events, running: running);
    final rows = HermesActivityPresenter.rows(
      run.isEmpty ? events : run.events,
      running: running,
    );
    final agentic = showAgentic
        ? ref.watch(hermesAgenticStateProvider(sessionId)).value ??
              HermesAgenticSnapshot.empty
        : HermesAgenticSnapshot.empty;
    final plan = agentic.hasPlan ? agentic.todo : null;
    final workers = agentic.subagents;
    final current = rows.reversed
        .where((row) => row.state == HermesActivityRowState.running)
        .firstOrNull;
    // Multiple turns include time between requests, not execution duration.
    final elapsed = events.where((event) => event.isTerminal).length > 1
        ? null
        : run.elapsed(startedAt: running ? startedAt?.toUtc() : null);
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
              if (elapsed != null && elapsed.inSeconds > 0)
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
          if (agentic.info?.model != null || model != null)
            Text(
              'Model · ${agentic.info?.model ?? model}',
              style: HermezType.meta(palette),
            ),
          HermezLiveText(
            headline,
            live: running,
            maxLines: 2,
            style: HermezType.display(palette)
                .copyWith(fontSize: running ? 30 : 22),
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
          // Only real counts: "0 steps · 0 tools" says nothing.
          if (run.steps > 0 || run.tools.isNotEmpty || workers.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                if (run.steps > 0) _Stat(label: 'steps', value: '${run.steps}'),
                if (run.tools.isNotEmpty)
                  _Stat(label: 'tools', value: '${run.tools.length}'),
                if (workers.isNotEmpty)
                  _Stat(label: 'delegates', value: '${workers.length}'),
              ],
            ),
          ],
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

/// The same persisted requests as transcript/composer cards. Dismissal never
/// resolves them; store changes update the orb and sheet together.
class _PendingRunRequests extends ConsumerStatefulWidget {
  const _PendingRunRequests({required this.sessionId});
  final String sessionId;
  @override
  ConsumerState<_PendingRunRequests> createState() =>
      _PendingRunRequestsState();
}

class _PendingRunRequestsState extends ConsumerState<_PendingRunRequests>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(hermesPendingSessionDecisionsProvider(widget.sessionId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(
      hermesPendingSessionDecisionsProvider(widget.sessionId),
    );
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    if (pending.hasError) {
      return TextButton(
        onPressed: () => ref.invalidate(
          hermesPendingSessionDecisionsProvider(widget.sessionId),
        ),
        child: const Text('Could not load requests · Retry'),
      );
    }
    final decisions = pending.value ?? const [];
    if (decisions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: HermesPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Input needed'),
            for (final decision in decisions)
              Builder(
                builder: (rowContext) => RepaintBoundary(
                  child: ListTile(
                    title: Text(
                      decision.prompt ?? 'Hermes needs your response',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final resolved = await showHermesAttentionResolutionSheet(
                        context,
                        decision,
                        origin: HermezMorphOrigin.of(
                          rowContext,
                          radius: 18,
                          color: palette.surface,
                        ),
                      );
                      if (resolved == true && mounted) {
                        ref.invalidate(
                          hermesPendingSessionDecisionsProvider(
                            widget.sessionId,
                          ),
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
