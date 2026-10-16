import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/hermes_openui_image_source.dart';

/// What the OpenUI image components need from their host. The defaults fetch
/// only the image; tests substitute [remoteImageProvider] so nothing touches
/// the network.
@immutable
class HermesOpenuiImageEnvironment {
  const HermesOpenuiImageEnvironment({
    this.remoteImageProvider,
    this.mediaPreview,
  });

  /// Provider for an http(s) image. Defaults to [HermesBoundedNetworkImage].
  final ImageProvider Function(String url)? remoteImageProvider;

  /// A preview of an image declared with MEDIA: in the same reply, or null
  /// when the path was not declared.
  final Widget? Function(String path)? mediaPreview;
}

@immutable
class HermesOpenuiImageSpec {
  const HermesOpenuiImageSpec({
    required this.src,
    this.alt = '',
    this.details = '',
  });

  final String src;
  final String alt;

  /// Optional description shown with the image (and in the viewer).
  final String details;
}

/// Fetches one image with a plain GET: no cookies, credentials or custom
/// headers. Refuses non-image responses, large bodies and slow servers.
Future<Uint8List> fetchHermesOpenuiImageBytes(
  Uri uri, {
  int maxBytes = 8 * 1024 * 1024,
  Duration timeout = const Duration(seconds: 20),
  HttpClient Function()? clientFactory,
}) async {
  final client = (clientFactory ?? HttpClient.new)()
    ..connectionTimeout = timeout;
  try {
    return await () async {
      final request = await client.getUrl(uri);
      request.maxRedirects = 3;
      request.headers.set(HttpHeaders.acceptHeader, 'image/*');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Image request failed: ${response.statusCode}');
      }
      final type = response.headers.contentType;
      if (type != null &&
          type.primaryType != 'image' &&
          type.mimeType != 'application/octet-stream') {
        throw const HttpException('The response is not an image.');
      }
      if (response.contentLength > maxBytes) {
        throw const HttpException('The image is too large.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) {
          throw const HttpException('The image is too large.');
        }
      }
      return bytes.takeBytes();
    }().timeout(timeout);
  } finally {
    client.close(force: true);
  }
}

/// A network image that sends no cookies or credentials, limits the download
/// and accepts only image responses. Used instead of the app's authenticated
/// image cache, whose requests may carry the Hermes connection's headers.
@immutable
class HermesBoundedNetworkImage
    extends ImageProvider<HermesBoundedNetworkImage> {
  const HermesBoundedNetworkImage(this.url);

  final String url;

  @override
  Future<HermesBoundedNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<HermesBoundedNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(
    HermesBoundedNetworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: () async {
      final bytes = await fetchHermesOpenuiImageBytes(Uri.parse(key.url));
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    }(),
    scale: 1,
    debugLabel: 'OpenUI image',
  );

  @override
  bool operator ==(Object other) =>
      other is HermesBoundedNetworkImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Opens [provider] in a local, zoomable full-screen viewer. Sends nothing.
Future<void> showHermesOpenuiImageViewer(
  BuildContext context, {
  required ImageProvider provider,
  required String alt,
  String details = '',
}) => Navigator.of(context, rootNavigator: true).push<void>(
  PageRouteBuilder<void>(
    opaque: true,
    pageBuilder: (context, _, _) =>
        _HermesOpenuiImageViewer(provider: provider, alt: alt, details: details),
    transitionsBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

class _HermesOpenuiImageViewer extends StatefulWidget {
  const _HermesOpenuiImageViewer({
    required this.provider,
    required this.alt,
    required this.details,
  });

  final ImageProvider provider;
  final String alt;
  final String details;

  @override
  State<_HermesOpenuiImageViewer> createState() =>
      _HermesOpenuiImageViewerState();
}

class _HermesOpenuiImageViewerState extends State<_HermesOpenuiImageViewer>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom(Offset focal) {
    if (_transform.value != Matrix4.identity()) {
      _transform.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    _transform.value = Matrix4.identity()
      ..translateByDouble(-focal.dx * (scale - 1), -focal.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    Offset? lastTap;
    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTapDown: (d) => lastTap = d.localPosition,
            onDoubleTap: () => _toggleZoom(lastTap ?? Offset.zero),
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Semantics(
                  image: true,
                  label: widget.alt,
                  child: Image(
                    image: ResizeImage.resizeIfNeeded(2048, null, widget.provider),
                    fit: BoxFit.contain,
                    errorBuilder: (context, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.alt.isNotEmpty || widget.details.isNotEmpty)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: Colors.black54,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    [widget.alt, widget.details]
                        .where((t) => t.isNotEmpty)
                        .join('\n'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton.filledTonal(
                  tooltip: 'Close image',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One framed picture: loading shimmer, the image, or a styled placeholder
/// that carries the alt text. Never throws and never shows an error tile.
class HermesOpenuiPicture extends StatefulWidget {
  const HermesOpenuiPicture({
    super.key,
    required this.src,
    required this.alt,
    this.details = '',
    this.environment = const HermesOpenuiImageEnvironment(),
    this.aspectRatio = 16 / 10,
    this.maxHeight = 340,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  final String src;
  final String alt;
  final String details;
  final HermesOpenuiImageEnvironment environment;
  final double aspectRatio;
  final double maxHeight;
  final BorderRadius borderRadius;

  @override
  State<HermesOpenuiPicture> createState() => _HermesOpenuiPictureState();
}

class _HermesOpenuiPictureState extends State<HermesOpenuiPicture> {
  late HermesOpenuiImageSource _source;
  ImageProvider? _provider;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant HermesOpenuiPicture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src) _resolve();
  }

  void _resolve() {
    _source = classifyHermesOpenuiImageSource(widget.src);
    _provider = null;
    switch (_source.kind) {
      case HermesOpenuiImageKind.remote:
        _provider =
            (widget.environment.remoteImageProvider ??
                HermesBoundedNetworkImage.new)(_source.value);
      case HermesOpenuiImageKind.data:
        try {
          _provider = MemoryImage(
            UriData.parse(_source.value).contentAsBytes(),
          );
        } catch (_) {
          _source = const HermesOpenuiImageSource(
            HermesOpenuiImageKind.rejected,
          );
        }
      case HermesOpenuiImageKind.declared:
      case HermesOpenuiImageKind.rejected:
        break;
    }
  }

  String get _label => widget.alt.isEmpty ? 'Image' : widget.alt;

  Widget _placeholder(BuildContext context, {String note = 'Image unavailable'}) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: _label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: .5,
          ),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: widget.borderRadius,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_outlined,
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 6),
                Text(
                  _label,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Static on purpose: no continuous animation while many images load.
  Widget _loading(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    ),
    child: Center(
      child: Icon(
        Icons.image_outlined,
        size: 28,
        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(
          alpha: .5,
        ),
      ),
    ),
  );

  Widget _body(BuildContext context, double width) {
    switch (_source.kind) {
      case HermesOpenuiImageKind.rejected:
        return _placeholder(context);
      case HermesOpenuiImageKind.declared:
        final preview = widget.environment.mediaPreview?.call(_source.value);
        return preview == null
            ? _placeholder(context, note: 'Attach the image with MEDIA: to preview it')
            : ClipRRect(borderRadius: widget.borderRadius, child: preview);
      case HermesOpenuiImageKind.remote:
      case HermesOpenuiImageKind.data:
        final provider = _provider!;
        final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
        final cacheWidth = (width * ratio).round().clamp(96, 1600);
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: Semantics(
            image: true,
            button: true,
            label: 'View image: $_label',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => showHermesOpenuiImageViewer(
                context,
                provider: provider,
                alt: widget.alt,
                details: widget.details,
              ),
              child: Image(
                image: ResizeImage.resizeIfNeeded(cacheWidth, null, provider),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, sync) =>
                    sync || frame != null ? child : _loading(context),
                errorBuilder: (context, _, _) => _placeholder(context),
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
      final height = math.min(widget.maxHeight, width / widget.aspectRatio);
      return SizedBox(
        width: double.infinity,
        height: height,
        child: _body(context, width),
      );
    },
  );
}

/// `Image` (compact) and `ImageBlock` (full width).
class HermesOpenuiImage extends StatelessWidget {
  const HermesOpenuiImage({
    super.key,
    required this.spec,
    this.compact = false,
    this.environment = const HermesOpenuiImageEnvironment(),
  });

  final HermesOpenuiImageSpec spec;
  final bool compact;
  final HermesOpenuiImageEnvironment environment;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 280 : double.infinity),
      child: HermesOpenuiPicture(
        src: spec.src,
        alt: spec.alt,
        details: spec.details,
        environment: environment,
        aspectRatio: compact ? 4 / 3 : 16 / 10,
        maxHeight: compact ? 220 : 340,
      ),
    ),
  );
}

/// Horizontally swipeable images with page dots. Local only.
class HermesOpenuiImageGallery extends StatefulWidget {
  const HermesOpenuiImageGallery({
    super.key,
    required this.items,
    this.environment = const HermesOpenuiImageEnvironment(),
  });

  final List<HermesOpenuiImageSpec> items;
  final HermesOpenuiImageEnvironment environment;

  @override
  State<HermesOpenuiImageGallery> createState() =>
      _HermesOpenuiImageGalleryState();
}

class _HermesOpenuiImageGalleryState extends State<HermesOpenuiImageGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.items;
    final current = items[math.min(_page, items.length - 1)];
    final caption = [current.alt, current.details]
        .where((t) => t.isNotEmpty)
        .join(' · ');
    return Semantics(
      container: true,
      label: 'Image gallery, ${_page + 1} of ${items.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 320.0;
              return SizedBox(
                height: math.min(340, width / (16 / 10)),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: items.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, index) => HermesOpenuiPicture(
                    key: ValueKey<int>(index),
                    src: items[index].src,
                    alt: items[index].alt,
                    details: items[index].details,
                    environment: widget.environment,
                  ),
                ),
              );
            },
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (items.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Semantics(
                      button: true,
                      selected: i == _page,
                      label: 'Show image ${i + 1}',
                      excludeSemantics: true,
                      child: GestureDetector(
                        key: ValueKey<String>('openui-gallery-dot-$i'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _controller.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: i == _page ? 18 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    '${_page + 1} / ${items.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
