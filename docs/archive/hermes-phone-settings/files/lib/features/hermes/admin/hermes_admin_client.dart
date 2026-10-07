import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/utils/debug_logger.dart';
import '../models/hermes_config.dart';
import '../models/hermes_job.dart';
import '../models/hermes_mcp.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_desktop_transport.dart';
import '../services/hermes_identifier.dart';
import 'hermes_admin_models.dart';
import 'hermes_secret_redaction.dart';

/// What the admin client needs from a Hermes connection. The real one wraps
/// [HermesDesktopApiService]; tests supply a fake.
abstract interface class HermesAdminTransport {
  /// A gateway JSON-RPC call. Connects first when the gateway is not open.
  Future<Object?> rpc(String method, Map<String, dynamic> params);

  /// A REST call to an allowlisted admin route.
  Future<Object?> rest(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, Object?>? body,
  });

  /// An `mcp.*` call that carries `profile`, with REST fallback.
  Future<Map<String, dynamic>> mcp(String method, Map<String, dynamic> params);

  // The service's existing profile-aware readers and cron actions, reused
  // rather than re-implemented (KTD6).
  Future<List<Map<String, dynamic>>> skillCatalog(String profile);
  Future<Map<String, dynamic>> learningGraph(String profile);
  Future<List<Map<String, dynamic>>> cronJobs(String profile);
  Future<void> cronAction(
    String profile,
    String id,
    HermesAdminCronAction action,
  );
  Future<void> cronUpdate(
    String profile,
    String id, {
    String? name,
    String? prompt,
    String? schedule,
    bool? enabled,
  });
  Future<List<Map<String, dynamic>>> cronRuns(String profile, String id);
}

enum HermesAdminCronAction { pause, resume, run }

/// [HermesAdminTransport] over a Desktop Gateway connection: the public
/// `rpc` getter, `ensureAdminConnected`, `requestAdminJson` and the service's
/// existing wrappers. It never calls `cli.exec` or `shell.exec`.
final class HermesDesktopAdminTransport implements HermesAdminTransport {
  const HermesDesktopAdminTransport(this._service);

  final HermesDesktopApiService _service;

  @override
  Future<Object?> rpc(String method, Map<String, dynamic> params) async {
    await _service.ensureAdminConnected();
    return _service.rpc.request<Object?>(method, params: params);
  }

  @override
  Future<Object?> rest(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, Object?>? body,
  }) => _service.requestAdminJson(method, path, query: query, body: body);

  @override
  Future<Map<String, dynamic>> mcp(
    String method,
    Map<String, dynamic> params,
  ) => _service.requestAdminMcp(method, params: params);

  @override
  Future<List<Map<String, dynamic>>> skillCatalog(String profile) =>
      _service.skillCatalog(profile);

  @override
  Future<Map<String, dynamic>> learningGraph(String profile) =>
      _service.learningGraph(profile);

  @override
  Future<List<Map<String, dynamic>>> cronJobs(String profile) =>
      _service.listJobsForProfile(profile);

  @override
  Future<void> cronAction(
    String profile,
    String id,
    HermesAdminCronAction action,
  ) => switch (action) {
    HermesAdminCronAction.pause => _service.pauseJobForProfile(profile, id),
    HermesAdminCronAction.resume => _service.resumeJobForProfile(profile, id),
    HermesAdminCronAction.run => _service.runJobForProfile(profile, id),
  };

  @override
  Future<void> cronUpdate(
    String profile,
    String id, {
    String? name,
    String? prompt,
    String? schedule,
    bool? enabled,
  }) => _service.updateJobForProfile(
    profile,
    id,
    name: name,
    prompt: prompt,
    schedule: schedule,
    enabled: enabled,
  );

  @override
  Future<List<Map<String, dynamic>>> cronRuns(String profile, String id) =>
      _service.listJobRunsForProfile(profile, id);
}

final RegExp _envKeyName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,127}$');
final RegExp _toolsetName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$');
final RegExp _mcpServerName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$');
final RegExp _effortName = RegExp(r'^[a-z]{0,16}$');

/// JSON-RPC code Hermes uses for an unknown method.
const int _kRpcMethodNotFound = -32601;

/// JSON-RPC code `profiles.*` and `mcp.servers.remove` use for "not found".
const int _kRpcNotFound = 4064;

/// Every settings and bot-management call the app makes to Hermes (KTD6).
///
/// - Errors come back as [HermesAdminUnavailable] (not on this Hermes),
///   [HermesAdminNotFound] (the named profile, node or key is gone) or
///   [HermesAdminRejected] (Hermes refused). Anything else is a transport
///   problem and is rethrown as it was.
/// - Keys are write-only: nothing here calls `/api/env/reveal`, and a value
///   the caller sends never appears in an error message or a log line.
/// - Server error text is run through [HermesSecretRedaction] before it is
///   kept. Logs hold only the route name and the error type (R21).
/// - Writes apply to new sessions. MCP, plugin and env changes need
///   [reloadMcp] or a restart; the caller decides when.
final class HermesAdminClient {
  HermesAdminClient(this._transport);

  /// An admin client over a Desktop Gateway connection.
  factory HermesAdminClient.fromService(HermesDesktopApiService service) =>
      HermesAdminClient(HermesDesktopAdminTransport(service));

  final HermesAdminTransport _transport;

  /// Runs [call] and returns its result, or null when this Hermes does not
  /// have the feature. Other errors still throw.
  static Future<T?> ifAvailable<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on HermesAdminUnavailable {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Profiles (bots)
  // -------------------------------------------------------------------------

  Future<List<HermesAdminProfile>> listProfiles() =>
      _call('profiles.list', () async {
        final result = _object(
          await _transport.rpc('profiles.list', const {
            'include_sessions': false,
          }),
        );
        return _objects(result['profiles'])
            .map(HermesAdminProfile.fromJson)
            .whereType<HermesAdminProfile>()
            .take(256)
            .toList(growable: false);
      });

  Future<HermesAdminProfileDetail> describeProfile(String name) async {
    _requireProfile(name);
    return _call(
      'profiles.describe',
      () async => HermesAdminProfileDetail.fromJson(
        _object(await _transport.rpc('profiles.describe', {'name': name})),
      ),
    );
  }

  Future<HermesAdminProfileCreated> createProfile(
    HermesAdminProfileDraft draft,
  ) async {
    _requireProfile(draft.name);
    final cloneFrom = draft.cloneFrom;
    if (cloneFrom != null) _requireProfile(cloneFrom);
    _requireModelPair(draft.model, draft.provider);
    return _call(
      'profiles.create',
      () async => HermesAdminProfileCreated.fromJson(
        _object(
          await _transport.rpc('profiles.create', {
            'name': draft.name,
            if (draft.description?.trim().isNotEmpty ?? false)
              'description': draft.description!.trim(),
            if (draft.soul?.trim().isNotEmpty ?? false) 'soul': draft.soul,
            'model': ?_blank(draft.model),
            'provider': ?_blank(draft.provider),
            'clone_from': ?cloneFrom,
            if (draft.noSkills) 'no_skills': true,
          }),
        ),
        draft.name,
      ),
    );
  }

  /// Saves any of the bot's editable sections in one call. Each section
  /// applies on its own; see [HermesAdminConfigureResult.applied].
  ///
  /// A guarded model (expensive, or restricted by a data policy) comes back
  /// as a confirmation instead of being written. Confirming resends only the
  /// model, so the sections that were already saved are not sent twice.
  ///
  /// Toolsets are deliberately not a parameter: they go through
  /// [setToolsetEnabled], the per-toolset route (KTD7).
  Future<HermesAdminWrite<HermesAdminConfigureResult>> configureProfile(
    String name, {
    Map<String, Object?>? uiMeta,
    Map<String, int>? uiMetaExpectedRevisions,
    String? description,
    String? soul,
    String? model,
    String? provider,
    bool confirmedModel = false,
  }) async {
    _requireProfile(name);
    _requireModelPair(model, provider);
    return _call('profiles.configure', () async {
      final result = _object(
        await _transport.rpc('profiles.configure', {
          'name': name,
          'ui_meta': ?uiMeta,
          if (uiMeta != null && uiMetaExpectedRevisions != null)
            'ui_meta_expected_revisions': uiMetaExpectedRevisions,
          'description': ?description,
          'soul': ?soul,
          'model': ?_blank(model),
          'provider': ?_blank(provider),
          if (_blank(model) != null && confirmedModel)
            'confirm_expensive_model': true,
        }),
      );
      final parsed = HermesAdminConfigureResult.fromJson(result);
      if (result['confirm_required'] == true) {
        return HermesAdminWrite<HermesAdminConfigureResult>.needsConfirmation(
          HermesAdminConfirmation(
            message: _scrub(
              _textOr(result['confirm_message'], 'Confirm this model.'),
              const [],
            ),
            partial: parsed,
            confirm: () => configureProfile(
              name,
              model: model,
              provider: provider,
              confirmedModel: true,
            ),
          ),
        );
      }
      return HermesAdminWrite.done(parsed);
    });
  }

  Future<HermesAdminSoul> profileSoul(String name) async {
    _requireProfile(name);
    return _call('GET /api/profiles/{name}/soul', () async {
      final result = _object(
        await _transport.rest('GET', '/api/profiles/$name/soul'),
      );
      return HermesAdminSoul(
        content: result['content'] is String ? result['content'] as String : '',
        exists: result['exists'] == true,
      );
    });
  }

  Future<void> setProfileSoul(String name, String content) async {
    _requireProfile(name);
    return _call(
      'PUT /api/profiles/{name}/soul',
      () async => _transport.rest(
        'PUT',
        '/api/profiles/$name/soul',
        body: {'content': content},
      ),
    );
  }

  /// The bot's avatar as a `data:image/...` URL, or null when it has none.
  Future<String?> profileAvatar(String name) async {
    _requireProfile(name);
    return _call('profiles.get_asset', () async {
      final result = _object(
        await _transport.rpc('profiles.get_asset', {
          'name': name,
          'asset': 'avatar',
        }),
      );
      final data = result['data'];
      if (result['found'] != true ||
          data is! String ||
          data.length > _kMaxAvatarCharacters ||
          !data.startsWith('data:image/')) {
        return null;
      }
      return data;
    });
  }

  /// Stores a PNG, JPEG or WebP of at most 2 MB, given as a data URL.
  Future<void> setProfileAvatar(String name, String dataUrl) async {
    _requireProfile(name);
    return _call(
      'profiles.set_asset',
      () async => _transport.rpc('profiles.set_asset', {
        'name': name,
        'asset': 'avatar',
        'data': dataUrl,
      }),
    );
  }

  Future<void> clearProfileAvatar(String name) async {
    _requireProfile(name);
    return _call(
      'profiles.set_asset',
      () async => _transport.rpc('profiles.set_asset', {
        'name': name,
        'asset': 'avatar',
        'clear': true,
      }),
    );
  }

  /// Deletes a bot. The `default` bot cannot be deleted. The owner confirms
  /// by typing the bot's name before this is called (KTD10).
  Future<HermesAdminProfileDeleted> deleteProfile(String name) async {
    _requireProfile(name);
    if (name == 'default') {
      throw ArgumentError.value(
        name,
        'name',
        'The default bot cannot be deleted.',
      );
    }
    return _call(
      'DELETE /api/profiles/{name}',
      () async => HermesAdminProfileDeleted.fromJson(
        _object(await _transport.rest('DELETE', '/api/profiles/$name')),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Memory
  // -------------------------------------------------------------------------

  /// A bot's memory cards and learned skills. Read-only here; edit and
  /// delete go through [updateLearningNode] and [deleteLearningNode]. There
  /// is no way to add a memory: Hermes has no such route (KTD17).
  Future<HermesAdminLearningGraph> learningGraph(String profile) async {
    _requireProfile(profile);
    return _call(
      'learning.graph',
      () async => HermesAdminLearningGraph.fromJson(
        await _transport.learningGraph(profile),
      ),
    );
  }

  Future<HermesAdminLearningNodeDetail> learningNode(
    String profile,
    String id,
  ) async {
    _requireProfile(profile);
    _requireId(id, 'id');
    return _call(
      'GET /api/learning/node',
      () async => HermesAdminLearningNodeDetail.fromJson(
        _object(
          await _transport.rest(
            'GET',
            '/api/learning/node',
            query: {'id': id, 'profile': profile},
          ),
        ),
      ),
    );
  }

  /// Rewrites a memory chunk or skill. Hermes reads the profile from the
  /// body here, not the query.
  Future<void> updateLearningNode(
    String profile,
    String id,
    String content,
  ) async {
    _requireProfile(profile);
    _requireId(id, 'id');
    return _call(
      'PUT /api/learning/node',
      () async => _transport.rest(
        'PUT',
        '/api/learning/node',
        body: {'id': id, 'content': content, 'profile': profile},
      ),
    );
  }

  /// Removes a memory chunk, or archives a learned skill.
  Future<void> deleteLearningNode(String profile, String id) async {
    _requireProfile(profile);
    _requireId(id, 'id');
    return _call(
      'DELETE /api/learning/node',
      () async => _transport.rest(
        'DELETE',
        '/api/learning/node',
        body: {'id': id, 'profile': profile},
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Provider keys
  // -------------------------------------------------------------------------

  /// The bot's `.env` keys with Hermes' own redacted previews. The full
  /// value is never requested.
  Future<List<HermesAdminEnvKey>> listEnvKeys(String profile) async {
    _requireProfile(profile);
    return _call('GET /api/env', () async {
      final result = _object(
        await _transport.rest('GET', '/api/env', query: {'profile': profile}),
      );
      return [
        for (final entry in result.entries)
          if (entry.value is Map)
            ?HermesAdminEnvKey.fromJson(
              entry.key,
              Map<String, dynamic>.from(entry.value as Map),
            ),
      ];
    });
  }

  /// Saves a key to one bot's `.env`.
  Future<void> setEnvKey(String profile, String key, String value) async {
    _requireProfile(profile);
    _requireEnvKey(key);
    if (value.isEmpty) throw ArgumentError.value('', 'value', 'Empty value.');
    return _call(
      'PUT /api/env',
      () async => _transport.rest(
        'PUT',
        '/api/env',
        query: {'profile': profile},
        body: {'key': key, 'value': value},
      ),
      sensitive: [value],
    );
  }

  Future<void> deleteEnvKey(String profile, String key) async {
    _requireProfile(profile);
    _requireEnvKey(key);
    return _call(
      'DELETE /api/env',
      () async => _transport.rest(
        'DELETE',
        '/api/env',
        query: {'profile': profile},
        body: {'key': key},
      ),
    );
  }

  /// Probes a key with its provider before it is saved. [apiKey] is the
  /// bearer for a custom endpoint's `/models` check.
  Future<HermesAdminKeyValidation> validateProviderKey({
    required String key,
    required String value,
    String? apiKey,
  }) async {
    _requireEnvKey(key);
    final sensitive = [value, ?apiKey];
    return _call(
      'POST /api/providers/validate',
      () async => HermesAdminKeyValidation.fromJson(
        _object(
          await _transport.rest(
            'POST',
            '/api/providers/validate',
            body: {
              'key': key,
              'value': value,
              if (apiKey != null && apiKey.isNotEmpty) 'api_key': apiKey,
            },
          ),
        ),
        (text) => _scrub(text, sensitive),
      ),
      sensitive: sensitive,
    );
  }

  // -------------------------------------------------------------------------
  // Provider sign-in
  // -------------------------------------------------------------------------

  Future<List<HermesAdminProviderSignIn>> providerSignIns(
    String profile,
  ) async {
    _requireProfile(profile);
    return _call(
      'GET /api/providers/oauth',
      () async =>
          _objects(
                _object(
                  await _transport.rest(
                    'GET',
                    '/api/providers/oauth',
                    query: {'profile': profile},
                  ),
                )['providers'],
              )
              .map(HermesAdminProviderSignIn.fromJson)
              .whereType<HermesAdminProviderSignIn>()
              .toList(growable: false),
    );
  }

  /// Starts a device-code sign-in. Only the providers in
  /// [kHermesDeviceCodeProviders] have a working route (KTD8).
  Future<HermesAdminSignInStart> startProviderSignIn(
    String profile,
    String providerId,
  ) async {
    _requireProfile(profile);
    _requireId(providerId, 'providerId');
    if (!kHermesDeviceCodeProviders.contains(providerId)) {
      throw ArgumentError.value(
        providerId,
        'providerId',
        'Hermes cannot sign in to this provider from the app.',
      );
    }
    return _call('POST /api/providers/oauth/{id}/start', () async {
      final started = HermesAdminSignInStart.fromJson(
        _object(
          await _transport.rest(
            'POST',
            '/api/providers/oauth/${Uri.encodeComponent(providerId)}/start',
            query: {'profile': profile},
          ),
        ),
      );
      if (started == null) {
        throw const HermesAdminRejected(
          'Hermes sent an unusable sign-in code.',
        );
      }
      return started;
    });
  }

  Future<HermesAdminSignInPoll> pollProviderSignIn(
    String profile,
    String providerId,
    String sessionId,
  ) async {
    _requireProfile(profile);
    _requireId(providerId, 'providerId');
    _requireId(sessionId, 'sessionId');
    return _call(
      'GET /api/providers/oauth/{id}/poll/{session}',
      () async => HermesAdminSignInPoll.fromJson(
        _object(
          await _transport.rest(
            'GET',
            '/api/providers/oauth/${Uri.encodeComponent(providerId)}'
                '/poll/${Uri.encodeComponent(sessionId)}',
            query: {'profile': profile},
          ),
        ),
        (text) => _scrub(text, const []),
      ),
    );
  }

  Future<void> cancelProviderSignIn(String profile, String sessionId) async {
    _requireProfile(profile);
    _requireId(sessionId, 'sessionId');
    return _call(
      'DELETE /api/providers/oauth/sessions/{session}',
      () async => _transport.rest(
        'DELETE',
        '/api/providers/oauth/sessions/${Uri.encodeComponent(sessionId)}',
        query: {'profile': profile},
      ),
    );
  }

  Future<void> disconnectProvider(String profile, String providerId) async {
    _requireProfile(profile);
    _requireId(providerId, 'providerId');
    return _call(
      'DELETE /api/providers/oauth/{id}',
      () async => _transport.rest(
        'DELETE',
        '/api/providers/oauth/${Uri.encodeComponent(providerId)}',
        query: {'profile': profile},
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Models
  // -------------------------------------------------------------------------

  Future<HermesAdminModelOptions> modelOptions(
    String profile, {
    bool explicitOnly = false,
    bool includeUnconfigured = false,
    bool refresh = false,
  }) async {
    _requireProfile(profile);
    return _call(
      'model.options',
      () async => HermesAdminModelOptions.fromJson(
        _object(
          await _transport.rpc('model.options', {
            'profile': profile,
            if (explicitOnly) 'explicit_only': true,
            if (includeUnconfigured) 'include_unconfigured': true,
            if (refresh) 'refresh': true,
          }),
        ),
      ),
    );
  }

  /// Sets a bot's default model (`scope: main`) or an auxiliary slot
  /// (`scope: auxiliary`, with [task]).
  ///
  /// Hermes can hold a guarded model back and answer `confirm_required`;
  /// that comes back as a confirmation, and confirming resends the same
  /// request with the confirm flag. Nothing is written until then.
  ///
  /// The main default reasoning effort is not set here: `model/set` applies
  /// it to auxiliary slots only on 0.21.5. Use [setReasoningEffort].
  Future<HermesAdminWrite<void>> setModel({
    required String profile,
    required String provider,
    required String model,
    String scope = 'main',
    String task = '',
    String baseUrl = '',
    String apiKey = '',
    bool confirmed = false,
  }) async {
    _requireProfile(profile);
    if (provider.trim().isEmpty || model.trim().isEmpty) {
      throw ArgumentError('A model needs a provider and a name.');
    }
    if (scope != 'main' && scope != 'auxiliary') {
      throw ArgumentError.value(scope, 'scope');
    }
    final sensitive = [if (apiKey.isNotEmpty) apiKey];
    return _call('POST /api/model/set', () async {
      final result = _object(
        await _transport.rest(
          'POST',
          '/api/model/set',
          query: {'profile': profile},
          body: {
            'scope': scope,
            'provider': provider,
            'model': model,
            'task': task,
            'base_url': baseUrl,
            'api_key': apiKey,
            'confirm_expensive_model': confirmed,
            'profile': profile,
          },
        ),
      );
      if (result['confirm_required'] == true) {
        return HermesAdminWrite<void>.needsConfirmation(
          HermesAdminConfirmation<void>(
            message: _scrub(
              _textOr(result['confirm_message'], 'Confirm this model.'),
              sensitive,
            ),
            confirm: () => setModel(
              profile: profile,
              provider: provider,
              model: model,
              scope: scope,
              task: task,
              baseUrl: baseUrl,
              apiKey: apiKey,
              confirmed: true,
            ),
          ),
        );
      }
      return const HermesAdminWrite<void>.done(null);
    }, sensitive: sensitive);
  }

  /// Sets a bot's default reasoning effort. An empty string returns it to
  /// Hermes' default. Goes through the merging config route.
  Future<void> setReasoningEffort(String profile, String effort) async {
    if (!_effortName.hasMatch(effort)) {
      throw ArgumentError.value(effort, 'effort');
    }
    return mergeConfig(profile, {
      'agent': {'reasoning_effort': effort},
    });
  }

  /// Replaces a bot's fallback chain: each entry is tried in order when the
  /// main model fails. Also clears the legacy `fallback_model` key, which
  /// Hermes would otherwise fold back into the chain.
  Future<void> setFallbackProviders(
    String profile,
    List<({String provider, String model})> chain,
  ) async {
    for (final entry in chain) {
      if (entry.provider.trim().isEmpty || entry.model.trim().isEmpty) {
        throw ArgumentError('A fallback needs a provider and a model.');
      }
    }
    return mergeConfig(profile, {
      'fallback_providers': [
        for (final entry in chain)
          {'provider': entry.provider, 'model': entry.model},
      ],
      'fallback_model': null,
    });
  }

  // -------------------------------------------------------------------------
  // Config
  // -------------------------------------------------------------------------

  /// The merged config as the dashboard shows it. [profile] null is the
  /// server's own (root) config.
  Future<Map<String, dynamic>> config(
    String? profile, {
    bool includeDefaults = true,
  }) async {
    if (profile != null) _requireProfile(profile);
    return _call(
      'GET /api/config',
      () async => _object(
        await _transport.rest(
          'GET',
          '/api/config',
          query: {
            'profile': ?profile,
            if (!includeDefaults) 'include_defaults': false,
          },
        ),
      ),
    );
  }

  /// Deep-merges [patch] over the saved config. It can add and change keys,
  /// not delete them; use [saveRawConfig] to remove one.
  Future<void> mergeConfig(String? profile, Map<String, Object?> patch) async {
    if (profile != null) _requireProfile(profile);
    if (patch.isEmpty) throw ArgumentError.value(patch, 'patch', 'Empty.');
    return _call(
      'PUT /api/config',
      () async => _transport.rest(
        'PUT',
        '/api/config',
        query: {'profile': ?profile},
        body: {'config': patch, 'profile': ?profile},
      ),
      sensitive: HermesSecretRedaction.secretValuesIn(patch),
    );
  }

  /// The config file's text, unredacted. Mask it with
  /// [HermesSecretRedaction] before it is shown, diffed or stored.
  Future<HermesAdminRawConfig> rawConfig(String? profile) async {
    if (profile != null) _requireProfile(profile);
    return _call('GET /api/config/raw', () async {
      final result = _object(
        await _transport.rest(
          'GET',
          '/api/config/raw',
          query: {'profile': ?profile},
        ),
      );
      return HermesAdminRawConfig(
        yaml: result['yaml'] is String ? result['yaml'] as String : '',
        path: _textOr(result['path'], ''),
      );
    });
  }

  /// Replaces the whole config file. Hermes parses it first and refuses
  /// anything that is not a YAML mapping. Callers diff and confirm before
  /// calling this (KTD9).
  Future<void> saveRawConfig(String? profile, String yaml) async {
    if (profile != null) _requireProfile(profile);
    return _call(
      'PUT /api/config/raw',
      () async => _transport.rest(
        'PUT',
        '/api/config/raw',
        query: {'profile': ?profile},
        body: {'yaml_text': yaml, 'profile': ?profile},
      ),
      // An `Invalid YAML` error can quote lines of the file.
      sensitive: HermesSecretRedaction.secretValuesInYamlText(yaml),
    );
  }

  Future<HermesAdminConfigSchema> configSchema(String? profile) async {
    if (profile != null) _requireProfile(profile);
    return _call(
      'GET /api/config/schema',
      () async => HermesAdminConfigSchema.fromJson(
        _object(
          await _transport.rest(
            'GET',
            '/api/config/schema',
            query: {'profile': ?profile},
          ),
        ),
      ),
    );
  }

  /// Root keys Hermes knows: `DEFAULT_CONFIG`'s, read from the public
  /// `/api/config/defaults`, plus the ones that list leaves out
  /// ([kHermesExtraKnownRootKeys]).
  Future<Set<String>> knownConfigRootKeys() => _call(
    'GET /api/config/defaults',
    () async => {
      ..._object(await _transport.rest('GET', '/api/config/defaults')).keys,
      ...kHermesExtraKnownRootKeys,
    },
  );

  // -------------------------------------------------------------------------
  // Tools and extensions
  // -------------------------------------------------------------------------

  Future<List<HermesAdminToolset>> toolsets(String profile) async {
    _requireProfile(profile);
    return _call('GET /api/tools/toolsets', () async {
      final result = await _transport.rest(
        'GET',
        '/api/tools/toolsets',
        query: {'profile': profile},
      );
      return _objects(result)
          .map(HermesAdminToolset.fromJson)
          .whereType<HermesAdminToolset>()
          .toList(growable: false);
    });
  }

  /// Turns one toolset on or off for one bot, through the per-toolset route
  /// that writes the enforced `platform_toolsets` key (KTD7).
  Future<void> setToolsetEnabled(
    String profile,
    String name,
    bool enabled,
  ) async {
    _requireProfile(profile);
    if (!_toolsetName.hasMatch(name)) throw ArgumentError.value(name, 'name');
    return _call(
      'PUT /api/tools/toolsets/{name}',
      () async => _transport.rest(
        'PUT',
        '/api/tools/toolsets/${Uri.encodeComponent(name)}',
        query: {'profile': profile},
        body: {'enabled': enabled, 'profile': profile},
      ),
    );
  }

  Future<List<HermesAdminSkill>> skills(String profile) async {
    _requireProfile(profile);
    return _call(
      'GET /api/skills',
      () async =>
          (await _transport.skillCatalog(profile))
              .map(HermesAdminSkill.fromJson)
              .whereType<HermesAdminSkill>()
              .toList(growable: false),
    );
  }

  /// Enables or disables an installed skill for one bot. `skills.manage`
  /// cannot do this on 0.21.5; the REST toggle can.
  Future<void> setSkillEnabled(
    String profile,
    String name,
    bool enabled,
  ) async {
    _requireProfile(profile);
    _requireId(name, 'name', allowSlash: true);
    return _call(
      'PUT /api/skills/toggle',
      () async => _transport.rest(
        'PUT',
        '/api/skills/toggle',
        query: {'profile': profile},
        body: {'name': name, 'enabled': enabled, 'profile': profile},
      ),
    );
  }

  Future<List<HermesMcpServer>> mcpServers(String profile) async {
    _requireProfile(profile);
    return _call(
      'mcp.servers.list',
      () async =>
          _objects(
                (await _transport.mcp('mcp.servers.list', {
                  'profile': profile,
                }))['servers'],
              )
              .map(HermesMcpServer.fromJson)
              .where((server) => server.name.isNotEmpty)
              .toList(growable: false),
    );
  }

  Future<List<HermesAdminMcpCatalogEntry>> mcpCatalog(String profile) async {
    _requireProfile(profile);
    return _call(
      'mcp.catalog',
      () async =>
          _objects(
                (await _transport.mcp('mcp.catalog', {
                  'profile': profile,
                }))['servers'],
              )
              .map(HermesAdminMcpCatalogEntry.fromJson)
              .whereType<HermesAdminMcpCatalogEntry>()
              .toList(growable: false),
    );
  }

  /// Adds an MCP server from a catalog [preset], a [url] or a [command].
  /// [bearerToken] goes to the bot's `.env`; only a `${VAR}` reference is
  /// written to the config.
  Future<void> addMcpServer(
    String profile, {
    required String name,
    String? preset,
    String? url,
    String? command,
    List<String> arguments = const [],
    String? bearerToken,
  }) async {
    _requireProfile(profile);
    _requireMcpName(name);
    final token = bearerToken?.isNotEmpty == true ? bearerToken : null;
    return _call(
      'mcp.servers.add',
      () async => _transport.mcp('mcp.servers.add', {
        'profile': profile,
        'name': name,
        if (preset?.isNotEmpty == true) 'preset': preset,
        'config': {
          if (url?.isNotEmpty == true) 'url': url,
          if (command?.isNotEmpty == true) 'command': command,
          if (arguments.isNotEmpty) 'args': arguments,
        },
        'bearer_token': ?token,
      }),
      sensitive: [?token],
    );
  }

  Future<HermesMcpTestResult> testMcpServer(String profile, String name) async {
    _requireProfile(profile);
    _requireMcpName(name);
    return _call(
      'mcp.servers.test',
      () async => HermesMcpTestResult.fromJson(
        await _transport.mcp('mcp.servers.test', {
          'profile': profile,
          'name': name,
        }),
      ),
    );
  }

  Future<void> setMcpApiKey(String profile, String name, String value) async {
    _requireProfile(profile);
    _requireMcpName(name);
    if (value.isEmpty) throw ArgumentError.value('', 'value', 'Empty value.');
    return _call(
      'mcp.servers.set_api_key',
      () async => _transport.mcp('mcp.servers.set_api_key', {
        'profile': profile,
        'name': name,
        'value': value,
      }),
      sensitive: [value],
    );
  }

  Future<void> removeMcpServer(String profile, String name) async {
    _requireProfile(profile);
    _requireMcpName(name);
    return _call(
      'mcp.servers.remove',
      () async => _transport.mcp('mcp.servers.remove', {
        'profile': profile,
        'name': name,
      }),
    );
  }

  /// Turns an MCP server on or off for one bot. Hermes has no gateway method
  /// for this, so it is the REST route; it answers 409 for a server that a
  /// plugin provides ([HermesAdminRejected] with code 409).
  Future<void> setMcpServerEnabled(
    String profile,
    String name,
    bool enabled,
  ) async {
    _requireProfile(profile);
    _requireMcpName(name);
    return _call(
      'PUT /api/mcp/servers/{name}/enabled',
      () async => _transport.rest(
        'PUT',
        '/api/mcp/servers/${Uri.encodeComponent(name)}/enabled',
        query: {'profile': profile},
        body: {'enabled': enabled, 'profile': profile},
      ),
    );
  }

  /// Starts an MCP server sign-in. The caller opens
  /// [HermesAdminMcpOAuthStart.authUrl] and polls [pollMcpOAuth].
  Future<HermesAdminMcpOAuthStart> startMcpOAuth(
    String profile,
    String name,
  ) async {
    _requireProfile(profile);
    _requireMcpName(name);
    return _call('mcp.servers.oauth.start', () async {
      final started = HermesAdminMcpOAuthStart.fromJson(
        await _transport.mcp('mcp.servers.oauth.start', {
          'profile': profile,
          'name': name,
        }),
      );
      if (started == null) {
        throw const HermesAdminRejected(
          'Hermes sent an unusable sign-in link.',
        );
      }
      return started;
    });
  }

  Future<HermesAdminSignInPoll> pollMcpOAuth(
    String profile,
    String name,
    String sessionId,
  ) async {
    _requireProfile(profile);
    _requireMcpName(name);
    _requireId(sessionId, 'sessionId');
    return _call(
      'mcp.servers.oauth.poll',
      () async => HermesAdminSignInPoll.fromJson(
        await _transport.mcp('mcp.servers.oauth.poll', {
          'profile': profile,
          'name': name,
          'session_id': sessionId,
        }),
        (text) => _scrub(text, const []),
      ),
    );
  }

  Future<void> cancelMcpOAuth(
    String profile,
    String name,
    String sessionId,
  ) async {
    _requireProfile(profile);
    _requireMcpName(name);
    _requireId(sessionId, 'sessionId');
    return _call(
      'mcp.servers.oauth.cancel',
      () async => _transport.mcp('mcp.servers.oauth.cancel', {
        'profile': profile,
        'name': name,
        'session_id': sessionId,
      }),
    );
  }

  /// Reloads MCP servers in the running gateway (`reload.mcp`). It is not
  /// per bot, and it invalidates the prompt cache, so Hermes asks first
  /// unless told otherwise. Without [confirm] that question comes back as a
  /// confirmation; confirming resends with `confirm: true`. Pass [confirm]
  /// when the owner has just pressed Save.
  Future<HermesAdminWrite<void>> reloadMcp({bool confirm = false}) =>
      _call('reload.mcp', () async {
        final result = _object(
          await _transport.rpc('reload.mcp', {'confirm': confirm}),
        );
        if (result['status'] == 'confirm_required') {
          return HermesAdminWrite<void>.needsConfirmation(
            HermesAdminConfirmation<void>(
              message: _scrub(
                _textOr(
                  result['message'],
                  'Reloading MCP clears the prompt cache.',
                ),
                const [],
              ),
              confirm: () => reloadMcp(confirm: true),
            ),
          );
        }
        return const HermesAdminWrite<void>.done(null);
      });

  Future<List<HermesAdminPlugin>> plugins(String profile) async {
    _requireProfile(profile);
    return _call(
      'plugins.manage.list',
      () async =>
          _objects(
                _object(
                  await _transport.rpc('plugins.manage', {
                    'action': 'list',
                    'profile': profile,
                  }),
                )['plugins'],
              )
              .map(HermesAdminPlugin.fromJson)
              .whereType<HermesAdminPlugin>()
              .toList(growable: false),
    );
  }

  /// Enables or disables a plugin by its canonical [key]. Plugin changes
  /// need a gateway restart before they apply; the caller says so.
  Future<void> setPluginEnabled(
    String profile,
    String key,
    bool enabled,
  ) async {
    _requireProfile(profile);
    _requireId(key, 'key', allowSlash: true);
    return _call(
      'plugins.manage.toggle',
      () async => _transport.rpc('plugins.manage', {
        'action': 'toggle',
        'key': key,
        'enable': enabled,
        'profile': profile,
      }),
    );
  }

  // -------------------------------------------------------------------------
  // Scheduled routines
  // -------------------------------------------------------------------------

  /// The bot's own routines. Hermes defaults the list to every bot, so the
  /// profile is always sent.
  Future<List<HermesJob>> cronJobs(String profile) async {
    _requireProfile(profile);
    return _call(
      'GET /api/cron/jobs',
      () async =>
          (await _transport.cronJobs(profile))
              .map(HermesJob.fromJson)
              .whereType<HermesJob>()
              .toList(growable: false),
    );
  }

  Future<void> pauseCronJob(String profile, String id) =>
      _cronAction(profile, id, HermesAdminCronAction.pause);

  Future<void> resumeCronJob(String profile, String id) =>
      _cronAction(profile, id, HermesAdminCronAction.resume);

  Future<void> runCronJob(String profile, String id) =>
      _cronAction(profile, id, HermesAdminCronAction.run);

  Future<void> _cronAction(
    String profile,
    String id,
    HermesAdminCronAction action,
  ) async {
    _requireProfile(profile);
    _requireId(id, 'id');
    return _call(
      'cron.${action.name}',
      () => _transport.cronAction(profile, id, action),
    );
  }

  Future<void> updateCronJob(
    String profile,
    String id, {
    String? name,
    String? prompt,
    String? schedule,
    bool? enabled,
  }) async {
    _requireProfile(profile);
    _requireId(id, 'id');
    return _call(
      'PUT /api/cron/jobs/{id}',
      () => _transport.cronUpdate(
        profile,
        id,
        name: name,
        prompt: prompt,
        schedule: schedule,
        enabled: enabled,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> cronRuns(String profile, String id) async {
    _requireProfile(profile);
    _requireId(id, 'id');
    return _call(
      'GET /api/cron/jobs/{id}/runs',
      () => _transport.cronRuns(profile, id),
    );
  }

  // -------------------------------------------------------------------------
  // Gateway
  // -------------------------------------------------------------------------

  /// Asks Hermes to restart its gateway, which interrupts every bot. Whether
  /// this works inside the Umbrel container is unverified, so it exists only
  /// behind an explicit owner action: pass [ownerConfirmed] true after the
  /// owner has said so.
  Future<void> restartGateway({
    required bool ownerConfirmed,
    String? profile,
  }) async {
    if (!ownerConfirmed) {
      throw StateError('Restarting the gateway needs the owner to confirm.');
    }
    if (profile != null) _requireProfile(profile);
    return _call(
      'POST /api/gateway/restart',
      () async => _transport.rest(
        'POST',
        '/api/gateway/restart',
        query: {'profile': ?profile},
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Plumbing
  // -------------------------------------------------------------------------

  /// Runs [body], maps its failure to a [HermesAdminException] where it is
  /// one, and logs the route and error type only. [sensitive] are values the
  /// call just sent; they are scrubbed from any error text.
  Future<T> _call<T>(
    String route,
    Future<T> Function() body, {
    Iterable<String> sensitive = const [],
  }) async {
    try {
      return await body();
    } catch (error, stackTrace) {
      final mapped = _mapError(error, sensitive.toList(growable: false));
      DebugLogger.warning(
        'admin-request-failed',
        scope: 'hermes/admin',
        data: {
          'route': route,
          'errorType': (mapped ?? error).runtimeType.toString(),
          if (mapped is HermesAdminRejected && mapped.code != null)
            'code': mapped.code,
        },
      );
      if (mapped == null) rethrow;
      Error.throwWithStackTrace(mapped, stackTrace);
    }
  }

  HermesAdminException? _mapError(Object error, List<String> sensitive) {
    if (error is HermesAdminException) return error;
    if (error is HermesDesktopRpcException) {
      final code = error.code;
      if (code == null) return null;
      if (code == _kRpcMethodNotFound) {
        return const HermesAdminUnavailable(_unavailableMessage);
      }
      final text = _scrub(error.message, sensitive);
      if (code == _kRpcNotFound) return HermesAdminNotFound(text);
      return HermesAdminRejected(text, code: code);
    }
    if (error is DioException) {
      final response = error.response;
      if (response == null) return null;
      return _mapStatus(
        response.statusCode,
        _decodeBody(response.data),
        sensitive,
      );
    }
    // The dashboard-cookie bridge reports a failed call as a StateError that
    // carries the status but not the body.
    if (error is StateError) {
      final match = RegExp(r'^Hermes dashboard request failed \((\d{3})\)')
          .firstMatch(error.message);
      if (match != null) {
        return _mapStatus(int.parse(match.group(1)!), null, sensitive);
      }
    }
    return null;
  }

  HermesAdminException? _mapStatus(
    int? status,
    Object? body,
    List<String> sensitive,
  ) {
    if (status == null) return null;
    final detail = _detail(body);
    switch (status) {
      case 404:
        // 0.21.5 answers an unknown GET with "No such API endpoint" (or, under
        // headless serve, an `error` body), and older servers with a bare
        // "Not Found". Anything else names a thing that is missing: a profile
        // ("Profile 'x' does not exist."), a node, an env key. Without a body
        // there is nothing to tell them apart, so assume the route.
        final bodyMap = body is Map ? body : null;
        final routeMissing =
            body == null ||
            detail == null ||
            detail == 'Not Found' ||
            detail.toLowerCase().startsWith('no such api endpoint') ||
            (bodyMap != null &&
                bodyMap.containsKey('error') &&
                !bodyMap.containsKey('detail'));
        return routeMissing
            ? const HermesAdminUnavailable(_unavailableMessage)
            : HermesAdminNotFound(_scrub(detail, sensitive));
      case 405:
        // Hermes' SPA catch-all swallows every path, so a missing PUT, POST or
        // DELETE route answers "Method Not Allowed" instead of 404.
        return const HermesAdminUnavailable(_unavailableMessage);
      case 400 || 409 || 413 || 422 || 429:
      case >= 500:
        return HermesAdminRejected(
          _scrub(detail ?? 'Hermes refused the request ($status).', sensitive),
          code: status,
        );
    }
    // 401 and 403 are sign-in problems, not admin answers; leave them to the
    // transport's own handling.
    return null;
  }

  static const String _unavailableMessage =
      "This Hermes server doesn't support that.";

  /// The response body as JSON when it is, or its text. Bounded, so a hostile
  /// page cannot make an error message huge.
  static Object? _decodeBody(Object? data) {
    String? text;
    if (data is List<int>) {
      text = utf8.decode(
        data.length > 16384 ? data.sublist(0, 16384) : data,
        allowMalformed: true,
      );
    } else if (data is String) {
      text = data.length > 16384 ? data.substring(0, 16384) : data;
    } else if (data is Map || data is List) {
      return data;
    }
    if (text == null || text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  /// The human-readable reason in a FastAPI error body.
  static String? _detail(Object? body) {
    if (body is String) return body.trim().isEmpty ? null : body.trim();
    if (body is! Map) return null;
    final detail = body['detail'] ?? body['error'] ?? body['message'];
    if (detail is String) return detail.trim().isEmpty ? null : detail.trim();
    if (detail is List) {
      // 422 validation: a list of {loc, msg, type}.
      final messages = detail
          .map((item) => item is Map ? item['msg'] : item)
          .whereType<String>()
          .take(3)
          .join('; ');
      return messages.isEmpty ? null : messages;
    }
    return null;
  }

  /// Server text made safe to keep or show: secrets removed, and bounded.
  static String _scrub(String text, Iterable<String> sensitive) {
    final clean = HermesSecretRedaction.redactText(
      text,
      secrets: sensitive,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length > 400 ? '${clean.substring(0, 399)}…' : clean;
  }

  static Map<String, dynamic> _object(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .take(10000)
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false)
      : const [];

  static String _textOr(Object? value, String fallback) =>
      validateHermesBoundedString(value, maxCharacters: 2048) ?? fallback;

  static String? _blank(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static void _requireProfile(String name) {
    if (!HermesConfig.isValidDesktopProfile(name)) {
      throw ArgumentError.value(name, 'profile');
    }
  }

  static void _requireModelPair(String? model, String? provider) {
    final hasModel = model?.trim().isNotEmpty ?? false;
    final hasProvider = provider?.trim().isNotEmpty ?? false;
    if (hasModel != hasProvider) {
      throw ArgumentError('A model and its provider are set together.');
    }
  }

  static void _requireEnvKey(String key) {
    if (!_envKeyName.hasMatch(key)) throw ArgumentError.value(key, 'key');
  }

  static void _requireMcpName(String name) {
    if (!_mcpServerName.hasMatch(name)) throw ArgumentError.value(name, 'name');
  }

  static void _requireId(String id, String label, {bool allowSlash = false}) {
    final safe = validateHermesOpaqueIdentifier(id);
    if (safe == null || (!allowSlash && id.contains('/'))) {
      throw ArgumentError.value(id, label);
    }
  }
}

/// Largest avatar data URL accepted: Hermes stores 2 MB of image bytes, which
/// base64 inflates by 4/3.
const int _kMaxAvatarCharacters = 3 * 1024 * 1024;
