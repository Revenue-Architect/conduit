import '../services/hermes_identifier.dart';

/// Root keys Hermes accepts besides `DEFAULT_CONFIG`'s own: `platform_toolsets`
/// and `mcp_servers` live here, so they must not warn as unknown. Hermes does
/// not expose this list over HTTP (`_EXTRA_KNOWN_ROOT_KEYS`,
/// `hermes_cli/config.py`, 0.21.5), so the app ships it. The `DEFAULT_CONFIG`
/// roots come at runtime from the public `GET /api/config/defaults`.
const List<String> kHermesExtraKnownRootKeys = [
  'allow_all_users',
  'always_log_local',
  'custom_providers',
  'fallback_model',
  'filter_silence_narration',
  'group_sessions_per_user',
  'image_gen',
  'known_builtin_toolsets',
  'known_plugin_toolsets',
  'mcp_servers',
  'multiplex_profiles',
  'platform_toolsets',
  'platforms',
  'plugins',
  'profile_routes',
  'require_mention',
  'reset_triggers',
  'signal',
  'smart_model_routing',
  'stt_echo_transcripts',
  'thread_sessions_per_user',
  'timeouts',
  'tool_gateway_declined_tools',
  'unauthorized_dm_behavior',
  'video_gen',
];

/// Provider sign-ins whose `/start` route works on Hermes 0.21.5 (KTD8). The
/// others (`qwen-oauth`, `copilot-acp`, `anthropic`, `claude-code`) answer
/// 400 and get API-key entry instead.
const Set<String> kHermesDeviceCodeProviders = {
  'nous',
  'openai-codex',
  'minimax-oauth',
  'xai-oauth',
};

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Why an admin call failed, in terms the settings UI can act on. Transport
/// failures (offline, timeout, signed out) are not wrapped; they surface as
/// the exception the transport raised.
sealed class HermesAdminException implements Exception {
  const HermesAdminException(this.message);

  /// Safe to show: server text has already been through the secret detector.
  final String message;

  @override
  String toString() => message;
}

/// "Not available on this Hermes": an unknown JSON-RPC method (-32601), an
/// unknown REST route (404 `No such API endpoint`, a headless-serve 404 or a
/// bare `Not Found`), or a route that answers 405 because the SPA catch-all
/// swallowed it. Hide the feature rather than show an error.
final class HermesAdminUnavailable extends HermesAdminException {
  const HermesAdminUnavailable(super.message);
}

/// The route exists but the thing named does not: a missing profile
/// (`Profile 'x' does not exist.`, RPC 4064), memory node or env key.
final class HermesAdminNotFound extends HermesAdminException {
  const HermesAdminNotFound(super.message);
}

/// Hermes refused the request: an invalid name (400), a conflict (409) or an
/// application-level RPC error. [code] is the HTTP status or RPC error code.
final class HermesAdminRejected extends HermesAdminException {
  const HermesAdminRejected(super.message, {this.code});

  final int? code;
}

// ---------------------------------------------------------------------------
// Guarded writes
// ---------------------------------------------------------------------------

/// A write that Hermes held back pending the owner's say-so (the expensive
/// model guard, the MCP reload prompt). Nothing was written yet. Call
/// [confirm] after the owner agrees; it resends the request with the confirm
/// flag set.
final class HermesAdminConfirmation<T> {
  const HermesAdminConfirmation({
    required this.message,
    required this.confirm,
    this.partial,
  });

  /// Hermes' own wording, already scrubbed.
  final String message;
  final Future<HermesAdminWrite<T>> Function() confirm;

  /// What the same request already wrote around the held-back part, when it
  /// had other sections (a bot save with a new description and a new model).
  final T? partial;
}

/// Either the finished write, or the confirmation Hermes asked for.
final class HermesAdminWrite<T> {
  const HermesAdminWrite.done(this.value) : confirmation = null;
  const HermesAdminWrite.needsConfirmation(this.confirmation) : value = null;

  final T? value;
  final HermesAdminConfirmation<T>? confirmation;

  bool get needsConfirmation => confirmation != null;
}

// ---------------------------------------------------------------------------
// Profiles (bots)
// ---------------------------------------------------------------------------

/// One `profiles.list` row.
final class HermesAdminProfile {
  const HermesAdminProfile({
    required this.name,
    required this.description,
    required this.displayName,
    required this.model,
    required this.provider,
    required this.isDefault,
    required this.skillCount,
    required this.hasAvatar,
    required this.uiMeta,
    required this.uiMetaRevisions,
  });

  static HermesAdminProfile? fromJson(Map<String, dynamic> json) {
    final name = validateHermesBoundedString(json['name'], maxCharacters: 64);
    if (name == null) return null;
    return HermesAdminProfile(
      name: name,
      description: _text(json['description'], 1024) ?? '',
      displayName: _text(json['display_name'], 256) ?? '',
      model: _text(json['model'], 512) ?? '',
      provider: _text(json['provider'], 128) ?? '',
      isDefault: json['is_default'] == true,
      skillCount: _int(json['skill_count']) ?? 0,
      hasAvatar: json['has_avatar'] == true,
      uiMeta: _map(json['ui_meta']),
      uiMetaRevisions: {
        for (final entry in _map(json['ui_meta_revisions']).entries)
          if (_int(entry.value) != null) entry.key: _int(entry.value)!,
      },
    );
  }

  final String name;
  final String description;
  final String displayName;
  final String model;
  final String provider;
  final bool isDefault;
  final int skillCount;
  final bool hasAvatar;

  /// Free-form per-profile UI data (`hermes-bots` holds title and look).
  final Map<String, dynamic> uiMeta;

  /// Per-key revisions for compare-and-swap writes of [uiMeta].
  final Map<String, int> uiMetaRevisions;
}

/// `profiles.describe`: everything the bot editor shows in one read.
final class HermesAdminProfileDetail {
  const HermesAdminProfileDetail({
    required this.name,
    required this.description,
    required this.soul,
    required this.model,
    required this.provider,
    required this.skills,
    required this.toolsets,
    required this.toolsetsPinned,
    required this.mcpServers,
  });

  static HermesAdminProfileDetail fromJson(Map<String, dynamic> json) {
    final model = _map(json['model']);
    return HermesAdminProfileDetail(
      name: _text(json['name'], 64) ?? '',
      description: _text(json['description'], 1024) ?? '',
      soul: json['soul'] is String ? json['soul'] as String : '',
      model: _text(model['default'], 512) ?? '',
      provider: _text(model['provider'], 128) ?? '',
      skills: _maps(json['skills'])
          .map(
            (row) => (
              name: _text(row['name'], 256) ?? '',
              enabled: row['enabled'] != false,
            ),
          )
          .where((row) => row.name.isNotEmpty)
          .toList(growable: false),
      toolsets: _maps(json['toolsets'])
          .map(HermesAdminToolset.fromJson)
          .whereType<HermesAdminToolset>()
          .toList(growable: false),
      toolsetsPinned: json['toolsets_pinned'] == true,
      mcpServers: _maps(json['mcp_servers'])
          .map(
            (row) => (
              name: _text(row['name'], 128) ?? '',
              enabled: row['enabled'] != false,
              transport: _text(row['transport'], 32) ?? '',
            ),
          )
          .where((row) => row.name.isNotEmpty)
          .toList(growable: false),
    );
  }

  final String name;
  final String description;
  final String soul;
  final String model;
  final String provider;
  final List<({String name, bool enabled})> skills;
  final List<HermesAdminToolset> toolsets;
  final bool toolsetsPinned;
  final List<({String name, bool enabled, String transport})> mcpServers;
}

/// What `profiles.create` takes. Only the name is required.
final class HermesAdminProfileDraft {
  const HermesAdminProfileDraft({
    required this.name,
    this.description,
    this.soul,
    this.model,
    this.provider,
    this.cloneFrom,
    this.noSkills = false,
  });

  final String name;
  final String? description;
  final String? soul;
  final String? model;
  final String? provider;
  final String? cloneFrom;
  final bool noSkills;
}

/// `profiles.create` outcome.
final class HermesAdminProfileCreated {
  const HermesAdminProfileCreated({
    required this.name,
    required this.soulWritten,
    required this.modelSet,
    required this.mirrored,
  });

  static HermesAdminProfileCreated fromJson(
    Map<String, dynamic> json,
    String fallbackName,
  ) => HermesAdminProfileCreated(
    name: _text(json['name'], 64) ?? fallbackName,
    soulWritten: json['soul_written'] == true,
    modelSet: json['model_set'] == true,
    mirrored: _map(json['mirrored']),
  );

  final String name;
  final bool soulWritten;
  final bool modelSet;

  /// What was copied from the launch profile (env, auth, voice, model).
  final Map<String, dynamic> mirrored;
}

/// `profiles.configure` outcome. Each section applies on its own.
final class HermesAdminConfigureResult {
  const HermesAdminConfigureResult({
    required this.ok,
    required this.applied,
    required this.uiMetaConflicts,
  });

  static HermesAdminConfigureResult fromJson(Map<String, dynamic> json) {
    final applied = _map(json['applied']);
    return HermesAdminConfigureResult(
      ok: json['ok'] == true,
      applied: {
        for (final entry in applied.entries)
          if (entry.key != 'ui_meta_conflicts' &&
              entry.key != 'ui_meta_revisions')
            entry.key: entry.value == true,
      },
      uiMetaConflicts: _map(applied['ui_meta_conflicts']).keys
          .toList(growable: false),
    );
  }

  final bool ok;

  /// Section name (`soul`, `description`, `model`, `ui_meta`) to whether it
  /// was written.
  final Map<String, bool> applied;

  /// `ui_meta` keys another client changed first. Nothing was written for
  /// them; reload and retry.
  final List<String> uiMetaConflicts;

  bool get hasConflicts => uiMetaConflicts.isNotEmpty;
}

/// A profile's `SOUL.md`.
final class HermesAdminSoul {
  const HermesAdminSoul({required this.content, required this.exists});

  final String content;
  final bool exists;
}

/// `DELETE /api/profiles/{name}` outcome. Hermes can answer `ok` while the
/// bot's gateway is still stopping; [retryCommand] then finishes the job.
final class HermesAdminProfileDeleted {
  const HermesAdminProfileDeleted({
    required this.settlementPending,
    this.retryCommand,
  });

  static HermesAdminProfileDeleted fromJson(Map<String, dynamic> json) =>
      HermesAdminProfileDeleted(
        settlementPending: json['settlement_pending'] == true,
        retryCommand: _text(json['retry_command'], 512),
      );

  final bool settlementPending;
  final String? retryCommand;
}

// ---------------------------------------------------------------------------
// Memory (learning graph)
// ---------------------------------------------------------------------------

/// One node of `GET /api/learning/graph`.
final class HermesAdminLearningNode {
  const HermesAdminLearningNode({
    required this.id,
    required this.label,
    required this.kind,
    this.memorySource,
    this.preview,
    this.category,
    this.useCount = 0,
    this.pinned = false,
  });

  final String id;
  final String label;

  /// `memory` or `skill`.
  final String kind;

  /// For memory: `memory` (MEMORY.md) or `profile` (USER.md).
  final String? memorySource;

  /// The card text, capped by Hermes at 1,200 characters.
  final String? preview;
  final String? category;
  final int useCount;
  final bool pinned;

  bool get isMemory => kind == 'memory';
}

/// The learning graph reduced to what the memory editor needs.
final class HermesAdminLearningGraph {
  const HermesAdminLearningGraph({required this.nodes});

  static HermesAdminLearningGraph fromJson(Map<String, dynamic> json) {
    final cards = _maps(json['memory']);
    var memoryIndex = 0;
    final nodes = <HermesAdminLearningNode>[];
    for (final row in _maps(json['nodes']).take(2000)) {
      final id = validateHermesBoundedString(row['id'], maxCharacters: 256);
      if (id == null) continue;
      final kind = _text(row['kind'], 32) ?? 'skill';
      String? preview;
      if (kind == 'memory') {
        if (memoryIndex < cards.length) {
          preview = _text(cards[memoryIndex]['body'], 1200);
        }
        memoryIndex++;
      }
      nodes.add(
        HermesAdminLearningNode(
          id: id,
          label: _text(row['label'], 256) ?? id,
          kind: kind,
          memorySource: _text(row['memorySource'], 32),
          preview: preview,
          category: _text(row['category'], 128),
          useCount: _int(row['useCount']) ?? 0,
          pinned: row['pinned'] == true,
        ),
      );
    }
    return HermesAdminLearningGraph(nodes: nodes);
  }

  final List<HermesAdminLearningNode> nodes;

  List<HermesAdminLearningNode> get memories =>
      nodes.where((node) => node.isMemory).toList(growable: false);
}

/// `GET /api/learning/node`: the full text of a memory chunk or skill.
final class HermesAdminLearningNodeDetail {
  const HermesAdminLearningNodeDetail({
    required this.id,
    required this.kind,
    required this.label,
    required this.content,
  });

  static HermesAdminLearningNodeDetail fromJson(Map<String, dynamic> json) =>
      HermesAdminLearningNodeDetail(
        id: _text(json['id'], 256) ?? '',
        kind: _text(json['kind'], 32) ?? 'memory',
        label: _text(json['label'], 256) ?? '',
        content: json['content'] is String ? json['content'] as String : '',
      );

  final String id;
  final String kind;
  final String label;
  final String content;
}

// ---------------------------------------------------------------------------
// Keys and sign-in
// ---------------------------------------------------------------------------

/// One row of `GET /api/env`. Hermes never sends the value; [redactedValue]
/// is its own preview of it.
final class HermesAdminEnvKey {
  const HermesAdminEnvKey({
    required this.name,
    required this.isSet,
    required this.redactedValue,
    required this.description,
    required this.category,
    required this.isPassword,
    required this.advanced,
    required this.channelManaged,
    required this.provider,
    required this.providerLabel,
    required this.custom,
    this.url,
  });

  static HermesAdminEnvKey? fromJson(String name, Map<String, dynamic> json) {
    if (name.isEmpty || name.length > 256) return null;
    return HermesAdminEnvKey(
      name: name,
      isSet: json['is_set'] == true,
      redactedValue: _text(json['redacted_value'], 256),
      description: _text(json['description'], 1024) ?? '',
      url: _text(json['url'], 512),
      category: _text(json['category'], 64) ?? '',
      isPassword: json['is_password'] == true,
      advanced: json['advanced'] == true,
      channelManaged: json['channel_managed'] == true,
      provider: _text(json['provider'], 128) ?? '',
      providerLabel: _text(json['provider_label'], 256) ?? '',
      custom: json['custom'] == true,
    );
  }

  final String name;
  final bool isSet;
  final String? redactedValue;
  final String description;
  final String? url;
  final String category;
  final bool isPassword;
  final bool advanced;

  /// Owned by a messaging channel card; hide it from the keys list.
  final bool channelManaged;

  /// Provider slug and label, for grouping rows by provider.
  final String provider;
  final String providerLabel;

  /// A `.env` entry that no catalog knows.
  final bool custom;
}

/// Result of probing a key before it is saved.
final class HermesAdminKeyValidation {
  const HermesAdminKeyValidation({
    required this.ok,
    required this.reachable,
    required this.message,
    this.models = const [],
  });

  static HermesAdminKeyValidation fromJson(
    Map<String, dynamic> json,
    String Function(String text) scrub,
  ) => HermesAdminKeyValidation(
    ok: json['ok'] == true,
    reachable: json['reachable'] != false,
    message: scrub(_text(json['message'], 512) ?? ''),
    models: _strings(json['models'], 256, 200),
  );

  /// The provider accepted the key.
  final bool ok;

  /// False when the probe could not run (offline, or no probe for this
  /// provider). The key may still be saved, with a warning.
  final bool reachable;
  final String message;
  final List<String> models;

  /// The key was rejected by a provider that answered.
  bool get rejected => !ok && reachable;
}

/// One provider in `GET /api/providers/oauth`.
final class HermesAdminProviderSignIn {
  const HermesAdminProviderSignIn({
    required this.id,
    required this.name,
    required this.flow,
    required this.loggedIn,
    required this.disconnectable,
    this.cliCommand,
    this.docsUrl,
    this.disconnectHint,
  });

  static HermesAdminProviderSignIn? fromJson(Map<String, dynamic> json) {
    final id = validateHermesOpaqueIdentifier(json['id']);
    if (id == null) return null;
    final status = _map(json['status']);
    return HermesAdminProviderSignIn(
      id: id,
      name: _text(json['name'], 256) ?? id,
      flow: _text(json['flow'], 32) ?? 'external',
      loggedIn: status['logged_in'] == true,
      disconnectable: json['disconnectable'] == true,
      cliCommand: _text(json['cli_command'], 256),
      docsUrl: _text(json['docs_url'], 512),
      disconnectHint: _text(json['disconnect_hint'], 512),
    );
  }

  final String id;
  final String name;

  /// `device_code` or `external`.
  final String flow;
  final bool loggedIn;
  final bool disconnectable;
  final String? cliCommand;
  final String? docsUrl;
  final String? disconnectHint;

  /// Whether the app can sign in here (KTD8). Everything else gets API-key
  /// entry with a short explanation.
  bool get supportsDeviceCode =>
      flow == 'device_code' && kHermesDeviceCodeProviders.contains(id);
}

/// A started device-code sign-in: show [userCode] and open [verificationUrl].
final class HermesAdminSignInStart {
  const HermesAdminSignInStart({
    required this.sessionId,
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.pollInterval,
  });

  static HermesAdminSignInStart? fromJson(Map<String, dynamic> json) {
    final sessionId = validateHermesOpaqueIdentifier(json['session_id']);
    final userCode = _text(json['user_code'], 64);
    final url = _text(json['verification_url'], 1024);
    if (sessionId == null || userCode == null || url == null) return null;
    return HermesAdminSignInStart(
      sessionId: sessionId,
      userCode: userCode,
      verificationUrl: url,
      expiresIn: Duration(seconds: _int(json['expires_in']) ?? 900),
      pollInterval: Duration(
        seconds: (_int(json['poll_interval']) ?? 5).clamp(1, 60).toInt(),
      ),
    );
  }

  final String sessionId;
  final String userCode;
  final String verificationUrl;
  final Duration expiresIn;
  final Duration pollInterval;
}

enum HermesAdminSignInState { pending, approved, failed, expired }

/// One poll of a device-code sign-in.
final class HermesAdminSignInPoll {
  const HermesAdminSignInPoll({
    required this.state,
    this.errorMessage,
    this.accountEmail,
    this.model,
  });

  static HermesAdminSignInPoll fromJson(
    Map<String, dynamic> json,
    String Function(String text) scrub,
  ) {
    final raw = _text(json['status'], 32)?.toLowerCase();
    final state = switch (raw) {
      'approved' ||
      'authorized' ||
      'complete' ||
      'completed' => HermesAdminSignInState.approved,
      'expired' || 'timeout' => HermesAdminSignInState.expired,
      'error' ||
      'failed' ||
      'denied' ||
      'cancelled' => HermesAdminSignInState.failed,
      _ => HermesAdminSignInState.pending,
    };
    final error = _text(json['error_message'], 512);
    return HermesAdminSignInPoll(
      state: state,
      errorMessage: error == null ? null : scrub(error),
      accountEmail: _text(json['account_email'], 256),
      model: _text(json['model'], 512),
    );
  }

  final HermesAdminSignInState state;
  final String? errorMessage;
  final String? accountEmail;
  final String? model;
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// A provider in `model.options`.
final class HermesAdminModelProvider {
  const HermesAdminModelProvider({
    required this.slug,
    required this.name,
    required this.authenticated,
    required this.models,
  });

  static HermesAdminModelProvider? fromJson(Map<String, dynamic> json) {
    final slug = validateHermesBoundedString(
      json['slug'] ?? json['id'] ?? json['name'],
      maxCharacters: 128,
    );
    if (slug == null) return null;
    return HermesAdminModelProvider(
      slug: slug,
      name: _text(json['name'], 256) ?? slug,
      authenticated: json['authenticated'] != false,
      models: (json['models'] is List ? json['models'] as List : const [])
          .map((model) => model is Map ? model['id'] ?? model['name'] : model)
          .map((model) => _text(model, 512))
          .whereType<String>()
          .take(1000)
          .toList(growable: false),
    );
  }

  final String slug;
  final String name;
  final bool authenticated;
  final List<String> models;
}

/// `model.options` for one profile.
final class HermesAdminModelOptions {
  const HermesAdminModelOptions({
    required this.model,
    required this.provider,
    required this.providers,
  });

  static HermesAdminModelOptions fromJson(Map<String, dynamic> json) =>
      HermesAdminModelOptions(
        model: _text(json['model'], 512) ?? '',
        provider: _text(json['provider'], 128) ?? '',
        providers: _maps(json['providers'])
            .map(HermesAdminModelProvider.fromJson)
            .whereType<HermesAdminModelProvider>()
            .take(256)
            .toList(growable: false),
      );

  /// The profile's current default model and provider.
  final String model;
  final String provider;
  final List<HermesAdminModelProvider> providers;
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

/// `GET /api/config/raw`. The YAML is unredacted: mask it with
/// `HermesSecretRedaction` before it is shown, diffed or stored.
final class HermesAdminRawConfig {
  const HermesAdminRawConfig({required this.yaml, required this.path});

  final String yaml;
  final String path;

  @override
  String toString() =>
      'HermesAdminRawConfig(path: $path, ${yaml.length} chars)';
}

/// `GET /api/config/schema`.
final class HermesAdminConfigSchema {
  const HermesAdminConfigSchema({
    required this.fields,
    required this.categoryOrder,
  });

  static HermesAdminConfigSchema fromJson(Map<String, dynamic> json) =>
      HermesAdminConfigSchema(
        fields: _map(json['fields']),
        categoryOrder: _strings(json['category_order'], 128, 200),
      );

  /// Dotted key to field description (`type`, `options`, `category`, ...).
  final Map<String, dynamic> fields;
  final List<String> categoryOrder;
}

// ---------------------------------------------------------------------------
// Tools and extensions
// ---------------------------------------------------------------------------

/// One toolset of `GET /api/tools/toolsets` or `profiles.describe`.
final class HermesAdminToolset {
  const HermesAdminToolset({
    required this.name,
    required this.label,
    required this.description,
    required this.enabled,
    required this.configured,
    required this.platform,
    required this.toolCount,
  });

  static HermesAdminToolset? fromJson(Map<String, dynamic> json) {
    final name = validateHermesOpaqueIdentifier(json['name']);
    if (name == null) return null;
    final tools = json['tools'];
    return HermesAdminToolset(
      name: name,
      label: _text(json['label'], 512) ?? name,
      description: _text(json['description'], 4096) ?? '',
      enabled: json['enabled'] == true,
      // Hermes omits `configured` in `profiles.describe`.
      configured: json['configured'] != false,
      platform: _text(json['platform'], 64) ?? 'cli',
      toolCount: tools is List ? tools.length : _int(json['tool_count']) ?? 0,
    );
  }

  final String name;
  final String label;
  final String description;
  final bool enabled;

  /// False when the toolset still needs a key or setup before it works.
  final bool configured;

  /// The platform whose `platform_toolsets` entry the toggle writes.
  final String platform;
  final int toolCount;
}

/// One installed skill of `GET /api/skills`.
final class HermesAdminSkill {
  const HermesAdminSkill({
    required this.name,
    required this.description,
    required this.enabled,
    required this.usage,
    required this.provenance,
    this.category,
  });

  static HermesAdminSkill? fromJson(Map<String, dynamic> json) {
    final name = validateHermesBoundedString(json['name'], maxCharacters: 256);
    if (name == null) return null;
    return HermesAdminSkill(
      name: name,
      description: _text(json['description'], 2048) ?? '',
      enabled: json['enabled'] != false,
      usage: _int(json['usage']) ?? 0,
      provenance: _text(json['provenance'], 32) ?? 'agent',
      category: _text(json['category'], 128),
    );
  }

  final String name;
  final String description;
  final bool enabled;
  final int usage;

  /// `hub`, `bundled` or `agent` (written by the bot or by hand).
  final String provenance;
  final String? category;
}

/// One row of `plugins.manage list`.
final class HermesAdminPlugin {
  const HermesAdminPlugin({
    required this.key,
    required this.name,
    required this.version,
    required this.description,
    required this.source,
    required this.status,
  });

  static HermesAdminPlugin? fromJson(Map<String, dynamic> json) {
    final name = validateHermesBoundedString(json['name'], maxCharacters: 256);
    if (name == null) return null;
    return HermesAdminPlugin(
      key: _text(json['key'], 256) ?? name,
      name: name,
      version: _text(json['version'], 64) ?? '',
      description: _text(json['description'], 2048) ?? '',
      source: _text(json['source'], 64) ?? '',
      status: _text(json['status'], 64) ?? '',
    );
  }

  /// Canonical id; names collide across categories, so toggle by this.
  final String key;
  final String name;
  final String version;
  final String description;
  final String source;

  /// Hermes' own wording: `enabled`, `disabled`, `not enabled`.
  final String status;

  bool get enabled => status.toLowerCase() == 'enabled';
}

/// One entry of the MCP catalog (`mcp.catalog`).
final class HermesAdminMcpCatalogEntry {
  const HermesAdminMcpCatalogEntry({
    required this.name,
    required this.description,
    required this.installed,
    required this.enabled,
    required this.requires,
    required this.transport,
  });

  static HermesAdminMcpCatalogEntry? fromJson(Map<String, dynamic> json) {
    final name = validateHermesBoundedString(json['name'], maxCharacters: 128);
    if (name == null) return null;
    return HermesAdminMcpCatalogEntry(
      name: name,
      description: _text(json['description'], 1024) ?? '',
      installed: json['installed'] == true,
      enabled: json['enabled'] == true,
      requires: _strings(json['requires'], 128, 32),
      transport: _text(json['transport'], 32) ?? '',
    );
  }

  final String name;
  final String description;
  final bool installed;
  final bool enabled;

  /// Environment variables the server needs a value for.
  final List<String> requires;
  final String transport;
}

/// An MCP server sign-in flow started through the gateway.
final class HermesAdminMcpOAuthStart {
  const HermesAdminMcpOAuthStart({
    required this.sessionId,
    required this.authUrl,
  });

  static HermesAdminMcpOAuthStart? fromJson(Map<String, dynamic> json) {
    final sessionId = validateHermesOpaqueIdentifier(json['session_id']);
    final url = _text(json['auth_url'], 4096);
    if (sessionId == null || url == null) return null;
    return HermesAdminMcpOAuthStart(sessionId: sessionId, authUrl: url);
  }

  final String sessionId;
  final String authUrl;
}

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

String? _text(Object? value, int maxCharacters) =>
    validateHermesBoundedString(value, maxCharacters: maxCharacters);

int? _int(Object? value) => value is num ? value.toInt() : null;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .take(10000)
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false)
    : const [];

List<String> _strings(Object? value, int maxCharacters, int maxItems) =>
    value is List
    ? value
          .map((item) => _text(item, maxCharacters))
          .whereType<String>()
          .take(maxItems)
          .toList(growable: false)
    : const [];
