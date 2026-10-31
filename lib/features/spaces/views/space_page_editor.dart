import 'dart:async';

import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../../../shared/widgets/platform_ui/platform_ui.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../notes/views/note_editor_page.dart'
    show buildNoteEditorFleatherTheme;
import '../../hermes/widgets/hermez_chat_palette.dart';
import '../../hermes/widgets/hermez_surfaces.dart';
import '../../hermes/views/hermes_page_chrome.dart' show HermesPanel;
import '../models/spaces_models.dart';
import '../providers/spaces_providers.dart';
import '../services/hermes_spaces_client.dart';
import '../services/page_chat_launcher.dart';
import '../services/page_draft_controller.dart';
import '../utils/page_document_codec.dart';
import '../../hermes/providers/hermes_providers.dart';
import '../widgets/page_autosave_status.dart';
import '../widgets/page_chat_picker_sheet.dart';
import '../widgets/page_conflict_banner.dart';
import '../widgets/page_move_sheet.dart';
import '../../hermes/views/hermes_sky_sheet_page.dart';
import '../widgets/spaces_state_views.dart';
import '../../hermes/widgets/hermez_status_morph.dart';

enum _PageAction { subpage, move, source, visual, copy, delete }

/// One Page: title, Markdown body (visual or source), autosave, conflicts,
/// and "Ask Hermes" into a Page conversation with any Hermes profile.
class SpacePageEditorPage extends ConsumerStatefulWidget {
  const SpacePageEditorPage({
    super.key,
    required this.spaceId,
    required this.pageId,
  });

  final String spaceId;
  final String pageId;

  @override
  ConsumerState<SpacePageEditorPage> createState() =>
      _SpacePageEditorPageState();
}

class _SpacePageEditorPageState extends ConsumerState<SpacePageEditorPage> {
  final _title = TextEditingController();
  final _source = TextEditingController();
  final _bodyFocus = FocusNode();
  final _sourceFocus = FocusNode();
  final _scroll = ScrollController();
  FleatherController? _visual;
  StreamSubscription<Object?>? _visualChanges;
  PageDraftController? _draft;
  Object? _loadError;
  bool _sourceMode = false;
  String? _sourceReason;
  bool _asking = false;
  bool _leaving = false;
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: _refreshFromServer,
    onInactive: () => unawaited(_draft?.flush()),
  );

  HermesSpacesClient? get _client => ref.read(hermesSpacesClientProvider);

  @override
  void initState() {
    super.initState();
    _lifecycle;
    _bodyFocus.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _visualChanges?.cancel();
    _visual?.dispose();
    _draft?.dispose();
    _title.dispose();
    _source.dispose();
    _bodyFocus.dispose();
    _sourceFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) {
      setState(() => _loadError = const SpacesUnavailable());
      return;
    }
    try {
      final page = await client.page(widget.pageId);
      if (!mounted) return;
      _install(page);
      setState(() {
        _loadError = null;
        _draft = PageDraftController(
          client: client,
          page: page,
          readMarkdown: _currentMarkdown,
          readTitle: () => _title.text,
        )..addListener(_onDraftChanged);
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// Puts [page] into the editors, choosing visual or source mode.
  void _install(HermesPage page) {
    _title.text = page.title;
    _sourceReason = sourceModeReason(page.content);
    _sourceMode = _sourceReason != null || _sourceMode;
    _visualChanges?.cancel();
    _visual?.dispose();
    _visual = null;
    if (_sourceMode) {
      _source.text = page.content;
    } else {
      final controller = FleatherController(
        document: pageDocumentFromMarkdown(page.content),
      );
      _visualChanges = controller.document.changes.listen((_) => _edited());
      _visual = controller;
    }
  }

  String _currentMarkdown() {
    final visual = _visual;
    if (!_sourceMode && visual != null) {
      return pageMarkdownFromDocument(visual.document);
    }
    return _source.text;
  }

  void _edited() => _draft?.markEdited();

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshFromServer() async {
    final draft = _draft;
    if (draft == null || !mounted) return;
    final latest = await draft.refreshFromServer();
    if (latest != null && mounted) setState(() => _install(latest));
  }

  // -- leaving ---------------------------------------------------------------

  Future<void> _leave() async {
    if (_leaving) return;
    final draft = _draft;
    if (draft == null) {
      if (mounted) context.pop();
      return;
    }
    _leaving = true;
    final saved = await draft.flush();
    _leaving = false;
    if (!mounted) return;
    if (saved) {
      context.pop();
      return;
    }
    if (draft.status == PageSaveStatus.conflict) {
      showSpacesError(context, 'Resolve the conflict before leaving.');
      return;
    }
    final leave = await ThemedDialogs.confirm(
      context,
      title: 'Leave without saving?',
      message:
          '${draft.errorMessage ?? 'Your latest changes are not saved.'} '
          'Copy them first if you want to keep them.',
      confirmText: 'Leave',
      cancelText: 'Stay',
      isDestructive: true,
    );
    if (leave && mounted) context.pop();
  }

  // -- ask -------------------------------------------------------------------

  Future<void> _ask() async {
    final draft = _draft;
    if (draft == null || _asking) return;
    setState(() => _asking = true);
    try {
      if (!await draft.flush()) {
        if (mounted) {
          showSpacesError(
            context,
            draft.status == PageSaveStatus.conflict
                ? 'Resolve the conflict first, so Hermes reads the right version.'
                : 'Save the Page first: ${draft.errorMessage ?? 'it has unsaved changes.'}',
          );
        }
        return;
      }
      if (!mounted) return;
      final client = _client;
      if (client == null) return;
      final bots = await ref.read(hermesBotsProvider.future);
      if (bots.isEmpty) {
        throw const PageChatUnavailable('No Hermes profile is available.');
      }
      final chats = await client.pageChats(draft.page.id);
      if (!mounted) return;
      final bot = bots.length == 1
          ? bots.single
          : await showPageChatPicker(
              context,
              pageTitle: draft.page.title,
              bots: bots,
              chats: chats,
            );
      if (bot == null || !mounted) return;
      await openPageChat(context, ref, page: draft.page, bot: bot);
    } on PageChatUnavailable catch (error) {
      if (mounted) showSpacesError(context, error.message);
    } catch (_) {
      if (mounted) {
        showSpacesError(context, 'Could not open the Page conversation.');
      }
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  // -- actions ---------------------------------------------------------------

  Future<void> _onAction(_PageAction action) async {
    final draft = _draft;
    final client = _client;
    if (draft == null || client == null) return;
    switch (action) {
      case _PageAction.subpage:
        final title = await ThemedDialogs.promptTextInput(
          context,
          title: 'New subpage',
          hintText: 'Title',
          confirmText: 'Create',
          maxLength: SpacesLimits.pageTitle,
        );
        if (title == null || title.trim().isEmpty || !mounted) return;
        try {
          final child = await client.createPage(
            widget.spaceId,
            title: title.trim(),
            parentId: draft.page.id,
          );
          if (!mounted) return;
          await draft.flush();
          if (!mounted) return;
          context.pushReplacementNamed(
            RouteNames.spacePage,
            pathParameters: {'spaceId': widget.spaceId, 'pageId': child.id},
          );
        } on SpacesApiException catch (error) {
          if (mounted) showSpacesError(context, error.message);
        }
      case _PageAction.move:
        if (!await draft.flush()) {
          if (mounted) {
            showSpacesError(context, 'Save the Page before moving it.');
          }
          return;
        }
        if (!mounted) return;
        final target = await showPageMoveSheet(
          context,
          client: client,
          page: draft.page,
        );
        if (target == null || !mounted) return;
        try {
          final moved = await client.updatePage(
            draft.page.id,
            expectedRevision: draft.savedRevision,
            parentId: target,
          );
          draft.adoptSaved(moved);
        } on SpacesRevisionConflict {
          await _refreshFromServer();
          if (mounted) showSpacesError(context, 'The Page changed. Try again.');
        } on SpacesApiException catch (error) {
          if (mounted) showSpacesError(context, error.message);
        }
      case _PageAction.source:
        final markdown = _currentMarkdown();
        _visualChanges?.cancel();
        _visual?.dispose();
        setState(() {
          _visual = null;
          _source.text = markdown;
          _sourceMode = true;
        });
      case _PageAction.visual:
        final reason = sourceModeReason(_source.text);
        if (reason != null) {
          showSpacesError(
            context,
            'This Page uses $reason, which the visual editor would lose.',
          );
          return;
        }
        final controller = FleatherController(
          document: pageDocumentFromMarkdown(_source.text),
        );
        _visualChanges = controller.document.changes.listen((_) => _edited());
        setState(() {
          _visual = controller;
          _sourceMode = false;
          _sourceReason = null;
        });
      case _PageAction.copy:
        await Clipboard.setData(ClipboardData(text: _currentMarkdown()));
        if (mounted) showSpacesError(context, 'Markdown copied.');
      case _PageAction.delete:
        final confirmed = await ThemedDialogs.confirm(
          context,
          title: 'Delete "${draft.page.title}"?',
          message: 'This permanently deletes the Page. This cannot be undone.',
          confirmText: 'Delete',
          isDestructive: true,
        );
        if (!confirmed || !mounted) return;
        try {
          await client.deletePage(draft.page.id);
          ref.invalidate(spacesListProvider);
          draft.removeListener(_onDraftChanged);
          if (mounted) context.pop();
        } on SpacesApiException catch (error) {
          if (mounted) showSpacesError(context, error.message);
        }
    }
  }

  // -- conflict --------------------------------------------------------------

  Future<void> _reviewLatest() async {
    final remote = _draft?.remote;
    if (remote == null) return;
    await showPageVersionSheet(context, page: remote);
  }

  Future<void> _keepMine() async {
    final draft = _draft;
    if (draft == null) return;
    final confirmed = await ThemedDialogs.confirm(
      context,
      title: 'Keep your draft?',
      message:
          'Your draft replaces the newer version saved elsewhere. Review it '
          'first if you are not sure.',
      confirmText: 'Keep my draft',
      isDestructive: true,
    );
    if (confirmed) await draft.keepMine();
  }

  Future<void> _useLatest() async {
    final draft = _draft;
    if (draft == null) return;
    final confirmed = await ThemedDialogs.confirm(
      context,
      title: 'Use the latest version?',
      message:
          'Your draft is replaced by the newer version. Copy your draft '
          'first if you want to keep any of it.',
      confirmText: 'Use latest',
      isDestructive: true,
    );
    if (!confirmed) return;
    final latest = await draft.useLatest();
    if (latest != null && mounted) setState(() => _install(latest));
  }

  Future<void> _copyDraft() async {
    await Clipboard.setData(
      ClipboardData(text: '# ${_title.text}\n\n${_currentMarkdown()}'),
    );
    if (mounted) showSpacesError(context, 'Draft copied.');
  }

  // -- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final draft = _draft;
    // From the Spaces list when it is already loaded; no line otherwise.
    final spaceName = ref
        .watch(spacesListProvider)
        .value
        ?.where((space) => space.id == widget.spaceId)
        .firstOrNull
        ?.name;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: SkySheetPage(
        onBack: _leave,
        // White, the page to write on (s06); the list pages use the canvas.
        sheetColor: palette.raised,
        toolbarTitle: draft == null
            ? const SizedBox.shrink()
            : PageAutosaveStatus(
                status: draft.status,
                revision: draft.savedRevision,
                spaceName: spaceName,
              ),
        actions: [
          if (draft != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _AskHermesPill(busy: _asking, onPressed: _ask),
            ),
          if (draft != null)
            // The ⋯ grows into its menu card.
            AdaptivePopupMenuButton.icon<_PageAction>(
              icon: Icons.more_vert_rounded,
              tooltip: 'Page options',
              tint: Colors.white,
              buttonStyle: PopupButtonStyle.plain,
              onSelected: (_, entry) => _onAction(entry.value!),
              items: [
                const AdaptivePopupMenuItem(
                  value: _PageAction.subpage,
                  icon: Icons.note_add_outlined,
                  label: 'New subpage',
                ),
                const AdaptivePopupMenuItem(
                  value: _PageAction.move,
                  icon: Icons.drive_file_move_outlined,
                  label: 'Move page',
                ),
                if (_sourceMode)
                  const AdaptivePopupMenuItem(
                    value: _PageAction.visual,
                    icon: Icons.edit_note_rounded,
                    label: 'Visual editor',
                  )
                else
                  const AdaptivePopupMenuItem(
                    value: _PageAction.source,
                    icon: Icons.code_rounded,
                    label: 'Markdown source',
                  ),
                const AdaptivePopupMenuItem(
                  value: _PageAction.copy,
                  icon: Icons.content_copy_rounded,
                  label: 'Copy Markdown',
                ),
                const AdaptivePopupMenuDivider(),
                const AdaptivePopupMenuItem(
                  value: _PageAction.delete,
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete page',
                  isDestructive: true,
                ),
              ],
            ),
        ],
        child: _body(context, palette, draft),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    HermezChatPalette palette,
    PageDraftController? draft,
  ) {
    if (_loadError != null) {
      return SpacesErrorState(
        error: _loadError!,
        onRetry: () {
          setState(() => _loadError = null);
          unawaited(_load());
        },
      );
    }
    if (draft == null) return const SpacesLoadingState();
    final visual = _visual;
    final showToolbar = !_sourceMode && visual != null && _bodyFocus.hasFocus;
    return Column(
      children: [
        if (draft.status == PageSaveStatus.conflict)
          PageConflictBanner(
            remoteRevision: draft.remote?.revision,
            onReview: _reviewLatest,
            onKeepMine: _keepMine,
            onUseLatest: _useLatest,
            onCopyDraft: _copyDraft,
          ),
        if (draft.status == PageSaveStatus.error)
          MaterialBanner(
            content: Text(draft.errorMessage ?? 'Could not save.'),
            actions: [
              TextButton(
                onPressed: () => unawaited(draft.save()),
                child: const Text('Retry'),
              ),
            ],
          ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 120),
            children: [
              TextField(
                controller: _title,
                onChanged: (_) => _edited(),
                maxLength: SpacesLimits.pageTitle,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                style: skyText(
                  30,
                  FontWeight.w600,
                  palette.ink,
                ).copyWith(letterSpacing: -1.2, height: 1.1),
                decoration: const InputDecoration(
                  hintText: 'Untitled',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  counterText: '',
                  isCollapsed: true,
                ),
              ),
              const SizedBox(height: 14),
              if (_sourceMode && _sourceReason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: HermesPanel(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Source mode. This Page contains Markdown ($_sourceReason) '
                      'that the visual editor cannot preserve safely.',
                      style: HermezType.meta(palette),
                    ),
                  ),
                ),
              if (_sourceMode)
                TextField(
                  controller: _source,
                  focusNode: _sourceFocus,
                  onChanged: (_) => _edited(),
                  maxLines: null,
                  minLines: 12,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    height: 1.5,
                    color: palette.ink,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: 'Write Markdown…',
                  ),
                )
              else if (visual != null)
                Stack(
                  children: [
                    // Fleather has no placeholder of its own.
                    if (visual.document.toPlainText().trim().isEmpty)
                      Positioned(
                        left: 0,
                        top: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Text(
                            'Write here, or tap Ask Hermes to work on it together.',
                            style: HermezType.body(palette)
                                .copyWith(color: palette.muted),
                          ),
                        ),
                      ),
                    FleatherTheme(
                      data: buildNoteEditorFleatherTheme(context),
                      child: FleatherEditor(
                        controller: visual,
                        focusNode: _bodyFocus,
                        scrollController: _scroll,
                        scrollable: false,
                        expands: false,
                        padding: EdgeInsets.zero,
                        minHeight: 280,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (showToolbar)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.raised,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: palette.border),
                  boxShadow: [
                    BoxShadow(
                      color: palette.ink.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Theme(
                    // The buttons fill with the canvas colour: the pill's.
                    data: Theme.of(context)
                        .copyWith(canvasColor: palette.raised),
                    child: FleatherTheme(
                      data: buildNoteEditorFleatherTheme(context),
                      // Only formatting that survives the Markdown round trip.
                      child: FleatherToolbar.basic(
                        controller: visual,
                        hideUnderLineButton: true,
                        hideBackgroundColor: true,
                        hideForegroundColor: true,
                        hideAlignment: true,
                        hideIndentation: true,
                        hideDirection: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Ask Hermes as a white pill in the band; no sparkle (s06).
class _AskHermesPill extends StatelessWidget {
  const _AskHermesPill({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF0E1116);
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.8),
        disabledForegroundColor: ink,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: const StadiumBorder(),
        textStyle: skyText(14, FontWeight.w600, ink),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            const HermezStatusMorph(
              state: HermezMorphState.working,
              size: 16,
              tint: ink,
              ink: ink,
            ),
            const SizedBox(width: 8),
          ],
          const Text('Ask Hermes'),
        ],
      ),
    );
  }
}
