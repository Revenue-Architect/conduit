import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/debug_logger.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../navigation/widgets/conversation_tile.dart';
import '../models/hermes_bot.dart';
import '../models/hermes_session.dart';
import '../providers/hermes_providers.dart';
import '../providers/hermes_session_totals_provider.dart';
import '../services/hermes_desktop_api_service.dart';
import 'hermes_session_tile.dart';
import 'hermes_bot_avatar.dart';

/// One Bot Mode agent in the sidebar roster. Tapping starts a new visible
/// conversation bound to the selected Hermes profile.
class HermesBotTile extends ConsumerStatefulWidget {
  const HermesBotTile({required this.bot, this.nested = false, super.key});

  final HermesBot bot;
  final bool nested;

  @override
  ConsumerState<HermesBotTile> createState() => _HermesBotTileState();
}

class _HermesBotTileState extends ConsumerState<HermesBotTile> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final bot = widget.bot;
    final avatar = bot.hasAvatar
        ? ref.watch(hermesBotAvatarProvider(bot.name)).asData?.value
        : null;
    final selected = false;
    final tile = ChatStyleSidebarTile(
      selected: selected,
      enabled: !_opening,
      semanticLabel: bot.title,
      onTap: _open,
      tintKey: const ValueKey<String>('conversation-tile-active-tint'),
      pressedKey: const ValueKey<String>('conversation-tile-pressed-tint'),
      child: SidebarListTileContent(
        title: widget.nested ? 'New chat with ${bot.title}' : bot.title,
        selected: selected,
        leading: widget.nested
            ? Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: context.conduitTheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 17,
                  color: context.conduitTheme.textPrimary,
                ),
              )
            : HermesBotAvatar(
                size: 32,
                imageUrl: avatar,
                label: bot.title,
                shape: bot.avatarShape,
                color: bot.avatarColor,
                imageKind: bot.avatarImageKind,
              ),
        trailing: _opening
            ? const SizedBox(
                width: IconSize.sm,
                height: IconSize.sm,
                child: CircularProgressIndicator(
                  strokeWidth: BorderWidth.medium,
                ),
              )
            : null,
      ),
    );
    if (!widget.nested) return tile;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.conduitTheme.cardBorder.withValues(alpha: 0.65),
        ),
      ),
      child: tile,
    );
  }

  Future<void> _open() async {
    final bot = widget.bot;
    final service = ref.read(hermesApiServiceProvider);
    if (service is! HermesDesktopApiService || _opening) return;
    setState(() => _opening = true);
    try {
      final storedId = await service.createBotConversation(bot);
      // A connection edit during the resolve invalidates the id we just bound.
      if (!mounted || !identical(ref.read(hermesApiServiceProvider), service)) {
        return;
      }
      ref.invalidate(hermesBotSessionsProvider(bot.name));
      ref.invalidate(hermesSessionsProvider);
      ref.invalidate(hermesSessionTotalsProvider);
      String? avatar;
      if (bot.hasAvatar) {
        try {
          avatar = await ref.read(hermesBotAvatarProvider(bot.name).future);
        } catch (_) {
          // Fall back to the shape avatar so a failed image cannot block chat.
        }
      }
      if (!mounted || !identical(ref.read(hermesApiServiceProvider), service)) {
        return;
      }
      await openHermesSession(
        context,
        ref,
        HermesSessionSummary(
          id: storedId,
          title: 'New conversation',
          profile: bot.name,
        ),
        bot: bot,
        botAvatar: avatar,
      );
    } catch (error) {
      DebugLogger.error(
        'open-bot-chat-failed',
        scope: 'hermes/bots',
        data: {'errorType': error.runtimeType.toString()},
      );
      if (mounted) {
        UiUtils.showMessage(
          context,
          AppLocalizations.of(context)!.hermesSessionLoadFailed,
          isError: true,
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
