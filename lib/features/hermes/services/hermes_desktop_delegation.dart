part of 'hermes_desktop_api_service.dart';

/// The same redaction applies to inline and full child transcript previews.
String safeHermesDelegatedText(String value, Iterable<String> sensitiveValues) {
  var text = value.replaceAll(
    RegExp(
      r'<(?:think|thinking|analysis)>.*?(?:</(?:think|thinking|analysis)>|$)',
      caseSensitive: false,
      dotAll: true,
    ),
    '',
  );
  for (final secret in sensitiveValues) {
    if (secret.length >= 4) text = text.replaceAll(secret, '••••');
  }
  return text.replaceAll(
    RegExp(
      r'\b(?:sk-[\w-]{12,}|Bearer\s+[\w.=-]{12,}|(?:api[_-]?key|token|password|secret)\s*[:=]\s*\S+)',
      caseSensitive: false,
    ),
    '[redacted]',
  );
}

extension HermesDesktopDelegation on HermesDesktopApiService {
  /// Existing authenticated plugin routing supplies profile isolation. A
  /// missing plugin degrades to native events; no unprotected fallback exists.
  Future<void> refreshDelegations(String parentSessionId) async {
    if (validateHermesOpaqueIdentifier(parentSessionId) == null) return;
    final profile = profileForSession(parentSessionId);
    final data = await _requestJson(
      'GET',
      '/api/plugins/conduit-delegation/workers',
      query: {'session_id': parentSessionId, 'profile': profile},
    );
    for (final row in _objects(data, 'workers').take(64)) {
      if (row['parent_session_id'] != parentSessionId ||
          row['parent_profile'] != profile) {
        continue;
      }
      final status = HermesSubagentStatus.parse(row['status']);
      _agentic.applySubagentEvent(
        parentSessionId,
        status.isTerminal ? 'delegation.complete' : 'delegation.progress',
        row,
      );
    }
  }

  /// Reads only; never resume a child, change its credentials, or send a prompt.
  Future<List<ChatMessage>> readDelegatedConversation(
    HermesSubagentState worker, {
    int maximum = 12,
  }) async {
    final id = validateHermesOpaqueIdentifier(worker.childSessionId);
    final profile = worker.childProfile;
    if (id == null ||
        profile == null ||
        !HermesConfig.isValidDesktopProfile(profile)) {
      throw StateError('Transcript unavailable');
    }
    final rows = await loadHermesDesktopTranscriptPages(
      (offset, limit) async => _objects(
        await _requestJson(
          'GET',
          '/api/sessions/${Uri.encodeComponent(id)}/messages',
          query: {
            'profile': profile,
            'limit': limit,
            'offset': offset,
            'order': 'oldest',
          },
        ),
        'messages',
      ),
      maximum: maximum == 12 ? 100 : maximum,
      pageSize: 100,
    );
    final visible = <ChatMessage>[];
    for (final row in rows) {
      final role = row['role'];
      if (role != 'user' && role != 'assistant') continue;
      final raw = row['content'];
      final content = raw is String
          ? raw
          : raw is List
          ? raw
                .whereType<Map>()
                .where(
                  (part) =>
                      part['type'] == 'text' || part['type'] == 'output_text',
                )
                .map(
                  (part) =>
                      part['text'] is String ? part['text'] as String : '',
                )
                .join('\n')
          : '';
      final safe = safeHermesDelegatedText(
        content,
        config.sensitiveValues,
      ).trim();
      if (safe.isEmpty) continue;
      visible.add(
        ChatMessage(
          id: row['id']?.toString() ?? '${visible.length}',
          role: role as String,
          content: safe.length > 16000 ? safe.substring(0, 16000) : safe,
          metadata: {
            if (row['tool_calls'] is List)
              'hermesToolCallIds': [
                for (final call in row['tool_calls'] as List)
                  if (call is Map) ?validateHermesOpaqueIdentifier(call['id']),
              ],
          },
          timestamp:
              DateTime.tryParse(row['timestamp']?.toString() ?? '') ??
              worker.updatedAt,
        ),
      );
    }
    return List.unmodifiable(
      visible.length > maximum
          ? visible.sublist(visible.length - maximum)
          : visible,
    );
  }

  Future<String> readDelegationArtifact(
    HermesSubagentState worker,
    int index,
  ) async {
    final parent = worker.parentSessionId;
    if (parent == null) throw StateError('Artifact unavailable');
    final data = await _requestJson(
      'GET',
      '/api/plugins/conduit-delegation/artifact/${Uri.encodeComponent(worker.id)}/$index',
      query: {
        'session_id': parent,
        'profile': worker.parentProfile ?? profileForSession(parent),
      },
    );
    final body = _object(data)['text'];
    if (body is! String) throw StateError('Artifact unavailable');
    return safeHermesDelegatedText(body, config.sensitiveValues);
  }
}
