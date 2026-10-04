import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../hermes/motion/hermez_motion.dart';
import '../../hermes/views/hermes_page_chrome.dart';
import '../../hermes/widgets/hermez_chat_palette.dart';
import '../../hermes/widgets/hermez_relative_time.dart';
import '../../hermes/widgets/hermez_surfaces.dart';
import '../models/spaces_models.dart';
import '../providers/spaces_providers.dart';
import '../services/hermes_spaces_client.dart';
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
    return HermesPageChrome(
      title: 'Spaces',
      subtitle: 'Pages you and Hermes keep working on',
      actions: [
        IconButton(
          tooltip: 'New Space',
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(spacesListProvider.future),
        child: switch (spaces) {
          AsyncValue(:final value?) when value.isEmpty => SpacesEmptyState(
            title: 'No Spaces yet',
            message:
                'A Space holds Pages: plans, research, notes you keep '
                'improving with Hermes.',
            actionLabel: 'New Space',
            onAction: () => _create(context, ref),
          ),
          AsyncValue(:final value?) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 96),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) =>
                _SpaceTile(space: value[index], palette: palette),
          ),
          AsyncValue(:final error?) => SpacesErrorState(
            error: error,
            onRetry: () => ref.invalidate(spacesListProvider),
          ),
          _ => const SpacesLoadingState(),
        },
      ),
    );
  }
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({required this.space, required this.palette});

  final HermesSpace space;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) {
    final count = space.pageCount;
    return HermezSurface(
      kind: HermezSurfaceKind.list,
      semanticLabel: '${space.name}, $count ${count == 1 ? 'page' : 'pages'}',
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      onOpen: (origin) => context.pushNamed(
        RouteNames.spaceLibrary,
        pathParameters: {'spaceId': space.id},
        extra: origin,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: space.icon != null
                ? Text(space.icon!, style: const TextStyle(fontSize: 20))
                : Icon(Icons.folder_open_rounded, color: palette.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  space.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HermezType.body(palette)
                      .copyWith(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count ${count == 1 ? 'page' : 'pages'} · '
                  '${hermezRelativeLabel(space.updatedAt)}',
                  style: HermezType.meta(palette),
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
