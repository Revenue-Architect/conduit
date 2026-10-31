import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../hermes/motion/hermez_motion.dart';
import '../../hermes/widgets/hermez_chat_palette.dart';
import '../../hermes/widgets/hermez_relative_time.dart';
import '../../hermes/widgets/hermez_surfaces.dart';
import '../models/spaces_models.dart';
import '../providers/spaces_providers.dart';
import '../services/hermes_spaces_client.dart';
import '../widgets/sky_sheet_page.dart';
import '../widgets/spaces_state_views.dart';

/// Every Space: the containers of Pages the user and Hermes work on.
class SpacesPage extends ConsumerWidget {
  const SpacesPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final client = ref.read(hermesSpacesClientProvider);
    if (client == null) return;
    final name = await ThemedDialogs.promptTextInput(
      context,
      title: 'New Space',
      hintText: 'Name, like Kaizen or Home',
      confirmText: 'Create',
      maxLength: SpacesLimits.spaceName,
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    try {
      final space = await client.createSpace(name.trim());
      ref.invalidate(spacesListProvider);
      if (context.mounted) {
        context.pushNamed(
          RouteNames.spaceLibrary,
          pathParameters: {'spaceId': space.id},
        );
      }
    } on SpacesApiException catch (error) {
      if (context.mounted) showSpacesError(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(spacesListProvider);
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return SkySheetPage(
      title: 'Spaces',
      actions: [
        IconButton(
          tooltip: 'New Space',
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
            child: Text(
              'Pages you and Hermes keep working on',
              style: skyText(15, FontWeight.w400, palette.muted),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(spacesListProvider.future),
              child: switch (spaces) {
                AsyncValue(:final value?) when value.isEmpty =>
                  SpacesEmptyState(
                    title: 'No Spaces yet',
                    message:
                        'A Space holds Pages: plans, research, notes you keep '
                        'improving with Hermes.',
                    actionLabel: 'New Space',
                    onAction: () => _create(context, ref),
                  ),
                AsyncValue(:final value?) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    for (final space in value)
                      _SpaceRow(space: space, palette: palette),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: Text(
                        'A Space holds Pages: plans, research and notes you '
                        'keep improving with Hermes.',
                        style: skyText(15, FontWeight.w400, palette.muted),
                      ),
                    ),
                  ],
                ),
                AsyncValue(:final error?) => SpacesErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(spacesListProvider),
                ),
                _ => const SpacesLoadingState(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One Space, as a Chats-style row: the folder, its name, pages and time.
/// A Space's own icon is not shown for now (owner): always the folder.
class _SpaceRow extends StatelessWidget {
  const _SpaceRow({required this.space, required this.palette});

  final HermesSpace space;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) {
    final count = space.pageCount;
    return HermezSurface(
      kind: HermezSurfaceKind.list,
      semanticLabel: '${space.name}, $count ${count == 1 ? 'page' : 'pages'}',
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      onOpen: (origin) => context.pushNamed(
        RouteNames.spaceLibrary,
        pathParameters: {'spaceId': space.id},
        extra: origin,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.raised,
              shape: BoxShape.circle,
              border: Border.all(color: palette.border),
            ),
            child: Icon(Icons.folder_outlined, color: palette.muted, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  space.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: skyText(
                    17,
                    FontWeight.w600,
                    palette.ink,
                  ).copyWith(letterSpacing: -0.3),
                ),
                Text(
                  '$count ${count == 1 ? 'page' : 'pages'} · '
                  '${hermezRelativeLabel(space.updatedAt)}',
                  style: skyText(13, FontWeight.w400, palette.muted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: palette.muted),
        ],
      ),
    );
  }
}

/// Opens Spaces when this Hermes has it.
void openSpaces(BuildContext context, {HermezMorphOrigin? origin}) =>
    context.pushNamed(RouteNames.spaces, extra: origin);
