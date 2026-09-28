import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_relative_time.dart';
import '../motion/hermez_motion.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermes_page_chrome.dart';

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
  final skills = safe(
    () async =>
        (await service.listSkillsForProfile(profile))
            .map((row) => row['name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toList(growable: false),
    <String>[],
  );
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
    return HermesPageChrome(
      title: bot?.title ?? profile,
      subtitle: bot?.description ?? 'Hermes profile',
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_botDataProvider(profile));
          await ref.read(_botDataProvider(profile).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 34),
          children: [
            HermezSurface(
              kind: HermezSurfaceKind.hero,
              motif: HermezMotif.crop,
              indexLabel: '01',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HermezMorph(
                    id: hermezBotMorphId(bot?.name ?? profile),
                    child: Row(
                      children: [
                        HermezBotMark(
                          identity: hermezIdentityForName(bot?.name ?? profile),
                          size: 72,
                          label: bot?.title ?? profile,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BOT',
                                style: HermezType.technical(palette.muted),
                              ),
                              Text(
                                bot?.title ?? profile,
                                style: HermezType.display(palette)
                                    .copyWith(fontSize: 28),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                bot?.lastActive == null
                                    ? 'Available'
                                    : hermezWhen(
                                        bot!.lastActive,
                                        prefix: 'Active',
                                      ),
                                style: HermezType.meta(palette),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    bot?.description ?? 'Hermes profile',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: HermezType.body(palette),
                  ),
                  const SizedBox(height: 16),
                  HermezSurface(
                    kind: HermezSurfaceKind.technical,
                    onTap: bot == null || _opening
                        ? null
                        : () => _openChat(bot!),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: Color(0xFFF6F5F2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _opening
                                ? 'Opening…'
                                : 'Chat with ${bot?.title ?? profile}',
                            style: const TextStyle(
                              color: Color(0xFFF6F5F2),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            data.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, _) => const HermesPanel(
                child: Text('Bot details unavailable. Pull to retry.'),
              ),
              data: (detail) {
                final curated = _curateCapabilities(
                  skills: detail.skills,
                  tools: detail.tools,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    HermezSurface(
                      kind: HermezSurfaceKind.utility,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: _metric(
                              '${totalConversations ?? detail.sessions.length}',
                              'Chats',
                              palette,
                            ),
                          ),
                          Expanded(
                            child: _metric(
                              '${detail.skills.length}',
                              'Skills',
                              palette,
                            ),
                          ),
                          Expanded(
                            child: _metric(
                              '${detail.jobs.length}',
                              'Schedules',
                              palette,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'CAPABILITIES',
                      style: HermezType.technical(palette.muted),
                    ),
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
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                name.replaceAll('_', ' '),
                                style: HermezType.meta(palette)
                                    .copyWith(color: palette.ink),
                              ),
                            ),
                        ],
                      ),
                    if (curated.rest.isNotEmpty)
                      Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            'All skills and tools',
                            style: HermezType.section(palette)
                                .copyWith(fontSize: 14),
                          ),
                          children: [
                            for (final name in curated.rest)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    name.replaceAll('_', ' '),
                                    style: HermezType.meta(palette),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
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
                      Column(
                        children: [
                          for (final session in detail.sessions.take(3))
                            HermesSessionTile(session: session, compact: true),
                        ],
                      ),
                    const SizedBox(height: 12),
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
                      Column(
                        children: [
                          for (final job in detail.jobs.take(3))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(job.displayName),
                              subtitle: Text(
                                job.nextRun == null
                                    ? describeHermesCronSchedule(job.schedule)
                                    : hermezWhen(job.nextRun, prefix: 'Next'),
                              ),
                              onTap: () async {
                                final run = await showHermesScheduledAgentSheet(
                                  context,
                                  job: job,
                                  profile: profile,
                                );
                                if (run != null && context.mounted) {
                                  await openHermesSession(context, ref, run);
                                }
                              },
                            ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String value, String label, HermezChatPalette palette) =>
      Column(
        children: [
          Text(
            value,
            style: HermezType.numeric(palette.ink).copyWith(fontSize: 22),
          ),
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
