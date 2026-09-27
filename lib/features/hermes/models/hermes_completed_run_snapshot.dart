import '../services/hermes_live_activity.dart';
import '../services/hermes_media_parser.dart';

/// An ephemeral presentation of a Desktop turn. No result score, invented
/// findings, or persisted run record is added to Hermes or Conduit.
final class HermesCompletedRunSnapshot {
  const HermesCompletedRunSnapshot({
    required this.sessionId,
    required this.title,
    this.profile,
    this.startedAt,
    required this.completedAt,
    required this.finalText,
    required this.activity,
    required this.artifacts,
  });

  final String sessionId;
  final String title;
  final String? profile;
  final DateTime? startedAt;
  final DateTime completedAt;
  final String finalText;
  final List<HermesLiveActivityEvent> activity;
  final List<HermesMediaArtifact> artifacts;
}
