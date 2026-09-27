import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/auth/native_cookie_manager.dart';
import '../../../core/auth/webview_cookie_helper.dart';
import '../models/hermes_config.dart';
import 'hermes_http_transport.dart';
import 'hermes_identifier.dart' show validateHermesOpaqueIdentifier;
import 'hermes_media_parser.dart';

enum HermesArtifactFailureKind { missing, authExpired, unavailable }

/// A sanitized artifact failure. It intentionally carries no URL, headers,
/// cookie values, server response text, or filesystem contents.
final class HermesArtifactException implements Exception {
  const HermesArtifactException(this.kind);

  final HermesArtifactFailureKind kind;

  @override
  String toString() => 'HermesArtifactException(${kind.name})';
}

final class HermesArtifactBytes {
  const HermesArtifactBytes({required this.bytes, this.contentType});

  final Uint8List bytes;
  final String? contentType;
}

final class HermesRemoteFile {
  const HermesRemoteFile({required this.name, required this.path});
  final String name;
  final String path;
}

typedef HermesArtifactCookieReader = Future<Map<String, String>> Function(
  String url,
);
typedef HermesArtifactNativeAuthorizationReader =
    Future<Map<String, String>?> Function();

/// Whether this client can safely retrieve artifacts using the current auth.
/// Dashboard cookies are only acquired for the configured HTTPS Gateway origin.
bool supportsHermesArtifactDownloads(HermesConfig config) {
  if (config.mode != HermesBackendMode.desktopGateway ||
      (config.desktopAuthKind != HermesDesktopAuthKind.dashboardCookie &&
          config.desktopAuthKind != HermesDesktopAuthKind.nativePkce)) {
    return false;
  }
  final endpoint = HermesConfig.connectionEndpoint(config.baseUrl);
  final uri = endpoint == null ? null : Uri.tryParse(endpoint);
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty;
}

/// Downloads MEDIA artifacts over the existing Hermes Dashboard session.
/// Binary responses use Dio directly; they never pass through the textual
/// WebView REST bridge.
final class HermesArtifactClient {
  HermesArtifactClient({
    required this.config,
    Dio? dio,
    HermesArtifactCookieReader? cookieReader,
    HermesArtifactNativeAuthorizationReader? nativeAuthorizationReader,
  }) : _dio = dio ?? _newDio(),
       _ownsDio = dio == null,
       _cookieReader = cookieReader ?? NativeCookieManager.getCookiesForUrl,
       _nativeAuthorizationReader = nativeAuthorizationReader {
    configureHermesTransport(_dio, config);
    // File downloads must not forward Dashboard credentials to a redirect
    // target, even if a caller injects a Dio with different defaults.
    _dio.options.followRedirects = false;
    _dio.options.validateStatus = (status) => status != null;
  }

  final HermesConfig config;
  final Dio _dio;
  final bool _ownsDio;
  final HermesArtifactCookieReader _cookieReader;
  final HermesArtifactNativeAuthorizationReader? _nativeAuthorizationReader;

  /// Lists only the app's known artifact directory. The server still enforces
  /// its authenticated filesystem policy; this is not a generic file browser.
  Future<List<HermesRemoteFile>> listDirectory(String path) async {
    if (path != '/opt/data/artifacts' ||
        !supportsHermesArtifactDownloads(config)) {
      throw const HermesArtifactException(
        HermesArtifactFailureKind.unavailable,
      );
    }
    final downloadUri = _downloadUri(path);
    final uri = downloadUri.replace(
      path: downloadUri.path.replaceFirst(RegExp(r'/download$'), '/list'),
    );
    final headers = <String, String>{};
    if (config.desktopAuthKind == HermesDesktopAuthKind.nativePkce) {
      headers.addAll(await _readNativeAuthorizationHeaders() ?? const {});
    } else {
      final cookies = await _cookieReader(uri.replace(query: '').toString());
      final cookieHeader = WebViewCookieHelper.formatCookieHeader(cookies);
      final configured = _headerValue(config.accessHeaders, 'cookie');
      final combined = [
        configured,
        cookieHeader,
      ].where((value) => value != null && value.trim().isNotEmpty).join('; ');
      if (combined.isNotEmpty) headers['Cookie'] = combined;
    }
    try {
      final response = await _dio.get<Object?>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.json,
          headers: headers,
          followRedirects: false,
          validateStatus: (status) => status != null,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status == 401 || status == 403) {
        throw const HermesArtifactException(
          HermesArtifactFailureKind.authExpired,
        );
      }
      if (status == 404) {
        throw const HermesArtifactException(HermesArtifactFailureKind.missing);
      }
      if (status < 200 || status >= 300 || response.data is! Map) {
        throw const HermesArtifactException(
          HermesArtifactFailureKind.unavailable,
        );
      }
      final entries = (response.data as Map)['entries'];
      if (entries is! List) return const [];
      return List.unmodifiable(
        entries.take(1000).whereType<Map>().map((row) {
          final name = row['name'];
          final filePath = row['path'];
          if (row['isDirectory'] == true ||
              name is! String ||
              filePath is! String ||
              name.isEmpty ||
              name.contains('/') ||
              name.contains('\\') ||
              filePath != '$path/$name') {
            return null;
          }
          return HermesRemoteFile(name: name, path: filePath);
        }).whereType<HermesRemoteFile>(),
      );
    } on HermesArtifactException {
      rethrow;
    } catch (_) {
      throw const HermesArtifactException(
        HermesArtifactFailureKind.unavailable,
      );
    }
  }

  Future<HermesArtifactBytes> download(
    HermesMediaArtifact artifact, {
    String? sessionId,
  }) async {
    if (!supportsHermesArtifactDownloads(config)) {
      throw const HermesArtifactException(
        HermesArtifactFailureKind.unavailable,
      );
    }

    final validatedSessionId = sessionId == null
        ? null
        : validateHermesOpaqueIdentifier(sessionId);
    if (sessionId != null && validatedSessionId == null) {
      throw const HermesArtifactException(
        HermesArtifactFailureKind.unavailable,
      );
    }
    final uri = _downloadUri(artifact.path, sessionId: validatedSessionId);
    return _downloadBytes(uri);
  }

  /// Kanban attachments are not necessarily under /opt/data/artifacts.
  /// Hermes authorizes these by board + attachment id and validates their
  /// stored path server-side; never substitute the returned stored_path into
  /// the general filesystem download route.
  Future<HermesArtifactBytes> downloadKanbanAttachment({
    required String board,
    required int attachmentId,
  }) async {
    if (!supportsHermesArtifactDownloads(config) ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$').hasMatch(board) ||
        attachmentId <= 0) {
      throw const HermesArtifactException(
        HermesArtifactFailureKind.unavailable,
      );
    }
    final root = _apiRoot();
    final uri = root
        .resolve('api/plugins/kanban/attachments/$attachmentId')
        .replace(queryParameters: {'board': board});
    if (uri.origin != root.origin || uri.scheme.toLowerCase() != 'https') {
      throw const HermesArtifactException(
        HermesArtifactFailureKind.unavailable,
      );
    }
    return _downloadBytes(uri);
  }

  Future<HermesArtifactBytes> _downloadBytes(Uri uri) async {
    final requestHeaders = <String, String>{};
    if (config.desktopAuthKind == HermesDesktopAuthKind.nativePkce) {
      final authorizationHeaders = await _readNativeAuthorizationHeaders();
      // An HTTPS Gateway may not require authentication. In that case the
      // native auth provider intentionally returns no Authorization header;
      // let the request proceed and map a server 401/403 to authExpired below.
      requestHeaders.addAll(authorizationHeaders ?? const <String, String>{});
    } else {
      // Ask the platform cookie store for cookies applicable to this exact
      // request path, without passing the artifact path through its URL parser.
      final cookies = await _cookieReader(
        Uri.parse(uri.toString().split('?').first).toString(),
      );
      final cookieHeader = WebViewCookieHelper.formatCookieHeader(cookies);
      final configuredCookieHeader = _headerValue(
        config.accessHeaders,
        'cookie',
      );
      final combinedCookieHeader = [
        configuredCookieHeader,
        cookieHeader,
      ].where((value) => value != null && value.trim().isNotEmpty).join('; ');
      if (combinedCookieHeader.isNotEmpty) {
        requestHeaders['Cookie'] = combinedCookieHeader;
      }
    }

    try {
      final response = await _dio.get<List<int>>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.bytes,
          headers: requestHeaders,
          followRedirects: false,
          validateStatus: (status) => status != null,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status == 401 || status == 403) {
        throw const HermesArtifactException(
          HermesArtifactFailureKind.authExpired,
        );
      }
      if (status == 404) {
        throw const HermesArtifactException(HermesArtifactFailureKind.missing);
      }
      if (status < 200 || status >= 300) {
        throw const HermesArtifactException(
          HermesArtifactFailureKind.unavailable,
        );
      }

      final responseBytes = response.data;
      return HermesArtifactBytes(
        bytes: responseBytes is Uint8List
            ? responseBytes
            : Uint8List.fromList(responseBytes ?? const <int>[]),
        contentType: response.headers.value(Headers.contentTypeHeader),
      );
    } on HermesArtifactException {
      rethrow;
    } catch (_) {
      // Do not retain or log Dio's request/response objects: they can contain
      // the Dashboard Cookie and configured access headers.
      throw const HermesArtifactException(
        HermesArtifactFailureKind.unavailable,
      );
    }
  }

  void close() {
    if (_ownsDio) _dio.close(force: true);
  }

  Future<Map<String, String>?> _readNativeAuthorizationHeaders() async {
    try {
      return await _nativeAuthorizationReader?.call();
    } catch (_) {
      // Keep token refresh and request details out of logs and UI errors.
      throw const HermesArtifactException(
        HermesArtifactFailureKind.unavailable,
      );
    }
  }

  Uri _downloadUri(String path, {String? sessionId}) {
    final root = _apiRoot();
    final queryParameters = <String, String>{
      'path': path,
      'profile': config.desktopProfile,
    };
    if (sessionId != null) queryParameters['session_id'] = sessionId;
    final uri = root
        .resolve('api/fs/download')
        .replace(queryParameters: queryParameters);
    if (uri.scheme.toLowerCase() != 'https' || uri.origin != root.origin) {
      throw const HermesArtifactException(
        HermesArtifactFailureKind.unavailable,
      );
    }
    return uri;
  }

  Uri _apiRoot() {
    final endpoint = HermesConfig.connectionEndpoint(config.baseUrl);
    final root = endpoint == null ? null : Uri.tryParse(endpoint);
    if (root == null ||
        root.scheme.toLowerCase() != 'https' ||
        root.host.isEmpty ||
        root.userInfo.isNotEmpty ||
        root.hasQuery ||
        root.hasFragment) {
      throw const HermesArtifactException(
        HermesArtifactFailureKind.unavailable,
      );
    }

    final rootPath = root.path.endsWith('/') ? root.path : '${root.path}/';
    return root.replace(path: rootPath);
  }

  static String? _headerValue(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  static Dio _newDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 2),
      followRedirects: false,
      validateStatus: (status) => status != null,
    ),
  );
}
