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
    this.unread,
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

  /// Hermes' own read state (`sessions.last_read_at`): true when activity
  /// postdates the watermark. Null when the server does not report it.
  final bool? unread;

  /// API transport alone does not distinguish a person from an automation.
  bool get isAutomated => const {
    'cron',
    'webhook',
    'subagent',
  }.contains(source?.trim().toLowerCase());

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
      unread: switch (json['unread']) {
        final bool value => value,
        _ => null,
      },
    );
  }
}

/// A session's read watermark as Hermes keeps it, in server epoch seconds.
/// Hermes stamps `last_read_at` across the whole compression lineage, so a
/// rotated Bot Chat tip reads the same as its root.
class HermesSessionReadState {
  const HermesSessionReadState({this.lastReadAt, this.lastActive});

  /// Null: Hermes has never tracked this session, which it counts as read.
  final double? lastReadAt;

  final double? lastActive;

  /// Hermes' own rule: activity after the watermark.
  bool get unread => lastReadAt != null && (lastActive ?? 0) > lastReadAt!;

  /// Reads one `GET /api/sessions/{id}` row.
  static HermesSessionReadState fromJson(Map<String, dynamic> json) {
    double? seconds(Object? value) =>
        value is num && value.isFinite && value >= 0 ? value.toDouble() : null;
    final activity = [
      seconds(json['last_active']),
      seconds(json['last_activity_at']),
      seconds(json['started_at']),
    ].whereType<double>();
    return HermesSessionReadState(
      lastReadAt: seconds(json['last_read_at']),
      lastActive: activity.isEmpty
          ? null
          : activity.reduce((a, b) => a > b ? a : b),
    );
  }
}
