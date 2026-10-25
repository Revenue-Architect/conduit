import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../models/hermes_bot.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import '../sheets/hermes_active_work_sheet.dart' show hermesSummaryForSession;
import '../widgets/hermes_home_needs_you.dart';
import '../widgets/hermes_home_working.dart';
import '../widgets/hermes_session_tile.dart' show openHermesSession;
import 'manga_portrait.dart';
import 'manga_theme.dart';
import 'manga_widgets.dart';

/// Work's first block in the manga layout: everything waiting on the owner,
/// on one ink panel with the count in orange. The rows are the shared Needs
/// you rows, drawn in the opposite theme so they read on the panel.
class MangaNeedsBlock extends ConsumerWidget {
  const MangaNeedsBlock({super.key});

  static const _shown = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = watchHermesNeedsYou(ref);
    final ink = MangaInk.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedSize(
      duration: MangaMotion.enter,
      curve: MangaMotion.easeOut,
      alignment: Alignment.topCenter,
      child: items.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ink.ink,
                  border: Border.all(color: ink.ink, width: ink.border),
                ),
                child: Theme(
                  data: dark ? ThemeData.light() : ThemeData.dark(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${items.length}',
                              style: MangaType.display(
                                dark ? MangaInk.light.accentText : ink.accent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                items.length == 1 ? 'needs you' : 'need you',
                                style: MangaType.panel(ink.ground),
                              ),
                            ),
                            if (items.length > _shown)
                              MangaPress(
                                semanticLabel: 'See everything that needs you',
                                onTap: () => context.pushNamed(
                                  RouteNames.hermesAttention,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    'See all',
                                    style: MangaType.line(ink.ground),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        for (final item in items.take(_shown))
                          HermesNeedsYouRow(key: ValueKey(item.id), item: item),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// What is running now: one panel per working bot, speed lines behind it,
/// what it is doing, and an "On it" stamp. Opens its conversation.
class MangaRunningBlock extends ConsumerWidget {
  const MangaRunningBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final working = watchHermesWorkingAgents(ref);
    final bots = ref.watch(hermesBotsProvider).value ?? const <HermesBot>[];
    final live = ref.watch(hermesActiveWorkProvider).value ?? const [];
    final ink = MangaInk.of(context);
    return AnimatedSize(
      duration: MangaMotion.enter,
      curve: MangaMotion.easeOut,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final agent in working)
            Padding(
              key: ValueKey('running-${agent.storedId}'),
              padding: const EdgeInsets.only(top: 7),
              child: Builder(
                builder: (context) {
                  final bot = bots
                      .where((b) => b.name == agent.profile)
                      .firstOrNull;
                  final name = bot?.title ?? agent.profile;
                  String? title;
                  for (final session in live) {
                    if (session.storedId == agent.storedId) {
                      title = session.title;
                    }
                  }
                  return MangaPress(
                    scale: .985,
                    semanticLabel: '$name is working. ${agent.line}',
                    onTap: () => openHermesSession(
                      context,
                      ref,
                      hermesSummaryForSession(ref, agent.storedId, name),
                      bot: bot,
                    ),
                    child: SizedBox(
                      height: 80,
                      child: MangaPanel(
                        working: true,
                        rayCentre: const Alignment(-.82, .7),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 6,
                              bottom: -14,
                              width: 70,
                              height: 84,
                              child: MangaPortrait(botName: agent.profile),
                            ),
                            Positioned(
                              left: 86,
                              right: 76,
                              top: 0,
                              bottom: 0,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (title?.isNotEmpty ?? false)
                                        ? title!
                                        : name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MangaType.panel(ink.ink),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '$name · ${agent.line}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MangaType.meta(ink.ink2),
                                  ),
                                ],
                              ),
                            ),
                            const Positioned(
                              right: 10,
                              top: 0,
                              bottom: 0,
                              child: Center(child: MangaStamp('On it')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
