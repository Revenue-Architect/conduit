import 'dart:convert';

import 'hermes_activity_presenter.dart';
import 'hermes_identifier.dart';
import 'hermes_live_activity.dart';
import '../../../core/models/chat_message.dart';
import 'hermes_run_transport.dart' show sanitizeHermesProviderErrorMessage;

/// New assistant continuations belong to the same answer until another user
/// turn begins. An old answer never inherits the latest answer's live controls.
List<ChatMessage> hermesCurrentAnswerMessages(
  List<ChatMessage> transcript,
  List<ChatMessage> answer,
) {
  final boundary = transcript.lastIndexWhere(
    (message) => message.role == 'user',
  );
  final tail = transcript
      .skip(boundary + 1)
      .where((message) => message.role == 'assistant')
      .toList();
  final ids = answer.map((message) => message.id).toSet();
  return tail.any((message) => ids.contains(message.id)) ? tail : const [];
}

/// A bot/profile display name is not a model. Only display stored model data.
String? hermesTranscriptModel(
  List<Map<String, dynamic>> messages, {
  Iterable<String> sensitiveValues = const [],
}) {
  for (final message in messages.reversed) {
    if (message['role'] != 'assistant') continue;
    final metadata = message['metadata'];
    final model =
        message['model'] ?? (metadata is Map ? metadata['model'] : null);
    if (model is String && model.trim().isNotEmpty) {
      return HermesActivityPresenter.clean(
        model,
        sensitiveValues: sensitiveValues,
        max: 120,
      );
    }
  }
  return null;
}

List<ChatStatusUpdate> hermesSafeRunStatuses(
  List<ChatStatusUpdate> statuses,
  Iterable<String> sensitiveValues,
) {
  String? safe(String? value) => value == null
      ? null
      : sanitizeHermesProviderErrorMessage(
          value,
          sensitiveValues: sensitiveValues,
          maxCharacters: 2048,
        );
  return [
    for (final status in statuses)
      status.copyWith(
        description: safe(status.description),
        query: safe(status.query),
        queries: [for (final query in status.queries) safe(query)!],
        items: [
          for (final item in status.items)
            item.copyWith(title: safe(item.title), snippet: safe(item.snippet)),
        ],
      ),
  ];
}

/// Locate an answer's actual stored turn by message id, or unique exact content
/// when an optimistic id was replaced. Never guess the latest turn for an older
/// answer. The surrounding user boundaries keep tool-only assistant rows.
List<Map<String, dynamic>> hermesAnswerTranscript(
  List<Map<String, dynamic>> transcript,
  List<ChatMessage> answer,
) {
  final ids = answer.map((message) => message.id).toSet();
  var index = transcript.indexWhere(
    (message) =>
        message['role'] == 'assistant' &&
        ids.contains(message['id']?.toString()),
  );
  if (index < 0) {
    final texts = answer
        .map((message) => message.content.trim())
        .where((text) => text.isNotEmpty)
        .toSet();
    final matches = <int>[
      for (var i = 0; i < transcript.length; i++)
        if (transcript[i]['role'] == 'assistant' &&
            texts.contains(transcript[i]['content']?.toString().trim()))
          i,
    ];
    // Repeated response text is not an identity.
    if (matches.length != 1) return const [];
    index = matches.single;
  }
  var start = index;
  while (start > 0 && transcript[start - 1]['role'] != 'user') {
    start--;
  }
  var end = index + 1;
  while (end < transcript.length && transcript[end]['role'] != 'user') {
    end++;
  }
  return transcript.sublist(start, end);
}

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
