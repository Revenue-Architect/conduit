import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/providers/storage_providers.dart';
import '../../../core/services/secure_credential_storage.dart';
import '../../../core/utils/debug_logger.dart';
import '../models/approval.dart';
import '../models/push_health.dart';
import '../platform/conduit_push_api.g.dart';
import '../services/push_gateway_client.dart';
import '../services/push_registration_service.dart';

/// The native bridge. Overridden in tests with a fake.
final pushHostApiProvider = Provider<ConduitPushHostApi>(
  (ref) => ConduitPushHostApi(),
);

final pushSecureStorageProvider = Provider<SecureCredentialStorage>(
  (ref) => SecureCredentialStorage(instance: ref.watch(secureStorageProvider)),
);

final pushRegistrationServiceProvider = Provider<PushRegistrationService>(
  (ref) => PushRegistrationService(
    host: ref.watch(pushHostApiProvider),
    secure: ref.watch(pushSecureStorageProvider),
  ),
);

/// The gateway client for the current pairing, or null when not paired.
/// Overridden in tests. Re-read after pairing/unpairing through
/// [pushPairingProvider].
final pushGatewayClientProvider = Provider<PushGatewayClient?>((ref) {
  final pairing = ref.watch(pushPairingProvider).asData?.value;
  if (pairing == null) return null;
  return PushGatewayClient(origin: pairing.gateway, token: pairing.token);
});

/// The stored pairing. Invalidate after pair/unpair.
final pushPairingProvider = FutureProvider<PushDeviceSecrets?>(
  (ref) => ref.watch(pushRegistrationServiceProvider).pairing(),
);

/// Local facts (native) plus the server's view, as the health card needs.
class PushStatus {
  const PushStatus({
    required this.native,
    required this.server,
    required this.serverError,
    required this.serverChecked,
    required this.health,
  });

  final PushNativeStatus? native;
  final DeviceHealth? server;
  final String? serverError;
  final bool serverChecked;
  final PushHealth health;

  bool get paired => native?.paired ?? false;
}

class PushStatusNotifier extends AsyncNotifier<PushStatus> {
  @override
  Future<PushStatus> build() => _load(checkServer: true);

  /// Re-reads native state and asks the gateway again.
  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _load(checkServer: true));
  }

  /// Re-reads only native state (cheap; used on native change callbacks).
  Future<void> refreshLocal() async {
    final previous = state.asData?.value;
    final next = await AsyncValue.guard(
      () => _load(
        checkServer: false,
        keepServer: previous?.server,
        keepServerError: previous?.serverError,
        keepChecked: previous?.serverChecked ?? false,
      ),
    );
    state = next;
  }

  Future<PushStatus> _load({
    required bool checkServer,
    DeviceHealth? keepServer,
    String? keepServerError,
    bool keepChecked = false,
  }) async {
    final service = ref.read(pushRegistrationServiceProvider);
    final native = await service.nativeStatus();
    DeviceHealth? server = keepServer;
    String? serverError = keepServerError;
    var checked = keepChecked;
    if (checkServer && native != null && native.paired) {
      final pairing = await service.pairing();
      if (pairing != null) {
        try {
          server = await PushGatewayClient(
            origin: pairing.gateway,
            token: pairing.token,
          ).deviceMe();
          serverError = null;
        } on PushGatewayException catch (error) {
          server = null;
          serverError = error.message;
        }
        checked = true;
      }
    }
    return PushStatus(
      native: native,
      server: server,
      serverError: serverError,
      serverChecked: checked,
      health: evaluatePushHealth(
        native: native,
        server: server,
        serverError: serverError,
        serverChecked: checked,
      ),
    );
  }
}

final pushStatusProvider =
    AsyncNotifierProvider<PushStatusNotifier, PushStatus>(
      PushStatusNotifier.new,
    );

/// Pending approvals, newest first.
final approvalsPendingProvider = FutureProvider.autoDispose<List<Approval>>((
  ref,
) async {
  final client = ref.watch(pushGatewayClientProvider);
  if (client == null) return const [];
  final page = await client.listApprovals(status: 'pending', limit: 50);
  return page.items.where((a) => a.isPending).toList();
});

/// One approval with its payload and event timeline.
final approvalDetailProvider = FutureProvider.autoDispose
    .family<Approval, String>((ref, id) async {
      final client = ref.watch(pushGatewayClientProvider);
      if (client == null) {
        throw const PushGatewayException(
          message: 'This phone is not paired with Hermes yet.',
          statusCode: 401,
        );
      }
      return client.getApproval(id);
    });

/// Decided and expired approvals, paged by the gateway's `before` cursor.
class ApprovalsHistoryState {
  const ApprovalsHistoryState({
    this.items = const [],
    this.nextBefore,
    this.loading = false,
    this.loaded = false,
    this.error,
  });

  final List<Approval> items;
  final String? nextBefore;
  final bool loading;
  final bool loaded;
  final String? error;

  bool get hasMore => nextBefore != null;

  ApprovalsHistoryState copyWith({
    List<Approval>? items,
    Object? nextBefore = _keep,
    bool? loading,
    bool? loaded,
    Object? error = _keep,
  }) => ApprovalsHistoryState(
    items: items ?? this.items,
    nextBefore: identical(nextBefore, _keep)
        ? this.nextBefore
        : nextBefore as String?,
    loading: loading ?? this.loading,
    loaded: loaded ?? this.loaded,
    error: identical(error, _keep) ? this.error : error as String?,
  );
}

const Object _keep = Object();

class ApprovalsHistoryNotifier extends Notifier<ApprovalsHistoryState> {
  static const int pageSize = 30;

  @override
  ApprovalsHistoryState build() => const ApprovalsHistoryState();

  Future<void> refresh() async {
    state = const ApprovalsHistoryState();
    await loadMore();
  }

  Future<void> loadMore() async {
    if (state.loading) return;
    final client = ref.read(pushGatewayClientProvider);
    if (client == null) {
      state = state.copyWith(loaded: true);
      return;
    }
    if (state.loaded && !state.hasMore) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final page = await client.listApprovals(
        status: 'all',
        limit: pageSize,
        before: state.nextBefore,
      );
      final seen = {for (final a in state.items) a.id};
      final fresh = page.items
          .where((a) => !a.isPending && seen.add(a.id))
          .toList();
      state = state.copyWith(
        items: [...state.items, ...fresh],
        nextBefore: page.nextBefore,
        loading: false,
        loaded: true,
      );
    } on PushGatewayException catch (error) {
      state = state.copyWith(loading: false, loaded: true, error: error.message);
    }
  }
}

final approvalsHistoryProvider =
    NotifierProvider<ApprovalsHistoryNotifier, ApprovalsHistoryState>(
      ApprovalsHistoryNotifier.new,
    );

/// How a decision ended, for the UI to explain in plain words.
enum ApprovalDecisionKind {
  decided,
  alreadyDecided,
  changed,
  gone,
  notPaired,
  failed,
}

class ApprovalDecisionOutcome {
  const ApprovalDecisionOutcome(this.kind, this.message, {this.status});

  final ApprovalDecisionKind kind;
  final String message;
  final ApprovalStatus? status;

  bool get succeeded => kind == ApprovalDecisionKind.decided;
}

/// Sends decisions from inside the app and keeps every list in step.
class ApprovalDecider {
  ApprovalDecider(this._ref);

  final Ref _ref;

  Future<ApprovalDecisionOutcome> decide(
    Approval approval,
    ApprovalDecision decision,
  ) async {
    final client = _ref.read(pushGatewayClientProvider);
    final pairing = _ref.read(pushPairingProvider).asData?.value;
    final digest = approval.payloadDigest;
    if (client == null || pairing == null) {
      return const ApprovalDecisionOutcome(
        ApprovalDecisionKind.notPaired,
        'This phone is not paired with Hermes yet.',
      );
    }
    if (digest == null || digest.isEmpty) {
      return const ApprovalDecisionOutcome(
        ApprovalDecisionKind.changed,
        'This request has no verification code. Refresh and try again.',
      );
    }
    try {
      final status = await client.decide(
        id: approval.id,
        decision: decision,
        digest: digest,
        deviceId: pairing.deviceId,
      );
      await _afterChange(approval);
      return ApprovalDecisionOutcome(
        ApprovalDecisionKind.decided,
        status == ApprovalStatus.approved ? 'Approved.' : 'Denied.',
        status: status,
      );
    } on PushGatewayException catch (error) {
      if (error.isConflict) {
        await _afterChange(approval);
        if (error.isDigestMismatch) {
          return ApprovalDecisionOutcome(
            ApprovalDecisionKind.changed,
            error.message,
          );
        }
        final current = error.currentStatus;
        final word = current == null || current == ApprovalStatus.unknown
            ? 'decided'
            : current.label.toLowerCase();
        return ApprovalDecisionOutcome(
          ApprovalDecisionKind.alreadyDecided,
          'Already $word.',
          status: current,
        );
      }
      if (error.isNotFound) {
        await _afterChange(approval);
        return ApprovalDecisionOutcome(ApprovalDecisionKind.gone, error.message);
      }
      if (error.isUnauthorized) {
        return ApprovalDecisionOutcome(
          ApprovalDecisionKind.notPaired,
          error.message,
        );
      }
      return ApprovalDecisionOutcome(ApprovalDecisionKind.failed, error.message);
    }
  }

  Future<void> _afterChange(Approval approval) async {
    _ref.invalidate(approvalsPendingProvider);
    _ref.invalidate(approvalDetailProvider(approval.id));
    unawaited(_ref.read(approvalsHistoryProvider.notifier).refresh());
    unawaited(
      _ref
          .read(pushRegistrationServiceProvider)
          .dismissNotification('approval:${approval.id}'),
    );
  }
}

final approvalDeciderProvider = Provider<ApprovalDecider>(ApprovalDecider.new);

/// What the pairing page does: exchange the code, store the credentials, then
/// switch push on. Returns a message for the person; null on success.
class PushPairingController {
  PushPairingController(this._ref);

  final Ref _ref;

  Future<String?> pair({
    required String origin,
    required String code,
    required String deviceName,
  }) async {
    final normalized = normalizeGatewayOrigin(origin);
    if (normalized == null) return 'Enter the gateway address, for example https://umbrel.tail4c9e01.ts.net:8450.';
    final cleaned = normalizePairingCode(code);
    if (cleaned.length < 8) return 'Enter the pairing code from the Umbrel.';
    final service = _ref.read(pushRegistrationServiceProvider);
    String version = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Version is informational only.
    }
    try {
      final result = await PushGatewayClient.pair(
        origin: normalized,
        code: cleaned,
        deviceName: deviceName.trim().isEmpty ? 'Android phone' : deviceName.trim(),
        appVersion: version,
      );
      await service.savePairing(result, normalized);
    } on PushGatewayException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403 || error.statusCode == 400) {
        return 'That code was not accepted. Codes work once and expire after '
            'five minutes. Create a new one and try again.';
      }
      return error.message;
    }
    _ref.invalidate(pushPairingProvider);
    final enabled = await service.enable();
    DebugLogger.log('paired', scope: 'push/pairing', data: {'enable': enabled.name});
    await _ref.read(pushStatusProvider.notifier).refresh();
    return switch (enabled) {
      PushEnableResult.ok => null,
      PushEnableResult.noDistributor =>
        'Paired. Install ntfy from the Play Store, open it once, then check '
            'push health.',
      PushEnableResult.notPaired => 'Pairing was not saved. Try again.',
      PushEnableResult.failed => 'Paired, but Android did not register push. '
          'Check push health.',
    };
  }

  Future<void> unpair() async {
    await _ref.read(pushRegistrationServiceProvider).forgetPairing();
    _ref.invalidate(pushPairingProvider);
    await _ref.read(pushStatusProvider.notifier).refresh();
  }
}

final pushPairingControllerProvider = Provider<PushPairingController>(
  PushPairingController.new,
);
