import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../models/hermes_job.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_pending_decision_store.dart';
import '../sheets/hermes_attention_resolution_sheet.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_technical_background.dart';
import '../motion/hermez_morph_origin.dart';
import 'hermes_page_chrome.dart';

final _attentionDecisionsProvider =
    FutureProvider.autoDispose<List<HermesPendingDesktopDecision>>((ref) async {
      final service = ref.watch(hermesApiServiceProvider);
      return service is HermesDesktopApiService
          ? service.pendingDecisions()
          : <HermesPendingDesktopDecision>[];
    });

final _failedJobsProvider =
    FutureProvider.autoDispose<List<(String, HermesJob)>>((ref) async {
      final service = ref.watch(hermesApiServiceProvider);
      final bots = await ref.watch(hermesBotsProvider.future);
      if (service is! HermesDesktopApiService) return <(String, HermesJob)>[];
      final profiles = {
        service.config.desktopProfile,
        ...bots.map((bot) => bot.name),
      };
      final failures = <(String, HermesJob)>[];
      for (final profile in profiles) {
        try {
          final rows = await service.listJobsForProfile(profile);
          for (final job
              in rows.map(HermesJob.fromJson).whereType<HermesJob>()) {
            final status = (job.lastStatus ?? '').toLowerCase();
            if (job.lastError != null ||
                job.lastDeliveryError != null ||
                status.contains('fail') ||
                status.contains('error')) {
              failures.add((profile, job));
            }
          }
        } catch (_) {
          // A profile's jobs endpoint can be unavailable independently.
        }
      }
      return failures;
    });

class HermesAttentionPage extends ConsumerWidget {
  const HermesAttentionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final decisions = ref.watch(_attentionDecisionsProvider);
    final failedJobs = ref.watch(_failedJobsProvider);
    final pending =
        decisions.asData?.value ?? const <HermesPendingDesktopDecision>[];
    final failed = failedJobs.asData?.value ?? const <(String, HermesJob)>[];
    final sessionTitles = <String, String>{
      for (final session
          in ref.watch(hermesSessionsProvider).asData?.value ??
              const <HermesSessionSummary>[])
        session.id: session.title,
    };
    return HermesPageChrome(
      title: 'Attention',
      subtitle: 'Stay in control of what needs you.',
      actions: [
        IconButton(
          tooltip: 'Refresh attention',
          onPressed: () {
            ref.invalidate(_attentionDecisionsProvider);
            ref.invalidate(_failedJobsProvider);
          },
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_attentionDecisionsProvider);
          ref.invalidate(_failedJobsProvider);
          await ref.read(_attentionDecisionsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
          children: [
            HermesPanel(
              backgroundVariant: HermezBackgroundVariant.mechanical,
              child: Row(
                children: [
                  CircleAvatar(backgroundColor: palette.accent, radius: 11),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${pending.length + failed.length} items need your review',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Across approvals, questions, and scheduled runs.',
                          style: TextStyle(fontSize: 11, color: palette.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 19),
            if (decisions.isLoading || failedJobs.isLoading)
              const LinearProgressIndicator(minHeight: 2),
            if (decisions.hasError || failedJobs.hasError)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Some attention sources are unavailable. Pull to retry.',
                ),
              ),
            if (pending.isEmpty &&
                failed.isEmpty &&
                !decisions.isLoading &&
                !failedJobs.isLoading)
              const HermesPanel(
                child: Text('Nothing needs your attention right now.'),
              ),
            for (final kind in HermesPendingDesktopDecisionKind.values) ...[
              if (pending.any((item) => item.kind == kind)) ...[
                HermesSectionTitle(_heading(kind)),
                const SizedBox(height: 8),
                for (final item in pending.where(
                  (item) => item.kind == kind,
                )) ...[
                  Builder(
                    builder: (rowContext) => HermesPanel(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_icon(kind), color: palette.accent),
                        // What is asked, by which bot, in which conversation.
                        title: Text(
                          (item.prompt?.trim().isNotEmpty ?? false)
                              ? item.prompt!.trim()
                              : _title(kind),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            if (item.profile?.isNotEmpty ?? false)
                              item.profile!,
                            switch (sessionTitles[item.storedSessionId]) {
                              final String title when title.trim().isNotEmpty =>
                                'In “${title.trim()}”',
                              _ => 'Open to respond',
                            },
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          // The request card grows into its resolution sheet
                          // and contracts back into it.
                          final resolved =
                              await showHermesAttentionResolutionSheet(
                                context,
                                item,
                                origin: HermezMorphOrigin.of(
                                  rowContext,
                                  radius: 18,
                                  color: palette.surface,
                                ),
                              );
                          if (resolved == true) {
                            ref.invalidate(_attentionDecisionsProvider);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 12),
              ],
            ],
            if (failed.isNotEmpty) ...[
              const HermesSectionTitle('Failed scheduled runs'),
              const SizedBox(height: 8),
              for (final (profile, job) in failed) ...[
                HermesPanel(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.error_outline_rounded,
                      color: palette.accent,
                    ),
                    title: Text(
                      job.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '$profile · ${job.lastError ?? job.lastDeliveryError ?? job.lastStatus ?? 'Failed'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.pushNamed(RouteNames.hermesJobs),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _heading(HermesPendingDesktopDecisionKind kind) =>
      switch (kind) {
        HermesPendingDesktopDecisionKind.approval => 'Approvals',
        HermesPendingDesktopDecisionKind.clarification => 'Needs input',
        HermesPendingDesktopDecisionKind.sudo => 'Admin access',
        HermesPendingDesktopDecisionKind.secret => 'Credentials',
        HermesPendingDesktopDecisionKind.mcpSetup => 'Connector setup',
      };

  static String _title(HermesPendingDesktopDecisionKind kind) => switch (kind) {
    HermesPendingDesktopDecisionKind.approval => 'Tool approval requested',
    HermesPendingDesktopDecisionKind.clarification => 'Hermes asked a question',
    HermesPendingDesktopDecisionKind.sudo => 'Admin access required',
    HermesPendingDesktopDecisionKind.secret => 'Credential required',
    HermesPendingDesktopDecisionKind.mcpSetup => 'Connector needs setup',
  };

  static IconData _icon(HermesPendingDesktopDecisionKind kind) =>
      switch (kind) {
        HermesPendingDesktopDecisionKind.approval =>
          Icons.verified_user_outlined,
        HermesPendingDesktopDecisionKind.clarification =>
          Icons.chat_bubble_outline_rounded,
        HermesPendingDesktopDecisionKind.sudo =>
          Icons.admin_panel_settings_outlined,
        HermesPendingDesktopDecisionKind.secret => Icons.key_outlined,
        HermesPendingDesktopDecisionKind.mcpSetup => Icons.link_rounded,
      };
}
