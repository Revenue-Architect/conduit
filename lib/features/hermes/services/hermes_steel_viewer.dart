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

/// The build-time viewer URL without any trailing comment or whitespace.
String sanitizeSteelViewerDefine(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.split(RegExp(r'\s')).first;
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
  static const _rawBuildDefault = String.fromEnvironment(
    'HERMES_STEEL_VIEWER_URL',
  );

  /// A define copied from a notes file can carry a trailing comment
  /// ("http://host/v1/...  # private"). The '#' would parse as a fragment and
  /// hide the viewer, so only the first token counts: a URL has no spaces.
  static final String buildDefault = sanitizeSteelViewerDefine(
    _rawBuildDefault,
  );
  // A cleared field falls back to the build default rather than hiding the
  // viewer on a build that ships one.
  @override
  String build() {
    final saved = PreferencesStore.getString(
      PreferenceKeys.hermesSteelViewerUrl,
    )?.trim();
    return saved == null || saved.isEmpty ? buildDefault : saved;
  }

  Future<void> save(String source) async {
    final value = source.trim();
    if (value.isNotEmpty && parseSteelViewerUrl(value) == null) {
      throw const FormatException('Enter an HTTP or HTTPS Steel viewer URL.');
    }
    await PreferencesStore.putChecked(
      PreferenceKeys.hermesSteelViewerUrl,
      value,
    );
    state = value.isEmpty ? buildDefault : value;
  }
}
