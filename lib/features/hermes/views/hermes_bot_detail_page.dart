import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../feedback/hermez_feedback.dart';
import '../../../core/services/navigation_service.dart';
import '../models/hermes_bot.dart';
import '../models/hermes_config.dart';
import '../models/hermes_job.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../providers/hermes_session_totals_provider.dart';
import '../services/hermes_desktop_api_service.dart';
import '../sheets/hermes_scheduled_agent_sheet.dart';
import '../utils/hermes_schedule_format.dart';
import '../widgets/hermes_session_tile.dart';
import '../widgets/hermez_bot_identity.dart';
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_relative_time.dart';
import '../motion/hermez_motion.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermes_page_chrome.dart';
import '../widgets/hermes_bot_knowledge.dart';
import '../widgets/hermez_bot_presence.dart';
import '../widgets/hermez_expandable_section.dart';

final class _BotData {
  const _BotData(this.sessions, this.skills, this.tools, this.jobs);
  final List<HermesSessionSummary> sessions;
  final List<String> skills;
  final List<String> tools;
  final List<HermesJob> jobs;
}

final _botDataProvider = FutureProvider.autoDispose.family<_BotData, String>((
  ref,
  profile,
) async {
  final service = ref.watch(hermesApiServiceProvider);
  if (service is! HermesDesktopApiService ||
      !HermesConfig.isValidDesktopProfile(profile)) {
    return const _BotData([], [], [], []);
  }
  Future<T> safe<T>(Future<T> Function() load, T fallback) async {
    try {
      return await load();
    } catch (_) {
      return fallback;
    }
  }

  final sessions = safe(
    () async =>
        (await service.listSessionsForProfile(profile))
            .map(HermesSessionSummary.fromJson)
            .whereType<HermesSessionSummary>()
            .where((row) => row.profile == null || row.profile == profile)
            .toList(growable: false),
    <HermesSessionSummary>[],
  );
  final skills = safe(() async {
    final listed = (await service.listSkillsForProfile(profile))
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (listed.isNotEmpty) return listed;
    // Gateways that return nothing for a profile's skills over RPC still
    // serve the dashboard catalog; count the enabled ones.
    return (await service.skillCatalog(profile))
        .where((row) => row['enabled'] != false)
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }, <String>[]);
  final tools = safe(
    () async =>
        (await service.listToolsetsForProfile(profile))
            .map((row) => (row['name'] ?? row['title'] ?? '').toString())
            .where((name) => name.isNotEmpty)
            .toList(growable: false),
    <String>[],
  );
  final jobs = safe(
    () async =>
        (await service.listJobsForProfile(profile))
            .map(HermesJob.fromJson)
            .whereType<HermesJob>()
            .toList(growable: false),
    <HermesJob>[],
  );
  return _BotData(await sessions, await skills, await tools, await jobs);
});

class HermesBotDetailPage extends ConsumerStatefulWidget {
  const HermesBotDetailPage({super.key, required this.profile});
  final String profile;

  @override
  ConsumerState<HermesBotDetailPage> createState() =>
      _HermesBotDetailPageState();
}

class _HermesBotDetailPageState extends ConsumerState<HermesBotDetailPage> {
  bool _opening = false;

  /// Screen-local: whether the Systems compartment is open.
  bool _systemsExpanded = false;

  Future<void> _openChat(HermesBot bot) async {
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService || _opening) return;
    setState(() => _opening = true);
    try {
      final id = await service.createBotConversation(bot);
      if (!mounted || !identical(ref.read(hermesApiServiceProvider), service)) {
        return;
      }
      ref.invalidate(hermesBotSessionsProvider(bot.name));
      ref.invalidate(hermesSessionsProvider);
      ref.invalidate(hermesSessionTotalsProvider);
      await openHermesSession(
        context,
        ref,
        HermesSessionSummary(
          id: id,
          title: 'New conversation',
          profile: bot.name,
        ),
        bot: bot,
        botAvatar: bot.hasAvatar
            ? ref.read(hermesBotAvatarProvider(bot.name)).asData?.value
            : null,
      );
    } catch (_) {
      // Presentation only, alongside the existing error.
      HermezFeedback.play(HermezFeedbackCue.runFailed);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this bot chat.')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final bots =
        ref.watch(hermesBotsProvider).asData?.value ?? const <HermesBot>[];
    HermesBot? bot;
    for (final candidate in bots) {
      if (candidate.name == profile) {
        bot = candidate;
        break;
      }
    }
    final data = ref.watch(_botDataProvider(profile));
    final totalConversations = ref
        .watch(hermesSessionTotalsProvider)
        .asData
        ?.value[profile];
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final service = ref.watch(hermesApiServiceProvider);
    final running = bot != null && hermezBotRunning(service, bot);
    final title = bot?.title ?? profile;
    final description = bot?.description?.trim();
    final morphId = hermezBotMorphId(bot?.name ?? profile);
    final detail = data.asData?.value;
    return HermesPageChrome(
      title: title,
      subtitle: description ?? 'Hermes profile',
      showHeader: false,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_botDataProvider(profile));
          await ref.read(_botDataProvider(profile).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 34),
          children: [
            HermezSurface(
              kind: HermezSurfaceKind.hero,
              motif: HermezMotif.etched,
              motifMorphId: hermezMorphPart(morphId, 'motif'),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      HermezMorph(
                        id: hermezMorphPart(morphId, 'mark'),
                        child: HermezBotPresence(
                          identity: hermezIdentityForName(bot?.name ?? profile),
                          size: 88,
                          label: title,
                          service: switch (ref.watch(
                            hermesApiServiceProvider,
                          )) {
                            final HermesDesktopApiService s => s,
                            _ => null,
                          },
                          sessionId: bot?.chatSessionId,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HermezMorphText(
                              'BOT',
                              id: hermezMorphPart(morphId, 'kind'),
                              style: HermezBotStyles.detailKind(palette),
                            ),
                            const SizedBox(height: 4),
                            HermezMorphText(
                              title,
                              id: hermezMorphPart(morphId, 'name'),
                              style: HermezBotStyles.detailName(palette),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  HermezMorphText(
                    description == null || description.isEmpty
                        ? 'Hermes profile'
                        : description,
                    id: hermezMorphPart(morphId, 'about'),
                    maxLines: 3,
                    style: HermezBotStyles.detailAbout(palette),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      HermezMorph(
                        id: hermezMorphPart(morphId, 'dot'),
                        child: HermezStatusDot(running: running, size: 7),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: HermezMorphText(
                          bot == null
                              ? 'Available'
                              : hermezBotStatus(bot, running: running),
                          id: hermezMorphPart(morphId, 'status'),
                          style: HermezType.meta(palette),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  HermezEntrance(
                    order: 0,
                    child: HermezSurface(
                      kind: HermezSurfaceKind.technical,
                      motif: HermezMotif.slash,
                      semanticLabel: 'Chat with $title',
                      feedbackCue: HermezFeedbackCue.botEngage,
                      onTap: bot == null || _opening
                          ? null
                          : () => _openChat(bot!),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: Color(0xFFF6F5F2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _opening ? 'Opening…' : 'Chat with $title',
                                  style: const TextStyle(
                                    color: Color(0xFFF6F5F2),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                const Text(
                                  'Start a new conversation',
                                  style: TextStyle(
                                    color: Color(0xFFA9ABB0),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFFF6F5F2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            HermezEntrance(
              order: 1,
              child: HermezSurface(
                kind: HermezSurfaceKind.utility,
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: _metric(
                        '${totalConversations ?? detail?.sessions.length ?? '—'}',
                        'Chats',
                        palette,
                      ),
                    ),
                    Expanded(
                      child: _metric(
                        '${detail?.skills.length ?? '—'}',
                        'Skills',
                        palette,
                      ),
                    ),
                    Expanded(
                      child: _metric(
                        '${detail?.jobs.length ?? '—'}',
                        'Schedules',
                        palette,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            HermezPresence(
              presenceKey: ValueKey(
                detail != null
                    ? 'data'
                    : data.hasError
                    ? 'error'
                    : 'loading',
              ),
              weight: HermezMotionWeight.medium,
              child: detail != null
                  ? _details(context, detail, palette, profile)
                  : data.hasError
                  ? const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: HermesPanel(
                        child: Text('Bot details unavailable. Pull to retry.'),
                      ),
                    )
                  : const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: CircularProgressIndicator()),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _details(
    BuildContext context,
    _BotData detail,
    HermezChatPalette palette,
    String profile,
  ) {
    final curated = _curateCapabilities(
      skills: detail.skills,
      tools: detail.tools,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        HermezEntrance(
          order: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CAPABILITIES', style: HermezType.technical(palette.muted)),
              const SizedBox(height: 8),
              if (curated.featured.isEmpty)
                Text(
                  'No profile capabilities reported.',
                  style: HermezType.meta(palette),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in curated.featured)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: palette.border.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Text(
                          name.replaceAll('_', ' '),
                          style: HermezType.meta(palette)
                              .copyWith(color: palette.ink),
                        ),
                      ),
                  ],
                ),
              if (curated.rest.isNotEmpty) ...[
                const SizedBox(height: 14),
                // More of the same object: the capabilities compartment
                // opens in place and pushes Knowledge and the rest down.
                HermezExpandableSection(
                  expanded: _systemsExpanded,
                  onExpansionChanged: (expanded) =>
                      setState(() => _systemsExpanded = expanded),
                  semanticLabel: 'All skills and tools',
                  openFeedback: HermezFeedbackCue.compartmentOpen,
                  closeFeedback: HermezFeedbackCue.compartmentClose,
                  header: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // The rows inside: every capability not featured.
                        'SYSTEMS / ${curated.rest.length}',
                        style: HermezType.technical(palette.muted),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'All skills & tools',
                        style: HermezType.section(palette)
                            .copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final name in curated.rest)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            name.replaceAll('_', ' '),
                            style: HermezType.meta(palette),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        HermesBotKnowledgeSection(profile: profile, botTitle: profile),
        const SizedBox(height: 12),
        HermezEntrance(
          order: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HermezSectionBar(
                label: 'CONVERSATIONS',
                onAction: () =>
                    context.pushNamed(RouteNames.hermesConversations),
              ),
              if (detail.sessions.isEmpty)
                Text(
                  'No conversations for this profile yet.',
                  style: HermezType.meta(palette),
                )
              else
                HermezSurface(
                  kind: HermezSurfaceKind.utility,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final session in detail.sessions.take(3))
                        HermesSessionTile(session: session, compact: true),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        HermezEntrance(
          order: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HermezSectionBar(
                label: 'SCHEDULED',
                onAction: () => context.pushNamed(RouteNames.hermesJobs),
              ),
              if (detail.jobs.isEmpty)
                Text(
                  'No schedules for this profile.',
                  style: HermezType.meta(palette),
                )
              else
                for (final job in detail.jobs.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: HermezSurface(
                      kind: HermezSurfaceKind.utility,
                      semanticLabel: job.displayName,
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      onOpen: (origin) async {
                        final run = await showHermesScheduledAgentSheet(
                          context,
                          job: job,
                          profile: profile,
                          origin: origin,
                        );
                        if (run != null && context.mounted) {
                          await openHermesSession(context, ref, run);
                        }
                      },
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 20,
                            color: job.enabled ? palette.accent : palette.muted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                HermezMorphText(
                                  job.displayName,
                                  id: hermezMorphPart(
                                    hermezJobMorphId(profile, job.id),
                                    'title',
                                  ),
                                  style: HermezType.body(palette)
                                      .copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  job.nextRun == null
                                      ? describeHermesCronSchedule(job.schedule)
                                      : hermezWhen(job.nextRun, prefix: 'Next'),
                                  style: HermezType.meta(palette),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: palette.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metric(String value, String label, HermezChatPalette palette) =>
      Column(
        children: [
          Text(
            value,
            style: HermezType.numeric(palette.ink).copyWith(fontSize: 22),
          ),
          const SizedBox(height: 2),
          Text(label, style: HermezType.meta(palette)),
        ],
      );
}

class _CuratedCapabilities {
  const _CuratedCapabilities(this.featured, this.rest);
  final List<String> featured;
  final List<String> rest;
}

_CuratedCapabilities _curateCapabilities({
  required List<String> skills,
  required List<String> tools,
}) {
  final all = <String>{...skills, ...tools}.toList(growable: false);
  bool technical(String name) {
    final value = name.toLowerCase();
    const markers = [
      'api',
      'server',
      'engine',
      'mcp',
      'cron',
      'context',
      'gateway',
      'sdk',
      'plugin',
    ];
    return markers.any(value.contains);
  }

  final human = all.where((name) => !technical(name)).toList(growable: false);
  final machine = all.where(technical).toList(growable: false);
  final featured = <String>[
    ...human.take(8),
    if (human.length < 6) ...machine.take(6 - human.length),
  ];
  final rest = all.where((name) => !featured.contains(name)).toList();
  return _CuratedCapabilities(featured, rest);
}
