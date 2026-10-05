import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'hermes_activity_presenter.dart';

/// One tool call as the transcript recorded it: what was asked and what came
/// back. Text is bounded and redacted; nothing here is re-run or edited.
@immutable
final class HermesToolCallRecord {
  const HermesToolCallRecord({
    required this.id,
    required this.name,
    this.input,
    this.result,
    this.inputTruncated = false,
    this.resultTruncated = false,
    this.failed = false,
  });

  static const int maxInputCharacters = 12000;
  static const int maxResultCharacters = 24000;

  final String id;
  final String name;
  final String? input;
  final String? result;
  final bool inputTruncated;
  final bool resultTruncated;
  final bool failed;

  bool get finished => result != null;
}

/// Finds [toolId] in a session transcript (Hermes' own stored messages).
/// The deferred-tool bridge is unwrapped so the record names the real tool.
HermesToolCallRecord? findHermesToolCall(
  List<Map<String, dynamic>> messages,
  String toolId, {
  Iterable<String> sensitiveValues = const [],
}) {
  String? name;
  Object? arguments;
  for (final message in messages.reversed) {
    if ((message['role'] ?? message['author']) != 'assistant') continue;
    // The REST transcript can carry the calls as stored: a JSON string.
    final calls = _decode(message['tool_calls'] ?? message['toolCalls']);
    if (calls is! List) continue;
    for (final call in calls) {
      if (call is! Map) continue;
      final id = call['id'] ?? call['tool_call_id'];
      if (id != toolId) continue;
      final function = call['function'];
      name = (function is Map ? function['name'] : call['name'])?.toString();
      arguments = function is Map
          ? function['arguments']
          : call['arguments'] ?? call['args'];
      break;
    }
    if (name != null) break;
  }
  Object? output;
  var sawResult = false;
  for (final message in messages) {
    if ((message['role'] ?? message['author']) != 'tool') continue;
    if ((message['tool_call_id'] ?? message['toolCallId']) != toolId) continue;
    output = message['content'] ?? message['text'] ?? '';
    name ??= message['tool_name']?.toString() ?? message['name']?.toString();
    sawResult = true;
    break;
  }
  if (name == null && !sawResult) return null;
  final decodedArgs = _decode(arguments);
  final call = HermesActivityPresenter.unwrap(name ?? 'tool', decodedArgs);
  final input = _render(
    call.name != (name ?? 'tool') ? call.args : decodedArgs,
    sensitiveValues,
    HermesToolCallRecord.maxInputCharacters,
  );
  final result = sawResult
      ? _render(
          _decode(output),
          sensitiveValues,
          HermesToolCallRecord.maxResultCharacters,
        )
      : null;
  final decodedResult = sawResult ? _decode(output) : null;
  return HermesToolCallRecord(
    id: toolId,
    name: call.name,
    input: input?.text,
    inputTruncated: input?.truncated ?? false,
    result: result?.text,
    resultTruncated: result?.truncated ?? false,
    failed: HermesActivityPresenter.resultFailed(decodedResult),
  );
}

Object? _decode(Object? value) {
  if (value is! String) return value;
  final text = value.trim();
  if (!(text.startsWith('{') || text.startsWith('['))) return value;
  if (text.length > 400000) return value;
  try {
    return jsonDecode(text);
  } catch (_) {
    return value;
  }
}

({String text, bool truncated})? _render(
  Object? value,
  Iterable<String> secrets,
  int max,
) {
  if (value == null) return null;
  String text;
  if (value is Map || value is List) {
    try {
      text = const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      text = value.toString();
    }
  } else {
    text = value.toString();
  }
  for (final secret in secrets) {
    if (secret.length >= 4 && text.contains(secret)) {
      text = text.replaceAll(secret, '••••');
    }
  }
  text = text.replaceAll(
    RegExp(r'\b(?:sk|pk|rk|ghp|gho|xox[abpr]|AKIA)[-_A-Za-z0-9]{12,}\b'),
    '••••',
  );
  final truncated = text.length > max;
  return (
    text: truncated ? text.substring(0, max) : text,
    truncated: truncated,
  );
}
