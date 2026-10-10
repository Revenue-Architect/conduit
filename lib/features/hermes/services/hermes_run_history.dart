import 'dart:convert';

import 'hermes_activity_presenter.dart';
import 'hermes_identifier.dart';
import 'hermes_live_activity.dart';

/// A read-only projection of the stored transcript, not a second event store.
List<HermesLiveActivityEvent> hermesTranscriptActivity(
  String sessionId,
  List<Map<String, dynamic>> messages, {
  Iterable<String> sensitiveValues = const [],
}) {
  final events = <HermesLiveActivityEvent>[];
  final names = <String, String>{};
  Object? decoded(Object? value) {
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  for (final message in messages) {
    final rawTime = message['timestamp'] ?? message['created_at'];
    final time =
        rawTime is num &&
            rawTime.isFinite &&
            rawTime >= 0 &&
            rawTime < 253402300800
        ? DateTime.fromMillisecondsSinceEpoch(
            (rawTime * 1000).round(),
            isUtc: true,
          )
        : DateTime.tryParse(rawTime?.toString() ?? '');
    final calls = decoded(message['tool_calls']);
    if (calls is List) {
      for (final raw in calls) {
        if (raw is! Map) continue;
        final function = raw['function'];
        final name = function is Map ? function['name'] : raw['name'];
        final id = validateHermesOpaqueIdentifier(raw['id']);
        if (name is! String || id == null) continue;
        final call = HermesActivityPresenter.unwrap(
          name,
          decoded(function is Map ? function['arguments'] : raw['arguments']),
        );
        final safeName = HermesActivityPresenter.clean(
          call.name,
          sensitiveValues: sensitiveValues,
        );
        if (safeName == null) continue;
        names[id] = safeName;
        events.add(
          HermesLiveActivityEvent(
            sessionId: sessionId,
            kind: HermesLiveActivityKind.toolStarted,
            title: 'Started $safeName',
            detail: safeName,
            toolId: id,
            timestamp:
                time ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            timestampKnown: time != null,
            preview: HermesActivityPresenter.clean(
              HermesActivityPresenter.objectFromArgs(call.name, call.args),
              sensitiveValues: sensitiveValues,
            ),
          ),
        );
      }
    }
    if (message['role'] == 'tool') {
      final id = validateHermesOpaqueIdentifier(message['tool_call_id']);
      final name =
          names[id] ??
          HermesActivityPresenter.clean(
            message['tool_name']?.toString(),
            sensitiveValues: sensitiveValues,
          );
      if (id == null && name == null) continue;
      final result = decoded(message['content']);
      events.add(
        HermesLiveActivityEvent(
          sessionId: sessionId,
          kind: HermesLiveActivityKind.toolCompleted,
          title: 'Completed ${name ?? 'tool'}',
          detail: name,
          toolId: id,
          timestamp:
              time ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          timestampKnown: time != null,
          failed: HermesActivityPresenter.resultFailed(result),
          page: name == null
              ? null
              : HermesActivityPresenter.pageFromResult(name, result),
        ),
      );
    }
    if (message['role'] == 'assistant' &&
        (calls is! List || calls.isEmpty) &&
        message['content'] is String &&
        (message['content'] as String).trim().isNotEmpty) {
      events.add(
        HermesLiveActivityEvent(
          sessionId: sessionId,
          kind: HermesLiveActivityKind.completed,
          title: 'Response saved',
          timestamp:
              time ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          timestampKnown: time != null,
        ),
      );
    }
  }
  return events;
}

/// Stored calls keep their order; live copies replace matching calls so richer
/// runtime summaries survive without counting each call twice.
List<HermesLiveActivityEvent> mergeHermesRunHistory(
  List<HermesLiveActivityEvent> stored,
  List<HermesLiveActivityEvent> live,
) {
  final result = [...stored];
  for (final event in live) {
    final index = event.toolId == null
        ? -1
        : result.indexWhere(
            (row) =>
                row.sessionId == event.sessionId &&
                row.kind == event.kind &&
                row.toolId == event.toolId,
          );
    if (index < 0) {
      result.add(event);
    } else {
      result[index] = event;
    }
  }
  return result;
}
