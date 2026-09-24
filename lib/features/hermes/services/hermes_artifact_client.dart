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
    final base = root.replace(path: rootPath);
    final queryParameters = <String, String>{
      'path': path,
      'profile': config.desktopProfile,
    };
    if (sessionId != null) queryParameters['session_id'] = sessionId;
    final uri = base
        .resolve('api/fs/download')
        .replace(queryParameters: queryParameters);
    if (uri.scheme.toLowerCase() != 'https' || uri.origin != root.origin) {
      throw const HermesArtifactException(
        HermesArtifactFailureKind.unavailable,
      );
    }
    return uri;
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
