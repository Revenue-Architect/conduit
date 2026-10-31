import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/hermes_artifact_provider.dart';
import '../providers/hermes_providers.dart';
import '../models/hermes_config.dart';
import '../models/hermes_session.dart';
import '../services/hermes_artifact_provenance_store.dart';
import '../services/hermes_artifact_client.dart';
import '../services/hermes_media_parser.dart';
import '../widgets/hermes_artifact_view.dart';
import '../widgets/hermes_session_tile.dart' show openHermesSession;
import '../motion/hermez_motion.dart';
import '../widgets/hermez_chat_palette.dart';
import 'hermes_page_chrome.dart' show HermesPanel;
import '../../spaces/widgets/sky_sheet_page.dart';
import '../sheets/hermez_modal_sheet.dart';
import '../widgets/hermez_expandable_section.dart';
import '../feedback/hermez_feedback.dart';
import '../widgets/hermez_relative_time.dart';
import '../widgets/hermez_skeleton.dart';

const _artifactRoot = '/opt/data/artifacts';

/// A Kanban attachment is identified by the server's board-scoped id, not
/// its stored_path (which may be outside the general artifact directory).
final class HermesKanbanArtifactTarget {
  const HermesKanbanArtifactTarget({
    required this.board,
    required this.taskId,
    required this.attachmentId,
    required this.filename,
  });

  final String board;
  final String taskId;
  final int attachmentId;
  final String filename;

  static HermesKanbanArtifactTarget? fromAttachment({
    required String board,
    required String taskId,
    required Map<String, dynamic> attachment,
  }) {
    final rawId = attachment['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    final filename = attachment['filename'];
    if (id == null ||
        id <= 0 ||
        filename is! String ||
        filename.isEmpty ||
        filename.contains('/') ||
        filename.contains('\\')) {
      return null;
    }
    return HermesKanbanArtifactTarget(
      board: board,
      taskId: taskId,
      attachmentId: id,
      filename: filename,
    );
  }
}

final _artifactFilesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(hermesArtifactClientProvider).listDirectory(_artifactRoot),
);
final _thumbnailProvider = FutureProvider.autoDispose
    .family<HermesArtifactBytes, String>(
      (ref, path) => ref
          .watch(hermesArtifactClientProvider)
          .download(
            _artifact(HermesRemoteFile(name: path.split('/').last, path: path)),
          ),
    );

HermesMediaArtifact _artifact(HermesRemoteFile file) {
  final ext = file.name.split('.').last.toLowerCase();
  final kind = switch (ext) {
    'png' ||
    'jpg' ||
    'jpeg' ||
    'webp' ||
    'gif' ||
    'bmp' ||
    'tiff' ||
    'svg' => HermesMediaKind.image,
    'mp3' ||
    'm4a' ||
    'wav' ||
    'ogg' ||
    'opus' ||
    'flac' => HermesMediaKind.audio,
    'mp4' || 'mov' || 'webm' || 'mkv' => HermesMediaKind.video,
    _ => HermesMediaKind.file,
  };
  return HermesMediaArtifact(path: file.path, filename: file.name, kind: kind);
}

class HermesArtifactsPage extends ConsumerStatefulWidget {
  const HermesArtifactsPage({super.key, this.selectedKanbanAttachment});

  final HermesKanbanArtifactTarget? selectedKanbanAttachment;

  @override
  ConsumerState<HermesArtifactsPage> createState() =>
      _HermesArtifactsPageState();
}

class _HermesArtifactsPageState extends ConsumerState<HermesArtifactsPage> {
  String _filter = 'All';

  Widget _selectedAttachment() {
    final target = widget.selectedKanbanAttachment!;
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final artifact = _artifact(
      HermesRemoteFile(
        name: target.filename,
        path: 'kanban:${target.board}:${target.attachmentId}',
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: HermesPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'KANBAN / ATTACHMENT',
              style: TextStyle(
                color: palette.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              target.filename,
              style: TextStyle(
                color: palette.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.35,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${target.board}  /  ${target.taskId}',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            HermesArtifactView(
              artifact: artifact,
              maxImageHeight: 380,
              download: () => ref
                  .read(hermesArtifactClientProvider)
                  .downloadKanbanAttachment(
                    board: target.board,
                    attachmentId: target.attachmentId,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final files = ref.watch(_artifactFilesProvider);
    final sessions =
        ref.watch(hermesSessionsProvider).asData?.value ??
        const <HermesSessionSummary>[];
    final config = ref.watch(hermesConfigProvider);
    final endpoint = HermesConfig.connectionEndpoint(config.baseUrl);
    final identity = endpoint == null
        ? null
        : '$endpoint|${ref.read(hermesConfigProvider.notifier).documentTrustPrincipalId()}';
    return SkySheetPage(
      title: 'Artifacts',
      actions: [
        IconButton(
          tooltip: 'Refresh artifacts',
          onPressed: () => ref.invalidate(_artifactFilesProvider),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Files Hermes made for you',
                style: skyText(15, FontWeight.w400, palette.muted),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(_artifactFilesProvider);
                await ref.read(_artifactFilesProvider.future);
              },
              child: files.when(
                loading: () => ListView(
                  children: [
                    if (widget.selectedKanbanAttachment != null)
                      _selectedAttachment(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: HermezSkeleton.rows(count: 4),
                    ),
                  ],
                ),
                error: (error, _) => ListView(
                  children: [
                    if (widget.selectedKanbanAttachment != null)
                      _selectedAttachment(),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: HermesPanel(
                        child: Text(
                          error is HermesArtifactException &&
                                  error.kind ==
                                      HermesArtifactFailureKind.authExpired
                              ? 'Hermes sign-in has expired. Sign in and pull to retry.'
                              : 'Artifacts are unavailable. Pull to retry.',
                        ),
                      ),
                    ),
                  ],
                ),
                data: (listed) {
                  // Files Hermes produced in conversations live wherever that run
                  // wrote them, not only in the artifacts folder. Everything a
                  // chat has shown on this connection is listed too, newest first.
                  final listedPaths = {for (final file in listed) file.path};
                  final seen = <String>{};
                  final fromChats = identity == null
                      ? const <HermesRemoteFile>[]
                      : ([...HermesArtifactProvenanceStore.allFor(identity)]
                              ..sort(
                                (a, b) => b.observedAt.compareTo(a.observedAt),
                              ))
                            .where(
                              (record) =>
                                  !listedPaths.contains(record.path) &&
                                  seen.add(record.path),
                            )
                            .map(
                              (record) => HermesRemoteFile(
                                name: record.path.split('/').last,
                                path: record.path,
                              ),
                            )
                            .toList(growable: false);
                  final all = [...fromChats, ...listed];
                  final visible = all
                      .where((file) {
                        final kind = _artifact(file).kind;
                        return _filter == 'All' ||
                            _filter == 'Images' &&
                                kind == HermesMediaKind.image ||
                            _filter == 'Docs' && kind == HermesMediaKind.file ||
                            _filter == 'Media' &&
                                (kind == HermesMediaKind.audio ||
                                    kind == HermesMediaKind.video);
                      })
                      .toList(growable: false);
                  return CustomScrollView(
                    slivers: [
                      if (widget.selectedKanbanAttachment != null)
                        SliverToBoxAdapter(child: _selectedAttachment()),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final filter in const [
                                    'All',
                                    'Images',
                                    'Docs',
                                    'Media',
                                  ])
                                    ChoiceChip(
                                      label: Text(filter),
                                      selected: _filter == filter,
                                      showCheckmark: false,
                                      selectedColor: palette.ink,
                                      backgroundColor: palette.canvas,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 10,
                                      ),
                                      shape: StadiumBorder(
                                        side: BorderSide(
                                          color: _filter == filter
                                              ? palette.ink
                                              : palette.border,
                                        ),
                                      ),
                                      labelStyle: skyText(
                                        15,
                                        _filter == filter
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        _filter == filter
                                            ? palette.raised
                                            : palette.muted,
                                      ),
                                      onSelected: (_) =>
                                          setState(() => _filter = filter),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '${visible.length} '
                                '${visible.length == 1 ? 'file' : 'files'}',
                                style: skyText(
                                  13,
                                  FontWeight.w500,
                                  palette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (visible.isEmpty)
                        const SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverToBoxAdapter(
                            child: HermesPanel(
                              child: Text('No files in this category.'),
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 34),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.crossAxisExtent < 340
                                ? 1
                                : 2;
                            return SliverGrid.builder(
                              itemCount: visible.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 12,
                                    mainAxisExtent: 186,
                                  ),
                              itemBuilder: (context, index) {
                                final file = visible[index];
                                final provenance = identity == null
                                    ? null
                                    : HermesArtifactProvenanceStore.find(
                                        identity,
                                        file.path,
                                      );
                                HermesSessionSummary? related;
                                if (provenance != null) {
                                  for (final session in sessions) {
                                    if (session.id == provenance.sessionId) {
                                      related = session;
                                    }
                                  }
                                  related ??= HermesSessionSummary(
                                    id: provenance.sessionId,
                                    title: 'Related conversation',
                                  );
                                }
                                return _ArtifactTile(
                                  file: file,
                                  onOpen: (origin, bytes) async {
                                    final morphId = hermezArtifactMorphId(
                                      file.path,
                                    );
                                    if (bytes != null) {
                                      // Decode the full image before the flight so
                                      // the preview arrives painted, not loading.
                                      try {
                                        await precacheImage(
                                          MemoryImage(bytes.bytes),
                                          context,
                                        );
                                      } catch (_) {}
                                      if (!context.mounted) return;
                                    }
                                    final selected =
                                        await showHermezSheet<
                                          HermesSessionSummary
                                        >(
                                          context,
                                          fit: true,
                                          origin: origin,
                                          title: file.name,
                                          titleMorphId: hermezMorphPart(
                                            morphId,
                                            'name',
                                          ),
                                          leading: _ArtifactKindTile(
                                            file: file,
                                          ),
                                          subtitle: Text(
                                            '${file.name.split('.').last.toUpperCase()} · Hermes artifact',
                                            style: skyText(
                                              14,
                                              FontWeight.w400,
                                              palette.muted,
                                            ),
                                          ),
                                          body: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              HermesArtifactView(
                                                artifact: _artifact(file),
                                                maxImageHeight: 480,
                                                initialBytes: bytes,
                                                previewMorphId: bytes == null
                                                    ? null
                                                    : hermezMorphPart(
                                                        morphId,
                                                        'image',
                                                      ),
                                              ),
                                              if (provenance != null) ...[
                                                const SizedBox(height: 16),
                                                Divider(
                                                  height: 1,
                                                  color: palette.border,
                                                ),
                                                const SizedBox(height: 8),
                                                _ArtifactContext(
                                                  file: file,
                                                  provenance: provenance,
                                                  related: related,
                                                ),
                                              ],
                                              const SizedBox(height: 8),
                                              _RelatedConversation(
                                                related: related,
                                                onTap: related == null
                                                    ? null
                                                    : () => Navigator.pop(
                                                        context,
                                                        related,
                                                      ),
                                              ),
                                            ],
                                          ),
                                        );
                                    if (selected != null && context.mounted) {
                                      await openHermesSession(
                                        context,
                                        ref,
                                        selected,
                                      );
                                    }
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtifactTile extends ConsumerWidget {
  const _ArtifactTile({required this.file, required this.onOpen});
  final HermesRemoteFile file;
  final void Function(HermezMorphOrigin? origin, HermesArtifactBytes? bytes)
  onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artifact = _artifact(file);
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final thumbnail =
        artifact.kind == HermesMediaKind.image &&
            file.name.split('.').last.toLowerCase() != 'svg'
        ? ref.watch(_thumbnailProvider(file.path))
        : null;
    final bytes = thumbnail?.asData?.value;
    final morphId = hermezArtifactMorphId(file.path);
    return HermezMotionSurface(
      semanticLabel: file.name,
      originRadius: 20,
      originColor: palette.surface,
      originBorderColor: palette.border,
      onOpen: (origin) => onOpen(origin, bytes),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 112,
            width: double.infinity,
            child: IconTheme.merge(
              data: IconThemeData(color: palette.muted),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: palette.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(19),
                  child: thumbnail != null && bytes != null
                      ? HermezMorph(
                          id: hermezMorphPart(morphId, 'image'),
                          child: Image.memory(
                            bytes.bytes,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 112,
                            cacheWidth: 400,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) =>
                                _glyph(Icons.image_not_supported_outlined),
                          ),
                        )
                      : _glyph(
                          thumbnail != null
                              ? Icons.image_outlined
                              : _kindIcon(file),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: HermezMorphText(
              file.name,
              id: hermezMorphPart(morphId, 'name'),
              maxLines: 2,
              style: skyText(15, FontWeight.w600, palette.ink),
            ),
          ),
          Text(
            file.name.split('.').last.toUpperCase(),
            style: skyText(13, FontWeight.w400, palette.muted),
          ),
        ],
      ),
    );
  }

  Widget _glyph(IconData icon) => Center(child: Icon(icon, size: 30));
}

/// The glyph for a file with no thumbnail, by what kind of file it is.
IconData _kindIcon(HermesRemoteFile file) => switch (_artifact(file).kind) {
  HermesMediaKind.image => Icons.image_outlined,
  HermesMediaKind.audio => Icons.graphic_eq_rounded,
  HermesMediaKind.video => Icons.movie_outlined,
  _ => Icons.description_outlined,
};

/// The file-type tile beside an artifact's title in its sheet.
class _ArtifactKindTile extends StatelessWidget {
  const _ArtifactKindTile({required this.file});
  final HermesRemoteFile file;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(_kindIcon(file), color: palette.ink, size: 26),
    );
  }
}

/// File context, opened in place: only what this app already knows about the
/// file (its recorded source conversation, type, path, and when it was first
/// seen). No request is made for it. Shown only when provenance exists.
class _ArtifactContext extends StatefulWidget {
  const _ArtifactContext({
    required this.file,
    required this.provenance,
    required this.related,
  });

  final HermesRemoteFile file;
  final HermesArtifactProvenance provenance;
  final HermesSessionSummary? related;

  @override
  State<_ArtifactContext> createState() => _ArtifactContextState();
}

class _ArtifactContextState extends State<_ArtifactContext> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final related = widget.related;
    final name = widget.file.name;
    final type = name.contains('.') ? name.split('.').last.toUpperCase() : null;
    final rows = <(String, String)>[
      if (related?.profile != null && related!.profile!.isNotEmpty)
        ('Source', related.profile!),
      if (related != null) ('Conversation', related.title),
      if (type != null) ('Type', type),
      ('First seen', hermezRelativeLabel(widget.provenance.observedAt)),
      ('Saved at', widget.file.path),
    ];
    return HermezExpandableSection(
      expanded: _expanded,
      onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
      semanticLabel: 'File context',
      openFeedback: HermezFeedbackCue.compartmentOpen,
      closeFeedback: HermezFeedbackCue.compartmentClose,
      framed: false,
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
      childPadding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
      header: Text(
        'File context',
        style: skyText(17, FontWeight.w600, palette.ink),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(
                      label,
                      style: skyText(15, FontWeight.w400, palette.muted),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: skyText(16, FontWeight.w400, palette.ink),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The way back to the conversation that made the file; the card grows into
/// that chat. Without a recorded source it only says so.
class _RelatedConversation extends StatelessWidget {
  const _RelatedConversation({required this.related, required this.onTap});

  final HermesSessionSummary? related;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: palette.ink,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      related == null
                          ? 'Source unavailable'
                          : 'Related conversation',
                      style: skyText(17, FontWeight.w600, palette.ink),
                    ),
                    Text(
                      related == null
                          ? 'Hermes did not record where this file came from.'
                          : related!.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: skyText(14.5, FontWeight.w400, palette.muted),
                    ),
                  ],
                ),
              ),
              if (related != null)
                Icon(Icons.chevron_right_rounded, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}
