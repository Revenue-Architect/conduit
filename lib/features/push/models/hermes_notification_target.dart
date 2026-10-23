import '../../hermes/models/hermes_config.dart';
import '../../hermes/services/hermes_identifier.dart';

/// Both native and Dart notifications use `<profile>:<session>` on the wire.
/// Keep the profile separate before constructing a route or resuming a session.
({String sessionId, String? profile})? hermesNotificationTarget(String value) {
  final cut = value.indexOf(':');
  final prefix = cut > 0 ? value.substring(0, cut) : null;
  final scoped = prefix != null && HermesConfig.isValidDesktopProfile(prefix);
  final id = validateHermesOpaqueIdentifier(
    scoped ? value.substring(cut + 1) : value,
  );
  if (id == null) return null;
  return (sessionId: id, profile: scoped ? prefix : null);
}

String? hermesNotificationSessionRoute(String value, {bool openChat = true}) {
  final target = hermesNotificationTarget(value);
  if (target == null) return null;
  return Uri(
    pathSegments: ['', 'profile', 'hermes', 'live', target.sessionId],
    queryParameters: {
      if (openChat) 'open': 'chat',
      if (target.profile != null) 'profile': target.profile!,
    },
  ).toString();
}
