import 'package:pigeon/pigeon.dart';

// Native push (UnifiedPush) bridge. Kept in its own Pigeon file so the large
// `conduit_platform_apis.dart` is not touched. Regenerate with
// `dart tool/pigeon_codegen/bin/generate.dart`.

/// What the native push layer knows right now. Everything is read from local
/// state (Android, the connector, the vault); nothing here is a server claim.
@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/features/push/platform/conduit_push_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/app/src/main/kotlin/app/cogwheel/conduit/push/ConduitPushApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'app.cogwheel.conduit.push'),
    dartPackageName: 'conduit',
  ),
)
class PushNativeStatus {
  PushNativeStatus({
    required this.notificationsAllowed,
    required this.distributors,
    required this.distributorSelected,
    required this.registered,
    required this.paired,
    required this.appBatteryUnrestricted,
    required this.pendingUpload,
    required this.pushCount,
    required this.tempUnavailable,
    this.distributor,
    this.endpointGeneration,
    this.lastPushAtMs,
    this.lastUploadAtMs,
    this.distributorBatteryUnrestricted,
    this.gatewayUrl,
    this.deviceId,
    this.lastError,
  });

  /// POST_NOTIFICATIONS and the app-level switch.
  bool notificationsAllowed;

  /// Installed UnifiedPush distributor package names.
  List<String> distributors;

  /// The distributor the user chose (saved), if any.
  String? distributor;

  /// True once a distributor has been chosen and still is installed.
  bool distributorSelected;

  /// True once the distributor delivered an endpoint for this install.
  bool registered;

  /// True when a device token is in the native vault.
  bool paired;

  /// Highest endpoint generation received so far (0 when none).
  int? endpointGeneration;

  /// Epoch ms of the last push received (any type), or null.
  int? lastPushAtMs;

  /// Epoch ms of the last successful endpoint upload, or null.
  int? lastUploadAtMs;

  /// Android's own answer for Hermez; Samsung "sleeping apps" is not visible.
  bool appBatteryUnrestricted;

  /// Android's answer for the distributor package; null when unknown.
  bool? distributorBatteryUnrestricted;

  /// An endpoint upload is queued and has not succeeded yet.
  bool pendingUpload;

  /// Pushes accepted since install (for the health card).
  int pushCount;

  /// The distributor reported its backend is temporarily down.
  bool tempUnavailable;

  /// Gateway origin kept in the vault (no secrets), or null.
  String? gatewayUrl;

  /// Device id issued at pairing, or null.
  String? deviceId;

  /// Last registration or upload error code, or null.
  String? lastError;
}

/// Local preferences the native renderer needs while the app is not running.
class PushNativePrefs {
  PushNativePrefs({required this.enabled, required this.disabledCategories});

  /// Master switch for rendering pushes. Approvals and critical ignore the
  /// per-category list but still honor this one.
  bool enabled;

  /// Category ids (alerts, proactive, briefs, agent, watch, status) the user
  /// turned off.
  List<String> disabledCategories;
}

@HostApi()
abstract class ConduitPushHostApi {
  PushNativeStatus status();

  /// Installed distributor packages.
  List<String> listDistributors();

  /// The saved distributor package or null.
  String? currentDistributor();

  void saveDistributor(String packageName);

  /// Asks the system to pick/confirm a distributor (shows the OS picker when
  /// several are installed). Completes with true when one is now selected.
  @async
  bool pickDistributor();

  /// Registers this install with the selected distributor. The result is
  /// delivered asynchronously through the connector (endpoint callbacks).
  /// Returns false when no distributor is selected.
  bool register();

  /// Unregisters and forgets the distributor registration.
  void unregister();

  /// Stores the device credential and gateway origin in the native vault
  /// (Android Keystore AES-GCM).
  void storeVault(
    String token,
    String gatewayUrl,
    String deviceId,
    int expiresAtMs,
  );

  void clearVault();

  PushNativePrefs getPrefs();

  void setPrefs(PushNativePrefs prefs);

  /// Queues an endpoint upload now (used after pairing and on app start).
  void syncEndpoint();

  /// Android's battery-optimization answer for [packageName].
  bool? batteryUnrestricted(String packageName);

  /// Opens Android's battery screen for [packageName] (the app's own details
  /// page; the OS has no deeper link for Samsung sleeping apps).
  void openBatterySettings(String packageName);

  /// Opens the launcher activity of [packageName] (e.g. the distributor).
  bool openApp(String packageName);

  /// Opens the system settings page of one channel category.
  void openChannelSettings(String category);

  /// Cancels a posted push notification by its tag.
  void cancelByTag(String tag);
}

@FlutterApi()
abstract class ConduitPushFlutterApi {
  void onEndpoint(String url, String pubKey, String authSecret, int generation);

  void onRegistrationFailed(String reason);

  void onUnregistered();

  /// A decrypted, authenticated envelope arrived while the app is in the
  /// foreground. The native side did not post a system notification.
  void onForegroundEnvelope(String json);

  /// Something in [PushNativeStatus] changed.
  void onStatusChanged();
}
