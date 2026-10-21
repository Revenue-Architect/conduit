import 'package:checks/checks.dart';
import 'package:conduit/features/push/models/push_health.dart';
import 'package:conduit/features/push/platform/conduit_push_api.g.dart';
import 'package:conduit/features/push/services/push_gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';

PushNativeStatus _native({
  bool allowed = true,
  List<String> distributors = const ['io.heckel.ntfy'],
  String? distributor = 'io.heckel.ntfy',
  bool registered = true,
  bool paired = true,
  bool appUnrestricted = true,
  bool? distributorUnrestricted = true,
  bool pendingUpload = false,
  bool tempUnavailable = false,
  String? lastError,
  int? lastPush,
}) => PushNativeStatus(
  notificationsAllowed: allowed,
  distributors: distributors,
  distributor: distributor,
  distributorSelected: distributor != null,
  registered: registered,
  paired: paired,
  appBatteryUnrestricted: appUnrestricted,
  distributorBatteryUnrestricted: distributorUnrestricted,
  pendingUpload: pendingUpload,
  pushCount: 3,
  tempUnavailable: tempUnavailable,
  lastError: lastError,
  lastPushAtMs: lastPush,
);

DeviceHealth _server({String state = 'verified', List<String> fallback = const []}) =>
    DeviceHealth(raw: const {}, endpointState: state, fallbackCategories: fallback);

PushHealth _eval(
  PushNativeStatus? native, {
  DeviceHealth? server,
  String? error,
  bool checked = true,
}) => evaluatePushHealth(
  native: native,
  server: server,
  serverError: error,
  serverChecked: checked,
);

void main() {
  test('everything good is healthy', () {
    final h = _eval(_native(lastPush: 1760841600000), server: _server());
    check(h.level).equals(PushHealthLevel.healthy);
    check(h.issues).isEmpty();
    check(h.lastPushAt).isNotNull();
  });

  test('off Android there is nothing to set up', () {
    final h = _eval(null);
    check(h.level).equals(PushHealthLevel.off);
    check(h.has(PushIssue.unsupported)).isTrue();
  });

  test('blocked notifications are a problem', () {
    final h = _eval(_native(allowed: false), server: _server());
    check(h.level).equals(PushHealthLevel.problem);
    check(h.headline).contains('blocking');
  });

  test('not paired is a problem and skips the server check', () {
    final h = _eval(_native(paired: false, registered: false));
    check(h.level).equals(PushHealthLevel.problem);
    check(h.has(PushIssue.notPaired)).isTrue();
    check(h.has(PushIssue.serverUnreachable)).isFalse();
  });

  test('no distributor installed', () {
    final h = _eval(
      _native(distributors: const [], distributor: null, registered: false),
    );
    check(h.has(PushIssue.noDistributor)).isTrue();
    check(h.headline).contains('Install ntfy');
  });

  test('installed but not chosen', () {
    final h = _eval(_native(distributor: null, registered: false));
    check(h.has(PushIssue.distributorNotSelected)).isTrue();
  });

  test('chosen but never registered', () {
    final h = _eval(_native(registered: false));
    check(h.has(PushIssue.notRegistered)).isTrue();
    check(h.level).equals(PushHealthLevel.problem);
  });

  test('pending and failed uploads are warnings with different text', () {
    check(_eval(_native(pendingUpload: true), server: _server()).has(PushIssue.uploadPending)).isTrue();
    final failed = _eval(
      _native(pendingUpload: true, lastError: 'endpoint_rejected_400'),
      server: _server(),
    );
    check(failed.has(PushIssue.uploadFailed)).isTrue();
    check(failed.level).equals(PushHealthLevel.warning);
  });

  test('battery restrictions are warnings', () {
    final h = _eval(
      _native(appUnrestricted: false, distributorUnrestricted: false),
      server: _server(),
    );
    check(h.level).equals(PushHealthLevel.warning);
    check(h.has(PushIssue.appBatteryRestricted)).isTrue();
    check(h.has(PushIssue.distributorBatteryRestricted)).isTrue();
  });

  test('an unknown distributor battery state is not reported as a fault', () {
    final h = _eval(_native(distributorUnrestricted: null), server: _server());
    check(h.has(PushIssue.distributorBatteryRestricted)).isFalse();
  });

  test('server unreachable and unverified endpoint', () {
    final down = _eval(_native(), error: 'Could not reach Hermes.');
    check(down.has(PushIssue.serverUnreachable)).isTrue();
    final unverified = _eval(_native(), server: _server(state: 'unverified'));
    check(unverified.has(PushIssue.serverEndpointNotVerified)).isTrue();
  });

  test('fallback flags from the server are surfaced', () {
    final h = _eval(_native(), server: _server(fallback: const ['alerts']));
    check(h.has(PushIssue.fallbackActive)).isTrue();
  });

  test('before the server has been asked there is no server complaint', () {
    final h = _eval(_native(), checked: false);
    check(h.level).equals(PushHealthLevel.healthy);
  });

  test('temporary distributor outage', () {
    final h = _eval(_native(tempUnavailable: true), server: _server());
    check(h.has(PushIssue.distributorTemporarilyDown)).isTrue();
  });

  test('every issue has plain-language help', () {
    for (final issue in PushIssue.values) {
      check(describePushIssue(issue)).isNotEmpty();
    }
  });

  group('DeviceHealth.fromJson', () {
    test('reads nested endpoint state and fallback map', () {
      final d = DeviceHealth.fromJson({
        'device': {'name': 'Pixel'},
        'endpoint': {'state': 'degraded', 'last_ack_at': 1760841600},
        'fallback': {'alerts': true, 'briefs': false},
      });
      check(d.name).equals('Pixel');
      check(d.endpointState).equals('degraded');
      check(d.fallbackCategories).deepEquals(['alerts']);
      check(d.lastAckAt).isNotNull();
    });

    test('reads the live gateway shape (categories, epoch seconds)', () {
      final d = DeviceHealth.fromJson({
        'device': {'id': 'd1', 'name': 'Phone'},
        'endpoint': {'state': 'verified', 'last_ack_at': 1760841600},
        'categories': {
          'alerts': {'mode': 'conduit', 'fallback_active': true},
          'briefs': {'mode': 'legacy', 'fallback_active': false},
        },
        'gateway_epoch': 1,
      });
      check(d.endpointState).equals('verified');
      check(d.fallbackCategories).deepEquals(['alerts']);
      check(DeviceHealth.fromJson({'device': {}, 'endpoint': null}).endpointState).isNull();
    });

    test('unknown shapes mean unknown, not healthy', () {
      final d = DeviceHealth.fromJson(null);
      check(d.endpointState).isNull();
      check(d.fallbackCategories).isEmpty();
    });
  });
}
