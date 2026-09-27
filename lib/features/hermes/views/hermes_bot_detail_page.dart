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
import '../widgets/hermes_bot_avatar.dart';
import '../widgets/hermes_session_tile.dart';
import '../widgets/hermez_chat_palette.dart';
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
      if (!mounted || !identical(ref.read(hermesApiServiceProvider), service))
        return;
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this bot chat.')),
        );
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
    final avatar = ref.watch(hermesBotAvatarProvider(profile)).asData?.value;
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
            HermesPanel(
              child: Column(
                children: [
                  Row(
                    children: [
                      HermesBotAvatar(
                        size: 72,
                        label: bot?.title ?? profile,
                        shape: bot?.avatarShape ?? 'squircle',
                        color: bot?.avatarColor ?? '#8b5cf6',
                        imageKind: bot?.avatarImageKind,
                        imageUrl: avatar,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bot?.title ?? profile,
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              bot?.description ?? 'Hermes bot',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              bot?.lastActive == null
                                  ? 'Profile available'
                                  : 'Last active ${bot!.lastActive!.toLocal()}',
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: bot == null || _opening
                          ? null
                          : () => _openChat(bot!),
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: Text(
                        _opening
                            ? 'Opening…'
                            : 'Chat with ${bot?.title ?? profile}',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.ink,
                        foregroundColor: palette.surface,
                        minimumSize: const Size(0, 50),
                      ),
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
              data: (detail) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HermesPanel(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: _metric(
                            '${totalConversations ?? detail.sessions.length}',
                            'Conversations',
                          ),
                        ),
                        Expanded(
                          child: _metric('${detail.skills.length}', 'Skills'),
                        ),
                        Expanded(
                          child: _metric('${detail.jobs.length}', 'Schedules'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const HermesSectionTitle('Capabilities'),
                  const SizedBox(height: 9),
                  HermesPanel(
                    child: detail.skills.isEmpty && detail.tools.isEmpty
                        ? const Text('No profile capabilities reported.')
                        : Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final name in {
                                ...detail.skills,
                                ...detail.tools,
                              }.take(24))
                                Chip(label: Text(name.replaceAll('_', ' '))),
                            ],
                          ),
                  ),
                  const SizedBox(height: 18),
                  HermesSectionTitle(
                    'Recent conversations',
                    trailing: TextButton(
                      onPressed: () =>
                          context.pushNamed(RouteNames.hermesConversations),
                      child: const Text('See all →'),
                    ),
                  ),
                  const SizedBox(height: 9),
                  HermesPanel(
                    child: detail.sessions.isEmpty
                        ? const Text('No conversations for this profile yet.')
                        : Column(
                            children: [
                              for (final session in detail.sessions.take(3))
                                HermesSessionTile(session: session),
                            ],
                          ),
                  ),
                  const SizedBox(height: 18),
                  HermesSectionTitle(
                    'Scheduled agents',
                    trailing: TextButton(
                      onPressed: () => context.pushNamed(RouteNames.hermesJobs),
                      child: const Text('See all →'),
                    ),
                  ),
                  const SizedBox(height: 9),
                  HermesPanel(
                    child: detail.jobs.isEmpty
                        ? const Text('No schedules for this profile.')
                        : Column(
                            children: [
                              for (final job in detail.jobs.take(3))
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.event_repeat_rounded,
                                  ),
                                  title: Text(job.displayName),
                                  subtitle: Text(
                                    job.nextRun == null
                                        ? job.schedule
                                        : 'Next: ${job.nextRun!.toLocal()}',
                                  ),
                                  onTap: () async {
                                    final run =
                                        await showHermesScheduledAgentSheet(
                                          context,
                                          job: job,
                                          profile: profile,
                                        );
                                    if (run != null && context.mounted) {
                                      await openHermesSession(
                                        context,
                                        ref,
                                        run,
                                      );
                                    }
                                  },
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String value, String label) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
      ),
      Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
    ],
  );
}
