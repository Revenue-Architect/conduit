import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/persistence_keys.dart';
import '../../../core/persistence/preferences_store.dart';

/// Steel owns the player and its transport; we only embed a user-configured
/// debug viewer. Never log this URL: Steel debug links can grant control.
Uri? parseSteelViewerUrl(String source) {
  final uri = Uri.tryParse(source.trim());
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return null;
  }
  return uri;
}

Uri steelViewerUri(String source, {required bool interactive}) {
  final base = parseSteelViewerUrl(source);
  if (base == null) throw const FormatException('Invalid Steel viewer URL');
  return base.replace(
    queryParameters: {
      ...base.queryParameters,
      'interactive': interactive.toString(),
    },
  );
}

final hermesSteelViewerUrlProvider =
    NotifierProvider<HermesSteelViewerUrlController, String>(
      HermesSteelViewerUrlController.new,
    );

class HermesSteelViewerUrlController extends Notifier<String> {
  // Personal builds can supply the installed viewer without baking a private
  // tailnet address into the public source or changing other installations.
  static const buildDefault = String.fromEnvironment('HERMES_STEEL_VIEWER_URL');
  @override
  String build() =>
      PreferencesStore.getString(PreferenceKeys.hermesSteelViewerUrl) ??
      buildDefault;

  Future<void> save(String source) async {
    final value = source.trim();
    if (value.isNotEmpty && parseSteelViewerUrl(value) == null) {
      throw const FormatException('Enter an HTTP or HTTPS Steel viewer URL.');
    }
    await PreferencesStore.putChecked(
      PreferenceKeys.hermesSteelViewerUrl,
      value,
    );
    state = value;
  }
}
