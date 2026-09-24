/// The way a `MEDIA:` artifact should be presented in a Hermes response.
enum HermesMediaKind { image, file, audio, video }

final class HermesMediaArtifact {
  const HermesMediaArtifact({
    required this.path,
    required this.filename,
    required this.kind,
  });

  final String path;
  final String filename;
  final HermesMediaKind kind;
}

final class HermesMediaParseResult {
  HermesMediaParseResult({
    required this.cleanText,
    required List<HermesMediaArtifact> artifacts,
  }) : artifacts = List.unmodifiable(artifacts);

  final String cleanText;
  final List<HermesMediaArtifact> artifacts;
}

// Keep this in sync with Hermes Desktop's MEDIA_DELIVERY_EXTS. The extension
// anchor is what lets an unquoted path such as "My Report.pdf" retain spaces.
const _mediaDeliveryExtensions = <String>[
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'tiff',
  'svg',
  'mp4',
  'mov',
  'avi',
  'mkv',
  'webm',
  '3gp',
  'mp3',
  'm2a',
  'wav',
  'ogg',
  'opus',
  'm4a',
  'flac',
  'pdf',
  'docx',
  'doc',
  'odt',
  'rtf',
  'txt',
  'md',
  'epub',
  'xlsx',
  'xls',
  'ods',
  'csv',
  'tsv',
  'json',
  'xml',
  'yaml',
  'yml',
  'kmz',
  'kml',
  'geojson',
  'gpx',
  'pptx',
  'ppt',
  'odp',
  'key',
  'zip',
  'tar',
  'gz',
  'tgz',
  'bz2',
  'xz',
  '7z',
  'rar',
  'apk',
  'ipa',
  'html',
  'htm',
];

String _caseInsensitiveExtension(String extension) =>
    extension.split('').map((character) {
      final lower = character.toLowerCase();
      final upper = character.toUpperCase();
      return lower == upper ? RegExp.escape(character) : '[$lower$upper]';
    }).join();

final _extensionAlternation =
    _mediaDeliveryExtensions.map(_caseInsensitiveExtension).toList()
      ..sort((left, right) => right.length.compareTo(left.length));

final _fencedCodePattern = RegExp(r'```[^\n]*\n.*?```', dotAll: true);
final _inlineCodePattern = RegExp(r'`[^`\r\n]+`');
final _blockquotePattern = RegExp(r'^[ \t]*>[^\r\n]*', multiLine: true);

const _pathEndBoundary =
    r"""(?=[\s`"'*_,;:)\]}\[（）〈〉《》：，。；！？、“”‘’【】!?]|\.(?=$|[\s`"'*_,;:)\]}!?])|MEDIA:|$)""";

final _anchoredMediaPathPattern =
    r'(?:~/|/|[A-Za-z]:[/\\])\S+?(?:[^\S\n]+\S+?)*?\.(?:' +
    _extensionAlternation.join('|') +
    r')' +
    _pathEndBoundary;

final _mediaDirectivePattern = RegExp(
  r"""(?<![A-Za-z0-9])[`"'*_]{0,3}MEDIA:[ \t]*(?<path>`[^`\r\n]+`|"[^"\r\n]+"|'[^'\r\n]+'|""" +
      _anchoredMediaPathPattern +
      r"""|\S+)[`"'*_]{0,3}""",
);

const _imageExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'tiff',
  'svg',
};

const _audioExtensions = <String>{
  'mp3',
  'm2a',
  'wav',
  'ogg',
  'opus',
  'm4a',
  'flac',
};

const _videoExtensions = <String>{'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'};

/// Extracts explicit Hermes `MEDIA:` directives and leaves surrounding prose
/// in [HermesMediaParseResult.cleanText]. Ordinary filesystem paths are never
/// interpreted.
HermesMediaParseResult parseHermesMedia(String text) {
  final artifacts = <HermesMediaArtifact>[];
  final removals = <({int start, int end})>[];
  final scanText = _maskProtectedSpans(text);

  for (final match in _mediaDirectivePattern.allMatches(scanText)) {
    final path = _unquoteMediaPath(match.namedGroup('path') ?? '');
    if (path.isEmpty) continue;

    final previousLineBreak = match.start == 0
        ? -1
        : text.lastIndexOf('\n', match.start - 1);
    final lineStart = previousLineBreak + 1;
    final nextLineBreak = text.indexOf('\n', match.end);
    final lineEnd = nextLineBreak < 0 ? text.length : nextLineBreak;
    final trailingLineText = text.substring(match.end, lineEnd).trim();
    final trailingPunctuationOnly = RegExp(r'^[.!?…。，；！？、]+$')
        .hasMatch(trailingLineText);
    final isOnlyContentOnLine =
        text.substring(lineStart, match.start).trim().isEmpty &&
        (trailingLineText.isEmpty || trailingPunctuationOnly);

    removals.add((
      start: isOnlyContentOnLine ? lineStart : match.start,
      end: isOnlyContentOnLine
          ? (nextLineBreak < 0 ? lineEnd : nextLineBreak + 1)
          : match.end,
    ));
    artifacts.add(
      HermesMediaArtifact(
        path: path,
        filename: _filenameForPath(path),
        kind: _kindForPath(path),
      ),
    );
  }

  if (artifacts.isEmpty) {
    return HermesMediaParseResult(cleanText: text, artifacts: const []);
  }

  final clean = StringBuffer();
  var cursor = 0;
  for (final removal in removals) {
    if (removal.start < cursor) continue;
    clean.write(text.substring(cursor, removal.start));
    cursor = removal.end;
  }
  clean.write(text.substring(cursor));
  final cleanedText = clean.toString();

  return HermesMediaParseResult(
    cleanText: cleanedText.trim().isEmpty ? '' : cleanedText,
    artifacts: artifacts,
  );
}

String _unquoteMediaPath(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 2) {
    final quote = trimmed[0];
    if (quote == trimmed[trimmed.length - 1] &&
        (quote == '"' || quote == "'" || quote == '`')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
  }
  final withoutTerminalPunctuation = trimmed.replaceFirst(
    RegExp(r'[.!?…。，；！？、]+$'),
    '',
  );
  if (withoutTerminalPunctuation != trimmed) {
    final filename = _filenameForPath(withoutTerminalPunctuation);
    final dot = filename.lastIndexOf('.');
    if (dot >= 0 &&
        _mediaDeliveryExtensions.contains(
          filename.substring(dot + 1).toLowerCase(),
        )) {
      return withoutTerminalPunctuation;
    }
  }
  return trimmed;
}

String _maskProtectedSpans(String text) {
  final spans = <({int start, int end})>[];
  for (final match in _fencedCodePattern.allMatches(text)) {
    spans.add((start: match.start, end: match.end));
  }

  for (final match in _inlineCodePattern.allMatches(text)) {
    if (spans.any(
      (span) => span.start <= match.start && match.end <= span.end,
    )) {
      continue;
    }
    final previousLineBreak = match.start == 0
        ? -1
        : text.lastIndexOf('\n', match.start - 1);
    final linePrefix = text.substring(previousLineBreak + 1, match.start);
    // Backticks immediately following MEDIA: quote the artifact path; they are
    // not a Markdown code span and must remain parseable.
    if (RegExp(r'MEDIA:\s*$').hasMatch(linePrefix)) continue;
    spans.add((start: match.start, end: match.end));
  }

  for (final match in _blockquotePattern.allMatches(text)) {
    spans.add((start: match.start, end: match.end));
  }

  spans.sort((left, right) => left.start.compareTo(right.start));
  final merged = <({int start, int end})>[];
  for (final span in spans) {
    if (merged.isNotEmpty && span.start <= merged.last.end) {
      final previous = merged.removeLast();
      merged.add((
        start: previous.start,
        end: span.end > previous.end ? span.end : previous.end,
      ));
    } else {
      merged.add(span);
    }
  }

  if (merged.isEmpty) return text;
  final codeUnits = List<int>.of(text.codeUnits);
  for (final span in merged) {
    for (var index = span.start; index < span.end; index++) {
      if (codeUnits[index] != 0x0A && codeUnits[index] != 0x0D) {
        codeUnits[index] = 0x20;
      }
    }
  }
  return String.fromCharCodes(codeUnits);
}

String _filenameForPath(String path) {
  final parts = path
      .split(RegExp(r'[/\\]'))
      .where((part) => part.isNotEmpty)
      .toList();
  return parts.isEmpty ? path : parts.last;
}

HermesMediaKind _kindForPath(String path) {
  final parts = path.split(RegExp(r'[/\\]'));
  final filename = parts.isEmpty ? path : parts.last;
  final dot = filename.lastIndexOf('.');
  final extension = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  if (_imageExtensions.contains(extension)) return HermesMediaKind.image;
  if (_audioExtensions.contains(extension)) return HermesMediaKind.audio;
  if (_videoExtensions.contains(extension)) return HermesMediaKind.video;
  return HermesMediaKind.file;
}
