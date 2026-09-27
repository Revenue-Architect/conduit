import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/hermes_artifact_provider.dart';
import '../services/hermes_artifact_client.dart';
import '../services/hermes_media_parser.dart';

class HermesArtifactView extends ConsumerStatefulWidget {
  const HermesArtifactView({
    super.key,
    required this.artifact,
    this.sessionId,
    this.maxImageHeight = 340,
    this.download,
  });

  final HermesMediaArtifact artifact;
  final String? sessionId;
  final double maxImageHeight;

  /// Overrides the filesystem route for server-owned artifacts such as
  /// Kanban attachments, which are downloaded by board and attachment id.
  final Future<HermesArtifactBytes> Function()? download;

  @override
  ConsumerState<HermesArtifactView> createState() => _HermesArtifactViewState();
}

class _HermesArtifactViewState extends ConsumerState<HermesArtifactView> {
  Future<HermesArtifactBytes>? _imageDownload;
  bool _isActionInProgress = false;
  String? _actionError;

  bool get _isImage => widget.artifact.kind == HermesMediaKind.image;

  @override
  void initState() {
    super.initState();
    if (_isImage) _imageDownload = _download();
  }

  @override
  void didUpdateWidget(covariant HermesArtifactView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artifact.path != widget.artifact.path ||
        oldWidget.sessionId != widget.sessionId ||
        oldWidget.artifact.kind != widget.artifact.kind) {
      _actionError = null;
      _isActionInProgress = false;
      _imageDownload = _isImage ? _download() : null;
    }
  }

  Future<HermesArtifactBytes> _download() =>
      widget.download?.call() ??
      ref
          .read(hermesArtifactClientProvider)
          .download(widget.artifact, sessionId: widget.sessionId);

  @override
  Widget build(BuildContext context) =>
      _isImage ? _buildImagePreview() : _buildFileCard(context);

  Widget _buildImagePreview() => FutureBuilder<HermesArtifactBytes>(
    future: _imageDownload,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return _imageFrame(context, _loadingPreview(context));
      }
      if (snapshot.hasError || snapshot.data == null) {
        return _imageFrame(
          context,
          _imageErrorPreview(context, snapshot.error),
        );
      }

      final bytes = snapshot.data!.bytes;
      final image = _extension == 'svg'
          ? SvgPicture.memory(
              bytes,
              width: double.infinity,
              height: widget.maxImageHeight,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _imageErrorPreview(
                context,
                const HermesArtifactException(
                  HermesArtifactFailureKind.unavailable,
                ),
              ),
            )
          : Image.memory(
              bytes,
              width: double.infinity,
              height: widget.maxImageHeight,
              fit: BoxFit.contain,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) return child;
                return _loadingPreview(context);
              },
              errorBuilder: (_, _, _) => _imageErrorPreview(
                context,
                const HermesArtifactException(
                  HermesArtifactFailureKind.unavailable,
                ),
              ),
            );
      return Column(
        children: [
          _imageFrame(
            context,
            InteractiveViewer(minScale: 1, maxScale: 5, child: image),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _isActionInProgress
                    ? null
                    : () => _runAction(open: true),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open'),
              ),
              TextButton.icon(
                onPressed: _isActionInProgress
                    ? null
                    : () => _runAction(open: false),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Share'),
              ),
            ],
          ),
          if (_actionError != null)
            Text(
              _actionError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      );
    },
  );

  Widget _imageFrame(BuildContext context, Widget child) => Container(
    width: double.infinity,
    constraints: BoxConstraints(maxHeight: widget.maxImageHeight + 20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _loadingPreview(BuildContext context) => SizedBox(
    height: 240,
    child: Center(
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  Widget _imageErrorPreview(BuildContext context, Object? error) => SizedBox(
    height: 180,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              _friendlyError(error),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton.icon(
              onPressed: () => setState(() => _imageDownload = _download()),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildFileCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final extensionLabel = _extension.isEmpty
        ? 'FILE'
        : _extension.toUpperCase();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_fileIcon, size: 30, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.artifact.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      extensionLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isActionInProgress)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _isActionInProgress
                    ? null
                    : () => _runAction(open: true),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open'),
              ),
              TextButton.icon(
                onPressed: _isActionInProgress
                    ? null
                    : () => _runAction(open: false),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Share'),
              ),
            ],
          ),
          if (_actionError != null) ...[
            const SizedBox(height: 4),
            Text(
              _actionError!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _runAction({required bool open}) async {
    setState(() {
      _isActionInProgress = true;
      _actionError = null;
    });
    try {
      // Non-image data is fetched only after the user asks to open or share it.
      final result = await _download();
      if (!mounted) return;
      final directory = await getTemporaryDirectory();
      final safeName = _safeLocalFilename(widget.artifact.filename);
      final localPath = p.join(
        directory.path,
        'hermes_${DateTime.now().microsecondsSinceEpoch}_$safeName',
      );
      await File(localPath).writeAsBytes(result.bytes, flush: true);
      if (!mounted) return;

      if (open) {
        final openResult = await OpenFilex.open(localPath);
        if (openResult.type != ResultType.done) {
          throw _ArtifactActionException(openResult.type);
        }
      } else {
        final renderObject = context.findRenderObject();
        final sharePositionOrigin =
            renderObject is RenderBox && renderObject.hasSize
            ? renderObject.localToGlobal(Offset.zero) & renderObject.size
            : null;
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile(
                localPath,
                name: widget.artifact.filename,
                mimeType: _mimeType(result.contentType),
              ),
            ],
            sharePositionOrigin: sharePositionOrigin,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _actionError = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  String get _extension {
    final dot = widget.artifact.filename.lastIndexOf('.');
    return dot < 0
        ? ''
        : widget.artifact.filename.substring(dot + 1).toLowerCase();
  }

  IconData get _fileIcon => switch (widget.artifact.kind) {
    HermesMediaKind.audio => Icons.audio_file_outlined,
    HermesMediaKind.video => Icons.video_file_outlined,
    HermesMediaKind.image => Icons.image_outlined,
    HermesMediaKind.file => switch (_extension) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'xls' || 'xlsx' || 'ods' || 'csv' || 'tsv' => Icons.table_chart_outlined,
      'zip' ||
      'tar' ||
      'gz' ||
      'tgz' ||
      '7z' ||
      'rar' => Icons.archive_outlined,
      _ => Icons.insert_drive_file_outlined,
    },
  };

  static String _safeLocalFilename(String filename) {
    final basename = p.basename(filename);
    final safe = basename.replaceAll(RegExp(r'[\u0000-\u001f<>:"/\\|?*]'), '_');
    return safe.isEmpty ? 'artifact' : safe;
  }

  static String? _mimeType(String? value) {
    final mime = value?.split(';').first.trim();
    return mime == null || mime.isEmpty ? null : mime;
  }

  static String _friendlyError(Object? error) {
    if (error is HermesArtifactException) {
      return switch (error.kind) {
        HermesArtifactFailureKind.authExpired =>
          'Hermes sign-in expired. Sign in and try again.',
        HermesArtifactFailureKind.missing =>
          'This file is no longer available.',
        HermesArtifactFailureKind.unavailable =>
          'Unable to load this file from Hermes.',
      };
    }
    if (error is _ArtifactActionException) {
      return switch (error.resultType) {
        ResultType.noAppToOpen => 'No app on this device can open this file.',
        ResultType.fileNotFound =>
          'The downloaded file is missing. Try downloading it again.',
        ResultType.permissionDenied =>
          'This device denied access to the downloaded file.',
        ResultType.error || ResultType.done => 'Unable to open this file.',
      };
    }
    return 'Unable to open or share this file.';
  }
}

final class _ArtifactActionException implements Exception {
  const _ArtifactActionException(this.resultType);

  final ResultType resultType;
}
