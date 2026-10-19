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

// A bare, absolute server path under /opt/data/ that ends in a delivery
// extension, e.g. the handoff file a specialist names without a MEDIA: line.
// It deliberately has no spaces: only unquoted prose paths the model writes
// whole are recognised. The download itself is still authorised by the server
// (/api/fs/download); nothing here widens what can be fetched.
const _optDataPathChars = r"""[^\s`"'<>|*]""";

final _bareOptDataPathPattern = RegExp(
  '(?<![A-Za-z0-9_./~\\-])/opt/data/$_optDataPathChars+?\\.'
  '(?:${_extensionAlternation.join('|')})$_pathEndBoundary',
);

// A backticked span that is exactly such a path (how the model usually writes
// it) is a path, not code, so it must not be masked.
final _exactBacktickedOptDataPath = RegExp(
  '^`/opt/data/$_optDataPathChars+\\.'
  '(?:${_extensionAlternation.join('|')})`\$',
);

/// Server paths that must never become a download card, even though they sit
/// under /opt/data: secrets, environment files, auth and config. Anything with
/// a `..` segment is refused too.
bool _isDeniedServerPath(String path) {
  if (path.contains('..')) return true;
  final segments = path.split('/').where((part) => part.isNotEmpty).toList();
  for (final segment in segments) {
    final lower = segment.toLowerCase();
    if (lower == '.secrets' || lower.startsWith('.env')) return true;
  }
  final name = segments.isEmpty ? '' : segments.last.toLowerCase();
  return name == 'auth.json' || name == 'config.yaml';
}

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

/// Extracts Hermes `MEDIA:` directives, plus bare absolute server paths under
/// `/opt/data/` that end in a delivery extension (the safety net for replies
/// that name a file without a `MEDIA:` line), and leaves the surrounding prose
/// in [HermesMediaParseResult.cleanText]. A bare path is replaced by its file
/// name so the sentence still reads; a `MEDIA:` directive is removed. Other
/// filesystem paths are never interpreted, and neither is anything inside
/// fenced code, inline code (other than a span that is exactly the path), or a
/// blockquote.
HermesMediaParseResult parseHermesMedia(String text) {
  final artifacts = <HermesMediaArtifact>[];
  final edits = <({int start, int end, String replacement})>[];
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

    edits.add((
      start: isOnlyContentOnLine ? lineStart : match.start,
      end: isOnlyContentOnLine
          ? (nextLineBreak < 0 ? lineEnd : nextLineBreak + 1)
          : match.end,
      replacement: '',
    ));
    artifacts.add(
      HermesMediaArtifact(
        path: path,
        filename: _filenameForPath(path),
        kind: _kindForPath(path),
      ),
    );
  }

  // Bare /opt/data paths. A path already delivered by a MEDIA: directive (or
  // earlier in the same message) gets no second card, but is still shortened
  // to its file name in the prose.
  final seenPaths = {for (final artifact in artifacts) artifact.path};
  for (final match in _bareOptDataPathPattern.allMatches(scanText)) {
    final path = match.group(0)!;
    if (_isDeniedServerPath(path)) continue;
    if (edits.any((e) => match.start < e.end && e.start < match.end)) continue;
    final filename = _filenameForPath(path);
    edits.add((start: match.start, end: match.end, replacement: filename));
    if (seenPaths.add(path)) {
      artifacts.add(
        HermesMediaArtifact(
          path: path,
          filename: filename,
          kind: _kindForPath(path),
        ),
      );
    }
  }

  if (artifacts.isEmpty) {
    return HermesMediaParseResult(cleanText: text, artifacts: const []);
  }

  edits.sort((left, right) => left.start.compareTo(right.start));
  final clean = StringBuffer();
  var cursor = 0;
  for (final edit in edits) {
    if (edit.start < cursor) continue;
    clean.write(text.substring(cursor, edit.start));
    clean.write(edit.replacement);
    cursor = edit.end;
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
    // A span that is exactly a server file path is a path, not code.
    if (_exactBacktickedOptDataPath.hasMatch(match.group(0)!)) continue;
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
