import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hermes_job.dart';
import '../models/hermes_session.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../utils/hermes_schedule_format.dart';
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_relative_time.dart';
import '../widgets/hermez_sheet_parts.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermez_modal_sheet.dart';
import '../feedback/hermez_feedback.dart';

/// Returns a real cron-run session when the user selects one. The caller opens
/// it after the sheet closes, avoiding navigation beneath an active modal.
///
/// With [origin] the sheet grows out of the row or card that was tapped.
Future<HermesSessionSummary?> showHermesScheduledAgentSheet(
  BuildContext context, {
  required HermesJob job,
  required String profile,
  HermezMorphOrigin? origin,
}) => pushHermezSheetRoute<HermesSessionSummary>(
  context,
  origin: origin,
  builder: (_) => _ScheduledAgentSheet(job: job, profile: profile),
);

class _ScheduledAgentSheet extends ConsumerStatefulWidget {
  const _ScheduledAgentSheet({required this.job, required this.profile});
  final HermesJob job;
  final String profile;

  @override
  ConsumerState<_ScheduledAgentSheet> createState() =>
      _ScheduledAgentSheetState();
}

enum _SheetAction { run, toggle }

class _ScheduledAgentSheetState extends ConsumerState<_ScheduledAgentSheet> {
  late HermesJob _job = widget.job;
  late Future<List<HermesSessionSummary>> _runs = _loadRuns();
  _SheetAction? _busy;
  String? _error;

  HermesDesktopApiService? get _service {
    final value = ref.read(hermesApiServiceProvider);
    return value is HermesDesktopApiService ? value : null;
  }

  Future<List<HermesSessionSummary>> _loadRuns() async {
    final service = _service;
    if (service == null) return const [];
    final rows = await service.listJobRunsForProfile(widget.profile, _job.id);
    return rows
        .map(HermesSessionSummary.fromJson)
        .whereType<HermesSessionSummary>()
        .toList(growable: false);
  }

  Future<void> _mutate(
    _SheetAction action,
    Future<void> Function(HermesDesktopApiService) run,
  ) async {
    if (_busy != null) return;
    final service = _service;
    if (service == null) return;
    setState(() {
      _busy = action;
      _error = null;
    });
    // Sensory cues are presentation only: sent, then Hermes' answer.
    HermezFeedback.play(HermezFeedbackCue.controlSelect);
    var done = false;
    try {
      await run(service);
      done = true;
      HermezFeedback.play(HermezFeedbackCue.approvalAccepted);
      final jobs = await service.listJobsForProfile(widget.profile);
      final fresh = jobs
          .map(HermesJob.fromJson)
          .whereType<HermesJob>()
          .where((job) => job.id == _job.id);
      if (mounted) {
        setState(() {
          if (fresh.isNotEmpty) _job = fresh.first;
          _runs = _loadRuns();
        });
        ref.invalidate(hermesJobsProvider);
      }
    } catch (_) {
      if (!done) HermezFeedback.play(HermezFeedbackCue.runFailed);
      if (mounted) {
        setState(
          () => _error = 'Hermes could not complete that action. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _time(BuildContext context, DateTime value) =>
      MaterialLocalizations.of(context)
          .formatTimeOfDay(TimeOfDay.fromDateTime(value.toLocal()));

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final job = _job;
    final next = job.nextRun?.toLocal();
    final weekdays = hermezCronWeekdays(job.schedule);
    final scheduleText = describeHermesCronSchedule(job.schedule);
    return HermezModalSheet(
      title: job.displayName,
      titleMorphId: hermezMorphPart(
        hermezJobMorphId(widget.profile, job.id),
        'title',
      ),
      leading: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: palette.canvas,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border.withValues(alpha: 0.7)),
        ),
        alignment: Alignment.center,
        child: HermezBotMark(
          identity: hermezIdentityForName(widget.profile),
          size: 52,
          label: widget.profile,
        ),
      ),
      subtitle: Text.rich(
        TextSpan(
          style: HermezType.meta(palette).copyWith(fontSize: 13),
          children: [
            const TextSpan(text: 'Powered by '),
            TextSpan(
              text: widget.profile,
              style: TextStyle(color: palette.ink, fontWeight: FontWeight.w800),
            ),
            TextSpan(
              text: '  ●',
              style: TextStyle(color: palette.accent, fontSize: 10),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            job.prompt,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: HermezType.body(palette)
                .copyWith(color: palette.muted, fontSize: 15),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final status = HermezStatTile(
                label: 'Status',
                icon: Icons.event_available_outlined,
                value: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: job.enabled
                            ? const Color(0xFF2FB36B)
                            : palette.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: Text(job.enabled ? 'Scheduled' : 'Paused')),
                  ],
                ),
              );
              final nextRun = HermezStatTile(
                label: 'Next run',
                icon: Icons.schedule_rounded,
                value: Text(
                  next == null ? 'Not scheduled' : hermezRelativeLabel(next),
                ),
              );
              if (constraints.maxWidth < 360 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                return Column(
                  children: [status, const SizedBox(height: 9), nextRun],
                );
              }
              return Row(
                children: [
                  Expanded(child: status),
                  const SizedBox(width: 9),
                  Expanded(child: nextRun),
                ],
              );
            },
          ),
          const SizedBox(height: 9),
          HermezSurface(
            kind: HermezSurfaceKind.utility,
            motif: weekdays == null ? HermezMotif.none : HermezMotif.slash,
            border: Border.all(color: palette.border.withValues(alpha: 0.75)),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Wrap(
              spacing: 16,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 120),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 22,
                        color: palette.ink,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SCHEDULE',
                              style: HermezType.technical(palette.muted)
                                  .copyWith(fontSize: 9.5, letterSpacing: 1.8),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              scheduleText,
                              style: HermezType.body(palette)
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (hermesScheduleNeedsRawDisplay(job.schedule))
                              Text(
                                job.schedule,
                                style: HermezType.meta(palette)
                                    .copyWith(fontFamily: 'monospace'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (weekdays != null) HermezWeekdayBars(days: weekdays),
              ],
            ),
          ),
          const SizedBox(height: 9),
          HermezSurface(
            kind: HermezSurfaceKind.utility,
            border: Border.all(color: palette.border.withValues(alpha: 0.75)),
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    job.enabled
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: palette.accent,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.enabled ? 'Agent is enabled' : 'Agent is paused',
                        style: HermezType.section(palette),
                      ),
                      Text(
                        job.enabled
                            ? 'Will run automatically on schedule.'
                            : 'Runs only when you start it.',
                        style: HermezType.meta(palette),
                      ),
                    ],
                  ),
                ),
                _busy == _SheetAction.toggle
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Switch(
                        value: job.enabled,
                        activeTrackColor: palette.accent,
                        onChanged: _busy != null
                            ? null
                            : (_) => _mutate(
                                _SheetAction.toggle,
                                (service) => job.enabled
                                    ? service.pauseJobForProfile(
                                        widget.profile,
                                        job.id,
                                      )
                                    : service.resumeJobForProfile(
                                        widget.profile,
                                        job.id,
                                      ),
                              ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const HermezSectionLabel('Run history', icon: Icons.history_rounded),
          const SizedBox(height: 10),
          FutureBuilder<List<HermesSessionSummary>>(
            future: _runs,
            builder: (context, snapshot) {
              final Widget content;
              if (!snapshot.hasData && !snapshot.hasError) {
                content = const Padding(
                  key: ValueKey('runs-loading'),
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                );
              } else if (snapshot.hasError) {
                content = Text(
                  'Could not load run history.',
                  key: const ValueKey('runs-error'),
                  style: HermezType.meta(palette),
                );
              } else if (snapshot.data!.isEmpty) {
                content = Text(
                  'No runs yet.',
                  key: const ValueKey('runs-empty'),
                  style: HermezType.meta(palette),
                );
              } else {
                final runs = snapshot.data!.take(20).toList();
                content = Column(
                  key: const ValueKey('runs-data'),
                  children: [
                    for (var index = 0; index < runs.length; index++)
                      _RunRow(
                        run: runs[index],
                        first: index == 0,
                        last: index == runs.length - 1,
                        time: runs[index].updatedAt == null
                            ? 'Run'
                            : hermezRelativeLabel(runs[index].updatedAt!),
                        onTap: () => Navigator.pop(context, runs[index]),
                      ),
                  ],
                );
              }
              return HermezPresence(
                presenceKey: content.key!,
                weight: HermezMotionWeight.medium,
                child: content,
              );
            },
          ),
          HermezReveal(
            visible: _error != null,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error ?? '',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ],
      ),
      footer: FutureBuilder<List<HermesSessionSummary>>(
        future: _runs,
        builder: (context, snapshot) {
          final latest = snapshot.data?.isNotEmpty == true
              ? snapshot.data!.first
              : null;
          final run = HermezActionTile(
            primary: true,
            icon: Icons.play_arrow_rounded,
            title: _busy == _SheetAction.run ? 'Starting…' : 'Run now',
            subtitle: 'Start a manual run',
            busy: _busy == _SheetAction.run,
            onTap: _busy != null
                ? null
                : () => _mutate(
                    _SheetAction.run,
                    (service) =>
                        service.runJobForProfile(widget.profile, job.id),
                  ),
          );
          final open = HermezActionTile(
            icon: Icons.description_outlined,
            title: 'Open latest output',
            subtitle: latest?.updatedAt == null
                ? 'Most recent run'
                : 'From ${_time(context, latest!.updatedAt!)}',
            onTap: latest == null ? null : () => Navigator.pop(context, latest),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              run,
              HermezReveal(
                visible: latest != null,
                weight: HermezMotionWeight.medium,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: open,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({
    required this.run,
    required this.first,
    required this.last,
    required this.time,
    required this.onTap,
  });

  final HermesSessionSummary run;
  final bool first;
  final bool last;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezMotionSurface(
      weight: HermezMotionWeight.light,
      semanticLabel: '${run.title}, $time',
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 22,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: first ? 18 : 0,
                    bottom: last ? null : 0,
                    height: last ? 18 : null,
                    child: Container(width: 2, color: palette.border),
                  ),
                  Positioned(
                    top: 13,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: first ? palette.accent : palette.ink,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.surface, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: last
                      ? null
                      : Border(
                          bottom: BorderSide(
                            color: palette.border.withValues(alpha: 0.6),
                          ),
                        ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(time, style: HermezType.meta(palette)),
                          const SizedBox(height: 2),
                          Text(
                            run.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HermezType.body(palette)
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (run.preview?.trim().isNotEmpty == true)
                            Text(
                              run.preview!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HermezType.meta(palette),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: palette.muted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
