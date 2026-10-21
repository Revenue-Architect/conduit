import 'dart:convert';

const _interactionPrefix = '[A2UI_INTERACTION]\n';
final _actionNamePattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*)*$',
);

/// A short label for an A2UI action turn. The stored message and the text sent
/// to Hermes remain the original protocol payload.
String? hermesA2uiInteractionLabel(String content) {
  final approval = hermesApprovalNoticeLabel(content);
  if (approval != null) return approval;
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

const _approvalNoticePrefix = '[Hermes V2 - approval decided]';
final _approvalNoticePattern = RegExp(
  r'^Approval \S+ for "([^"\n]{1,80})" was (APPROVED|DENIED|EXPIRED|CANCELLED) by [^\n]*? at ([^\n(]{1,20}?) \(via',
  multiLine: true,
);

/// The automated "approval decided" notice the server sends to wake a chat is
/// machine instruction text. People see a one-line receipt instead; the stored
/// message and what the agent receives are unchanged.
String? hermesApprovalNoticeLabel(String content) {
  if (!content.startsWith(_approvalNoticePrefix) || content.length > 6000) {
    return null;
  }
  final match = _approvalNoticePattern.firstMatch(content);
  if (match == null) return null;
  final word = match.group(2)!.toLowerCase();
  final status = '${word[0].toUpperCase()}${word.substring(1)}';
  return '$status \u00b7 ${match.group(1)} \u00b7 ${match.group(3)!.trim()}';
}
