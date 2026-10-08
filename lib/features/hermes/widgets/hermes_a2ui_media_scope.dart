import 'package:flutter/material.dart';

import '../services/hermes_media_parser.dart';
import 'hermes_artifact_view.dart';

/// Optional previews of already-declared MEDIA artifacts from this message.
/// The parent owns the allowlist and authenticated downloader; arbitrary paths
/// in an A2UI object cannot create file access or external URL requests.
class HermesA2uiMediaScope extends InheritedWidget {
  const HermesA2uiMediaScope({
    super.key,
    required this.preview,
    required super.child,
  });
  final Widget Function(String path)? preview;
  static Widget image(BuildContext context, String path) =>
      context
          .dependOnInheritedWidgetOfExactType<HermesA2uiMediaScope>()
          ?.preview
          ?.call(path) ??
      const Text('Image preview unavailable: attach the image with MEDIA.');
  @override
  bool updateShouldNotify(HermesA2uiMediaScope oldWidget) =>
      preview != oldWidget.preview;
}

/// Exact membership in the message's parsed MEDIA image list is required.
/// Constructing a catalog object alone never grants access to a file.
Widget hermesDeclaredImagePreview(
  String path, {
  required Map<String, HermesMediaArtifact> declaredImages,
  String? sessionId,
}) {
  final artifact = declaredImages[path];
  if (artifact == null || artifact.kind != HermesMediaKind.image) {
    return const Text(
      'Image preview unavailable: attach this image with MEDIA.',
    );
  }
  return HermesArtifactView(artifact: artifact, sessionId: sessionId);
}
