/// One renderable part of a completed Hermes assistant response.
sealed class HermesRichOutputSegment {
  const HermesRichOutputSegment(this.content);

  final String content;
}

/// Markdown that remains in Conduit's existing renderer.
final class MarkdownSegment extends HermesRichOutputSegment {
  const MarkdownSegment(super.content);
}

/// The body of an explicit, completed ```a2ui fenced block.
final class A2uiSegment extends HermesRichOutputSegment {
  const A2uiSegment(super.content);
}

final _fenceOpeningPattern = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
final _fenceClosingPattern = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*$');

/// Splits explicit A2UI fences from a Hermes response without interpreting
/// ordinary JSON/code fences or changing Conduit's Markdown grammar.
List<HermesRichOutputSegment> parseHermesRichOutput(String text) {
  if (text.isEmpty) return const <HermesRichOutputSegment>[];

  final segments = <HermesRichOutputSegment>[];
  var markdownStart = 0;
  var cursor = 0;

  while (cursor < text.length) {
    final lineEnd = text.indexOf('\n', cursor);
    final hasLineFeed = lineEnd >= 0;
    final currentLineEnd = hasLineFeed ? lineEnd : text.length;
    final line = _withoutCarriageReturn(text.substring(cursor, currentLineEnd));
    final opening = _parseFenceOpening(line);

    if (opening != null) {
      final closing = _findClosingFence(
        text,
        hasLineFeed ? lineEnd + 1 : text.length,
        opening.character,
        opening.length,
      );
      if (closing == null) {
        // An incomplete fence is ordinary Markdown, and its contents cannot
        // accidentally start a nested A2UI surface.
        break;
      }

      if (opening.info == 'a2ui') {
        _appendMarkdown(segments, text.substring(markdownStart, cursor));
        final contentStart = hasLineFeed ? lineEnd + 1 : text.length;
        segments.add(A2uiSegment(text.substring(contentStart, closing.start)));
        markdownStart = closing.after;
      }
      cursor = closing.after;
      continue;
    }

    if (!hasLineFeed) break;
    cursor = lineEnd + 1;
  }

  _appendMarkdown(segments, text.substring(markdownStart));
  if (segments.isEmpty) {
    return <HermesRichOutputSegment>[MarkdownSegment(text)];
  }
  return List<HermesRichOutputSegment>.unmodifiable(segments);
}

void _appendMarkdown(List<HermesRichOutputSegment> segments, String content) {
  if (content.isNotEmpty) segments.add(MarkdownSegment(content));
}

({String character, int length, String info})? _parseFenceOpening(String line) {
  final match = _fenceOpeningPattern.firstMatch(line);
  if (match == null) return null;
  final marker = match.group(1)!;
  final character = marker[0];
  final info = match.group(2) ?? '';
  if (character == '`' && info.contains('`')) return null;
  return (character: character, length: marker.length, info: info.trim());
}

({int start, int after})? _findClosingFence(
  String text,
  int searchStart,
  String character,
  int minimumLength,
) {
  var lineStart = searchStart;
  while (lineStart < text.length) {
    final lineEnd = text.indexOf('\n', lineStart);
    final hasLineFeed = lineEnd >= 0;
    final currentLineEnd = hasLineFeed ? lineEnd : text.length;
    final line = _withoutCarriageReturn(
      text.substring(lineStart, currentLineEnd),
    );
    final match = _fenceClosingPattern.firstMatch(line);
    if (match != null) {
      final marker = match.group(1)!;
      if (marker.length >= minimumLength && marker[0] == character) {
        return (
          start: lineStart,
          after: hasLineFeed ? lineEnd + 1 : text.length,
        );
      }
    }
    if (!hasLineFeed) break;
    lineStart = lineEnd + 1;
  }
  return null;
}

String _withoutCarriageReturn(String line) =>
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
