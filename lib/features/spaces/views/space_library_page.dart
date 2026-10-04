import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../hermes/views/hermes_page_chrome.dart';
import '../../hermes/widgets/hermez_chat_palette.dart';
import '../../hermes/widgets/hermez_relative_time.dart';
import '../../hermes/widgets/hermez_surfaces.dart';
import '../models/spaces_models.dart';
import '../providers/spaces_providers.dart';
import '../services/hermes_spaces_client.dart';
import '../widgets/spaces_state_views.dart';

final _spaceProvider = FutureProvider.autoDispose.family<HermesSpace, String>((
  ref,
  spaceId,
) async {
  final client = ref.watch(hermesSpacesClientProvider);
  if (client == null) throw const SpacesUnavailable();
  return client.space(spaceId);
});

enum _SpaceAction { sortRecent, sortName, rename, delete }

/// The Pages of one Space, newest first, with search.
class SpaceLibraryPage extends ConsumerStatefulWidget {
  const SpaceLibraryPage({super.key, required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<SpaceLibraryPage> createState() => _SpaceLibraryPageState();
}

class _SpaceLibraryPageState extends ConsumerState<SpaceLibraryPage> {
  final _search = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  bool _byName = false;
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: _refresh,
  );

  SpacePagesQuery get _pagesQuery =>
      (spaceId: widget.spaceId, query: _query, byName: _byName);

  @override
  void initState() {
    super.initState();
    _lifecycle; // start listening
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(spacePagesProvider(_pagesQuery));
    ref.invalidate(_spaceProvider(widget.spaceId));
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _openPage(String pageId) async {
    await context.pushNamed(
      RouteNames.spacePage,
      pathParameters: {'spaceId': widget.spaceId, 'pageId': pageId},
    );
    _refresh();
  }

  Future<void> _createPage() async {
    final client = ref.read(hermesSpacesClientProvider);
    if (client == null) return;
    final title = await ThemedDialogs.promptTextInput(
      context,
      title: 'New Page',
      hintText: 'Title',
      confirmText: 'Create',
      maxLength: SpacesLimits.pageTitle,
    );
    if (title == null || title.trim().isEmpty || !mounted) return;
    try {
      final page = await client.createPage(widget.spaceId, title: title.trim());
      ref.invalidate(spacesListProvider);
      await _openPage(page.id);
    } on SpacesApiException catch (error) {
      if (mounted) showSpacesError(context, error.message);
    }
  }

  Future<void> _onAction(_SpaceAction action, HermesSpace? space) async {
    final client = ref.read(hermesSpacesClientProvider);
    if (client == null) return;
    switch (action) {
      case _SpaceAction.sortRecent:
        setState(() => _byName = false);
      case _SpaceAction.sortName:
        setState(() => _byName = true);
      case _SpaceAction.rename:
        final name = await ThemedDialogs.promptTextInput(
          context,
          title: 'Rename Space',
          hintText: 'Name',
          initialValue: space?.name,
          maxLength: SpacesLimits.spaceName,
        );
        if (name == null || name.trim().isEmpty || !mounted) return;
        try {
          await client.renameSpace(widget.spaceId, name.trim());
          _refresh();
          ref.invalidate(spacesListProvider);
        } on SpacesApiException catch (error) {
          if (mounted) showSpacesError(context, error.message);
        }
      case _SpaceAction.delete:
        final count = space?.pageCount ?? 0;
        final confirmed = await ThemedDialogs.confirm(
          context,
          title: 'Delete ${space?.name ?? 'this Space'}?',
          message: count == 0
              ? 'This Space is empty.'
              : 'This permanently deletes the Space and its $count '
                    '${count == 1 ? 'Page' : 'Pages'}. This cannot be undone.',
          confirmText: 'Delete',
          isDestructive: true,
        );
        if (!confirmed || !mounted) return;
        try {
          await client.deleteSpace(widget.spaceId, cascade: count > 0);
          ref.invalidate(spacesListProvider);
          if (mounted) context.pop();
        } on SpacesApiException catch (error) {
          if (mounted) showSpacesError(context, error.message);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(_spaceProvider(widget.spaceId)).value;
    final pages = ref.watch(spacePagesProvider(_pagesQuery));
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final count = space?.pageCount;
    return HermesPageChrome(
      title: space?.name ?? 'Space',
      subtitle: count == null
          ? 'Pages'
          : '$count ${count == 1 ? 'page' : 'pages'}',
      actions: [
        IconButton(
          tooltip: 'New Page',
          onPressed: _createPage,
          icon: const Icon(Icons.note_add_outlined),
        ),
        PopupMenuButton<_SpaceAction>(
          tooltip: 'Space options',
          onSelected: (action) => _onAction(action, space),
          itemBuilder: (context) => [
            CheckedPopupMenuItem(
              value: _SpaceAction.sortRecent,
              checked: !_byName,
              child: const Text('Recently updated'),
            ),
            CheckedPopupMenuItem(
              value: _SpaceAction.sortName,
              checked: _byName,
              child: const Text('Name'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _SpaceAction.rename,
              child: Text('Rename Space'),
            ),
            const PopupMenuItem(
              value: _SpaceAction.delete,
              child: Text('Delete Space'),
            ),
          ],
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search pages…',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                fillColor: palette.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.border),
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: switch (pages) {
                AsyncValue(:final value?) when value.isEmpty =>
                  _query.isNotEmpty
                      ? const SpacesEmptyState(
                          title: 'No matching Pages',
                          message: 'Try a different word.',
                        )
                      : SpacesEmptyState(
                          title: 'No Pages yet',
                          message:
                              'Write something here, or ask Hermes to turn a '
                              'conversation into a Page.',
                          actionLabel: 'New Page',
                          onAction: _createPage,
                        ),
                AsyncValue(:final value?) => _PageList(
                  pages: value,
                  palette: palette,
                  onOpen: _openPage,
                ),
                AsyncValue(:final error?) => SpacesErrorState(
                  error: error,
                  onRetry: _refresh,
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

class _PageList extends StatelessWidget {
  const _PageList({
    required this.pages,
    required this.palette,
    required this.onOpen,
  });

  final List<HermesPageSummary> pages;
  final HermezChatPalette palette;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final titles = {for (final page in pages) page.id: page.title};
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 96),
      itemCount: pages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final page = pages[index];
        final parent = page.parentId == null ? null : titles[page.parentId];
        final meta = [
          hermezRelativeLabel(page.updatedAt),
          if (parent != null) 'in $parent',
          if (page.childCount > 0)
            '${page.childCount} ${page.childCount == 1 ? 'subpage' : 'subpages'}',
        ].join(' · ');
        return HermezSurface(
          kind: HermezSurfaceKind.list,
          semanticLabel: page.title,
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          onTap: () => onOpen(page.id),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      page.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HermezType.body(palette)
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (page.excerpt.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        page.excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HermezType.meta(palette),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(meta, style: HermezType.technical(palette.muted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.muted),
            ],
          ),
        );
      },
    );
  }
}
