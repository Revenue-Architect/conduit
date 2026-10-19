import 'package:conduit/core/services/secure_credential_storage.dart';
import 'package:conduit/features/push/platform/conduit_push_api.g.dart';
import 'package:conduit/features/push/services/push_gateway_client.dart';
import 'package:conduit/features/push/services/push_registration_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Host extends Mock implements ConduitPushHostApi {}

class _Client extends Mock implements PushGatewayClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Host host;
  late _Client client;
  late SecureCredentialStorage secure;
  late PushRegistrationService service;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secure = SecureCredentialStorage(instance: const FlutterSecureStorage());
    host = _Host();
    client = _Client();
    service = PushRegistrationService(
      host: host,
      secure: secure,
      isAndroid: true,
      clientFactory: (_, _) => client,
    );
    when(() => host.unregister()).thenAnswer((_) async {});
    when(() => host.clearVault()).thenAnswer((_) async {});
    when(() => host.register()).thenAnswer((_) async => true);
    when(() => host.syncEndpoint()).thenAnswer((_) async {});
    when(() => host.storeVault(any(), any(), any(), any()))
        .thenAnswer((_) async {});
    when(() => host.status()).thenAnswer(
      (_) async => PushNativeStatus(
        notificationsAllowed: true,
        distributors: ['io.heckel.ntfy'],
        distributorSelected: true,
        registered: true,
        paired: true,
        appBatteryUnrestricted: true,
        pendingUpload: false,
        pushCount: 0,
        tempUnavailable: false,
      ),
    );
  });

  Future<void> pair({int days = 100}) => secure.savePushDevice(
    token: 'hpd_old',
    gateway: 'https://example.test:8450',
    deviceId: 'd1',
    expiresAt: DateTime.now().add(Duration(days: days)),
    gatewayEpoch: 'epoch1',
  );

  test('epoch change discards pairing before registration or inbox', () async {
    await pair();
    when(() => client.deviceMe()).thenAnswer(
      (_) async => const DeviceHealth(raw: {'gateway_epoch': 'epoch2'}),
    );
    await service.startup();
    expect(await secure.readPushDevice(), isNull);
    verify(() => host.clearVault()).called(1);
    verifyNever(() => host.syncEndpoint());
  });

  test('near-expiry token renews both vaults before inbox sync', () async {
    await pair(days: 5);
    final expiry = DateTime.now().add(const Duration(days: 180));
    when(() => client.deviceMe()).thenAnswer(
      (_) async => const DeviceHealth(raw: {'gateway_epoch': 'epoch1'}),
    );
    when(() => client.rotateToken('d1', 'epoch1')).thenAnswer(
      (_) async => PairResult(
        deviceId: 'd1',
        token: 'hpd_new',
        expiresAt: expiry,
        scopes: [],
        gatewayEpoch: 'epoch1',
      ),
    );
    await service.startup();
    expect((await secure.readPushDevice())!.token, 'hpd_new');
    verifyInOrder([
      () => host.storeVault(
        'hpd_new',
        'https://example.test:8450',
        'd1',
        expiry.millisecondsSinceEpoch,
      ),
      () => host.syncEndpoint(),
    ]);
  });

  test('temporary network failure keeps the pairing', () async {
    await pair();
    when(() => client.deviceMe())
        .thenThrow(const PushGatewayException(message: 'offline'));
    await service.startup();
    expect((await secure.readPushDevice())!.token, 'hpd_old');
    verifyNever(() => host.clearVault());
  });

  test('revoked token requires pairing again', () async {
    await pair();
    when(() => client.deviceMe()).thenThrow(
      const PushGatewayException(message: 'revoked', statusCode: 401),
    );
    await service.startup();
    expect(await secure.readPushDevice(), isNull);
  });
}
