import 'package:parchment/parchment.dart';

import '../../notes/utils/note_document_codec.dart';

/// Markdown is the canonical Page format. The visual (Fleather) editor only
/// models a subset of it; a Page using anything outside that subset opens in
/// source mode so nothing is silently stripped on the next save.

/// Why [markdown] cannot be edited visually, or null when it can.
String? sourceModeReason(String markdown) {
  if (markdown.isEmpty) return null;
  for (final (pattern, reason) in _unsupported) {
    if (pattern.hasMatch(markdown)) return reason;
  }
  return null;
}

final List<(RegExp, String)> _unsupported = [
  (RegExp(r'^---[ \t]*\n[\s\S]*?\n---[ \t]*(\n|$)'), 'front matter'),
  (RegExp(r'<\/?[A-Za-z][A-Za-z0-9-]*(\s[^>]*)?>|<!--'), 'raw HTML'),
  (RegExp(r'!\[[^\]]*\]\('), 'images'),
  (RegExp(r'\[\^[^\]]+\]'), 'footnotes'),
  (RegExp(r'^\s*:::', multiLine: true), 'directives'),
  (RegExp(r'\$\$'), 'display math'),
  (RegExp(r'^\s*\|.*\|\s*$\n^\s*\|?\s*:?-{3,}', multiLine: true), 'tables'),
  // Nested lists and indented blocks flatten in the visual model.
  (RegExp(r'^( {2,}|\t)([-*+]|\d+[.)])\s', multiLine: true), 'nested lists'),
  (RegExp(r'^\[[^\]]+\]:\s*\S', multiLine: true), 'reference links'),
  (RegExp(r'^={3,}\s*$', multiLine: true), 'setext headings'),
];

/// Visual-mode decode: Markdown to a Fleather document.
ParchmentDocument pageDocumentFromMarkdown(String markdown) =>
    documentFromMarkdown(markdown);

/// Visual-mode encode: a Fleather document back to Markdown.
String pageMarkdownFromDocument(ParchmentDocument document) {
  final markdown = markdownFromDocument(document);
  // An empty document encodes as a lone newline.
  return markdown.trim().isEmpty ? '' : markdown;
}
