import '../services/hermes_identifier.dart';

enum HermesConnectionTargetKind { connector, mcp, plugin, skill }

enum HermesConnectionTargetAction {
  authorize,
  connect,
  enable,
  install,
  reconnect,
}

enum HermesConnectionTargetState {
  pending,
  initiated,
  connected,
  skipped,
  failed,
  expired,
  notConnected,
}

HermesConnectionTargetState? _targetState(Object? value) => switch (value) {
  'pending' => HermesConnectionTargetState.pending,
  'initiated' => HermesConnectionTargetState.initiated,
  'connected' => HermesConnectionTargetState.connected,
  'skipped' => HermesConnectionTargetState.skipped,
  'failed' => HermesConnectionTargetState.failed,
  'expired' => HermesConnectionTargetState.expired,
  'not_connected' => HermesConnectionTargetState.notConnected,
  _ => null,
};

String _wireState(HermesConnectionTargetState state) => switch (state) {
  HermesConnectionTargetState.pending => 'pending',
  HermesConnectionTargetState.initiated => 'initiated',
  HermesConnectionTargetState.connected => 'connected',
  HermesConnectionTargetState.skipped => 'skipped',
  HermesConnectionTargetState.failed => 'failed',
  HermesConnectionTargetState.expired => 'expired',
  HermesConnectionTargetState.notConnected => 'not_connected',
};

final class HermesConnectionEnvField {
  const HermesConnectionEnvField({
    required this.name,
    required this.required,
    required this.secret,
    this.prompt,
    this.defaultValue,
  });

  final String name;
  final bool required;
  final bool secret;
  final String? prompt;

  /// Kept only in the live operation object; never included in safeJson().
  final String? defaultValue;

  static HermesConnectionEnvField? parse(
    Object? value, {
    bool safeOnly = false,
  }) {
    if (value is! Map) return null;
    final name = validateHermesBoundedString(value['name'], maxCharacters: 128);
    if (name == null ||
        value['required'] is! bool ||
        value['secret'] is! bool) {
      return null;
    }
    return HermesConnectionEnvField(
      name: name,
      required: value['required'] as bool,
      secret: value['secret'] as bool,
      prompt: validateHermesBoundedString(value['prompt'], maxCharacters: 256),
      defaultValue: safeOnly
          ? null
          : validateHermesBoundedString(
              value['default'],
              maxCharacters: 4096,
              allowEmpty: true,
            ),
    );
  }

  Map<String, Object?> safeJson() => <String, Object?>{
    'name': name,
    'required': required,
    'secret': secret,
    if (prompt != null) 'prompt': prompt,
  };
}

final class HermesConnectionTarget {
  const HermesConnectionTarget({
    required this.name,
    required this.kind,
    required this.action,
    required this.state,
    this.detail,
    this.instructions,
    this.connectUrl,
    this.requiredEnv = const <HermesConnectionEnvField>[],
  });

  final String name;
  final HermesConnectionTargetKind kind;
  final HermesConnectionTargetAction action;
  final HermesConnectionTargetState state;
  final String? detail;
  final String? instructions;

  /// OAuth/deep-link URL is live-only and deliberately excluded from safeJson.
  final String? connectUrl;
  final List<HermesConnectionEnvField> requiredEnv;

  static HermesConnectionTarget? parse(Object? value, {bool safeOnly = false}) {
    if (value is! Map) return null;
    final name = validateHermesBoundedString(value['name'], maxCharacters: 128);
    final kind = HermesConnectionTargetKind.values.where(
      (candidate) => candidate.name == value['kind'],
    );
    final action = HermesConnectionTargetAction.values.where(
      (candidate) => candidate.name == value['action'],
    );
    final state = _targetState(value['state']);
    final env = value['required_env'] ?? value['requiredEnv'];
    if (name == null ||
        kind.isEmpty ||
        action.isEmpty ||
        state == null ||
        (env != null && env is! List)) {
      return null;
    }
    final parsedEnv = <HermesConnectionEnvField>[];
    for (final raw in (env as List? ?? const []).take(32)) {
      final field = HermesConnectionEnvField.parse(raw, safeOnly: safeOnly);
      if (field == null) return null;
      parsedEnv.add(field);
    }
    return HermesConnectionTarget(
      name: name,
      kind: kind.first,
      action: action.first,
      state: state,
      detail: validateHermesBoundedString(value['detail'], maxCharacters: 512),
      instructions: validateHermesBoundedString(
        value['instructions'],
        maxCharacters: 1024,
      ),
      connectUrl: safeOnly
          ? null
          : validateHermesBoundedString(
              value['connect_url'] ?? value['connectUrl'],
              maxCharacters: 4096,
            ),
      requiredEnv: List.unmodifiable(parsedEnv),
    );
  }

  Map<String, Object?> safeJson() => <String, Object?>{
    'name': name,
    'kind': kind.name,
    'action': action.name,
    'state': _wireState(state),
    if (detail != null) 'detail': detail,
    if (instructions != null) 'instructions': instructions,
    if (requiredEnv.isNotEmpty)
      'required_env': requiredEnv.map((field) => field.safeJson()).toList(),
  };
}

/// Full contract-8 operation snapshot. Safe serialization intentionally drops
/// OAuth URLs and environment defaults, which can carry credentials.
final class HermesConnectionOperation {
  const HermesConnectionOperation({
    required this.opId,
    required this.seq,
    required this.deadlineAt,
    required this.settled,
    required this.targets,
    this.toolCallId,
  });

  final String opId;
  final int seq;
  final DateTime deadlineAt;
  final bool settled;
  final String? toolCallId;
  final List<HermesConnectionTarget> targets;

  static HermesConnectionOperation? parse(
    Object? value, {
    bool safeOnly = false,
  }) {
    if (value is! Map) return null;
    final opId = validateHermesOpaqueIdentifier(
      value['op_id'] ?? value['opId'],
    );
    final seq = value['seq'];
    final deadline = value['deadline_at'] ?? value['deadlineAt'];
    final rawTargets = value['targets'];
    final settled = value['settled'] ?? false;
    if (opId == null ||
        seq is! num ||
        !seq.isFinite ||
        seq < 0 ||
        seq % 1 != 0 ||
        seq > 9007199254740991 ||
        deadline is! num ||
        !deadline.isFinite ||
        deadline <= 0 ||
        deadline > 253402300799 ||
        rawTargets is! List ||
        rawTargets.length > 32 ||
        settled is! bool) {
      return null;
    }
    final targets = <HermesConnectionTarget>[];
    final names = <String>{};
    for (final raw in rawTargets) {
      final target = HermesConnectionTarget.parse(raw, safeOnly: safeOnly);
      if (target == null || !names.add(target.name)) return null;
      targets.add(target);
    }
    if (targets.isEmpty) return null;
    final deadlineAt = DateTime.fromMillisecondsSinceEpoch(
      (deadline * 1000).round(),
      isUtc: true,
    );
    return HermesConnectionOperation(
      opId: opId,
      seq: seq.toInt(),
      deadlineAt: deadlineAt,
      settled: settled,
      toolCallId: validateHermesOpaqueIdentifier(
        value['tool_call_id'] ?? value['toolCallId'],
      ),
      targets: List.unmodifiable(targets),
    );
  }

  Map<String, Object?> safeJson() => <String, Object?>{
    'op_id': opId,
    'seq': seq,
    'deadline_at': deadlineAt.millisecondsSinceEpoch / 1000,
    'settled': settled,
    'targets': targets.map((target) => target.safeJson()).toList(),
  };
}
