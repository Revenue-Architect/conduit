import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback/hermez_feedback.dart';
import '../models/hermes_subagent.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../widgets/hermez_action_pills.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_live.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermez_modal_sheet.dart';

HermezLiveState hermesWorkerLiveState(HermesSubagentStatus status) =>
    switch (status) {
      HermesSubagentStatus.queued ||
      HermesSubagentStatus.running => HermezLiveState.working,
      HermesSubagentStatus.completed => HermezLiveState.done,
      HermesSubagentStatus.failed ||
      HermesSubagentStatus.timeout => HermezLiveState.failed,
      HermesSubagentStatus.interrupted ||
      HermesSubagentStatus.unknown => HermezLiveState.idle,
    };

String hermesWorkerStatusLabel(HermesSubagentStatus status) => switch (status) {
  HermesSubagentStatus.queued => 'Queued',
  HermesSubagentStatus.running => 'Working',
  HermesSubagentStatus.completed => 'Done',
  HermesSubagentStatus.failed => 'Failed',
  HermesSubagentStatus.interrupted => 'Stopped',
  HermesSubagentStatus.timeout => 'Timed out',
  HermesSubagentStatus.unknown => 'Unknown',
};

/// "2 delegates working · 1 done" for the run surface.
String hermesDelegatesSummary(List<HermesSubagentState> workers) {
  final live = workers.live;
  final done = workers.finished;
  final problems = workers.problems;
  return [
    if (live > 0) '$live ${live == 1 ? 'delegate' : 'delegates'} working',
    if (live == 0)
      '${workers.length} ${workers.length == 1 ? 'delegate' : 'delegates'}',
    if (done > 0 && live > 0) '$done done',
    if (problems > 0) '$problems failed',
  ].join(' · ');
}

/// Elapsed time from what Hermes reported: its own duration once finished,
/// else time since the worker was first seen.
Duration hermesWorkerElapsed(HermesSubagentState worker, DateTime now) {
  final seconds = worker.durationSeconds;
  if (worker.status.isTerminal && seconds != null) {
    return Duration(milliseconds: (seconds * 1000).round());
  }
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

Future<void> showHermesDelegatesSheet(
  BuildContext context, {
  required String sessionId,
  HermezMorphOrigin? origin,
}) => pushHermezSheetRoute<void>(
  context,
  origin: origin,
  heightFactor: 0.88,
  builder: (_) => _HermesDelegatesSheet(sessionId: sessionId),
);

class _HermesDelegatesSheet extends ConsumerStatefulWidget {
  const _HermesDelegatesSheet({required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<_HermesDelegatesSheet> createState() =>
      _HermesDelegatesSheetState();
}

class _HermesDelegatesSheetState extends ConsumerState<_HermesDelegatesSheet> {
  Timer? _tick;
  String? _open;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final workers =
          ref
              .read(hermesAgenticStateProvider(widget.sessionId))
              .value
              ?.subagents ??
          const [];
      if (mounted && workers.live > 0) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final workers =
        ref
            .watch(hermesAgenticStateProvider(widget.sessionId))
            .value
            ?.subagents ??
        const <HermesSubagentState>[];
    final now = DateTime.now();
    return HermezModalSheet(
      eyebrow: workers.isEmpty
          ? 'DELEGATES'
          : hermesDelegatesSummary(workers).toUpperCase(),
      title: 'Delegates',
      subtitle: Text(
        'Workers Hermes handed parts of this task to.',
        style: HermezType.meta(palette),
      ),
      body: workers.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No delegates in this turn.',
                style: HermezType.body(palette).copyWith(color: palette.muted),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, worker) in workers.reversed.indexed) ...[
                  if (index > 0) const SizedBox(height: 10),
                  _WorkerCard(
                    key: ValueKey('worker-${worker.id}'),
                    sessionId: widget.sessionId,
                    worker: worker,
                    now: now,
                    open: _open == worker.id,
                    onToggle: () => setState(
                      () => _open = _open == worker.id ? null : worker.id,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _WorkerCard extends ConsumerStatefulWidget {
  const _WorkerCard({
    super.key,
    required this.sessionId,
    required this.worker,
    required this.now,
    required this.open,
    required this.onToggle,
  });

  final String sessionId;
  final HermesSubagentState worker;
  final DateTime now;
  final bool open;
  final VoidCallback onToggle;

  @override
  ConsumerState<_WorkerCard> createState() => _WorkerCardState();
}

class _WorkerCardState extends ConsumerState<_WorkerCard> {
  bool _busy = false;
  String? _notice;

  /// Runs a delegate control; true when Hermes accepted it.
  Future<bool> _run(
    Future<bool> Function(HermesDesktopApiService) action, {
    required String ok,
    required String refused,
  }) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService || _busy) return false;
    setState(() {
      _busy = true;
      _notice = null;
    });
    HermezFeedback.play(HermezFeedbackCue.controlSelect);
    var accepted = false;
    try {
      accepted = await action(service);
    } catch (_) {
      accepted = false;
    }
    HermezFeedback.play(
      accepted
          ? HermezFeedbackCue.approvalAccepted
          : HermezFeedbackCue.runFailed,
    );
    if (!mounted) return accepted;
    setState(() {
      _busy = false;
      _notice = accepted ? ok : refused;
    });
    return accepted;
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final worker = widget.worker;
    final live = worker.status.isLive;
    final steerable = live && worker.steerableId != null;
    final elapsed = hermesWorkerElapsed(worker, widget.now);
    final facts = [
      hermesWorkerStatusLabel(worker.status),
      if (worker.model != null) worker.model!,
      if (worker.toolCount != null && worker.toolCount! > 0)
        '${worker.toolCount} ${worker.toolCount == 1 ? 'tool' : 'tools'}',
      if (worker.filesWritten > 0)
        '${worker.filesWritten} ${worker.filesWritten == 1 ? 'file' : 'files'} changed',
    ].join(' · ');
    final now = worker.currentTool != null
        ? (worker.latest ?? worker.currentTool!)
        : worker.latest;
    return HermezSurface(
      kind: HermezSurfaceKind.list,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      semanticLabel:
          '${worker.goal}. ${hermesWorkerStatusLabel(worker.status)}, ${_clock(elapsed)}',
      onTap: widget.onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: HermezLiveDot(
                  state: hermesWorkerLiveState(worker.status),
                  size: 7,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  worker.goal,
                  maxLines: widget.open ? 6 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: HermezType.body(palette)
                      .copyWith(fontWeight: FontWeight.w800, height: 1.3),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _clock(elapsed),
                style: HermezType.meta(palette).copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 23, top: 2),
            child: Text(
              facts,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HermezType.meta(palette),
            ),
          ),
          if (now != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 23, top: 6),
              child: HermezLiveText(
                now,
                live: live,
                style: HermezType.meta(palette).copyWith(color: palette.ink),
              ),
            ),
          HermezReveal(
            visible: widget.open,
            revealKey: ValueKey('worker-open-${worker.id}'),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 23, top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line
                      in worker.lines.reversed.take(6).toList().reversed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            line.error
                                ? Icons.error_outline_rounded
                                : line.tool
                                ? Icons.subdirectory_arrow_right_rounded
                                : Icons.notes_rounded,
                            size: 14,
                            color: line.error ? palette.accent : palette.muted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              line.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: HermezType.meta(palette),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (worker.summary != null && worker.status.isTerminal) ...[
                    const SizedBox(height: 8),
                    Text(
                      worker.summary!,
                      style: HermezType.body(palette).copyWith(fontSize: 13.5),
                    ),
                  ],
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
                              widget.sessionId,
                              worker.steerableId!,
                              text,
                            ),
                            ok: 'Direction queued. It reaches the delegate at its next step.',
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
                              : () => unawaited(
                                  _run(
                                    (service) => service.stopSubagent(
                                      widget.sessionId,
                                      worker.steerableId!,
                                    ),
                                    ok: 'Stop requested.',
                                    refused:
                                        'This delegate is no longer running.',
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_notice!, style: HermezType.meta(palette)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
