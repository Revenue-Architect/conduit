import 'hermes_notification_target.dart';

/// Routes a push may open. A pushed route is data from the network, so only
/// Hermes pages inside the app are accepted; anything else is dropped.
String? safePushRoute(String? candidate) {
  if (candidate == null || candidate.isEmpty) return null;
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  final path = uri.path;
  if (!path.startsWith('/profile/hermes/')) return null;
  if (path.contains('..') || path.contains('//')) return null;
  final segments = uri.pathSegments;
  if (segments.length == 4 &&
      segments.take(3).join('/') == 'profile/hermes/live') {
    final canonical = hermesNotificationSessionRoute(segments.last);
    if (canonical == null) return null;
    final target = Uri.parse(canonical);
    return target
        .replace(
          queryParameters: {
            ...target.queryParameters,
            ...uri.queryParameters,
            'open': 'chat',
          },
        )
        .toString();
  }
  return uri.toString();
}
