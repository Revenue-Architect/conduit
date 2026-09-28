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
import '../widgets/hermez_sheet_parts.dart';
import '../widgets/hermez_technical_background.dart';
import 'hermes_page_chrome.dart';
import '../sheets/hermez_modal_sheet.dart';

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
        backgroundVariant: HermezBackgroundVariant.editorial,
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
    return HermesPageChrome(
      title: 'Artifacts',
      subtitle: 'Files Hermes made for you.',
      actions: [
        IconButton(
          tooltip: 'Refresh artifacts',
          onPressed: () => ref.invalidate(_artifactFilesProvider),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
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
              const Center(child: CircularProgressIndicator()),
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
                            error.kind == HermesArtifactFailureKind.authExpired
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
                        ..sort((a, b) => b.observedAt.compareTo(a.observedAt)))
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
                      _filter == 'Images' && kind == HermesMediaKind.image ||
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
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 9),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 7,
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
                                selectedColor: palette.ink,
                                labelStyle: TextStyle(
                                  color: _filter == filter
                                      ? palette.surface
                                      : palette.ink,
                                ),
                                onSelected: (_) =>
                                    setState(() => _filter = filter),
                              ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Text(
                          '${visible.length} files in artifacts',
                          style: TextStyle(fontSize: 11, color: palette.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  const SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    sliver: SliverToBoxAdapter(
                      child: HermesPanel(
                        child: Text('No files in this category.'),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 34),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.crossAxisExtent < 340 ? 1 : 2;
                      return SliverGrid.builder(
                        itemCount: visible.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 9,
                          crossAxisSpacing: 9,
                          mainAxisExtent: 190,
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
                              final morphId = hermezArtifactMorphId(file.path);
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
                                  await showHermezSheet<HermesSessionSummary>(
                                    context,
                                    origin: origin,
                                    title: file.name,
                                    titleMorphId: hermezMorphPart(
                                      morphId,
                                      'name',
                                    ),
                                    eyebrow: 'Artifact',
                                    leading: _ArtifactKindTile(file: file),
                                    subtitle: Text(
                                      '${file.name.split('.').last.toUpperCase()} · Hermes artifact',
                                      style: TextStyle(
                                        color: palette.muted,
                                        fontSize: 13,
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
                                        const SizedBox(height: 14),
                                        HermezActionTile(
                                          icon: Icons.forum_outlined,
                                          title: related == null
                                              ? 'Source unavailable'
                                              : 'Related conversation',
                                          subtitle: related == null
                                              ? 'Hermes did not record where this file came from.'
                                              : related.title,
                                          showChevron: related != null,
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
                                await openHermesSession(context, ref, selected);
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
      originRadius: 19,
      originColor: palette.surface,
      originBorderColor: palette.border,
      onOpen: (origin) => onOpen(origin, bytes),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: palette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 116,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: palette.canvas,
                    child: thumbnail != null
                        ? bytes == null
                              ? const Icon(Icons.image_outlined, size: 32)
                              : HermezMorph(
                                  id: hermezMorphPart(morphId, 'image'),
                                  child: Image.memory(
                                    bytes.bytes,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: 116,
                                    cacheWidth: 400,
                                    gaplessPlayback: true,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.image_not_supported_outlined,
                                    ),
                                  ),
                                )
                        : Icon(
                            artifact.kind == HermesMediaKind.file
                                ? Icons.description_outlined
                                : Icons.perm_media_outlined,
                            size: 37,
                            color: palette.accent,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              HermezMorphText(
                file.name,
                id: hermezMorphPart(morphId, 'name'),
                maxLines: 2,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                file.name.split('.').last.toUpperCase(),
                style: TextStyle(fontSize: 10, color: palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The file-type tile beside an artifact's title in its sheet.
class _ArtifactKindTile extends StatelessWidget {
  const _ArtifactKindTile({required this.file});
  final HermesRemoteFile file;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final ext = file.name.split('.').last.toLowerCase();
    final kind = _artifact(file).kind;
    final (icon, color) = switch (kind) {
      _ when ext == 'pdf' => (
        Icons.picture_as_pdf_rounded,
        const Color(0xFFE5452B),
      ),
      HermesMediaKind.image => (Icons.image_outlined, palette.ink),
      HermesMediaKind.audio => (Icons.graphic_eq_rounded, palette.ink),
      HermesMediaKind.video => (Icons.movie_outlined, palette.ink),
      _ => (Icons.description_outlined, palette.ink),
    };
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border.withValues(alpha: 0.7)),
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}
