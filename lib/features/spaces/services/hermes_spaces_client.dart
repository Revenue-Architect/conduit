import 'dart:convert';

import 'package:dio/dio.dart';

import '../../hermes/models/hermes_config.dart';
import '../../hermes/services/hermes_dashboard_rest_bridge.dart';
import '../../hermes/services/hermes_desktop_api_service.dart';
import '../../hermes/services/hermes_json_guard.dart';
import '../models/spaces_models.dart';

/// One response from the Spaces API: the HTTP status and decoded JSON body.
typedef SpacesResponse = ({int status, Object? json});

/// Sends one request to `/api/plugins/spaces<path>`.
typedef SpacesTransport = Future<SpacesResponse> Function(
  String method,
  String path, {
  Map<String, String>? query,
  Map<String, Object?>? body,
  CancelToken? cancelToken,
});

/// A failed Spaces request with the server's stable error code.
class SpacesApiException implements Exception {
  const SpacesApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  bool get notFound => status == 404;

  @override
  String toString() => message;
}

/// The Page changed on the server since this client loaded it. Never a
/// generic failure: the caller keeps its draft and resolves it explicitly.
class SpacesRevisionConflict extends SpacesApiException {
  const SpacesRevisionConflict(this.currentRevision)
    : super(
        409,
        'revision_conflict',
        'The page changed since this draft was loaded.',
      );

  final int currentRevision;
}

/// This Hermes does not have the Spaces plugin (or it is disabled).
class SpacesUnavailable implements Exception {
  const SpacesUnavailable();
  @override
  String toString() => 'Spaces is not available on this Hermes.';
}

const _base = '/api/plugins/spaces';

/// Spaces and Pages over the same Hermes connection and sign-in as the rest
/// of Hermes: native PKCE requests through [HermesDesktopApiService], or the
/// Dashboard cookie bridge. No arbitrary URLs; ids are validated first.
class HermesSpacesClient {
  HermesSpacesClient(this._send);

  /// The client for a connected Hermes, or null when no supported sign-in
  /// is available.
  static HermesSpacesClient? forService(Object? service, HermesConfig config) {
    if (config.mode != HermesBackendMode.desktopGateway) return null;
    if (service is HermesDesktopApiService &&
        config.desktopAuthKind == HermesDesktopAuthKind.nativePkce) {
      return HermesSpacesClient(_nativeTransport(service));
    }
    if (config.desktopAuthKind == HermesDesktopAuthKind.dashboardCookie) {
      final endpoint = HermesConfig.connectionEndpoint(config.baseUrl);
      if (endpoint == null) return null;
      final root = Uri.parse(endpoint);
      return HermesSpacesClient(
        _bridgeTransport(
          HermesDashboardRestBridge(config: config, root: root),
          root,
        ),
      );
    }
    return null;
  }

  final SpacesTransport _send;

  static const _timeout = Duration(seconds: 20);

  Future<Object?> _call(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    CancelToken? cancelToken,
  }) async {
    final SpacesResponse response;
    try {
      response = await _send(
        method,
        path,
        query: query,
        body: body,
        cancelToken: cancelToken,
      ).timeout(_timeout);
    } on SpacesApiException {
      rethrow;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw const SpacesApiException(
        0,
        'network',
        'Could not reach Hermes. Check your connection and retry.',
      );
    }
    final status = response.status;
    if (status >= 200 && status < 300) return response.json;
    final json = response.json;
    final code = json is Map && json['error'] is String
        ? json['error'] as String
        : '';
    if (status == 409 && code == 'revision_conflict') {
      final current = json is Map ? json['current_revision'] : null;
      throw SpacesRevisionConflict(current is int ? current : -1);
    }
    if (status == 404 && path == '/health') throw const SpacesUnavailable();
    final message = json is Map && json['message'] is String
        ? json['message'] as String
        : switch (status) {
            401 || 403 => 'Hermes sign-in expired. Sign in again.',
            404 => 'Not found. It may have been deleted.',
            _ => 'Spaces request failed ($status).',
          };
    throw SpacesApiException(
      status,
      code.isEmpty ? 'http_$status' : code,
      message,
    );
  }

  static String _id(String id) {
    if (!isSpacesId(id)) {
      throw const SpacesApiException(404, 'not_found', 'Not found.');
    }
    return id;
  }

  // -- capability ------------------------------------------------------------

  /// Whether this Hermes has Spaces. False for an older Hermes (404/405)
  /// rather than an error, so the rest of the app is unaffected.
  Future<bool> available() async {
    try {
      final json = await _call('GET', '/health');
      return json is Map && json['ok'] == true;
    } on SpacesUnavailable {
      return false;
    } on SpacesApiException catch (error) {
      if (error.status == 404 || error.status == 405) return false;
      rethrow;
    }
  }

  // -- spaces ----------------------------------------------------------------

  Future<List<HermesSpace>> spaces() async {
    final json = await _call('GET', '/spaces');
    return _list(json, 'spaces', HermesSpace.fromJson);
  }

  Future<HermesSpace> space(String spaceId) async {
    final json = await _call('GET', '/spaces/${_id(spaceId)}');
    return _one(json, 'space', HermesSpace.fromJson);
  }

  Future<HermesSpace> createSpace(String name) async {
    final json = await _call('POST', '/spaces', body: {'name': name});
    return _one(json, 'space', HermesSpace.fromJson);
  }

  Future<HermesSpace> renameSpace(String spaceId, String name) async {
    final json = await _call(
      'PATCH',
      '/spaces/${_id(spaceId)}',
      body: {'name': name},
    );
    return _one(json, 'space', HermesSpace.fromJson);
  }

  Future<void> deleteSpace(String spaceId, {bool cascade = false}) async {
    await _call(
      'DELETE',
      '/spaces/${_id(spaceId)}',
      query: cascade ? const {'cascade': 'true'} : null,
    );
  }

  // -- pages -----------------------------------------------------------------

  Future<List<HermesPageSummary>> pages(
    String spaceId, {
    String? query,
    bool byName = false,
    CancelToken? cancelToken,
  }) async {
    final trimmed = query?.trim() ?? '';
    final json = await _call(
      'GET',
      '/spaces/${_id(spaceId)}/pages',
      query: {
        if (trimmed.isNotEmpty)
          'q': trimmed.substring(0, trimmed.length.clamp(0, 200)),
        'sort': byName ? 'name' : 'updated',
      },
      cancelToken: cancelToken,
    );
    return _list(json, 'pages', HermesPageSummary.fromJson);
  }

  Future<HermesPage> page(String pageId, {CancelToken? cancelToken}) async {
    final json = await _call(
      'GET',
      '/pages/${_id(pageId)}',
      cancelToken: cancelToken,
    );
    return _one(json, 'page', HermesPage.fromJson);
  }

  Future<HermesPage> createPage(
    String spaceId, {
    required String title,
    String content = '',
    String? parentId,
    String? sourceSessionId,
  }) async {
    final json = await _call(
      'POST',
      '/spaces/${_id(spaceId)}/pages',
      body: {
        'title': title,
        'content': content,
        if (parentId != null) 'parent_id': _id(parentId),
        'source_session_id': ?sourceSessionId,
      },
    );
    return _one(json, 'page', HermesPage.fromJson);
  }

  /// Saves against [expectedRevision]; throws [SpacesRevisionConflict] when
  /// the Page moved on. [parentId] '' moves the Page to the top level.
  Future<HermesPage> updatePage(
    String pageId, {
    required int expectedRevision,
    String? title,
    String? content,
    String? parentId,
    CancelToken? cancelToken,
  }) async {
    final json = await _call(
      'PATCH',
      '/pages/${_id(pageId)}',
      body: {
        'expected_revision': expectedRevision,
        'title': ?title,
        'content': ?content,
        if (parentId != null)
          'parent_id': parentId.isEmpty ? null : _id(parentId),
      },
      cancelToken: cancelToken,
    );
    return _one(json, 'page', HermesPage.fromJson);
  }

  Future<void> deletePage(String pageId) async {
    await _call('DELETE', '/pages/${_id(pageId)}');
  }

  // -- page chats ------------------------------------------------------------

  /// Every profile's conversation for this Page, most recent first.
  Future<List<PageChatBinding>> pageChats(String pageId) async {
    final json = await _call('GET', '/pages/${_id(pageId)}/chats');
    return _list(json, 'chats', PageChatBinding.fromJson);
  }

  Future<PageChatBinding?> pageChat(String pageId, String profile) async {
    final json = await _call(
      'GET',
      '/pages/${_id(pageId)}/chat',
      query: {'profile': profile},
    );
    return json is Map ? PageChatBinding.fromJson(json['chat']) : null;
  }

  Future<PageChatBinding> bindPageChat(
    String pageId,
    String profile,
    String sessionId,
  ) async {
    final json = await _call(
      'PUT',
      '/pages/${_id(pageId)}/chat',
      body: {'profile': profile, 'session_id': sessionId},
    );
    return _one(json, 'chat', PageChatBinding.fromJson);
  }

  /// The Page a conversation belongs to, if any.
  Future<HermesPageSummary?> pageForSession(String sessionId) async {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$').hasMatch(sessionId)) {
      return null;
    }
    final json = await _call(
      'GET',
      '/sessions/${Uri.encodeComponent(sessionId)}/page',
    );
    return json is Map ? HermesPageSummary.fromJson(json['page']) : null;
  }

  // -- decoding --------------------------------------------------------------

  static List<T> _list<T>(Object? json, String key, T? Function(Object?) read) {
    if (json is! Map || json[key] is! List) {
      throw const SpacesApiException(
        0,
        'bad_response',
        'Unexpected reply from Hermes.',
      );
    }
    return [for (final item in (json[key] as List).take(1000)) ?read(item)];
  }

  static T _one<T>(Object? json, String key, T? Function(Object?) read) {
    final value = json is Map ? read(json[key]) : null;
    if (value == null) {
      throw const SpacesApiException(
        0,
        'bad_response',
        'Unexpected reply from Hermes.',
      );
    }
    return value;
  }
}

SpacesTransport _nativeTransport(HermesDesktopApiService service) =>
    (method, path, {query, body, cancelToken}) async {
      try {
        final json = await service.requestSpacesJson(
          method,
          '$_base$path',
          query: query,
          body: body,
          cancelToken: cancelToken,
        );
        return (status: 200, json: json);
      } on DioException catch (error) {
        final response = error.response;
        if (response == null || CancelToken.isCancel(error)) rethrow;
        return (status: response.statusCode ?? 0, json: _decode(response.data));
      }
    };

SpacesTransport _bridgeTransport(HermesDashboardRestBridge bridge, Uri root) =>
    (method, path, {query, body, cancelToken}) async {
      final prefix = root.path == '/' ? '' : root.path;
      final uri = root.replace(
        path: '$prefix$_base$path'.replaceAll(RegExp(r'//+'), '/'),
        queryParameters: query == null || query.isEmpty ? null : query,
      );
      if (uri.host != root.host || uri.port != root.port) {
        throw StateError('Cross-origin Spaces request refused.');
      }
      final response = await bridge.request(
        method,
        uri,
        body: body == null ? null : jsonEncode(body),
      );
      return (status: response.status, json: _decode(response.body));
    };

/// Decodes an error body defensively: never surfaces HTML or huge payloads.
Object? _decode(Object? data) {
  try {
    final text = switch (data) {
      final String value => value,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null || text.isEmpty || text.length > 200000) return null;
    validateHermesJsonSource(text);
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}
