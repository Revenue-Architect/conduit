import '../utils/hermes_time_parsing.dart';
import '../services/hermes_identifier.dart';
import 'hermes_config.dart';

const int kMaxHermesSessionTitleCharacters = 512;
const int kMaxHermesSessionPreviewCharacters = 4096;
const int kMaxHermesSessionSourceCharacters = 128;

/// Lightweight summary of a Hermes server-side session, for the sessions list.
class HermesSessionSummary {
  const HermesSessionSummary({
    required this.id,
    required this.title,
    this.preview,
    this.source,
    this.updatedAt,
    this.profile,
    this.messageCount,
  });

  final String id;

  /// Display title; falls back to "Untitled session" when the server has none.
  final String title;

  /// First-line preview of the transcript, when the server provides one.
  final String? preview;

  /// Origin channel (e.g. `telegram`, `cron`, `api_server`).
  final String? source;

  final DateTime? updatedAt;

  /// Owning Hermes profile on the unified Desktop session endpoint.
  final String? profile;
  final int? messageCount;

  /// Parses one session object from `GET /api/sessions`, or null when it has no
  /// usable id. Tolerant of the field-name variations across Hermes versions.
  static HermesSessionSummary? fromJson(Map<String, dynamic> json) {
    final id =
        validateHermesOpaqueIdentifier(json['id']) ??
        validateHermesOpaqueIdentifier(json['session_id']);
    if (id == null) return null;

    final rawTitle =
        validateHermesBoundedString(
          json['title'],
          maxCharacters: kMaxHermesSessionTitleCharacters,
        ) ??
        validateHermesBoundedString(
          json['name'],
          maxCharacters: kMaxHermesSessionTitleCharacters,
        );
    final rawPreview = validateHermesBoundedString(
      json['preview'],
      maxCharacters: kMaxHermesSessionPreviewCharacters,
    );

    return HermesSessionSummary(
      id: id,
      title: rawTitle ?? 'Untitled session',
      preview: rawPreview,
      source: validateHermesBoundedString(
        json['source'],
        maxCharacters: kMaxHermesSessionSourceCharacters,
      ),
      updatedAt: parseHermesTimestamp(
        json['last_active'] ??
            json['updated_at'] ??
            json['updatedAt'] ??
            json['started_at'],
      ),
      profile: switch (json['profile'] ?? json['profile_name']) {
        final String value when HermesConfig.isValidDesktopProfile(value) =>
          value,
        _ => null,
      },
      messageCount: switch (json['message_count']) {
        final int value when value >= 0 => value,
        _ => null,
      },
    );
  }
}
