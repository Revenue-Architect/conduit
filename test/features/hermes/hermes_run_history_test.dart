import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/services/hermes_live_activity.dart';
import 'package:conduit/features/hermes/services/hermes_run_history.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> savedRunMessages() => [
  {'role': 'user', 'content': 'Research the earlier question'},
  {
    'role': 'assistant',
    'tool_calls': jsonEncode([
      {
        'id': 'call-1',
        'function': {
          'name': 'web_search',
          'arguments': jsonEncode({'query': 'earlier research'}),
        },
      },
    ]),
  },
  {'role': 'tool', 'tool_call_id': 'call-1', 'content': '{"results":[]}'},
  {'role': 'assistant', 'content': 'Earlier saved conclusion'},
  {'role': 'user', 'content': 'Now check the files'},
  {
    'role': 'assistant',
    'tool_calls': [
      {
        'id': 'call-2',
        'function': {'name': 'read_file', 'arguments': '{"path":"notes.txt"}'},
      },
    ],
  },
  {
    'role': 'tool',
    'tool_call_id': 'call-2',
    'content': '{"error":"not found"}',
  },
  {'role': 'assistant', 'content': 'Latest saved conclusion'},
];

void main() {
  test(
    'stored history retains calls and conclusions across multiple turns',
    () {
      final events = hermesTranscriptActivity('session-1', savedRunMessages());
      final summary = HermesRunSummary.conversation(events, running: false);
      expect(summary.steps, 2);
      expect(events.where((event) => event.isTerminal), hasLength(2));
      expect(
        events
            .where(
              (event) => event.kind == HermesLiveActivityKind.toolCompleted,
            )
            .last
            .failed,
        isTrue,
      );
      expect(
        summary.elapsed(),
        isNull,
        reason: 'Missing timestamps must not invent duration',
      );
      expect(HermesRunSummary.latest(events, running: false).steps, 1);
    },
  );

  test('live copies enrich stored calls without double counting or crossing sessions', () {
    final events = hermesTranscriptActivity('session-1', savedRunMessages());
    final richer = HermesLiveActivityEvent(
      sessionId: 'session-1',
      kind: HermesLiveActivityKind.toolCompleted,
      title: 'Live summary',
      toolId: 'call-1',
      timestamp: DateTime.utc(2026),
      summary: 'Search complete',
    );
    final merged = mergeHermesRunHistory(events, [richer]);
    expect(merged.length, events.length);
    expect(
      merged
          .where(
            (event) =>
                event.toolId == 'call-1' &&
                event.kind == HermesLiveActivityKind.toolCompleted,
          )
          .single,
      same(richer),
    );
    final other = HermesLiveActivityEvent(
      sessionId: 'session-2',
      kind: richer.kind,
      title: 'Other',
      toolId: richer.toolId,
      timestamp: richer.timestamp,
    );
    expect(
      mergeHermesRunHistory(events, [other]),
      hasLength(events.length + 1),
    );
  });

  test('bridge calls are unwrapped and previews redact configured secrets', () {
    final events = hermesTranscriptActivity(
      'session-1',
      [
        {
          'role': 'assistant',
          'timestamp': 1800000000,
          'tool_calls': [
            {
              'id': 'call-3',
              'function': {
                'name': 'tool_call',
                'arguments': jsonEncode({
                  'name': 'web_search',
                  'arguments': {'query': 'find secret-credential'},
                }),
              },
            },
          ],
        },
      ],
      sensitiveValues: ['secret-credential'],
    );
    expect(events.single.detail, 'web_search');
    expect(events.single.preview, isNot(contains('secret-credential')));
    expect(events.single.timestampKnown, isTrue);
  });

  test('malformed transcript rows do not crash or invent tools', () {
    expect(
      hermesTranscriptActivity('session-1', [
        {
          'role': 'assistant',
          'timestamp': double.infinity,
          'tool_calls': 'invalid',
        },
        {
          'role': 'assistant',
          'tool_calls': [
            null,
            7,
            {'id': 'x'},
          ],
        },
        {'role': 'tool', 'content': 'invalid'},
      ]),
      isEmpty,
    );
  });

  test('saved detail read is paginated, exact-profile GET only, and never resumes RPC', () async {
    final adapter = _HistoryAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final service = HermesDesktopApiService(
      config: HermesConfig(
        enabled: true,
        baseUrl: 'https://hermes.example',
        mode: HermesBackendMode.desktopGateway,
        desktopCredentials: HermesDesktopCredentials(legacyToken: 'test-token'),
      ),
      dio: dio,
    );
    addTearDown(service.close);
    service.bindSessionProfile('session-1', 'strong');
    final messages = await service.readRunDetailsMessages('session-1');
    expect(messages, hasLength(205));
    final requests = adapter.requests
        .where((request) => request.uri.path.endsWith('/messages'))
        .toList();
    expect(requests, hasLength(2));
    expect(requests.map((request) => request.uri.queryParameters['offset']), [
      '0',
      '200',
    ]);
    for (final request in requests) {
      expect(request.method, 'GET');
      expect(request.uri.path, '/api/sessions/session-1/messages');
      expect(request.uri.queryParameters['profile'], 'strong');
      expect(request.uri.queryParameters['order'], 'oldest');
    }
    expect(
      adapter.requests.every((request) => request.method == 'GET'),
      isTrue,
    );
  });
}

class _HistoryAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final status = options.uri.path == '/api/status';
    final offset =
        int.tryParse(options.uri.queryParameters['offset'] ?? '0') ?? 0;
    final data = status
        ? {'auth_required': false}
        : {
            'messages': List.generate(
              offset == 0 ? 200 : 5,
              (index) => {
                'role': 'assistant',
                'content': 'Saved ${offset + index}',
              },
            ),
          };
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
