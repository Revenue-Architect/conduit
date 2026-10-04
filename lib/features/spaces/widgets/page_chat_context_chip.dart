import 'package:flutter/material.dart';

import '../../../core/services/navigation_service.dart';
import '../../hermes/widgets/hermez_chat_palette.dart';
import '../../hermes/widgets/hermez_surfaces.dart';
import '../models/spaces_models.dart';

/// Above the composer in a Page's own conversation: which Page this chat
/// works on, and the way back to it.
class PageChatContextChip extends StatelessWidget {
  const PageChatContextChip({super.key, required this.page});

  final HermesPageSummary page;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Semantics(
      container: true,
      label: 'This conversation works on the Page ${page.title}',
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => NavigationService.router.pushNamed(
            RouteNames.spacePage,
            pathParameters: {'spaceId': page.spaceId, 'pageId': page.id},
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
            child: Row(
              children: [
                Icon(Icons.article_outlined, size: 18, color: palette.accent),
                const SizedBox(width: 8),
                Text('PAGE', style: HermezType.technical(palette.muted)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    page.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HermezType.body(palette)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  'Open',
                  style: TextStyle(
                    color: palette.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
