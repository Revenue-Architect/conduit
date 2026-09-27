import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hermes_job.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../utils/hermes_schedule_format.dart';
import '../views/hermes_page_chrome.dart';
import '../widgets/hermez_chat_palette.dart';
import 'hermez_modal_sheet.dart';

/// Returns a real cron-run session when the user selects one. The caller opens
/// it after the sheet closes, avoiding navigation beneath an active modal.
Future<HermesSessionSummary?> showHermesScheduledAgentSheet(
  BuildContext context, {
  required HermesJob job,
  required String profile,
}) => showModalBottomSheet<HermesSessionSummary>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
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

class _ScheduledAgentSheetState extends ConsumerState<_ScheduledAgentSheet> {
  late HermesJob _job = widget.job;
  late Future<List<HermesSessionSummary>> _runs = _loadRuns();
  bool _busy = false;
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
    Future<void> Function(HermesDesktopApiService) action,
  ) async {
    if (_busy) return;
    final service = _service;
    if (service == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(service);
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
      if (mounted)
        setState(
          () => _error = 'Hermes could not complete that action. Retry.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final job = _job;
    final next = job.nextRun?.toLocal();
    return HermezModalSheet(
      title: job.displayName,
      eyebrow: 'Scheduled agent · ${widget.profile}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(job.prompt, maxLines: 5, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: HermesPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'STATUS',
                        style: TextStyle(fontSize: 10, letterSpacing: 1.4),
                      ),
                      Text(
                        job.enabled ? '●  Scheduled' : '●  Paused',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HermesPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NEXT RUN',
                        style: TextStyle(fontSize: 10, letterSpacing: 1.4),
                      ),
                      Text(
                        next == null
                            ? 'Not scheduled'
                            : MaterialLocalizations.of(
                                context,
                              ).formatTimeOfDay(TimeOfDay.fromDateTime(next)),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          HermesPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SCHEDULE',
                  style: TextStyle(fontSize: 10, letterSpacing: 1.4),
                ),
                Text(
                  describeHermesCronSchedule(job.schedule),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const HermesSectionTitle('Run history'),
          const SizedBox(height: 7),
          FutureBuilder<List<HermesSessionSummary>>(
            future: _runs,
            builder: (context, snapshot) {
              if (!snapshot.hasData && !snapshot.hasError) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError)
                return const Text('Could not load run history.');
              final runs = snapshot.data!;
              if (runs.isEmpty)
                return const HermesPanel(child: Text('No runs yet.'));
              return HermesPanel(
                child: Column(
                  children: [
                    for (final run in runs.take(20))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.history_rounded,
                          color: palette.accent,
                        ),
                        title: Text(run.title, maxLines: 1),
                        subtitle: Text(
                          run.updatedAt?.toLocal().toString() ?? 'Run',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(context, run),
                      ),
                  ],
                ),
              );
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _mutate(
                      (service) =>
                          service.runJobForProfile(widget.profile, job.id),
                    ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Run now'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _mutate(
                      (service) => job.enabled
                          ? service.pauseJobForProfile(widget.profile, job.id)
                          : service.resumeJobForProfile(widget.profile, job.id),
                    ),
              child: Text(job.enabled ? 'Pause' : 'Resume'),
            ),
          ),
        ],
      ),
    );
  }
}
