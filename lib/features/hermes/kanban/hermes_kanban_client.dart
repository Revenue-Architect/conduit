import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/hermes_config.dart';
import '../services/hermes_dashboard_rest_bridge.dart';

typedef KanbanRequest = Future<({int status, String body})> Function(
  String method,
  Uri uri, {
  String? body,
});

typedef KanbanNativeRequest = Future<Object?> Function(
  String method,
  String path, {
  String? board,
  Map<String, Object?>? body,
});

const kanbanLanes = <String>[
  'triage',
  'todo',
  'scheduled',
  'ready',
  'running',
  'blocked',
  'review',
  'done',
];

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

List<dynamic> _list(Object? value) => value is List ? value : const [];

final class KanbanBoardRef {
  const KanbanBoardRef(this.slug, this.name, this.total);
  final String slug;
  final String name;
  final int? total;

  factory KanbanBoardRef.fromJson(Object? value) {
    final data = _map(value);
    final slug = _text(data['slug']);
    if (slug == null) throw const FormatException('Invalid Kanban board.');
    return KanbanBoardRef(
      slug,
      _text(data['name']) ?? _text(data['title']) ?? slug,
      data['total'] is num ? (data['total'] as num).toInt() : null,
    );
  }
}

final class KanbanProfile {
  const KanbanProfile(this.name, this.description);
  final String name;
  final String? description;

  static KanbanProfile? fromJson(Object? value) {
    final data = _map(value);
    final name = _text(data['name']);
    if (name == null || !HermesConfig.isValidDesktopProfile(name)) {
      return null;
    }
    return KanbanProfile(name, _text(data['description']));
  }
}

final class KanbanTask {
  const KanbanTask({
    required this.id,
    required this.title,
    required this.status,
    this.body,
    this.assignee,
    this.priority,
    this.createdAt,
    this.summary,
    this.commentCount,
    this.childDone,
    this.childTotal,
    this.diagnostics = const [],
  });
  final String id;
  final String title;
  final String status;
  final String? body;
  final String? assignee;
  final int? priority;
  final Object? createdAt;
  final String? summary;
  final int? commentCount;
  final int? childDone;
  final int? childTotal;
  final List<Map<String, dynamic>> diagnostics;

  factory KanbanTask.fromJson(Object? value) {
    final data = _map(value);
    final id = _text(data['id']);
    if (id == null) throw const FormatException('Invalid Kanban task.');
    final progress = _map(data['progress']);
    return KanbanTask(
      id: id,
      title: _text(data['title']) ?? 'Untitled task',
      status: _text(data['status']) ?? 'unknown',
      body: _text(data['body']),
      assignee: _text(data['assignee']),
      priority: data['priority'] is num
          ? (data['priority'] as num).toInt()
          : null,
      createdAt: data['created_at'],
      summary: _text(data['latest_summary']),
      commentCount: data['comment_count'] is num
          ? (data['comment_count'] as num).toInt()
          : null,
      childDone: progress['done'] is num
          ? (progress['done'] as num).toInt()
          : null,
      childTotal: progress['total'] is num
          ? (progress['total'] as num).toInt()
          : null,
      diagnostics: _list(data['diagnostics']).map(_map).toList(growable: false),
    );
  }
}

final class KanbanSnapshot {
  const KanbanSnapshot(
    this.boardSlug,
    this.lanes,
    this.eventId,
    this.fetchedAt,
  );
  final String boardSlug;
  final Map<String, List<KanbanTask>> lanes;
  final int? eventId;
  final DateTime fetchedAt;

  factory KanbanSnapshot.fromJson(String board, Object? value) {
    final data = _map(value);
    if (data['columns'] is! List) {
      throw const FormatException('Invalid Kanban board response.');
    }
    final lanes = <String, List<KanbanTask>>{
      for (final lane in kanbanLanes) lane: <KanbanTask>[],
    };
    for (final raw in _list(data['columns'])) {
      final column = _map(raw);
      final name = _text(column['name']);
      if (name == null || !lanes.containsKey(name)) continue;
      lanes[name] = _list(column['tasks'])
          .map(KanbanTask.fromJson)
          .toList(growable: false);
    }
    return KanbanSnapshot(
      board,
      lanes,
      data['latest_event_id'] is num
          ? (data['latest_event_id'] as num).toInt()
          : null,
      DateTime.now(),
    );
  }
}

final class KanbanTaskDetail {
  const KanbanTaskDetail(
    this.task,
    this.comments,
    this.runs,
    this.events,
    this.links,
    this.attachments,
    this.childResults,
  );
  final KanbanTask task;
  final List<Map<String, dynamic>> comments;
  final List<Map<String, dynamic>> runs;
  final List<Map<String, dynamic>> events;
  final Map<String, dynamic> links;
  final List<Map<String, dynamic>> attachments;
  final List<Map<String, dynamic>> childResults;

  factory KanbanTaskDetail.fromJson(Object? value) {
    final data = _map(value);
    List<Map<String, dynamic>> records(String key) =>
        _list(data[key]).map(_map).toList(growable: false);
    return KanbanTaskDetail(
      KanbanTask.fromJson(data['task']),
      records('comments'),
      records('runs'),
      records('events'),
      _map(data['links']),
      records('attachments'),
      records('child_results'),
    );
  }
}

final class KanbanApiException implements Exception {
  const KanbanApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Uses Dashboard cookies via the existing bounded same-origin JSON bridge.
final class HermesKanbanClient {
  HermesKanbanClient(
    HermesConfig config, {
    KanbanRequest? request,
    KanbanNativeRequest? nativeRequest,
  }) : _root = Uri.parse(
         HermesConfig.connectionEndpoint(config.baseUrl) ??
             (throw const FormatException('Invalid Hermes Dashboard URL.')),
       ),
       _bridge =
           request == null &&
               config.desktopAuthKind == HermesDesktopAuthKind.dashboardCookie
           ? HermesDashboardRestBridge(
               config: config,
               root: Uri.parse(
                 HermesConfig.connectionEndpoint(config.baseUrl)!,
               ),
             )
           : null,
       _requestOverride = request,
       _nativeRequest = nativeRequest,
       _authKind = config.desktopAuthKind {
    if (config.mode != HermesBackendMode.desktopGateway) {
      throw StateError('Kanban requires Hermes Desktop Gateway.');
    }
  }

  final Uri _root;
  final HermesDashboardRestBridge? _bridge;
  final KanbanRequest? _requestOverride;
  final KanbanNativeRequest? _nativeRequest;
  final HermesDesktopAuthKind _authKind;

  Uri uri(String path, {String? board}) {
    if (board != null && board.trim().isEmpty) {
      throw ArgumentError.value(board, 'board', 'Board is required.');
    }
    final prefix = _root.path == '/' ? '' : _root.path;
    final target = _root.replace(
      path: '$prefix/api/plugins/kanban$path'.replaceAll(RegExp(r'//+'), '/'),
      queryParameters: board == null ? null : {'board': board},
    );
    if (target.scheme != _root.scheme ||
        target.host != _root.host ||
        target.port != _root.port) {
      throw StateError('Cross-origin Kanban request refused.');
    }
    return target;
  }

  Future<Object?> _json(
    String method,
    String path, {
    String? board,
    Map<String, Object?>? body,
  }) async {
    if (_authKind == HermesDesktopAuthKind.nativePkce &&
        _requestOverride == null) {
      final native = _nativeRequest;
      if (native == null) {
        throw const KanbanApiException(401, 'Native Hermes sign-in required.');
      }
      try {
        return await native(
          method,
          '/api/plugins/kanban$path',
          board: board,
          body: body,
        );
      } on DioException catch (error) {
        final status = error.response?.statusCode ?? 0;
        throw KanbanApiException(status, switch (status) {
          401 || 403 => 'Native Hermes sign-in expired. Sign in and retry.',
          404 => 'Board or task not found. Refresh the board.',
          409 => 'This transition conflicts with the current task state.',
          _ => 'Kanban request failed. Check your connection and retry.',
        });
      }
    }
    if (_requestOverride == null && _bridge == null) {
      throw const KanbanApiException(
        401,
        'Choose native or Dashboard Hermes sign-in.',
      );
    }
    final response = await (_requestOverride ?? _bridge!.request)(
      method,
      uri(path, board: board),
      body: body == null ? null : jsonEncode(body),
    );
    if (response.status < 200 || response.status >= 300) {
      String? detail;
      try {
        detail = _text(_map(jsonDecode(response.body))['detail']);
      } catch (_) {
        /* Do not expose HTML or transport secrets. */
      }
      throw KanbanApiException(response.status, switch (response.status) {
        401 ||
        403 => 'Dashboard sign-in required. Open Hermes sign-in and retry.',
        404 => 'Board or task not found. Refresh the board.',
        409 =>
          detail ?? 'This transition conflicts with the current task state.',
        _ => detail ?? 'Kanban request failed (${response.status}).',
      });
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  Future<List<KanbanBoardRef>> boards() async =>
      _list(_map(await _json('GET', '/boards'))['boards'])
          .map(KanbanBoardRef.fromJson)
          .toList(growable: false);

  Future<List<KanbanProfile>> profiles() async =>
      _list(_map(await _json('GET', '/profiles'))['profiles'])
          .take(256)
          .map(KanbanProfile.fromJson)
          .whereType<KanbanProfile>()
          .toList(growable: false);

  Future<KanbanSnapshot> board(String slug) async =>
      KanbanSnapshot.fromJson(slug, await _json('GET', '/board', board: slug));

  Future<KanbanTaskDetail> task(String board, String id) async =>
      KanbanTaskDetail.fromJson(
        await _json('GET', '/tasks/${Uri.encodeComponent(id)}', board: board),
      );

  Future<void> create(
    String board,
    String title, {
    bool triage = false,
    String? assignee,
    String? body,
    int priority = 0,
  }) async {
    await _json(
      'POST',
      '/tasks',
      board: board,
      body: {
        'title': title,
        'triage': triage,
        'priority': priority,
        if (assignee != null && assignee.isNotEmpty) 'assignee': assignee,
        if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
      },
    );
  }

  Future<void> comment(String board, String id, String body) async {
    await _json(
      'POST',
      '/tasks/${Uri.encodeComponent(id)}/comments',
      board: board,
      body: {'body': body},
    );
  }

  Future<void> patchTask(
    String board,
    String id,
    Map<String, Object?> fields,
  ) async {
    if (fields.length != 1 ||
        !const {
          'title',
          'assignee',
          'priority',
          'status',
        }.contains(fields.keys.single) ||
        fields['status'] == 'running') {
      throw ArgumentError.value(fields, 'fields', 'Unsafe Kanban patch.');
    }
    await _json(
      'PATCH',
      '/tasks/${Uri.encodeComponent(id)}',
      board: board,
      body: fields,
    );
  }

  Future<void> close() => _bridge?.close() ?? Future<void>.value();
}
