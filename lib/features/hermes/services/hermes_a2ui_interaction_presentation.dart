import 'dart:convert';

const _interactionPrefix = '[A2UI_INTERACTION]\n';
final _actionNamePattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*)*$',
);

/// A short label for an A2UI action turn. The stored message and the text sent
/// to Hermes remain the original protocol payload.
String? hermesA2uiInteractionLabel(String content) {
  if (!content.startsWith(_interactionPrefix) ||
      content.length > _interactionPrefix.length + 4096) {
    return null;
  }

  try {
    final decoded = jsonDecode(content.substring(_interactionPrefix.length));
    if (decoded is! Map<String, dynamic> || decoded['version'] != 'v0.9') {
      return null;
    }
    final action = decoded['action'];
    if (action is! Map<String, dynamic>) return null;
    final name = action['name'];
    if (name is! String ||
        name.isEmpty ||
        name.length > 80 ||
        !_actionNamePattern.hasMatch(name)) {
      return null;
    }

    final separator = name.indexOf('.');
    if (separator < 0) return _humanize(name);
    final service = _humanize(name.substring(0, separator));
    final actionName = _humanize(name.substring(separator + 1));
    return '$service · $actionName';
  } on FormatException {
    return null;
  }
}

String _humanize(String identifier) {
  final words = identifier.replaceAll(RegExp(r'[._-]+'), ' ');
  return '${words[0].toUpperCase()}${words.substring(1)}';
}
