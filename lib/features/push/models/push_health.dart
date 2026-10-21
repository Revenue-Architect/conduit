import '../platform/conduit_push_api.g.dart';
import '../services/push_gateway_client.dart';

/// How worried the health card should look.
enum PushHealthLevel { healthy, warning, problem, off }

/// One thing the person can fix, in the order the card lists them.
enum PushIssue {
  unsupported,
  notificationsBlocked,
  notPaired,
  noDistributor,
  distributorNotSelected,
  notRegistered,
  uploadPending,
  uploadFailed,
  appBatteryRestricted,
  distributorBatteryRestricted,
  distributorTemporarilyDown,
  serverUnreachable,
  serverEndpointNotVerified,
  fallbackActive,
}

/// Everything the health card shows, computed from local facts (native
/// status) and the server's own view. Pure, so every combination is testable.
class PushHealth {
  const PushHealth({
    required this.level,
    required this.headline,
    required this.issues,
    this.lastPushAt,
  });

  final PushHealthLevel level;
  final String headline;
  final List<PushIssue> issues;
  final DateTime? lastPushAt;

  bool has(PushIssue issue) => issues.contains(issue);
}

PushHealth evaluatePushHealth({
  required PushNativeStatus? native,
  required DeviceHealth? server,
  required String? serverError,
  required bool serverChecked,
}) {
  if (native == null) {
    return const PushHealth(
      level: PushHealthLevel.off,
      headline: 'Push notifications are available on Android only.',
      issues: [PushIssue.unsupported],
    );
  }
  final issues = <PushIssue>[];
  if (!native.notificationsAllowed) issues.add(PushIssue.notificationsBlocked);
  if (!native.paired) issues.add(PushIssue.notPaired);
  if (native.distributors.isEmpty) {
    issues.add(PushIssue.noDistributor);
  } else if (!native.distributorSelected) {
    issues.add(PushIssue.distributorNotSelected);
  }
  if (native.paired && native.distributorSelected && !native.registered) {
    issues.add(PushIssue.notRegistered);
  }
  if (native.registered && native.paired) {
    if (native.lastError != null && native.pendingUpload) {
      issues.add(PushIssue.uploadFailed);
    } else if (native.pendingUpload) {
      issues.add(PushIssue.uploadPending);
    }
  }
  if (!native.appBatteryUnrestricted) {
    issues.add(PushIssue.appBatteryRestricted);
  }
  if (native.distributorSelected &&
      native.distributorBatteryUnrestricted == false) {
    issues.add(PushIssue.distributorBatteryRestricted);
  }
  if (native.tempUnavailable) issues.add(PushIssue.distributorTemporarilyDown);
  if (native.paired && serverChecked) {
    if (serverError != null) {
      issues.add(PushIssue.serverUnreachable);
    } else if (server != null &&
        native.registered &&
        server.endpointState != null &&
        server.endpointState != 'verified') {
      issues.add(PushIssue.serverEndpointNotVerified);
    }
    if (server != null && server.fallbackCategories.isNotEmpty) {
      issues.add(PushIssue.fallbackActive);
    }
  }

  const blocking = {
    PushIssue.notificationsBlocked,
    PushIssue.notPaired,
    PushIssue.noDistributor,
    PushIssue.distributorNotSelected,
    PushIssue.notRegistered,
  };
  final problem = issues.any(blocking.contains);
  final lastPush = native.lastPushAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(native.lastPushAtMs!);
  if (issues.isEmpty) {
    return PushHealth(
      level: PushHealthLevel.healthy,
      headline: 'Push is working.',
      issues: const [],
      lastPushAt: lastPush,
    );
  }
  if (problem) {
    return PushHealth(
      level: PushHealthLevel.problem,
      headline: _blockingHeadline(issues),
      issues: issues,
      lastPushAt: lastPush,
    );
  }
  return PushHealth(
    level: PushHealthLevel.warning,
    headline: 'Push is set up, with things to check.',
    issues: issues,
    lastPushAt: lastPush,
  );
}

String _blockingHeadline(List<PushIssue> issues) {
  if (issues.contains(PushIssue.notificationsBlocked)) {
    return 'Android is blocking notifications for Hermez.';
  }
  if (issues.contains(PushIssue.notPaired)) {
    return 'Pair this phone with Hermes to receive push.';
  }
  if (issues.contains(PushIssue.noDistributor)) {
    return 'Install ntfy to receive push.';
  }
  if (issues.contains(PushIssue.distributorNotSelected)) {
    return 'Choose the app that delivers push.';
  }
  return 'Push is not registered yet.';
}

/// Plain-language fix for each issue, shown under the headline.
String describePushIssue(PushIssue issue, {String? distributor}) {
  final name = distributor ?? 'ntfy';
  return switch (issue) {
    PushIssue.unsupported => 'This feature needs an Android phone.',
    PushIssue.notificationsBlocked =>
      'Allow notifications for Hermez in Android settings.',
    PushIssue.notPaired =>
      'Create a pairing code on the Umbrel, then enter it here.',
    PushIssue.noDistributor =>
      'Install ntfy from the Play Store and open it once. Hermez uses it to '
          'receive push; it stays out of sight.',
    PushIssue.distributorNotSelected =>
      'Pick which app delivers push (ntfy).',
    PushIssue.notRegistered =>
      'Open $name once so it can register Hermez, then check again.',
    PushIssue.uploadPending =>
      'The delivery address has not reached Hermes yet. It retries on its own.',
    PushIssue.uploadFailed =>
      'Hermes did not accept the delivery address. Check the connection and '
          'check again.',
    PushIssue.appBatteryRestricted =>
      'Set Hermez to Unrestricted battery use, and remove it from sleeping '
          'apps, so push arrives with the phone idle.',
    PushIssue.distributorBatteryRestricted =>
      'Set $name to Unrestricted battery use and remove it from sleeping '
          'apps. If Android stops it, push stops too.',
    PushIssue.distributorTemporarilyDown =>
      '$name reports its server is temporarily unavailable.',
    PushIssue.serverUnreachable =>
      'Hermes could not be reached. Check Tailscale on this phone.',
    PushIssue.serverEndpointNotVerified =>
      'Hermes has not yet confirmed it can reach this phone. Check again in a '
          'minute.',
    PushIssue.fallbackActive =>
      'Hermes is sending some alerts through plain ntfy because push looked '
          'unhealthy.',
  };
}
