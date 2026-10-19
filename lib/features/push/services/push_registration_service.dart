import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/services/secure_credential_storage.dart';
import '../../../core/utils/debug_logger.dart';
import '../platform/conduit_push_api.g.dart';
import 'push_gateway_client.dart';

/// How a request to switch push on ended.
enum PushEnableResult {
  /// A distributor is selected and registration was requested.
  ok,

  /// No UnifiedPush distributor (ntfy) is installed.
  noDistributor,

  /// This phone has not been paired with the gateway.
  notPaired,

  /// Android refused or the native layer failed.
  failed,
}

/// Wraps the native push bridge and the secure pairing record. It owns the
/// order of operations (pair, store vault, pick distributor, register, upload
/// endpoint) so the UI and startup code never repeat it.
class PushRegistrationService {
  PushRegistrationService({
    required ConduitPushHostApi host,
    required SecureCredentialStorage secure,
    bool? isAndroid,
  }) : _host = host,
       _secure = secure,
       _android = isAndroid ?? Platform.isAndroid;

  final ConduitPushHostApi _host;
  final SecureCredentialStorage _secure;
  final bool _android;

  bool get supported => _android;

  /// What the native layer knows right now; null off Android or on failure.
  Future<PushNativeStatus?> nativeStatus() async {
    if (!_android) return null;
    try {
      return await _host.status();
    } on PlatformException catch (error) {
      DebugLogger.warning(
        'native-status-failed',
        scope: 'push/registration',
        data: {'code': error.code},
      );
      return null;
    }
  }

  Future<PushDeviceSecrets?> pairing() async {
    try {
      return await _secure.readPushDevice();
    } catch (error) {
      DebugLogger.warning(
        'pairing-read-failed',
        scope: 'push/registration',
        data: {'errorType': error.runtimeType.toString()},
      );
      return null;
    }
  }

  /// Stores a fresh pairing (secure storage, then the native vault).
  Future<void> savePairing(PairResult result, String origin) async {
    await _secure.savePushDevice(
      token: result.token,
      gateway: origin,
      deviceId: result.deviceId,
      expiresAt: result.expiresAt,
    );
    if (_android) {
      await _host.storeVault(
        result.token,
        origin,
        result.deviceId,
        result.expiresAt.millisecondsSinceEpoch,
      );
    }
  }

  /// Forgets this phone's pairing. The server-side device is revoked from the
  /// Umbrel (`notifyctl devices revoke`); this only removes local credentials.
  Future<void> forgetPairing() async {
    if (_android) {
      try {
        await _host.unregister();
      } on PlatformException {
        // Nothing registered; fine.
      }
      await _host.clearVault();
    }
    await _secure.deletePushDevice();
  }

  /// Picks the distributor if needed, registers, and queues the endpoint
  /// upload. Safe to call repeatedly.
  Future<PushEnableResult> enable() async {
    if (!_android) return PushEnableResult.failed;
    try {
      if (await pairing() == null) return PushEnableResult.notPaired;
      final picked = await _host.pickDistributor();
      if (!picked) return PushEnableResult.noDistributor;
      final registered = await _host.register();
      if (!registered) return PushEnableResult.noDistributor;
      await _host.syncEndpoint();
      return PushEnableResult.ok;
    } on PlatformException catch (error) {
      DebugLogger.warning(
        'enable-failed',
        scope: 'push/registration',
        data: {'code': error.code},
      );
      return PushEnableResult.failed;
    }
  }

  /// Runs on app start (after the app is ready): re-asserts registration and
  /// repairs a lost native vault from secure storage.
  Future<void> startup() async {
    if (!_android) return;
    try {
      final pairing = await this.pairing();
      if (pairing == null) return;
      final status = await _host.status();
      if (!status.paired) {
        await _host.storeVault(
          pairing.token,
          pairing.gateway,
          pairing.deviceId,
          (pairing.expiresAt ?? DateTime.now().add(const Duration(days: 180)))
              .millisecondsSinceEpoch,
        );
      }
      if (status.distributorSelected) {
        await _host.register();
        await _host.syncEndpoint();
      }
    } on PlatformException catch (error) {
      DebugLogger.warning(
        'startup-failed',
        scope: 'push/registration',
        data: {'code': error.code},
      );
    }
  }

  Future<List<String>> distributors() async {
    if (!_android) return const [];
    try {
      return await _host.listDistributors();
    } on PlatformException {
      return const [];
    }
  }

  Future<void> chooseDistributor(String packageName) async {
    await _host.saveDistributor(packageName);
    await _host.register();
    await _host.syncEndpoint();
  }

  Future<PushNativePrefs> prefs() => _host.getPrefs();

  Future<void> setPrefs({
    required bool enabled,
    required Set<String> disabledCategories,
  }) => _host.setPrefs(
    PushNativePrefs(
      enabled: enabled,
      disabledCategories: disabledCategories.toList()..sort(),
    ),
  );

  Future<void> openBatterySettings(String packageName) =>
      _host.openBatterySettings(packageName);

  Future<bool> openApp(String packageName) => _host.openApp(packageName);

  Future<void> openChannelSettings(String category) =>
      _host.openChannelSettings(category);

  Future<void> dismissNotification(String tag) async {
    if (!_android) return;
    try {
      await _host.cancelByTag(tag);
    } on PlatformException {
      // The notification may already be gone.
    }
  }
}
