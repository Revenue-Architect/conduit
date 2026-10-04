import 'package:flutter/material.dart';

import '../../hermes/models/hermes_bot.dart';
import '../../hermes/sheets/hermez_modal_sheet.dart';
import '../../hermes/widgets/hermez_bot_mark.dart';
import '../../hermes/widgets/hermez_chat_palette.dart';
import '../../hermes/widgets/hermez_surfaces.dart';
import '../models/spaces_models.dart';
import '../services/page_chat_launcher.dart';

/// "Ask Hermes": which Hermes profile to work on this Page with. A profile
/// that already has a conversation for the Page continues it; any other
/// starts one.
Future<HermesBot?> showPageChatPicker(
  BuildContext context, {
  required String pageTitle,
  required List<HermesBot> bots,
  required List<PageChatBinding> chats,
}) {
  final ordered = orderPageChatBots(bots, chats);
  final existing = {for (final chat in chats) chat.profile};
  return pushHermezSheetRoute<HermesBot>(
    context,
    heightFactor: 0.72,
    builder: (sheetContext) {
      final palette = HermezChatPalette.forBrightness(
        Theme.of(sheetContext).brightness,
      );
      return HermezModalSheet(
        eyebrow: 'Ask Hermes',
        title: pageTitle,
        subtitle: Text(
          'Each profile keeps its own conversation about this Page.',
          style: HermezType.meta(palette),
        ),
        body: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: ordered.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final bot = ordered[index];
            final continues = existing.contains(bot.name);
            return HermezSurface(
              kind: HermezSurfaceKind.list,
              semanticLabel:
                  '${continues ? 'Continue with' : 'Ask'} ${bot.title}',
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              onTap: () => Navigator.pop(sheetContext, bot),
              child: Row(
                children: [
                  HermezBotMark(
                    identity: hermezIdentityForBot(bot),
                    size: 36,
                    label: bot.title,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bot.title,
                          style: HermezType.body(palette)
                              .copyWith(fontWeight: FontWeight.w800),
                        ),
                        if ((bot.description ?? '').trim().isNotEmpty)
                          Text(
                            bot.description!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HermezType.meta(palette),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    continues ? 'CONTINUE' : 'NEW',
                    style: HermezType.technical(
                      continues ? palette.accent : palette.muted,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}
