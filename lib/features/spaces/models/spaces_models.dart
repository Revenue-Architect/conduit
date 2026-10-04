import 'package:flutter/foundation.dart';

/// A container of working Pages ("Personal", "Hermes", "Kaizen").
@immutable
class HermesSpace {
  const HermesSpace({
    required this.id,
    required this.name,
    this.icon,
    this.pageCount = 0,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? icon;
  final int pageCount;
  final DateTime updatedAt;

  static HermesSpace? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || !isSpacesId(id) || name is! String) return null;
    return HermesSpace(
      id: id,
      name: name,
      icon: json['icon'] is String ? json['icon'] as String : null,
      pageCount: json['page_count'] is int ? json['page_count'] as int : 0,
      updatedAt: _time(json['updated_at']),
    );
  }
}

/// A Page as listed: metadata and a short excerpt, never the body.
@immutable
class HermesPageSummary {
  const HermesPageSummary({
    required this.id,
    required this.spaceId,
    this.parentId,
    required this.title,
    this.excerpt = '',
    required this.revision,
    this.childCount = 0,
    required this.updatedAt,
  });

  final String id;
  final String spaceId;
  final String? parentId;
  final String title;
  final String excerpt;
  final int revision;
  final int childCount;
  final DateTime updatedAt;

  static HermesPageSummary? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final spaceId = json['space_id'];
    final title = json['title'];
    final revision = json['revision'];
    if (id is! String ||
        !isSpacesId(id) ||
        spaceId is! String ||
        title is! String ||
        revision is! int) {
      return null;
    }
    final parent = json['parent_id'];
    return HermesPageSummary(
      id: id,
      spaceId: spaceId,
      parentId: parent is String && isSpacesId(parent) ? parent : null,
      title: title,
      excerpt: json['excerpt'] is String ? json['excerpt'] as String : '',
      revision: revision,
      childCount: json['child_count'] is int ? json['child_count'] as int : 0,
      updatedAt: _time(json['updated_at']),
    );
  }
}

/// A full Page. [content] is canonical Markdown and untrusted document data.
@immutable
class HermesPage {
  const HermesPage({
    required this.id,
    required this.spaceId,
    this.parentId,
    required this.title,
    required this.content,
    required this.revision,
    this.sourceSessionId,
    required this.updatedAt,
  });

  final String id;
  final String spaceId;
  final String? parentId;
  final String title;
  final String content;
  final int revision;
  final String? sourceSessionId;
  final DateTime updatedAt;

  static HermesPage? fromJson(Object? json) {
    final summary = HermesPageSummary.fromJson(json);
    if (summary == null || json is! Map) return null;
    final content = json['content'];
    if (content is! String) return null;
    final source = json['source_session_id'];
    return HermesPage(
      id: summary.id,
      spaceId: summary.spaceId,
      parentId: summary.parentId,
      title: summary.title,
      content: content,
      revision: summary.revision,
      sourceSessionId: source is String ? source : null,
      updatedAt: summary.updatedAt,
    );
  }
}

/// Which Hermes conversation is a Page's chat for one profile.
@immutable
class PageChatBinding {
  const PageChatBinding({
    required this.pageId,
    required this.profile,
    required this.sessionId,
  });

  final String pageId;
  final String profile;
  final String sessionId;

  static PageChatBinding? fromJson(Object? json) {
    if (json is! Map) return null;
    final pageId = json['page_id'];
    final profile = json['profile'];
    final sessionId = json['session_id'];
    if (pageId is! String || profile is! String || sessionId is! String) {
      return null;
    }
    return PageChatBinding(
      pageId: pageId,
      profile: profile,
      sessionId: sessionId,
    );
  }
}

final RegExp _spacesId = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Space and Page ids are server-issued UUIDs; anything else is refused
/// before it reaches a URL.
bool isSpacesId(String value) => _spacesId.hasMatch(value);

DateTime _time(Object? value) => value is int
    ? DateTime.fromMillisecondsSinceEpoch(value)
    : DateTime.fromMillisecondsSinceEpoch(0);

/// Limits shared with the server (it re-validates everything).
abstract final class SpacesLimits {
  static const spaceName = 80;
  static const pageTitle = 160;
  static const pageContent = 100000;
}
