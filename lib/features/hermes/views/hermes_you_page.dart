import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../sky/hermez_sky_band.dart';
import '../sky/hermez_weather.dart' show kHermezCity;
import '../../../core/services/navigation_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../profile/views/profile_page.dart';
import '../models/hermes_bot.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../widgets/hermes_home_lines.dart' show watchHermesHomeStale;
import '../widgets/hermes_tab_dock.dart';
import '../widgets/hermez_bot_mark.dart';
import '../widgets/hermez_chat_palette.dart';

/// Hermes' memory status, or null when it can't be read.
final _memoryProvider =
    FutureProvider.autoDispose<
      ({String provider, int userBytes, int memoryBytes})?
    >((ref) async {
      final service = ref.watch(hermesApiServiceProvider);
      if (service is! HermesDesktopApiService) return null;
      try {
        return await service.memoryStatus();
      } catch (_) {
        return null;
      }
    });

/// The last seven days of tokens and cost, or null when it can't be read.
final _usageProvider =
    FutureProvider.autoDispose<
      ({int tokens, double cost, List<int> dailyTokens})?
    >((ref) async {
      final service = ref.watch(hermesApiServiceProvider);
      if (service is! HermesDesktopApiService) return null;
      try {
        return await service.usageAnalytics(days: 7);
      } catch (_) {
        return null;
      }
    });

/// "1.2M tokens · $4.12": the week's usage line.
String hermesUsageLine(int tokens, double cost) {
  final String t;
  if (tokens >= 1000000) {
    t = '${(tokens / 1000000).toStringAsFixed(1)}M';
  } else if (tokens >= 1000) {
    t = '${(tokens / 1000).toStringAsFixed(tokens >= 10000 ? 0 : 1)}K';
  } else {
    t = '$tokens';
  }
  return cost > 0 ? '$t tokens · \$${cost.toStringAsFixed(2)}' : '$t tokens';
}

TextStyle _geist(double size, FontWeight weight, Color color) => TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// You (docs/app-design-2026-10-30, y01): what Hermes knows and does on the
/// owner's behalf, from CoWork OS's ideas and only what Hermes exposes —
/// the connection, memory, what needs the owner's OK, the week's usage, the
/// bots, and the look. Every other setting is one tap away.
class HermesYouPage extends ConsumerWidget {
  const HermesYouPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final bots = ref.watch(hermesBotsProvider).value ?? const <HermesBot>[];
    final stale = watchHermesHomeStale(ref);
    final memory = ref.watch(_memoryProvider).value;
    final usage = ref.watch(_usageProvider).value;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final top = MediaQuery.of(context).padding.top;

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
      child: Text(
        text,
        style: _geist(
          15,
          FontWeight.w600,
          palette.ink,
        ).copyWith(letterSpacing: -0.3),
      ),
    );

    Widget row({
      required IconData icon,
      required String title,
      required String sub,
      String? value,
      VoidCallback? onTap,
      Widget? leading,
    }) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            leading ??
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: palette.raised,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.border),
                  ),
                  child: Icon(icon, size: 20, color: palette.muted),
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _geist(15, FontWeight.w500, palette.ink)),
                  Text(
                    sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _geist(13, FontWeight.w400, palette.muted),
                  ),
                ],
              ),
            ),
            if (value != null)
              Text(value, style: _geist(13, FontWeight.w500, palette.muted)),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: palette.faint),
          ],
        ),
      ),
    );

    String kb(int bytes) =>
        bytes >= 1024 ? '${(bytes / 1024).toStringAsFixed(1)} KB' : '$bytes B';

    final daily = usage?.dailyTokens ?? const <int>[];
    final peak = daily.isEmpty ? 0 : daily.reduce((a, b) => a > b ? a : b);

    return Material(
      color: palette.canvas,
      child: ListView(
        padding: EdgeInsets.only(bottom: hermesDockClearance(context) + 24),
        children: [
          Stack(
            children: [
              const Positioned.fill(child: HermezSkyBand(skylineHeight: 34)),
              Padding(
                padding: EdgeInsets.fromLTRB(20, top + 14, 20, 34),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You',
                      style: _geist(
                        30,
                        FontWeight.w600,
                        Colors.white,
                      ).copyWith(letterSpacing: -1.2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$kHermezCity · ${bots.length} bots',
                      style: _geist(
                        15,
                        FontWeight.w400,
                        Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          row(
            icon: Icons.dns_outlined,
            title: 'Umbrel',
            sub: stale
                ? 'Can’t reach Hermes right now'
                : 'Connected · Hermes with ${bots.length} bots',
            onTap: () => context.pushNamed(RouteNames.hermesSettings),
          ),
          heading('What the team knows about you'),
          row(
            icon: Icons.menu_book_outlined,
            title: 'Memory',
            sub: memory == null
                ? 'Hermes keeps notes about you and its work'
                : 'About you ${kb(memory.userBytes)} · its own notes ${kb(memory.memoryBytes)}'
                      '${memory.provider.isEmpty ? '' : ' · ${memory.provider}'}',
          ),
          heading('What needs your OK'),
          row(
            icon: Icons.verified_user_outlined,
            title: 'Approvals',
            sub: 'What you approved or denied, and what is waiting',
            onTap: () => context.pushNamed(RouteNames.hermesApprovals),
          ),
          if (usage != null) ...[
            heading('This week'),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      hermesUsageLine(usage.tokens, usage.cost),
                      style: _geist(17, FontWeight.w600, palette.ink),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    height: 40,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < daily.length && i < 7; i++)
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              height: peak == 0 ? 3 : 3 + 37 * daily[i] / peak,
                              decoration: BoxDecoration(
                                color: i == daily.length - 1
                                    ? palette.ink
                                    : palette.border,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (bots.isNotEmpty) heading('Your bots'),
          for (final bot in bots)
            row(
              icon: Icons.smart_toy_outlined,
              leading: ClipOval(
                child: SizedBox.square(
                  dimension: 40,
                  child: HermezBotMark(
                    identity: hermezIdentityForBot(bot),
                    botName: bot.name,
                    size: 40,
                    label: bot.title,
                  ),
                ),
              ),
              title: bot.title,
              sub: bot.description ?? bot.name,
              onTap: () => context.pushNamed(
                RouteNames.hermesBotDetail,
                pathParameters: {'profile': bot.name},
              ),
            ),
          heading('Look'),
          row(
            icon: dark ? Icons.dark_mode_outlined : Icons.wb_sunny_outlined,
            title: 'Sky',
            sub: dark
                ? 'Dark mode shows the evening sky'
                : 'Follows $kHermezCity’s time and weather',
          ),
          row(
            icon: Icons.tune_rounded,
            title: 'All settings',
            sub: 'Accounts, appearance, notifications and more',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
            ),
          ),
        ],
      ),
    );
  }
}
