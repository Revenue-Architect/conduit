/// Image sources for the OpenUI `Image`, `ImageCard` and `ImageGallery`
/// components. Keep identical to Desktop's `src/image-source.ts`.
library;

const hermesOpenuiImageUrlMax = 2048;
const hermesOpenuiImageDataMax = 49152;

enum HermesOpenuiImageKind { remote, data, declared, rejected }

final class HermesOpenuiImageSource {
  const HermesOpenuiImageSource(this.kind, [this.value = '']);

  final HermesOpenuiImageKind kind;

  /// The URL for remote/data sources, or the MEDIA path for declared ones.
  final String value;
}

const _rejected = HermesOpenuiImageSource(HermesOpenuiImageKind.rejected);
final _dataPattern = RegExp(
  r'^data:image/(?:png|jpe?g|gif|webp|avif|bmp);base64,[A-Za-z0-9+/]+={0,2}$',
  caseSensitive: false,
);
final _schemePattern = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*):');
final _controlPattern = RegExp(r'[\x00-\x1f\x7f]');

/// http(s) image URLs (any host, including private/LAN ones), raster data:image
/// URIs and bare paths (resolved only against MEDIA files declared in the same
/// reply) are usable. Every other scheme, embedded credentials and control
/// characters are rejected. Rejection renders a placeholder, never an error.
HermesOpenuiImageSource classifyHermesOpenuiImageSource(String src) {
  if (src.isEmpty ||
      src.length > hermesOpenuiImageDataMax ||
      src.startsWith('//') ||
      _controlPattern.hasMatch(src)) {
    return _rejected;
  }
  final scheme = _schemePattern.firstMatch(src)?.group(1)?.toLowerCase();
  // A single letter is a Windows drive ("C:\\x"), not a URL scheme.
  if (scheme == null || scheme.length == 1) {
    return HermesOpenuiImageSource(HermesOpenuiImageKind.declared, src);
  }
  if (scheme == 'data') {
    return _dataPattern.hasMatch(src)
        ? HermesOpenuiImageSource(HermesOpenuiImageKind.data, src)
        : _rejected;
  }
  if (scheme != 'http' && scheme != 'https') return _rejected;
  if (src.length > hermesOpenuiImageUrlMax || src.contains(RegExp(r'\s'))) {
    return _rejected;
  }
  final uri = Uri.tryParse(src);
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return _rejected;
  }
  return HermesOpenuiImageSource(HermesOpenuiImageKind.remote, src);
}
