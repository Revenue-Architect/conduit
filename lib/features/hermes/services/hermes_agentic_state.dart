import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/hermes_subagent.dart';
import '../models/hermes_todo.dart';

/// What a session is running on right now, from Hermes' own `session.info`.
@immutable
final class HermesSessionRuntimeInfo {
  const HermesSessionRuntimeInfo({
    this.model,
    this.provider,
    this.reasoningEffort,
    this.fast = false,
    this.running,
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.costUsd,
  });

  final String? model;
  final String? provider;

  /// `''`/null = the provider's default, `none` = thinking off.
  final String? reasoningEffort;
  final bool fast;
  final bool? running;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;

  /// Only when Hermes reported a cost; never estimated here.
  final double? costUsd;

  static HermesSessionRuntimeInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    String? text(Object? value, [int max = 256]) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty || trimmed.length > max ? null : trimmed;
    }

    int? count(Object? value) => switch (value) {
      final int number when number >= 0 => number,
      final double number when number.isFinite && number >= 0 => number.round(),
      _ => null,
    };
    final usage = json['usage'];
    final usageMap = usage is Map ? usage : const {};
    final cost = usageMap['cost_usd'] ?? usageMap['cost'];
    final model = text(json['model'], 512);
    final provider = text(json['provider'], 128);
    if (model == null && provider == null && usage is! Map) return null;
    return HermesSessionRuntimeInfo(
      model: model,
      provider: provider,
      reasoningEffort: text(json['reasoning_effort'], 32),
      fast: json['fast'] == true,
      running: json['running'] is bool ? json['running'] as bool : null,
      inputTokens: count(usageMap['input'] ?? usageMap['input_tokens']),
      outputTokens: count(usageMap['output'] ?? usageMap['output_tokens']),
      totalTokens: count(usageMap['total'] ?? usageMap['total_tokens']),
      costUsd: cost is num && cost.isFinite && cost >= 0
          ? cost.toDouble()
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HermesSessionRuntimeInfo &&
      other.model == model &&
      other.provider == provider &&
      other.reasoningEffort == reasoningEffort &&
      other.fast == fast &&
      other.running == running &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens &&
      other.totalTokens == totalTokens &&
      other.costUsd == costUsd;

  @override
  int get hashCode => Object.hash(
    model,
    provider,
    reasoningEffort,
    fast,
    running,
    inputTokens,
    outputTokens,
    totalTokens,
    costUsd,
  );
}

/// One session's agentic state: its plan, its delegated workers, and what
/// it runs on. A projection of Hermes events; Conduit invents none of it.
@immutable
final class HermesAgenticSnapshot {
  const HermesAgenticSnapshot({
    this.todo,
    this.subagents = const [],
    this.info,
  });

  static const empty = HermesAgenticSnapshot();

  final HermesTodoSnapshot? todo;

  /// In the order they first appeared.
  final List<HermesSubagentState> subagents;
  final HermesSessionRuntimeInfo? info;

  bool get hasPlan => todo != null && !todo!.isEmpty;
}

/// Keeps [HermesAgenticSnapshot]s per stored session id and tells listeners
/// which session changed. Fed by the Desktop connection's event stream and
/// by resume/create results.
final class HermesAgenticStateStore {
  HermesAgenticStateStore({
    this.sensitiveValues = const [],
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Iterable<String> sensitiveValues;
  final DateTime Function() _clock;
  final Map<String, HermesTodoSnapshot> _todos = {};
  final Map<String, Map<String, HermesSubagentState>> _subagents = {};
  final Map<String, HermesSessionRuntimeInfo> _info = {};
  final StreamController<String> _changes = StreamController.broadcast();

  static const int _maxSessions = 64;
  static const int _maxSubagentsPerSession = 64;

  Stream<String> get changes => _changes.stream;

  HermesAgenticSnapshot snapshotFor(String storedId) {
    final todo = _todos[storedId];
    final workers = _subagents[storedId];
    final info = _info[storedId];
    if (todo == null && workers == null && info == null) {
      return HermesAgenticSnapshot.empty;
    }
    return HermesAgenticSnapshot(
      todo: todo,
      subagents: workers == null ? const [] : List.unmodifiable(workers.values),
      info: info,
    );
  }

  Stream<HermesAgenticSnapshot> watch(String storedId) =>
      Stream<HermesAgenticSnapshot>.multi((controller) {
        final subscription = _changes.stream.listen(
          (changed) {
            if (changed == storedId) controller.add(snapshotFor(storedId));
          },
          onError: controller.addError,
          onDone: controller.close,
        );
        controller
          ..add(snapshotFor(storedId))
          ..onCancel = subscription.cancel;
      });

  /// A full plan snapshot. Ignored when older than the one already held.
  bool applyTodo(String storedId, Object? json) {
    final snapshot = HermesTodoSnapshot.fromJson(json);
    if (snapshot == null) return false;
    final current = _todos[storedId];
    if (current != null && snapshot.revision < current.revision) return false;
    if (current == snapshot) return false;
    _remember(_todos, storedId, snapshot);
    _emit(storedId);
    return true;
  }

  bool applySessionInfo(String storedId, Object? json) {
    final info = HermesSessionRuntimeInfo.fromJson(json);
    if (info == null || _info[storedId] == info) return false;
    _remember(_info, storedId, info);
    _emit(storedId);
    return true;
  }

  bool applySubagentEvent(
    String storedId,
    String type,
    Map<String, Object?> payload,
  ) {
    if (!type.startsWith('subagent.')) return false;
    final workers = _subagents[storedId] ?? <String, HermesSubagentState>{};
    final probe = HermesSubagentState.reduce(
      null,
      type,
      payload,
      now: _clock(),
      sensitiveValues: sensitiveValues,
    );
    if (probe == null) return false;
    final previous = workers[probe.id];
    final next = previous == null
        ? probe
        : HermesSubagentState.reduce(
            previous,
            type,
            payload,
            now: _clock(),
            sensitiveValues: sensitiveValues,
          );
    if (next == null || identical(next, previous)) return false;
    workers[next.id] = next;
    while (workers.length > _maxSubagentsPerSession) {
      final oldest = workers.entries.firstWhere(
        (entry) => entry.value.status.isTerminal,
        orElse: () => workers.entries.first,
      );
      workers.remove(oldest.key);
    }
    _remember(_subagents, storedId, workers);
    _emit(storedId);
    return true;
  }

  /// A new turn: drop the previous turn's finished workers, keep live ones.
  void pruneFinishedSubagents(String storedId) {
    final workers = _subagents[storedId];
    if (workers == null) return;
    final before = workers.length;
    workers.removeWhere((_, worker) => worker.status.isTerminal);
    if (workers.length != before) _emit(storedId);
  }

  /// A stored id was re-keyed (fresh session -> canonical id).
  void alias(String fromId, String toId) {
    if (fromId == toId) return;
    var changed = false;
    if (_todos.remove(fromId) case final todo?) {
      _todos.putIfAbsent(toId, () => todo);
      changed = true;
    }
    if (_subagents.remove(fromId) case final workers?) {
      _subagents.putIfAbsent(toId, () => workers);
      changed = true;
    }
    if (_info.remove(fromId) case final info?) {
      _info.putIfAbsent(toId, () => info);
      changed = true;
    }
    if (changed) _emit(toId);
  }

  void clear() {
    final ids = {..._todos.keys, ..._subagents.keys, ..._info.keys};
    _todos.clear();
    _subagents.clear();
    _info.clear();
    ids.forEach(_emit);
  }

  void _remember<T>(Map<String, T> map, String id, T value) {
    map.remove(id);
    map[id] = value;
    while (map.length > _maxSessions) {
      map.remove(map.keys.first);
    }
  }

  void _emit(String storedId) {
    if (!_changes.isClosed) _changes.add(storedId);
  }

  Future<void> close() => _changes.close();
}
