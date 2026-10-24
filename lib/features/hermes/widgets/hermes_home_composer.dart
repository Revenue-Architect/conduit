import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/providers/chat_providers.dart'
    show composerAutofocusEnabledProvider, inputFocusTriggerProvider;
import '../models/hermes_bot.dart';
import '../models/hermes_session.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_providers.dart';
import '../providers/hermes_session_totals_provider.dart';
import '../services/hermes_desktop_api_service.dart';
import '../sheets/hermes_active_work_sheet.dart' show hermesSummaryForSession;
import 'hermes_home_inbox.dart' show hermesChiefProfile;
import 'hermes_session_tile.dart' show openHermesSession;
import 'hermes_tab_dock.dart';
import 'hermez_bot_mark.dart';
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';

/// Starts a new, independent conversation with [bot] and opens it. Returns
/// the new session's id, or null when it could not be started.
Future<String?> startHermesBotConversation(
  BuildContext context,
  WidgetRef ref,
  HermesBot bot,
) async {
  final service = ref.read(hermesApiServiceProvider);
  if (service is! HermesDesktopApiService) return null;
  try {
    final id = await service.createBotConversation(bot);
    if (!context.mounted ||
        !identical(ref.read(hermesApiServiceProvider), service)) {
      return null;
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
      botAvatar: ref.read(hermesBotAvatarProvider(bot.name)).asData?.value,
    );
    return id;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start a bot conversation.')),
      );
    }
    return null;
  }
}

/// Opens Chief's canonical chat with its composer focused. A Chief without a
/// canonical chat gets a new conversation instead, the same as choosing Chief
/// from the + menu. Nothing is sent from Home.
Future<void> openHermesChiefChat(BuildContext context, WidgetRef ref) async {
  final bots = ref.read(hermesBotsProvider).value ?? const <HermesBot>[];
  final chief = bots.where((bot) => bot.name == hermesChiefProfile).firstOrNull;
  if (chief == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chief is not available right now.')),
    );
    return;
  }
  // Taken before the awaits: where Home has no tab shell, opening the chat
  // unmounts it, and a widget ref can no longer be read after that.
  final container = ProviderScope.containerOf(context, listen: false);
  final canonical = chief.chatSessionId;
  final String? opened;
  if (canonical == null) {
    opened = await startHermesBotConversation(context, ref, chief);
  } else {
    await openHermesSession(
      context,
      ref,
      hermesSummaryForSession(
        ref,
        canonical,
        hermesProfileDisplayName(chief.name),
      ),
      bot: chief,
    );
    opened = canonical;
  }
  // The chat takes focus only if it really opened.
  if (opened != null && container.read(hermesActiveSessionProvider) == opened) {
    container.read(composerAutofocusEnabledProvider.notifier).set(true);
    container.read(inputFocusTriggerProvider.notifier).increment();
  }
}

/// The bar docked at the bottom of Home: type to Chief without first
/// choosing a conversation. It is a door, not a field: tapping opens Chief's
/// chat with the keyboard up, and nothing is sent from here.
class HermesHomeComposer extends ConsumerWidget {
  const HermesHomeComposer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final service = ref.watch(hermesApiServiceProvider);
    final bots = ref.watch(hermesBotsProvider).value;
    // Without a Desktop connection, or once the roster shows no Chief, there
    // is no one for the bar to open.
    final available =
        service is HermesDesktopApiService &&
        (bots == null || bots.any((bot) => bot.name == hermesChiefProfile));
    if (!available) return const SizedBox.shrink();
    return Padding(
      // Rests just above the floating dock.
      padding: EdgeInsets.fromLTRB(16, 8, 16, switch (hermesDockClearance(
        context,
      )) {
        0 => 12,
        final clearance => clearance + 4,
      }),
      child: HermezMotionSurface(
        weight: HermezMotionWeight.medium,
        semanticLabel: 'Message Chief',
        onTap: () => openHermesChiefChat(context, ref),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(28),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.add_rounded,
                      size: 24,
                      color: palette.muted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        'Message Chief…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HermezType.body(palette)
                            .copyWith(color: palette.muted, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  HermezBotMark(
                    identity: hermezIdentityForName(hermesChiefProfile),
                    botName: hermesChiefProfile,
                    size: 36,
                    label: hermesProfileDisplayName(hermesChiefProfile),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
