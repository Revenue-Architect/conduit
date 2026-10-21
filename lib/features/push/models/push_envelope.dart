import 'dart:convert';

/// Push categories (spec section 5.1). The wire names are the `cat` field.
enum PushCategory {
  approvals,
  critical,
  alerts,
  proactive,
  briefs,
  agent,
  watch,
  status;

  static PushCategory? fromWire(Object? value) {
    for (final category in PushCategory.values) {
      if (category.name == value) return category;
    }
    return null;
  }

  /// Approvals and critical can only be silenced by the master push switch.
  bool get alwaysOn =>
      this == PushCategory.approvals || this == PushCategory.critical;

  String get label => switch (this) {
    PushCategory.approvals => 'Approvals',
    PushCategory.critical => 'Critical alerts',
    PushCategory.alerts => 'Alerts',
    PushCategory.proactive => 'Proactive',
    PushCategory.briefs => 'Briefs',
    PushCategory.agent => 'Agent messages',
    PushCategory.watch => 'Watches',
    PushCategory.status => 'Status',
  };
}

enum PushOpenKind {
  approval,
  session,
  thread,
  brief,
  url,
  none;

  static PushOpenKind? fromWire(Object? value) {
    for (final kind in PushOpenKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

class PushOpen {
  const PushOpen({required this.kind, this.id, this.url});

  final PushOpenKind kind;
  final String? id;
  final String? url;
}

class PushAction {
  const PushAction({
    required this.id,
    required this.label,
    required this.kind,
    this.approval,
    this.url,
  });

  final String id;
  final String label;

  /// `decide`, `relay` or `view`.
  final String kind;
  final String? approval;
  final String? url;
}

/// The cleartext push envelope (v1). The native side authenticates and
/// de-duplicates before anything reaches Dart; this parser is a second,
/// defensive layer and the single place Dart reads the wire format.
class PushEnvelope {
  const PushEnvelope({
    required this.type,
    required this.id,
    required this.timestamp,
    required this.ttl,
    required this.category,
    required this.priority,
    required this.title,
    required this.body,
    required this.actions,
    required this.ack,
    required this.shadow,
    this.dedupe,
    this.tag,
    this.open,
    this.group,
  });

  static const int maxBytes = 4096;
  static const int maxTitle = 120;
  static const int maxBody = 600;
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_.:@/-]{1,128}$');
  static bool _validId(Object? value) =>
      value is String && _idPattern.hasMatch(value) && !value.contains('..');

  static const Set<String> _types = {
    'notify',
    'dismiss',
    'update',
    'probe',
    'verify',
  };

  /// notify | dismiss | update | probe | verify
  final String type;
  final String id;
  final String? dedupe;
  final String? tag;
  final int timestamp;
  final int ttl;
  final PushCategory category;
  final int priority;
  final String title;
  final String body;
  final PushOpen? open;
  final List<PushAction> actions;
  final String? group;
  final bool ack;
  final bool shadow;

  /// De-duplication key shared with the other notification sources.
  String get dedupKey => dedupe ?? id;

  /// Parses [raw] or returns null for anything that is not a valid v1 envelope.
  static PushEnvelope? tryParse(String raw) {
    if (raw.isEmpty || utf8.encode(raw).length > maxBytes) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final json = Map<String, Object?>.from(decoded);
    if (json['v'] != 1) return null;
    final type = json['t'];
    if (type is! String || !_types.contains(type)) return null;
    final id = json['id'];
    if (id is! String || !_validId(id)) return null;
    final ts = json['ts'];
    if (ts is! int || ts <= 0) return null;
    final bookkeeping = type == 'probe' || type == 'verify';
    final category =
        PushCategory.fromWire(json['cat']) ??
        (bookkeeping ? PushCategory.status : null);
    if (category == null) return null;
    final tag = json['tag'];
    if (tag != null && !_validId(tag)) {
      return null;
    }
    final ttl = json['ttl'];
    final pri = json['pri'];
    return PushEnvelope(
      type: type,
      id: id,
      dedupe: json['dedupe'] is String ? json['dedupe'] as String : null,
      tag: tag as String?,
      timestamp: ts,
      ttl: ttl is int && ttl > 0 ? ttl : 86400,
      category: category,
      priority: pri is int ? pri.clamp(1, 5) : 3,
      title: _clip(json['title'], maxTitle),
      body: _clip(json['body'], maxBody),
      open: _open(json['open']),
      actions: _actions(json['actions']),
      group: json['group'] is String ? json['group'] as String : null,
      ack: json['ack'] == true,
      shadow: json['shadow'] == true,
    );
  }

  static String _clip(Object? value, int max) {
    if (value is! String) return '';
    return value.length <= max ? value : '${value.substring(0, max - 1)}…';
  }

  static PushOpen? _open(Object? value) {
    if (value is! Map) return null;
    final kind = PushOpenKind.fromWire(value['k']);
    if (kind == null) return null;
    final id = value['id'];
    final url = value['url'];
    if (kind == PushOpenKind.none) return const PushOpen(kind: PushOpenKind.none);
    if (kind == PushOpenKind.url) {
      return url is String && url.startsWith(relayOrigin)
          ? PushOpen(kind: kind, url: url)
          : null;
    }
    if (!_validId(id)) return null;
    return PushOpen(kind: kind, id: id as String);
  }

  /// The signed-link relay is the only web origin a push may point at.
  static const String relayOrigin = 'https://umbrel.tail4c9e01.ts.net:8447/';

  static List<PushAction> _actions(Object? value) {
    if (value is! List) return const [];
    final out = <PushAction>[];
    for (final item in value.take(3)) {
      if (item is! Map) continue;
      final id = item['id'];
      final label = item['label'];
      final kind = item['kind'];
      if (id is! String || label is! String || kind is! String) continue;
      out.add(
        PushAction(
          id: id,
          label: label,
          kind: kind,
          approval: item['approval'] is String
              ? item['approval'] as String
              : null,
          url: item['url'] is String ? item['url'] as String : null,
        ),
      );
    }
    return out;
  }

  /// The in-app route this envelope opens, or null for none.
  String? get route => pushRouteFor(open);
}

/// Maps `open` to an app route. Kept as one function so the native side's
/// deep links and the Dart banner taps can never disagree.
String? pushRouteFor(PushOpen? open) {
  if (open == null) return null;
  switch (open.kind) {
    case PushOpenKind.approval:
      return open.id == null ? null : '/profile/hermes/approvals/${open.id}';
    case PushOpenKind.session:
      return open.id == null ? null : '/profile/hermes/live/${open.id}';
    case PushOpenKind.thread:
      return open.id == null
          ? null
          : '/profile/hermes/conversations?thread=${open.id}';
    case PushOpenKind.brief:
      return open.id == null ? null : '/profile/hermes/home?brief=${open.id}';
    case PushOpenKind.url:
    case PushOpenKind.none:
      return null;
  }
}
