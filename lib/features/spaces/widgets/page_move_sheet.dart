import 'package:flutter/material.dart';

import '../../hermes/sheets/hermez_modal_sheet.dart';
import '../../hermes/widgets/hermez_chat_palette.dart';
import '../../hermes/widgets/hermez_surfaces.dart';
import '../models/spaces_models.dart';
import '../services/hermes_spaces_client.dart';

/// Picks where to move [page]: the top level ('') or another Page of the
/// same Space. Only valid targets are offered (not the Page itself, not its
/// subpages, not its current parent); the server re-checks regardless.
Future<String?> showPageMoveSheet(
  BuildContext context, {
  required HermesSpacesClient client,
  required HermesPage page,
}) async {
  final List<HermesPageSummary> pages;
  try {
    pages = await client.pages(page.spaceId, byName: true);
  } on SpacesApiException {
    return null;
  }
  if (!context.mounted) return null;
  final descendants = _descendantsOf(page.id, pages);
  final targets = [
    for (final candidate in pages)
      if (candidate.id != page.id &&
          !descendants.contains(candidate.id) &&
          candidate.id != page.parentId)
        candidate,
  ];
  return pushHermezSheetRoute<String>(
    context,
    heightFactor: 0.7,
    builder: (sheetContext) {
      final palette = HermezChatPalette.forBrightness(
        Theme.of(sheetContext).brightness,
      );
      return HermezModalSheet(
        eyebrow: 'Move page',
        title: page.title,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            if (page.parentId != null)
              ListTile(
                leading: const Icon(Icons.vertical_align_top_rounded),
                title: const Text('Top level of this Space'),
                onTap: () => Navigator.pop(sheetContext, ''),
              ),
            if (targets.isEmpty && page.parentId == null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'There is no other Page to move this under yet.',
                  style: HermezType.meta(palette),
                ),
              ),
            for (final target in targets)
              ListTile(
                leading: const Icon(Icons.subdirectory_arrow_right_rounded),
                title: Text(
                  target.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: target.excerpt.isEmpty
                    ? null
                    : Text(
                        target.excerpt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => Navigator.pop(sheetContext, target.id),
              ),
          ],
        ),
      );
    },
  );
}

Set<String> _descendantsOf(String id, List<HermesPageSummary> pages) {
  final children = <String, List<String>>{};
  for (final page in pages) {
    final parent = page.parentId;
    if (parent != null) (children[parent] ??= []).add(page.id);
  }
  final found = <String>{};
  final stack = [...?children[id]];
  while (stack.isNotEmpty) {
    final next = stack.removeLast();
    if (found.add(next)) stack.addAll(children[next] ?? const []);
  }
  return found;
}

/// The newer server copy, read-only, during a conflict.
Future<void> showPageVersionSheet(
  BuildContext context, {
  required HermesPage page,
}) => pushHermezSheetRoute<void>(
  context,
  builder: (sheetContext) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(sheetContext).brightness,
    );
    return HermezModalSheet(
      eyebrow: 'Latest version · revision ${page.revision}',
      title: page.title,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
        children: [
          SelectableText(
            page.content.isEmpty ? '(empty)' : page.content,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
              color: palette.ink,
            ),
          ),
        ],
      ),
    );
  },
);
