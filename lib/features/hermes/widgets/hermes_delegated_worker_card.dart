import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../shared/widgets/conduit_dialog_route.dart';
import '../feedback/hermez_feedback.dart';
import '../models/hermes_subagent.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import 'hermez_action_pills.dart';
import 'hermez_bot_mark.dart';
import 'hermez_chat_palette.dart';
import 'hermez_live.dart';
import 'hermez_segments.dart';
import 'hermez_surfaces.dart';
import 'hermes_turn_delegation.dart';

HermezLiveState hermesWorkerLiveState(HermesSubagentStatus status) =>
    switch (status) {
      HermesSubagentStatus.queued => HermezLiveState.idle,
      HermesSubagentStatus.running => HermezLiveState.working,
      HermesSubagentStatus.waiting => HermezLiveState.attention,
      HermesSubagentStatus.completed => HermezLiveState.done,
      HermesSubagentStatus.failed ||
      HermesSubagentStatus.timeout => HermezLiveState.failed,
      HermesSubagentStatus.interrupted ||
      HermesSubagentStatus.unknown => HermezLiveState.idle,
    };

String hermesWorkerStatusLabel(HermesSubagentStatus status) => switch (status) {
  HermesSubagentStatus.queued => 'Queued',
  HermesSubagentStatus.running => 'Working',
  HermesSubagentStatus.waiting => 'Needs attention',
  HermesSubagentStatus.completed => 'Complete',
  HermesSubagentStatus.failed => 'Failed',
  HermesSubagentStatus.interrupted => 'Stopped',
  HermesSubagentStatus.timeout => 'Timed out',
  HermesSubagentStatus.unknown => 'Status unavailable',
};

/// "2 delegates working · 1 done" for existing run controls.
String hermesDelegatesSummary(List<HermesSubagentState> workers) {
  final live = workers.live;
  final done = workers
      .where((worker) => worker.status == HermesSubagentStatus.completed)
      .length;
  final problems = workers.problems;
  return [
    if (live > 0) '$live ${live == 1 ? 'delegate' : 'delegates'} working',
    if (live == 0)
      '${workers.length} ${workers.length == 1 ? 'delegate' : 'delegates'}',
    if (done > 0) '$done ${done == 1 ? 'complete' : 'complete'}',
    if (problems > 0) '$problems ${problems == 1 ? 'failed' : 'failed'}',
  ].join(' · ');
}

/// Elapsed time from a reported duration or reported start timestamp.
Duration hermesWorkerElapsed(HermesSubagentState worker, DateTime now) {
  final seconds = worker.durationSeconds;
  if (worker.status.isTerminal && seconds != null) {
    return Duration(milliseconds: (seconds * 1000).round());
  }
  if (!worker.reportedStart && seconds == null) return Duration.zero;
  if (seconds != null) return Duration(milliseconds: (seconds * 1000).round());
  final end = worker.status.isTerminal ? worker.updatedAt : now;
  final value = end.difference(worker.startedAt);
  return value.isNegative ? Duration.zero : value;
}

String _clock(Duration value) {
  final s = value.inSeconds;
  if (s < 60) return '${s}s';
  if (s < 3600) {
    return '${value.inMinutes}m ${(s % 60).toString().padLeft(2, '0')}s';
  }
  return '${value.inHours}h ${(value.inMinutes % 60).toString().padLeft(2, '0')}m';
}

/// A worker card shared by inline delegated work and the Delegates sheet.
class HermesDelegatedWorkerCard extends ConsumerStatefulWidget {
  const HermesDelegatedWorkerCard({
    super.key,
    required this.worker,
    required this.parentSessionId,
    required this.parentLabel,
    required this.expanded,
    required this.onToggle,
    this.onLayoutChanged,
    this.loadConversation,
    this.onOpenSession,
    this.loadArtifact,
    this.compact = true,
    this.conversationRevision = 0,
  });

  final HermesSubagentState worker;
  final String parentSessionId;
  final String parentLabel;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onLayoutChanged;
  final Future<List<ChatMessage>> Function(HermesSubagentState)?
  loadConversation;
  final Future<void> Function(HermesSubagentState, HermezMorphOrigin?)?
  onOpenSession;
  final Future<String> Function(HermesSubagentState, int)? loadArtifact;
  final bool compact;
  final int conversationRevision;

  @override
  ConsumerState<HermesDelegatedWorkerCard> createState() =>
      _HermesDelegatedWorkerCardState();
}

class _HermesDelegatedWorkerCardState
    extends ConsumerState<HermesDelegatedWorkerCard> {
  static const int _activityTab = 0;
  static const int _conversationTab = 1;

  bool _busy = false;
  String? _notice;
  int _selectedTab = _activityTab;
  bool _restoredTab = false;
  bool _conversationLoaded = false;
  bool _conversationUnavailable = false;
  bool _conversationLoading = false;
  List<ChatMessage> _messages = const [];
  bool _allActivity = false;

  @override
  void didUpdateWidget(covariant HermesDelegatedWorkerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.worker.childSessionId != widget.worker.childSessionId ||
        oldWidget.worker.updatedAt != widget.worker.updatedAt ||
        oldWidget.conversationRevision != widget.conversationRevision) {
      _conversationLoaded = false;
      if (_selectedTab == _conversationTab && widget.expanded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_loadConversation());
        });
      }
    }
  }

  String get _storageIdentifier =>
      'hermes-worker-tab:${widget.parentSessionId}:${widget.worker.id}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredTab) return;
    _restoredTab = true;
    final stored = PageStorage.maybeOf(context)
        ?.readState(context, identifier: _storageIdentifier);
    if (stored is int &&
        (stored == _activityTab || stored == _conversationTab)) {
      _selectedTab = stored;
      if (_selectedTab == _conversationTab && widget.expanded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadConversation();
        });
      }
    }
  }

  Future<void> _loadConversation() async {
    if (_conversationLoaded || _conversationLoading) return;
    final loader = widget.loadConversation;
    if (loader == null) {
      setState(() {
        _conversationLoaded = true;
        _conversationUnavailable = true;
      });
      widget.onLayoutChanged?.call();
      return;
    }
    setState(() => _conversationLoading = true);
    widget.onLayoutChanged?.call();
    try {
      // Service output is already redacted. Keep only ordinary user and
      // assistant messages; no system, tool, reasoning, or metadata fields.
      final result = await loader(widget.worker);
      final visible = result
          .where(
            (message) => message.role == 'user' || message.role == 'assistant',
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _messages = visible;
        _conversationLoaded = true;
        _conversationUnavailable = false;
        _conversationLoading = false;
      });
      widget.onLayoutChanged?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _conversationLoaded = true;
        _conversationUnavailable = true;
        _conversationLoading = false;
      });
      widget.onLayoutChanged?.call();
    }
  }

  void _selectTab(int index) {
    if (_selectedTab == index) return;
    setState(() => _selectedTab = index);
    PageStorage.maybeOf(context)
        ?.writeState(context, index, identifier: _storageIdentifier);
    widget.onLayoutChanged?.call();
    if (index == _conversationTab) unawaited(_loadConversation());
  }

  Future<bool> _run(
    Future<bool> Function(HermesDesktopApiService) action, {
    required String accepted,
    required String refused,
  }) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService || _busy) return false;
    setState(() {
      _busy = true;
      _notice = null;
    });
    HermezFeedback.play(HermezFeedbackCue.controlSelect);
    var wasAccepted = false;
    try {
      wasAccepted = await action(service);
    } catch (_) {
      wasAccepted = false;
    }
    HermezFeedback.play(
      wasAccepted
          ? HermezFeedbackCue.approvalAccepted
          : HermezFeedbackCue.runFailed,
    );
    if (!mounted) return wasAccepted;
    setState(() {
      _busy = false;
      _notice = widget.worker.status.isTerminal
          ? 'This delegate has finished.'
          : wasAccepted
          ? accepted
          : refused;
    });
    return wasAccepted;
  }

  Future<void> _confirmStop() async {
    final accepted = await showConduitDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop this delegate?'),
        content: const Text(
          'Hermes will receive a stop request. The delegate may finish before it is handled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Request stop'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final worker = widget.worker;
    final steerableId = worker.steerableId;
    if (!worker.supportsNativeControl ||
        !worker.status.isLive ||
        steerableId == null) {
      setState(() => _notice = 'This delegate is no longer running.');
      return;
    }
    await _run(
      (service) => service.stopSubagent(widget.parentSessionId, steerableId),
      accepted: 'Stop request accepted.',
      refused: 'This delegate is no longer running.',
    );
  }

  Future<void> _openSession(HermezMorphOrigin? origin) async {
    try {
      await widget.onOpenSession?.call(widget.worker, origin);
    } catch (_) {
      if (mounted) setState(() => _notice = 'Child session unavailable.');
    }
  }

  Future<void> _openArtifact(int index) async {
    try {
      final body = await widget.loadArtifact!(widget.worker, index);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        HermezRoute<void>(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Result artifact')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: SelectableText(body),
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _notice = 'Artifact unavailable.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final worker = widget.worker;
    final live = worker.status.isLive;
    final steerable =
        worker.supportsNativeControl && live && worker.steerableId != null;
    final showElapsed = worker.reportedStart || worker.durationSeconds != null;
    final facts = [
      hermesWorkerStatusLabel(worker.status),
      if (worker.model != null) worker.model!,
      if (worker.toolCount != null && worker.toolCount! > 0)
        '${worker.toolCount} ${worker.toolCount == 1 ? 'tool' : 'tools'}',
      if (worker.filesWritten > 0)
        '${worker.filesWritten} ${worker.filesWritten == 1 ? 'file' : 'files'} changed',
      if (showElapsed) _clock(hermesWorkerElapsed(worker, DateTime.now())),
    ].join(' · ');
    final openSession =
        widget.onOpenSession != null &&
        ((worker.childSessionId != null && worker.childProfile != null) ||
            (worker.kind == HermesDelegationKind.kanban &&
                worker.taskId != null &&
                worker.boardSlug != null));
    final borderColor = palette.border.withValues(alpha: 0.9);
    final radius = BorderRadius.circular(14);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: borderColor),
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HermezMotionSurface(
              weight: HermezMotionWeight.light,
              semanticLabel:
                  '${worker.displayName}. ${hermesWorkerStatusLabel(worker.status)}. ${widget.expanded ? 'Collapse' : 'Expand'} worker details.',
              semanticsExpanded: widget.expanded,
              onTap: widget.onToggle,
              originRadius: 14,
              originColor: palette.surface,
              originBorderColor: borderColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      // The name is the profile the worker ran as; a routed
                      // native child is stored under its parent's profile.
                      child: HermezBotMark(
                        botName: worker.displayName,
                        identity: hermezIdentityForName(worker.displayName),
                        size: 23,
                        label: worker.displayName,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  worker.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: HermezType.body(palette)
                                      .copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 7),
                              HermezLiveDot(
                                state: hermesWorkerLiveState(worker.status),
                                size: 6,
                                semanticLabel: hermesWorkerStatusLabel(
                                  worker.status,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  hermesWorkerStatusLabel(worker.status),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: HermezType.meta(palette).copyWith(
                                    color: palette.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            worker.goal,
                            maxLines: widget.expanded ? 4 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: HermezType.meta(palette)
                                .copyWith(color: palette.muted),
                          ),
                          if (facts.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              facts,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: HermezType.meta(palette),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      widget.expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: palette.muted,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
            HermezReveal(
              visible: widget.expanded,
              revealKey: ValueKey('worker-content:${widget.worker.id}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HermezSegments(
                      labels: const ['Activity', 'Conversation'],
                      index: _selectedTab,
                      height: (24 + MediaQuery.textScalerOf(context).scale(14))
                          .clamp(44, 100)
                          .toDouble(),
                      onChanged: _selectTab,
                    ),
                    const SizedBox(height: 10),
                    if (_selectedTab == _activityTab)
                      _activity(palette, worker)
                    else
                      _conversation(palette),
                    if (openSession) ...[
                      const SizedBox(height: 8),
                      HermezMotionSurface(
                        weight: HermezMotionWeight.light,
                        semanticLabel:
                            'Open ${worker.displayName} session. Back returns to ${widget.parentLabel}.',
                        onOpen: _openSession,
                        originRadius: 10,
                        originColor: palette.surface,
                        originBorderColor: palette.border,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 9,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                                color: palette.ink,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  worker.kind == HermesDelegationKind.kanban
                                      ? 'Open task result'
                                      : 'Open ${worker.displayName} session',
                                  style: HermezType.meta(palette).copyWith(
                                    color: palette.ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (widget.loadArtifact != null)
                      for (var i = 0; i < worker.artifacts.length; i++)
                        TextButton.icon(
                          onPressed: () => _openArtifact(i),
                          icon: const Icon(
                            Icons.description_outlined,
                            size: 17,
                          ),
                          label: Text('Result artifact ${i + 1}'),
                        ),
                    if (steerable) ...[
                      const SizedBox(height: 10),
                      HermezActionPills(
                        actions: [
                          HermezPillAction(
                            label: 'Steer',
                            icon: Icons.edit_outlined,
                            hint: 'What should change?',
                            onSubmit: (text) => _run(
                              (service) => service.steerSubagent(
                                widget.parentSessionId,
                                worker.steerableId!,
                                text,
                              ),
                              accepted: 'Direction queued. It reaches the delegate at its next step.',
                              refused:
                                  'The delegate could not take direction now.',
                            ),
                          ),
                          HermezPillAction(
                            label: 'Stop',
                            icon: Icons.stop_circle_outlined,
                            busy: _busy,
                            onTap: _busy
                                ? null
                                : () => unawaited(_confirmStop()),
                          ),
                        ],
                      ),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 8),
                      Text(_notice!, style: HermezType.meta(palette)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activity(HermezChatPalette palette, HermesSubagentState worker) {
    final lines = !_allActivity && worker.lines.length > 6
        ? worker.lines.sublist(worker.lines.length - 6)
        : worker.lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  line.error
                      ? Icons.error_outline_rounded
                      : line.tool
                      ? Icons.subdirectory_arrow_right_rounded
                      : Icons.notes_rounded,
                  size: 15,
                  color: line.error ? palette.accent : palette.muted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    line.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: HermezType.meta(palette)
                        .copyWith(color: palette.ink),
                  ),
                ),
              ],
            ),
          ),
        if (worker.summary case final summary?
            when summary.trim().isNotEmpty) ...[
          if (lines.isNotEmpty) const SizedBox(height: 7),
          Text(
            summary,
            style: HermezType.body(palette).copyWith(fontSize: 13.5),
          ),
        ],
        if (worker.lines.length > 6)
          TextButton(
            onPressed: () {
              widget.onLayoutChanged?.call();
              setState(() => _allActivity = !_allActivity);
            },
            child: Text(
              _allActivity
                  ? 'Show recent activity'
                  : 'Show all ${worker.lines.length} activity entries',
            ),
          ),
        if (lines.isEmpty &&
            (worker.summary == null || worker.summary!.trim().isEmpty))
          Text('No activity reported yet.', style: HermezType.meta(palette)),
      ],
    );
  }

  Widget _conversation(HermezChatPalette palette) {
    if (_conversationLoading) {
      return Text('Loading conversation…', style: HermezType.meta(palette));
    }
    if (_conversationUnavailable) {
      return Text('Transcript unavailable.', style: HermezType.meta(palette));
    }
    if (!_conversationLoaded) {
      // Selection triggers the asynchronous read immediately after this build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.expanded && _selectedTab == _conversationTab) {
          unawaited(_loadConversation());
        }
      });
      return Text('Loading conversation…', style: HermezType.meta(palette));
    }
    if (_messages.isEmpty) {
      return Text(
        'No conversation available.',
        style: HermezType.meta(palette),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final message in _messages.take(widget.compact ? 12 : 1000))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  message.role == 'assistant'
                      ? widget.worker.displayName
                      : '${widget.parentLabel} → ${widget.worker.displayName}',
                  style: HermezType.meta(
                    palette,
                  ).copyWith(color: palette.muted, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  message.content,
                  maxLines: widget.compact ? 8 : null,
                  overflow: TextOverflow.ellipsis,
                  style: HermezType.body(palette).copyWith(fontSize: 13.5),
                ),
              ],
            ),
          ),
        if (!widget.compact)
          for (final message in _messages.where((m) => m.role == 'assistant'))
            HermesTurnDelegation(
              sessionId: widget.worker.childSessionId!,
              message: message,
              parentLabel: widget.worker.displayName,
              turnMessages: _messages
                  .where((m) => m.role == 'assistant')
                  .toList(),
            ),
      ],
    );
  }
}
