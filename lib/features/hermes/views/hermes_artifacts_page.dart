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
import '../widgets/hermez_chat_palette.dart';
import 'hermes_page_chrome.dart';
import '../sheets/hermez_modal_sheet.dart';

const _artifactRoot = '/opt/data/artifacts';
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
  const HermesArtifactsPage({super.key});

  @override
  ConsumerState<HermesArtifactsPage> createState() =>
      _HermesArtifactsPageState();
}

class _HermesArtifactsPageState extends ConsumerState<HermesArtifactsPage> {
  String _filter = 'All';

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
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
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
          data: (all) {
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
                              if (session.id == provenance.sessionId)
                                related = session;
                            }
                            related ??= HermesSessionSummary(
                              id: provenance.sessionId,
                              title: 'Related conversation',
                            );
                          }
                          return _ArtifactTile(
                            file: file,
                            onTap: () async {
                              final selected =
                                  await showHermezSheet<HermesSessionSummary>(
                                    context,
                                    title: file.name,
                                    eyebrow: 'Artifact',
                                    body: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          file.name
                                              .split('.')
                                              .last
                                              .toUpperCase(),
                                        ),
                                        const SizedBox(height: 14),
                                        HermesArtifactView(
                                          artifact: _artifact(file),
                                          maxImageHeight: 480,
                                        ),
                                        const SizedBox(height: 14),
                                        HermesPanel(
                                          onTap: related == null
                                              ? null
                                              : () => Navigator.pop(
                                                  context,
                                                  related,
                                                ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  related == null
                                                      ? 'Source unavailable for this file.'
                                                      : 'Observed in ${related.title}',
                                                ),
                                              ),
                                              if (related != null)
                                                const Icon(
                                                  Icons.chevron_right_rounded,
                                                ),
                                            ],
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
  const _ArtifactTile({required this.file, required this.onTap});
  final HermesRemoteFile file;
  final VoidCallback onTap;

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
    return HermesPanel(
      onTap: onTap,
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
                    ? thumbnail.asData == null
                          ? const Icon(Icons.image_outlined, size: 32)
                          : Image.memory(
                              thumbnail.asData!.value.bytes,
                              fit: BoxFit.cover,
                              cacheWidth: 400,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.image_not_supported_outlined,
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
          Text(
            file.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            file.name.split('.').last.toUpperCase(),
            style: TextStyle(fontSize: 10, color: palette.muted),
          ),
        ],
      ),
    );
  }
}
