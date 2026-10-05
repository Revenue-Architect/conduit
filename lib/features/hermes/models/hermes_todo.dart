import 'package:flutter/foundation.dart';

/// A Hermes plan step's state, exactly as the `todo_list` tool reports it.
enum HermesTodoStatus {
  pending,
  inProgress,
  completed,
  cancelled;

  static HermesTodoStatus? parse(Object? value) => switch (value) {
    'pending' => HermesTodoStatus.pending,
    'in_progress' => HermesTodoStatus.inProgress,
    'completed' => HermesTodoStatus.completed,
    'cancelled' => HermesTodoStatus.cancelled,
    _ => null,
  };

  bool get isOpen =>
      this == HermesTodoStatus.pending || this == HermesTodoStatus.inProgress;
}

/// One step of the agent's plan.
@immutable
final class HermesTodoItem {
  const HermesTodoItem({
    required this.id,
    required this.content,
    required this.status,
    this.parent,
  });

  final String id;
  final String content;
  final HermesTodoStatus status;

  /// The step this one is a sub-step of. Only kept when that step exists.
  final String? parent;

  static const int maxContentCharacters = 4000;

  static HermesTodoItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final content = json['content'];
    final status = HermesTodoStatus.parse(json['status']);
    if (id is! String || id.trim().isEmpty || id.length > 256) return null;
    if (content is! String || status == null) return null;
    final text = content.trim();
    final parent = json['parent'];
    return HermesTodoItem(
      id: id.trim(),
      content: text.length > maxContentCharacters
          ? '${text.substring(0, maxContentCharacters)}…'
          : text,
      status: status,
      parent: parent is String && parent.trim().isNotEmpty
          ? parent.trim()
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HermesTodoItem &&
      other.id == id &&
      other.content == content &&
      other.status == status &&
      other.parent == parent;

  @override
  int get hashCode => Object.hash(id, content, status, parent);
}

/// A plan step placed in the outline: [depth] 0 is a top-level step.
typedef HermesTodoRow = ({HermesTodoItem item, int depth});

/// The agent's whole plan at one revision. Hermes sends the full list on
/// every change, so a snapshot replaces the previous one; a lower revision
/// is stale and ignored by the store.
@immutable
final class HermesTodoSnapshot {
  const HermesTodoSnapshot({required this.items, required this.revision});

  static const int maxItems = 256;

  final List<HermesTodoItem> items;
  final int revision;

  /// `{todos: [...], revision: n}`. Null when it is not a plan at all, or is
  /// the empty never-used list (revision 0). Bad steps are dropped, not
  /// guessed at; a step whose parent is missing or that would form a cycle
  /// is shown at the top level.
  static HermesTodoSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final rows = json['todos'];
    if (rows is! List) return null;
    final rawRevision = json['revision'];
    final revision = switch (rawRevision) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value.trim()),
      null => 0,
      _ => null,
    };
    if (revision == null || revision < 0) return null;
    final seen = <String>{};
    final items = <HermesTodoItem>[];
    for (final row in rows) {
      if (items.length >= maxItems) break;
      final item = HermesTodoItem.fromJson(row);
      if (item == null || !seen.add(item.id)) continue;
      items.add(item);
    }
    if (items.isEmpty && revision == 0) return null;
    return HermesTodoSnapshot(
      items: _withSoundParents(items),
      revision: revision,
    );
  }

  static List<HermesTodoItem> _withSoundParents(List<HermesTodoItem> items) {
    final byId = {for (final item in items) item.id: item};
    bool cycles(HermesTodoItem start) {
      final visited = <String>{start.id};
      var parent = start.parent;
      while (parent != null) {
        if (!visited.add(parent)) return true;
        parent = byId[parent]?.parent;
      }
      return false;
    }

    return [
      for (final item in items)
        if (item.parent != null &&
            (item.parent == item.id ||
                !byId.containsKey(item.parent) ||
                cycles(item)))
          HermesTodoItem(
            id: item.id,
            content: item.content,
            status: item.status,
          )
        else
          item,
    ];
  }

  int _count(HermesTodoStatus status) =>
      items.where((item) => item.status == status).length;

  int get completed => _count(HermesTodoStatus.completed);
  int get active => _count(HermesTodoStatus.inProgress);
  int get pending => _count(HermesTodoStatus.pending);

  /// Steps that count toward progress: cancelled ones are not work left.
  int get total => items.length - _count(HermesTodoStatus.cancelled);

  bool get hasActiveWork => items.any((item) => item.status.isOpen);
  bool get isEmpty => items.isEmpty;
  bool get isFinished => items.isNotEmpty && !hasActiveWork;

  /// The step being worked on, else the next one up.
  HermesTodoItem? get current =>
      items
          .where((item) => item.status == HermesTodoStatus.inProgress)
          .firstOrNull ??
      items
          .where((item) => item.status == HermesTodoStatus.pending)
          .firstOrNull;

  /// Steps in reading order with their nesting depth (children follow their
  /// parent, in the order Hermes listed them).
  List<HermesTodoRow> get outline {
    final children = <String, List<HermesTodoItem>>{};
    final roots = <HermesTodoItem>[];
    for (final item in items) {
      final parent = item.parent;
      if (parent == null) {
        roots.add(item);
      } else {
        children.putIfAbsent(parent, () => []).add(item);
      }
    }
    final rows = <HermesTodoRow>[];
    void visit(HermesTodoItem item, int depth) {
      rows.add((item: item, depth: depth));
      for (final child in children[item.id] ?? const <HermesTodoItem>[]) {
        visit(child, depth + 1);
      }
    }

    for (final root in roots) {
      visit(root, 0);
    }
    return rows;
  }

  /// At most [limit] steps for a glance: the current step first, then what
  /// comes next, then the most recently finished. A plan with nothing left
  /// reads in its own order.
  List<HermesTodoItem> preview({int limit = 3}) {
    if (!hasActiveWork) return items.take(limit).toList(growable: false);
    final current = this.current;
    final next = items.where(
      (item) => item.status.isOpen && item.id != current?.id,
    );
    final done = items.reversed.where(
      (item) => item.status == HermesTodoStatus.completed,
    );
    return [?current, ...next, ...done].take(limit).toList(growable: false);
  }

  @override
  bool operator ==(Object other) =>
      other is HermesTodoSnapshot &&
      other.revision == revision &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(revision, Object.hashAll(items));
}
