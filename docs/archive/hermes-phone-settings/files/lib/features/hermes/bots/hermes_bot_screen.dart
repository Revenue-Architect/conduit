import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../desktop/input/hermez_desktop_shortcuts.dart';
import '../../desktop/shell/desktop_nav_scope.dart';
import '../models/hermes_bot.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../settings/pages/hermes_bot_editor_page.dart';
import '../widgets/hermes_bot_tile.dart';
import '../widgets/hermez_chat_palette.dart';

/// A bot's live state on the roster (R23).
enum HermesBotLiveState { idle, working, needsYou, unknown }

/// Derives a bot's state from Active Work by its canonical chat (KTD11).
/// Stale or failed Active Work reads as unknown, never idle.
HermesBotLiveState hermesBotLiveState(
  HermesBot bot,
  AsyncValue<List<HermesLiveSession>> activeWork,
) {
  final sessions = activeWork.value;
  if (sessions == null || activeWork.hasError) {
    return HermesBotLiveState.unknown;
  }
  final chat = bot.chatSessionId;
  final mine = chat == null
      ? const <HermesLiveSession>[]
      : sessions.where((s) => s.storedId == chat || s.runtimeId == chat);
  if (mine.any((s) => s.needsYou)) return HermesBotLiveState.needsYou;
  if (mine.any((s) => s.working)) return HermesBotLiveState.working;
  return HermesBotLiveState.idle;
}

/// The bot roster (R23–R26): one row per bot with its live state; a row
/// opens that bot's chat, Edit opens the bot editor, New bot creates one.
class HermesBotScreen extends ConsumerWidget {
  const HermesBotScreen({super.key});

  Future<void> _openEditor(BuildContext context, {String? name}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HermesBotEditorPage(name: name),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final bots = ref.watch(hermesBotsProvider);
    final activeWork = ref.watch(hermesActiveWorkProvider);
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        leading: desktopNavMenuLeading(context),
        title: const Text('Bots'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton.icon(
              key: const ValueKey('bot-screen-new'),
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New bot'),
            ),
          ),
        ],
      ),
      body: DesktopRefreshScope(
        onRefresh: () async {
          ref.invalidate(hermesBotsProvider);
          await ref.read(hermesBotsProvider.future);
        },
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: bots.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Couldn\'t load your bots.'),
                    TextButton(
                      onPressed: () => ref.invalidate(hermesBotsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('No bots yet. Create one.'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final bot = list[index];
                        return _RosterRow(
                          key: ValueKey('bot-row-${bot.name}'),
                          bot: bot,
                          state: hermesBotLiveState(bot, activeWork),
                          onEdit: () => _openEditor(context, name: bot.name),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({
    super.key,
    required this.bot,
    required this.state,
    required this.onEdit,
  });

  final HermesBot bot;
  final HermesBotLiveState state;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final (label, color) = switch (state) {
      HermesBotLiveState.needsYou => ('Needs you', palette.accent),
      HermesBotLiveState.working => ('Working', palette.ink),
      HermesBotLiveState.idle => ('Idle', palette.muted),
      HermesBotLiveState.unknown => ('—', palette.muted),
    };
    return Row(
      children: [
        Expanded(child: HermesBotTile(bot: bot)),
        const SizedBox(width: 8),
        Text(
          label,
          key: ValueKey('bot-state-${bot.name}'),
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
        IconButton(
          tooltip: 'Edit bot',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    );
  }
}
