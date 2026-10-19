import 'package:dio/dio.dart';

import '../models/approval.dart';

/// A gateway call that did not succeed. [code] is the gateway's `error` string
/// when it sent one; [statusCode] is null for network failures.
class PushGatewayException implements Exception {
  const PushGatewayException({
    required this.message,
    this.statusCode,
    this.code,
    this.currentStatus,
  });

  final String message;
  final int? statusCode;
  final String? code;

  /// For a 409, the status the request already has (approved, denied, ...).
  final ApprovalStatus? currentStatus;

  bool get isNetwork => statusCode == null;
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;
  bool get isConflict => statusCode == 409;
  bool get isNotFound => statusCode == 404 || statusCode == 410;
  bool get isDigestMismatch => code == 'digest_mismatch';

  @override
  String toString() => 'PushGatewayException($statusCode, $code, $message)';
}

class PairResult {
  const PairResult({
    required this.deviceId,
    required this.token,
    required this.expiresAt,
    required this.scopes,
  });

  final String deviceId;
  final String token;
  final DateTime expiresAt;
  final List<String> scopes;
}

/// What the gateway says about this device (`GET /devices/me`). The route's
/// field names are read leniently; missing fields mean "unknown", never "ok".
class DeviceHealth {
  const DeviceHealth({
    required this.raw,
    this.name,
    this.endpointState,
    this.fallbackCategories = const [],
    this.lastAckAt,
  });

  final Map<String, dynamic> raw;
  final String? name;

  /// verified | unverified | degraded | retired | none, as the server reports.
  final String? endpointState;
  final List<String> fallbackCategories;
  final DateTime? lastAckAt;

  static DeviceHealth fromJson(Object? value) {
    final map = value is Map ? Map<String, dynamic>.from(value) : const {};
    final device = map['device'] is Map ? Map<String, dynamic>.from(map['device']) : map;
    final endpoint = map['endpoint'] is Map ? Map<String, dynamic>.from(map['endpoint']) : const <String, dynamic>{};
    final fallback = map['fallback'] ?? map['fallback_flags'] ?? map['fallbacks'];
    final categories = <String>[];
    final perCategory = map['categories'];
    if (perCategory is Map) {
      // Live gateway: {<cat>: {mode, fallback_active}}.
      perCategory.forEach((key, value) {
        if (value is Map && value['fallback_active'] == true) {
          categories.add('$key');
        }
      });
    }
    if (fallback is Map) {
      fallback.forEach((key, flag) {
        if (flag == true || (flag is Map && flag['active'] == true)) {
          categories.add('$key');
        }
      });
    } else if (fallback is List) {
      categories.addAll(fallback.whereType<String>());
    }
    final state = endpoint['state'] ?? map['endpoint_state'] ?? device['endpoint_state'];
    return DeviceHealth(
      raw: Map<String, dynamic>.from(map),
      name: device['name'] is String ? device['name'] as String : null,
      endpointState: state is String ? state : null,
      fallbackCategories: categories,
      lastAckAt: _epochOrIso(endpoint['last_ack_at'] ?? map['last_ack_at']),
    );
  }
}

DateTime? _epochOrIso(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true).toLocal();
  }
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

/// Normalizes what a person typed into a gateway origin (`https://host:port`),
/// or returns null when it cannot be one. A pasted `/phone/v1` tail is removed.
String? normalizeGatewayOrigin(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  if (uri.userInfo.isNotEmpty) return null;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  ).toString();
}

/// Normalizes the one-time pairing code: spaces and dashes removed, upper case.
String normalizePairingCode(String input) =>
    input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

/// The Dart side of the phone gateway (spec 5.3). The device token is only ever
/// sent as a bearer header and is never logged.
class PushGatewayClient {
  PushGatewayClient({
    required String origin,
    required String token,
    Dio? dio,
  }) : _dio = dio ?? _newDio(),
       _base = '${origin.replaceAll(RegExp(r'/+$'), '')}/phone/v1',
       _token = token;

  final Dio _dio;
  final String _base;
  final String _token;

  static Dio _newDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      followRedirects: false,
      validateStatus: (_) => true,
      responseType: ResponseType.json,
    ),
  );

  /// `POST /pair` (no token yet).
  static Future<PairResult> pair({
    required String origin,
    required String code,
    required String deviceName,
    required String appVersion,
    Dio? dio,
  }) async {
    final client = dio ?? _newDio();
    final response = await _send(
      () => client.post<Object?>(
        '${origin.replaceAll(RegExp(r'/+$'), '')}/phone/v1/pair',
        data: {
          'code': normalizePairingCode(code),
          'device_name': deviceName,
          'platform': 'android',
          'app_version': appVersion,
        },
      ),
    );
    final body = response.data;
    if (body is! Map ||
        body['token'] is! String ||
        body['device_id'] is! String) {
      throw const PushGatewayException(
        message: 'The gateway answered with an unexpected reply.',
      );
    }
    final scopes = body['scopes'];
    return PairResult(
      deviceId: body['device_id'] as String,
      token: body['token'] as String,
      expiresAt:
          _epochOrIso(body['expires_at']) ??
          DateTime.now().add(const Duration(days: 180)),
      scopes: scopes is List ? scopes.whereType<String>().toList() : const [],
    );
  }

  Future<DeviceHealth> deviceMe() async {
    final response = await _send(() => _get('/devices/me'));
    return DeviceHealth.fromJson(response.data);
  }

  Future<ApprovalPage> listApprovals({
    String status = 'pending',
    int limit = 50,
    String? before,
  }) async {
    final response = await _send(
      () => _get(
        '/approvals',
        query: {
          'status': status,
          'limit': limit,
          'before': ?before,
        },
      ),
    );
    return ApprovalPage.fromJson(response.data);
  }

  Future<Approval> getApproval(String id) async {
    final response = await _send(() => _get('/approvals/${Uri.encodeComponent(id)}'));
    final data = response.data;
    final item = data is Map && data['item'] is Map ? data['item'] : data;
    final approval = Approval.fromJson(item);
    if (approval == null) {
      throw const PushGatewayException(
        message: 'The gateway sent an approval that could not be read.',
      );
    }
    return approval;
  }

  /// Sends one decision. The idempotency key makes a repeated tap harmless;
  /// the digest proves the person decided on the request they saw.
  Future<ApprovalStatus> decide({
    required String id,
    required ApprovalDecision decision,
    required String digest,
    required String deviceId,
    String? notes,
  }) async {
    final response = await _send(
      () => _dio.post<Object?>(
        '$_base/approvals/${Uri.encodeComponent(id)}/decision',
        data: {
          'decision': decision.wire,
          'digest': digest,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
        options: _options(
          headers: {'Idempotency-Key': 'dec-$id-${decision.wire}-$deviceId'},
        ),
      ),
    );
    final data = response.data;
    final status = data is Map ? ApprovalStatus.parse(data['status']) : ApprovalStatus.unknown;
    if (status != ApprovalStatus.unknown) return status;
    return decision == ApprovalDecision.approve
        ? ApprovalStatus.approved
        : ApprovalStatus.denied;
  }

  Future<Response<Object?>> _get(String path, {Map<String, Object?>? query}) =>
      _dio.get<Object?>(
        '$_base$path',
        queryParameters: query,
        options: _options(),
      );

  Options _options({Map<String, String>? headers}) => Options(
    headers: {
      'Authorization': 'Bearer $_token',
      'Accept': 'application/json',
      ...?headers,
    },
  );

  /// Runs [call], turns transport failures and non-2xx replies into
  /// [PushGatewayException]s that never carry the token.
  static Future<Response<Object?>> _send(
    Future<Response<Object?>> Function() call,
  ) async {
    final Response<Object?> response;
    try {
      response = await call();
    } on DioException catch (error) {
      final carried = error.response;
      if (error.type == DioExceptionType.badResponse && carried != null) {
        return _checked(carried);
      }
      throw PushGatewayException(
        message: switch (error.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.sendTimeout => 'Hermes did not answer in time.',
          _ => 'Could not reach Hermes. Check Tailscale and try again.',
        },
      );
    }
    return _checked(response);
  }

  static Response<Object?> _checked(Response<Object?> response) {
    final code = response.statusCode ?? 0;
    if (code >= 200 && code < 300) return response;
    final data = response.data;
    final error = data is Map && data['error'] is String ? data['error'] as String : null;
    throw PushGatewayException(
      message: _messageFor(code, error),
      statusCode: code,
      code: error,
      currentStatus: data is Map ? ApprovalStatus.parse(data['status']) : null,
    );
  }

  static String _messageFor(int code, String? error) {
    if (code == 401 || code == 403) {
      return 'This phone is no longer paired. Pair it again in Notifications.';
    }
    if (code == 404 || code == 410) return 'Hermes no longer has this request.';
    if (code == 409) {
      return error == 'digest_mismatch'
          ? 'This request changed. Open it again to review.'
          : 'This request was already decided.';
    }
    if (code == 429) return 'Too many tries. Wait a minute and try again.';
    if (code >= 500) return 'Hermes had a problem. Try again shortly.';
    return 'Hermes rejected the request ($code).';
  }
}
