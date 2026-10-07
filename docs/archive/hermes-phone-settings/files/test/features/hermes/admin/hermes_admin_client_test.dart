import 'dart:async';
import 'dart:convert';

import 'package:conduit/features/hermes/admin/hermes_admin_client.dart';
import 'package:conduit/features/hermes/admin/hermes_admin_models.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_transport.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// One call the client made through the transport.
final class _Call {
  _Call(this.kind, this.name, {this.path, this.query, this.body, this.params});

  /// `rpc`, `rest`, `mcp`, `cron` or `reader`.
  final String kind;

  /// The RPC method, REST verb, or reader name.
  final String name;
  final String? path;
  final Map<String, dynamic>? query;
  final Map<String, Object?>? body;
  final Map<String, dynamic>? params;

  /// `GET /api/env` for REST, the method for RPC and MCP.
  String get route => kind == 'rest' ? '$name $path' : name;

  @override
  String toString() => '$kind $route $query $body $params';
}

typedef _Handler = FutureOr<Object?> Function(_Call call);

final class _FakeTransport implements HermesAdminTransport {
  final calls = <_Call>[];

  /// Keyed by RPC method, MCP method, or `VERB /path`.
  final handlers = <String, _Handler>{};

  List<Map<String, dynamic>> skillRows = const [];
  Map<String, dynamic> graph = const {};
  List<Map<String, dynamic>> jobs = const [];

  Future<Object?> _answer(_Call call) async {
    calls.add(call);
    final handler = handlers[call.route];
    return handler == null ? <String, Object?>{} : await handler(call);
  }

  Iterable<_Call> callsOf(String kind) => calls.where((c) => c.kind == kind);

  @override
  Future<Object?> rpc(String method, Map<String, dynamic> params) =>
      _answer(_Call('rpc', method, params: params));

  @override
  Future<Object?> rest(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, Object?>? body,
  }) => _answer(_Call('rest', method, path: path, query: query, body: body));

  @override
  Future<Map<String, dynamic>> mcp(
    String method,
    Map<String, dynamic> params,
  ) async {
    final result = await _answer(_Call('mcp', method, params: params));
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  @override
  Future<List<Map<String, dynamic>>> skillCatalog(String profile) async {
    calls.add(_Call('reader', 'skillCatalog', params: {'profile': profile}));
    return skillRows;
  }

  @override
  Future<Map<String, dynamic>> learningGraph(String profile) async {
    calls.add(_Call('reader', 'learningGraph', params: {'profile': profile}));
    return graph;
  }

  @override
  Future<List<Map<String, dynamic>>> cronJobs(String profile) async {
    calls.add(_Call('cron', 'list', params: {'profile': profile}));
    return jobs;
  }

  @override
  Future<void> cronAction(
    String profile,
    String id,
    HermesAdminCronAction action,
  ) async {
    calls.add(
      _Call('cron', action.name, params: {'profile': profile, 'id': id}),
    );
  }

  @override
  Future<void> cronUpdate(
    String profile,
    String id, {
    String? name,
    String? prompt,
    String? schedule,
    bool? enabled,
  }) async {
    calls.add(
      _Call(
        'cron',
        'update',
        params: {'profile': profile, 'id': id, 'enabled': enabled},
      ),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> cronRuns(String profile, String id) async {
    calls.add(_Call('cron', 'runs', params: {'profile': profile, 'id': id}));
    return const [];
  }
}

DioException _http(int status, Object? body) {
  final options = RequestOptions(path: '/api/x');
  return DioException(
    requestOptions: options,
    response: Response<List<int>>(
      requestOptions: options,
      statusCode: status,
      data: body == null ? null : utf8.encode(jsonEncode(body)),
    ),
    type: DioExceptionType.badResponse,
  );
}

HermesDesktopRpcException _rpcError(int code, String message) =>
    HermesDesktopRpcException(message, code: code);

void main() {
  late _FakeTransport transport;
  late HermesAdminClient client;

  setUp(() {
    transport = _FakeTransport();
    client = HermesAdminClient(transport);
  });

  group('profiles', () {
    test('list asks for profiles without session previews', () async {
      transport.handlers['profiles.list'] = (_) => {
        'profiles': [
          {
            'name': 'default',
            'is_default': true,
            'model': 'gpt-5',
            'provider': 'openai',
            'description': 'The main bot',
            'skill_count': 4,
            'has_avatar': true,
            'ui_meta': {
              'hermes-bots': {'title': 'Main'},
            },
            'ui_meta_revisions': {'hermes-bots': 3},
          },
          {'name': ''},
        ],
      };
      final profiles = await client.listProfiles();
      expect(transport.calls.single.params, {'include_sessions': false});
      expect(profiles, hasLength(1));
      expect(profiles.single.name, 'default');
      expect(profiles.single.isDefault, isTrue);
      expect(profiles.single.uiMetaRevisions, {'hermes-bots': 3});
    });

    test('describe and create name the profile', () async {
      transport.handlers['profiles.describe'] = (_) => {
        'name': 'ops',
        'soul': 'Be brief.',
        'model': {'provider': 'openai', 'default': 'gpt-5'},
        'skills': [
          {'name': 'git', 'enabled': false},
        ],
        'toolsets': [
          {'name': 'web', 'label': 'Web', 'enabled': true, 'tool_count': 3},
        ],
        'toolsets_pinned': true,
        'mcp_servers': [
          {'name': 'github', 'enabled': true, 'transport': 'http'},
        ],
      };
      final detail = await client.describeProfile('ops');
      expect(detail.soul, 'Be brief.');
      expect(detail.toolsets.single.toolCount, 3);
      expect(detail.skills.single.enabled, isFalse);
      expect(detail.mcpServers.single.transport, 'http');

      transport.handlers['profiles.create'] = (_) => {
        'ok': true,
        'name': 'qa-new',
        'soul_written': true,
        'model_set': true,
      };
      final created = await client.createProfile(
        const HermesAdminProfileDraft(
          name: 'qa-new',
          description: ' A helper ',
          soul: 'Be kind.',
          model: 'gpt-5',
          provider: 'openai',
        ),
      );
      expect(created.soulWritten, isTrue);
      expect(transport.calls.last.params, {
        'name': 'qa-new',
        'description': 'A helper',
        'soul': 'Be kind.',
        'model': 'gpt-5',
        'provider': 'openai',
      });
    });

    test('an invalid or half-given argument fails before any call', () async {
      await expectLater(
        client.describeProfile('Bad Name'),
        throwsArgumentError,
      );
      await expectLater(client.deleteProfile('default'), throwsArgumentError);
      await expectLater(
        client.createProfile(
          const HermesAdminProfileDraft(name: 'qa-x', model: 'gpt-5'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        client.setEnvKey('ops', 'bad key', 'v'),
        throwsArgumentError,
      );
      await expectLater(
        client.startProviderSignIn('ops', 'anthropic'),
        throwsArgumentError,
      );
      expect(transport.calls, isEmpty);
    });

    test(
      'configure sends only the sections given and flags conflicts',
      () async {
        transport.handlers['profiles.configure'] = (_) => {
          'ok': false,
          'applied': {
            'description': true,
            'ui_meta': false,
            'ui_meta_conflicts': {
              'hermes-bots': {'expected': 1, 'actual': 2},
            },
          },
        };
        final result = await client.configureProfile(
          'ops',
          description: 'New',
          uiMeta: {
            'hermes-bots': {'title': 'Ops'},
          },
          uiMetaExpectedRevisions: {'hermes-bots': 1},
        );
        final done = result.value!;
        expect(done.hasConflicts, isTrue);
        expect(done.uiMetaConflicts, ['hermes-bots']);
        expect(done.applied, {'description': true, 'ui_meta': false});
        expect(transport.calls.single.params, {
          'name': 'ops',
          'description': 'New',
          'ui_meta': {
            'hermes-bots': {'title': 'Ops'},
          },
          'ui_meta_expected_revisions': {'hermes-bots': 1},
        });
      },
    );

    test('configure with a guarded model asks first, then resends only the '
        'model with the confirm flag', () async {
      var guarded = true;
      transport.handlers['profiles.configure'] = (call) {
        if (call.params!['confirm_expensive_model'] == true) guarded = false;
        return guarded
            ? {
                'ok': true,
                'applied': {'description': true},
                'confirm_required': true,
                'confirm_message': 'This model costs a lot.',
              }
            : {
                'ok': true,
                'applied': {'model': true},
              };
      };
      final first = await client.configureProfile(
        'ops',
        description: 'New',
        model: 'big-model',
        provider: 'openai',
      );
      expect(first.needsConfirmation, isTrue);
      expect(first.confirmation!.message, 'This model costs a lot.');
      expect(first.confirmation!.partial!.applied, {'description': true});

      final second = await first.confirmation!.confirm();
      expect(second.needsConfirmation, isFalse);
      expect(second.value!.applied, {'model': true});
      expect(transport.calls, hasLength(2));
      expect(transport.calls.last.params, {
        'name': 'ops',
        'model': 'big-model',
        'provider': 'openai',
        'confirm_expensive_model': true,
      });
    });

    test('SOUL goes through the soul route', () async {
      transport.handlers['GET /api/profiles/ops/soul'] = (_) => {
        'content': 'Be brief.',
        'exists': true,
      };
      final soul = await client.profileSoul('ops');
      expect(soul.content, 'Be brief.');
      expect(soul.exists, isTrue);
      await client.setProfileSoul('ops', 'Be kind.');
      expect(transport.calls.last.route, 'PUT /api/profiles/ops/soul');
      expect(transport.calls.last.body, {'content': 'Be kind.'});
    });

    test('avatars use the asset methods, and a missing one is null', () async {
      transport.handlers['profiles.get_asset'] = (_) => {'found': false};
      expect(await client.profileAvatar('ops'), isNull);
      expect(transport.calls.last.params, {'name': 'ops', 'asset': 'avatar'});

      transport.handlers['profiles.get_asset'] = (_) => {
        'found': true,
        'data': 'data:image/png;base64,AAAA',
      };
      expect(await client.profileAvatar('ops'), 'data:image/png;base64,AAAA');

      await client.setProfileAvatar('ops', 'data:image/png;base64,AAAA');
      expect(transport.calls.last.params, {
        'name': 'ops',
        'asset': 'avatar',
        'data': 'data:image/png;base64,AAAA',
      });
      await client.clearProfileAvatar('ops');
      expect(transport.calls.last.params, {
        'name': 'ops',
        'asset': 'avatar',
        'clear': true,
      });
    });

    test(
      'delete uses the REST route and reports a pending settlement',
      () async {
        transport.handlers['DELETE /api/profiles/qa-gone'] = (_) => {
          'ok': true,
          'settlement_pending': true,
          'retry_command': 'hermes profile delete qa-gone',
        };
        final result = await client.deleteProfile('qa-gone');
        expect(result.settlementPending, isTrue);
        expect(result.retryCommand, 'hermes profile delete qa-gone');
      },
    );
  });

  group('memory', () {
    test('the graph is read through the existing wrapper', () async {
      transport.graph = {
        'nodes': [
          {
            'id': 'memory:memory:0',
            'label': 'Likes tea',
            'kind': 'memory',
            'memorySource': 'memory',
          },
          {'id': 'git-helper', 'label': 'git-helper', 'kind': 'skill'},
          {
            'id': 'memory:profile:1',
            'label': 'Lives in Leeds',
            'kind': 'memory',
            'memorySource': 'profile',
          },
        ],
        'memory': [
          {'source': 'memory', 'title': 'Likes tea', 'body': 'Likes tea.'},
          {'source': 'profile', 'title': 'Leeds', 'body': 'Lives in Leeds.'},
        ],
      };
      final graph = await client.learningGraph('ops');
      expect(transport.calls.single.name, 'learningGraph');
      expect(graph.memories.map((m) => m.preview), [
        'Likes tea.',
        'Lives in Leeds.',
      ]);
      expect(graph.nodes.where((n) => !n.isMemory).single.id, 'git-helper');
    });

    test(
      'profile is in the query for GET and in the body for PUT and DELETE',
      () async {
        transport.handlers['GET /api/learning/node'] = (_) => {
          'ok': true,
          'kind': 'memory',
          'id': 'memory:memory:0',
          'label': 'Likes tea',
          'content': 'Likes tea.',
        };
        final detail = await client.learningNode('ops', 'memory:memory:0');
        expect(detail.content, 'Likes tea.');
        expect(transport.calls.last.query, {
          'id': 'memory:memory:0',
          'profile': 'ops',
        });
        expect(transport.calls.last.body, isNull);

        await client.updateLearningNode(
          'ops',
          'memory:memory:0',
          'Likes coffee.',
        );
        expect(transport.calls.last.route, 'PUT /api/learning/node');
        expect(transport.calls.last.query, isNull);
        expect(transport.calls.last.body, {
          'id': 'memory:memory:0',
          'content': 'Likes coffee.',
          'profile': 'ops',
        });

        await client.deleteLearningNode('ops', 'memory:memory:0');
        expect(transport.calls.last.route, 'DELETE /api/learning/node');
        expect(transport.calls.last.body, {
          'id': 'memory:memory:0',
          'profile': 'ops',
        });
      },
    );
  });

  group('keys', () {
    test(
      'listing reads GET /api/env with the profile and never reveals',
      () async {
        transport.handlers['GET /api/env'] = (_) => {
          'OPENAI_API_KEY': {
            'is_set': true,
            'redacted_value': 'sk-...wxyz',
            'description': 'OpenAI',
            'category': 'provider',
            'is_password': true,
            'provider': 'openai',
            'provider_label': 'OpenAI',
          },
          'TELEGRAM_BOT_TOKEN': {
            'is_set': false,
            'channel_managed': true,
            'is_password': true,
          },
        };
        final keys = await client.listEnvKeys('ops');
        expect(keys.map((k) => k.name), [
          'OPENAI_API_KEY',
          'TELEGRAM_BOT_TOKEN',
        ]);
        expect(keys.first.redactedValue, 'sk-...wxyz');
        expect(keys.last.channelManaged, isTrue);
        expect(transport.calls.map((c) => c.route), ['GET /api/env']);
        expect(transport.calls.single.query, {'profile': 'ops'});
        expect(
          transport.calls.any((c) => (c.path ?? '').contains('reveal')),
          isFalse,
        );
      },
    );

    test('save, delete and validate use their routes', () async {
      await client.setEnvKey('ops', 'OPENAI_API_KEY', 'sk-live-abc');
      expect(transport.calls.last.route, 'PUT /api/env');
      expect(transport.calls.last.query, {'profile': 'ops'});
      expect(transport.calls.last.body, {
        'key': 'OPENAI_API_KEY',
        'value': 'sk-live-abc',
      });

      await client.deleteEnvKey('ops', 'OPENAI_API_KEY');
      expect(transport.calls.last.route, 'DELETE /api/env');
      expect(transport.calls.last.body, {'key': 'OPENAI_API_KEY'});

      transport.handlers['POST /api/providers/validate'] = (_) => {
        'ok': false,
        'reachable': true,
        'message': 'That API key was rejected.',
      };
      final verdict = await client.validateProviderKey(
        key: 'OPENAI_API_KEY',
        value: 'sk-live-abc',
      );
      expect(verdict.rejected, isTrue);
      expect(transport.calls.last.body, {
        'key': 'OPENAI_API_KEY',
        'value': 'sk-live-abc',
      });
    });
  });

  group('provider sign-in', () {
    test(
      'device-code flow uses start, poll and cancel with the profile',
      () async {
        transport.handlers['GET /api/providers/oauth'] = (_) => {
          'providers': [
            {
              'id': 'nous',
              'name': 'Nous Portal',
              'flow': 'device_code',
              'disconnectable': true,
              'status': {'logged_in': true},
            },
            {'id': 'anthropic', 'name': 'Anthropic', 'flow': 'external'},
          ],
        };
        final providers = await client.providerSignIns('ops');
        expect(providers.first.supportsDeviceCode, isTrue);
        expect(providers.first.loggedIn, isTrue);
        expect(providers.last.supportsDeviceCode, isFalse);

        transport.handlers['POST /api/providers/oauth/nous/start'] = (_) => {
          'session_id': 'sess-1',
          'flow': 'device_code',
          'user_code': 'ABCD-1234',
          'verification_url': 'https://portal.example/device',
          'expires_in': 600,
          'poll_interval': 3,
        };
        final started = await client.startProviderSignIn('ops', 'nous');
        expect(started.userCode, 'ABCD-1234');
        expect(started.pollInterval, const Duration(seconds: 3));
        expect(transport.calls.last.query, {'profile': 'ops'});

        transport.handlers['GET /api/providers/oauth/nous/poll/sess-1'] = (_) =>
            {
              'session_id': 'sess-1',
              'status': 'approved',
              'account_email': 'me@example.com',
            };
        final poll = await client.pollProviderSignIn('ops', 'nous', 'sess-1');
        expect(poll.state, HermesAdminSignInState.approved);
        expect(poll.accountEmail, 'me@example.com');

        await client.cancelProviderSignIn('ops', 'sess-1');
        expect(
          transport.calls.last.route,
          'DELETE /api/providers/oauth/sessions/sess-1',
        );
        await client.disconnectProvider('ops', 'nous');
        expect(transport.calls.last.route, 'DELETE /api/providers/oauth/nous');
      },
    );
  });

  group('models', () {
    test('options are read per profile', () async {
      transport.handlers['model.options'] = (_) => {
        'model': 'gpt-5',
        'provider': 'openai',
        'providers': [
          {
            'slug': 'openai',
            'name': 'OpenAI',
            'authenticated': true,
            'models': ['gpt-5', 'gpt-5-mini'],
          },
        ],
      };
      final options = await client.modelOptions('ops', explicitOnly: true);
      expect(options.model, 'gpt-5');
      expect(options.providers.single.models, ['gpt-5', 'gpt-5-mini']);
      expect(transport.calls.single.params, {
        'profile': 'ops',
        'explicit_only': true,
      });
    });

    test('a guarded model surfaces a confirmation, and confirming resends '
        'with the confirm flag', () async {
      transport.handlers['POST /api/model/set'] = (call) =>
          call.body!['confirm_expensive_model'] == true
          ? {'ok': true, 'scope': 'main'}
          : {
              'ok': false,
              'confirm_required': true,
              'confirm_message': 'This model is expensive.',
            };
      final first = await client.setModel(
        profile: 'ops',
        provider: 'openai',
        model: 'big-model',
      );
      expect(first.needsConfirmation, isTrue);
      expect(first.confirmation!.message, 'This model is expensive.');
      expect(transport.calls, hasLength(1));
      expect(transport.calls.single.body!['confirm_expensive_model'], false);
      expect(transport.calls.single.query, {'profile': 'ops'});

      final second = await first.confirmation!.confirm();
      expect(second.needsConfirmation, isFalse);
      expect(transport.calls, hasLength(2));
      expect(transport.calls.last.body, {
        'scope': 'main',
        'provider': 'openai',
        'model': 'big-model',
        'task': '',
        'base_url': '',
        'api_key': '',
        'confirm_expensive_model': true,
        'profile': 'ops',
      });
    });

    test('reasoning effort goes through the merging config route, not '
        'model/set', () async {
      await client.setReasoningEffort('ops', 'high');
      expect(transport.calls.single.route, 'PUT /api/config');
      expect(transport.calls.single.query, {'profile': 'ops'});
      expect(transport.calls.single.body, {
        'config': {
          'agent': {'reasoning_effort': 'high'},
        },
        'profile': 'ops',
      });
      await expectLater(
        client.setReasoningEffort('ops', 'HIGH!'),
        throwsArgumentError,
      );
    });

    test('fallbacks replace the chain and clear the legacy key', () async {
      await client.setFallbackProviders('ops', [
        (provider: 'openai', model: 'gpt-5-mini'),
      ]);
      expect(transport.calls.single.body!['config'], {
        'fallback_providers': [
          {'provider': 'openai', 'model': 'gpt-5-mini'},
        ],
        'fallback_model': null,
      });
    });
  });

  group('config', () {
    test('a null profile reads and writes the server root', () async {
      transport.handlers['GET /api/config/raw'] = (_) => {
        'yaml': 'model: gpt-5\n',
        'path': '/opt/data/config.yaml',
      };
      final raw = await client.rawConfig(null);
      expect(raw.yaml, 'model: gpt-5\n');
      expect(transport.calls.last.query, isEmpty);
      await client.saveRawConfig(null, 'model: gpt-5-mini\n');
      expect(transport.calls.last.route, 'PUT /api/config/raw');
      expect(transport.calls.last.body, {'yaml_text': 'model: gpt-5-mini\n'});

      await client.rawConfig('ops');
      expect(transport.calls.last.query, {'profile': 'ops'});
    });

    test('the raw config never prints its YAML', () {
      const raw = HermesAdminRawConfig(
        yaml: 'api_key: secret-value',
        path: '/p',
      );
      expect(raw.toString(), isNot(contains('secret-value')));
    });

    test('known root keys are the defaults plus the shipped extras', () async {
      transport.handlers['GET /api/config/defaults'] = (_) => {
        'model': '',
        'agent': {},
      };
      final roots = await client.knownConfigRootKeys();
      expect(roots, containsAll(['model', 'agent']));
      expect(roots, containsAll(['platform_toolsets', 'mcp_servers']));
    });

    test('the schema is read with the profile', () async {
      transport.handlers['GET /api/config/schema'] = (_) => {
        'fields': {
          'model': {'type': 'string'},
        },
        'category_order': ['general'],
      };
      final schema = await client.configSchema('ops');
      expect(schema.fields.keys, ['model']);
      expect(schema.categoryOrder, ['general']);
      expect(transport.calls.last.query, {'profile': 'ops'});
    });
  });

  group('tools and extensions', () {
    test('toolset changes use the REST per-profile route, not '
        'profiles.configure', () async {
      transport.handlers['GET /api/tools/toolsets'] = (_) => [
        {
          'name': 'web',
          'label': 'Web',
          'enabled': true,
          'configured': false,
          'platform': 'cli',
          'tools': ['search', 'extract'],
        },
      ];
      final toolsets = await client.toolsets('ops');
      expect(toolsets.single.configured, isFalse);
      expect(toolsets.single.toolCount, 2);

      await client.setToolsetEnabled('ops', 'web', false);
      expect(transport.calls.last.route, 'PUT /api/tools/toolsets/web');
      expect(transport.calls.last.query, {'profile': 'ops'});
      expect(transport.calls.last.body, {'enabled': false, 'profile': 'ops'});
      expect(
        transport.calls.where((c) => c.name == 'profiles.configure'),
        isEmpty,
      );
    });

    test(
      'skills are listed by the existing wrapper and toggled over REST',
      () async {
        transport.skillRows = [
          {
            'name': 'git',
            'description': 'Git helper',
            'enabled': false,
            'usage': 2,
            'provenance': 'hub',
          },
        ];
        final skills = await client.skills('ops');
        expect(skills.single.enabled, isFalse);
        expect(skills.single.provenance, 'hub');
        await client.setSkillEnabled('ops', 'git', true);
        expect(transport.calls.last.route, 'PUT /api/skills/toggle');
        expect(transport.calls.last.query, {'profile': 'ops'});
        expect(transport.calls.last.body, {
          'name': 'git',
          'enabled': true,
          'profile': 'ops',
        });
      },
    );

    test('MCP calls carry the profile; enable is the REST route', () async {
      transport.handlers['mcp.servers.list'] = (_) => {
        'servers': [
          {
            'name': 'github',
            'url': 'https://example.test/mcp',
            'enabled': true,
            'auth': 'oauth',
            'tools': ['issues'],
          },
        ],
      };
      final servers = await client.mcpServers('ops');
      expect(servers.single.auth, 'oauth');
      expect(transport.calls.last.params, {'profile': 'ops'});

      transport.handlers['mcp.catalog'] = (_) => {
        'servers': [
          {
            'name': 'slack',
            'installed': false,
            'requires': ['SLACK_BOT_TOKEN'],
          },
        ],
      };
      final catalog = await client.mcpCatalog('ops');
      expect(catalog.single.requires, ['SLACK_BOT_TOKEN']);

      await client.addMcpServer(
        'ops',
        name: 'mine',
        url: 'https://example.test/mcp',
        bearerToken: 'tok-123456',
      );
      expect(transport.calls.last.route, 'mcp.servers.add');
      expect(transport.calls.last.params, {
        'profile': 'ops',
        'name': 'mine',
        'config': {'url': 'https://example.test/mcp'},
        'bearer_token': 'tok-123456',
      });

      transport.handlers['mcp.servers.test'] = (_) => {
        'ok': true,
        'tools': [
          {'name': 'issues'},
        ],
      };
      final test = await client.testMcpServer('ops', 'github');
      expect(test.ok, isTrue);
      expect(test.toolNames, ['issues']);

      await client.setMcpApiKey('ops', 'github', 'key-123456');
      expect(transport.calls.last.params, {
        'profile': 'ops',
        'name': 'github',
        'value': 'key-123456',
      });
      await client.removeMcpServer('ops', 'github');
      expect(transport.calls.last.route, 'mcp.servers.remove');

      await client.setMcpServerEnabled('ops', 'github', false);
      expect(transport.calls.last.route, 'PUT /api/mcp/servers/github/enabled');
      expect(transport.calls.last.query, {'profile': 'ops'});
      expect(transport.calls.last.body, {'enabled': false, 'profile': 'ops'});
    });

    test('MCP sign-in starts and polls through the gateway', () async {
      transport.handlers['mcp.servers.oauth.start'] = (_) => {
        'ok': true,
        'session_id': 'flow-1',
        'auth_url': 'https://auth.example/authorize',
      };
      final started = await client.startMcpOAuth('ops', 'github');
      expect(started.authUrl, 'https://auth.example/authorize');
      transport.handlers['mcp.servers.oauth.poll'] = (_) => {
        'ok': true,
        'status': 'pending',
      };
      final poll = await client.pollMcpOAuth('ops', 'github', 'flow-1');
      expect(poll.state, HermesAdminSignInState.pending);
      expect(transport.calls.last.params, {
        'profile': 'ops',
        'name': 'github',
        'session_id': 'flow-1',
      });
    });

    test(
      'reload.mcp asks for confirmation, and confirming resends confirm:true',
      () async {
        transport.handlers['reload.mcp'] = (call) =>
            call.params!['confirm'] == true
            ? {'status': 'reloaded'}
            : {
                'status': 'confirm_required',
                'message': 'Reloading clears the prompt cache.',
              };
        final first = await client.reloadMcp();
        expect(first.needsConfirmation, isTrue);
        expect(
          first.confirmation!.message,
          'Reloading clears the prompt cache.',
        );
        expect(transport.calls.single.params, {'confirm': false});

        final second = await first.confirmation!.confirm();
        expect(second.needsConfirmation, isFalse);
        expect(transport.calls.last.params, {'confirm': true});

        // After the owner's own Save the caller skips the question.
        transport.calls.clear();
        final direct = await client.reloadMcp(confirm: true);
        expect(direct.needsConfirmation, isFalse);
        expect(transport.calls.single.params, {'confirm': true});
      },
    );

    test('plugins list and toggle per profile', () async {
      transport.handlers['plugins.manage'] = (call) =>
          call.params!['action'] == 'list'
          ? {
              'plugins': [
                {
                  'key': 'browser/steel',
                  'name': 'browser-steel',
                  'status': 'enabled',
                  'source': 'user',
                },
              ],
            }
          : {'ok': true};
      final plugins = await client.plugins('ops');
      expect(plugins.single.enabled, isTrue);
      expect(plugins.single.key, 'browser/steel');
      await client.setPluginEnabled('ops', 'browser/steel', false);
      expect(transport.calls.last.params, {
        'action': 'toggle',
        'key': 'browser/steel',
        'enable': false,
        'profile': 'ops',
      });
    });
  });

  group('routines and gateway', () {
    test('cron always names the bot', () async {
      transport.jobs = [
        {'id': 'job-1', 'prompt': 'Say hi', 'schedule': '0 9 * * *'},
      ];
      final jobs = await client.cronJobs('ops');
      expect(jobs.single.id, 'job-1');
      await client.pauseCronJob('ops', 'job-1');
      await client.resumeCronJob('ops', 'job-1');
      await client.runCronJob('ops', 'job-1');
      await client.updateCronJob('ops', 'job-1', enabled: false);
      await client.cronRuns('ops', 'job-1');
      expect(
        transport.callsOf('cron').map((c) => c.params!['profile']).toSet(),
        {'ops'},
      );
      expect(transport.callsOf('cron').map((c) => c.name), [
        'list',
        'pause',
        'resume',
        'run',
        'update',
        'runs',
      ]);
    });

    test('a gateway restart needs the owner to confirm first', () async {
      await expectLater(
        client.restartGateway(ownerConfirmed: false),
        throwsStateError,
      );
      expect(transport.calls, isEmpty);
      await client.restartGateway(ownerConfirmed: true);
      expect(transport.calls.single.route, 'POST /api/gateway/restart');
    });
  });

  group('error mapping', () {
    Future<Object?> failing(Object error) async {
      transport.handlers['GET /api/env'] = (_) => throw error;
      try {
        await client.listEnvKeys('ops');
      } catch (caught) {
        return caught;
      }
      return null;
    }

    test('an unknown RPC method is "unavailable"', () async {
      transport.handlers['profiles.list'] = (_) =>
          throw _rpcError(-32601, 'unknown method: profiles.list — upgrade');
      await expectLater(
        client.listProfiles(),
        throwsA(isA<HermesAdminUnavailable>()),
      );
    });

    test(
      'RPC 4064 is "not found"; other coded errors are rejections',
      () async {
        transport.handlers['profiles.describe'] = (_) =>
            throw _rpcError(4064, "profile 'ghost' not found");
        await expectLater(
          client.describeProfile('ghost'),
          throwsA(
            isA<HermesAdminNotFound>().having(
              (e) => e.message,
              'message',
              "profile 'ghost' not found",
            ),
          ),
        );
        transport.handlers['profiles.create'] = (_) =>
            throw _rpcError(4062, 'profile already exists');
        await expectLater(
          client.createProfile(const HermesAdminProfileDraft(name: 'qa-dup')),
          throwsA(
            isA<HermesAdminRejected>().having((e) => e.code, 'code', 4062),
          ),
        );
      },
    );

    test('a transport failure with no code is rethrown untouched', () async {
      transport.handlers['profiles.list'] = (_) =>
          throw const HermesDesktopRpcException(
            'Hermes gateway is not connected.',
          );
      await expectLater(
        client.listProfiles(),
        throwsA(isA<HermesDesktopRpcException>()),
      );
    });

    test('REST 404 "No such API endpoint" is unavailable', () async {
      expect(
        await failing(_http(404, {'detail': 'No such API endpoint: /api/env'})),
        isA<HermesAdminUnavailable>(),
      );
    });

    test('a bare FastAPI Not Found is unavailable too', () async {
      expect(
        await failing(_http(404, {'detail': 'Not Found'})),
        isA<HermesAdminUnavailable>(),
      );
    });

    test('a headless-serve 404 with an error body is unavailable', () async {
      expect(
        await failing(
          _http(404, {'error': 'Headless backend serves no dashboard API.'}),
        ),
        isA<HermesAdminUnavailable>(),
      );
    });

    test('405 Method Not Allowed is unavailable (the SPA catch-all)', () async {
      expect(
        await failing(_http(405, {'detail': 'Method Not Allowed'})),
        isA<HermesAdminUnavailable>(),
      );
    });

    test('a 404 for a missing profile is not found', () async {
      final caught = await failing(
        _http(404, {'detail': "Profile 'ghost' does not exist."}),
      );
      expect(caught, isA<HermesAdminNotFound>());
      expect(
        (caught! as HermesAdminNotFound).message,
        "Profile 'ghost' does not exist.",
      );
    });

    test(
      'learning-node and env-key 404s are not found, even in lower case',
      () async {
        expect(
          await failing(_http(404, {'detail': 'not found'})),
          isA<HermesAdminNotFound>(),
        );
        expect(
          await failing(_http(404, {'detail': "skill 'x' not found"})),
          isA<HermesAdminNotFound>(),
        );
        expect(
          await failing(
            _http(404, {'detail': 'OPENAI_API_KEY not found in .env'}),
          ),
          isA<HermesAdminNotFound>(),
        );
      },
    );

    test('400, 409 and 422 are rejections with Hermes\' reason', () async {
      final bad = await failing(
        _http(400, {'detail': 'Invalid profile name.'}),
      );
      expect(bad, isA<HermesAdminRejected>());
      final rejected = bad! as HermesAdminRejected;
      expect(rejected.code, 400);
      expect(rejected.message, 'Invalid profile name.');

      final conflict = await failing(
        _http(409, {'detail': 'Server is provided by a plugin.'}),
      );
      expect((conflict! as HermesAdminRejected).code, 409);

      final invalid = await failing(
        _http(422, {
          'detail': [
            {
              'loc': ['body', 'key'],
              'msg': 'Field required',
              'type': 'missing',
            },
          ],
        }),
      );
      expect((invalid! as HermesAdminRejected).message, 'Field required');
    });

    test('a 401 is left for the sign-in handling, not wrapped', () async {
      final caught = await failing(_http(401, {'detail': 'Unauthorized'}));
      expect(caught, isA<DioException>());
    });

    test('a cookie-bridge failure maps by status alone', () async {
      expect(
        await failing(StateError('Hermes dashboard request failed (405).')),
        isA<HermesAdminUnavailable>(),
      );
      expect(
        await failing(StateError('Hermes dashboard request failed (400).')),
        isA<HermesAdminRejected>(),
      );
      expect(
        await failing(StateError('Hermes dashboard sign-in expired.')),
        isA<StateError>(),
      );
    });

    test(
      'ifAvailable turns "unavailable" into null and keeps other errors',
      () async {
        transport.handlers['profiles.list'] = (_) =>
            throw _rpcError(-32601, 'unknown method');
        expect(
          await HermesAdminClient.ifAvailable(client.listProfiles),
          isNull,
        );
        transport.handlers['profiles.list'] = (_) =>
            throw _rpcError(4062, 'nope');
        await expectLater(
          HermesAdminClient.ifAvailable(client.listProfiles),
          throwsA(isA<HermesAdminRejected>()),
        );
      },
    );
  });

  group('secrets', () {
    late List<String> logged;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      logged = [];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logged.add(message);
      };
    });

    tearDown(() => debugPrint = originalDebugPrint);

    const typedKey = 'sk-proj-ABCDEFGHIJKLMNOP1234';

    test(
      'a failed key save logs the route and error type, never the value',
      () async {
        transport.handlers['PUT /api/env'] = (_) => throw _http(400, {
          'detail': 'Rejected value $typedKey for OPENAI_API_KEY.',
        });
        Object? caught;
        try {
          await client.setEnvKey('ops', 'OPENAI_API_KEY', typedKey);
        } catch (error) {
          caught = error;
        }
        expect(caught, isA<HermesAdminRejected>());
        final rejected = caught! as HermesAdminRejected;
        expect(rejected.message, isNot(contains(typedKey)));
        expect(rejected.toString(), isNot(contains(typedKey)));

        expect(logged, isNotEmpty);
        final log = logged.join('\n');
        expect(log, contains('PUT /api/env'));
        expect(log, contains('HermesAdminRejected'));
        expect(log, isNot(contains(typedKey)));
        expect(log, isNot(contains('ABCDEFGH')));
      },
    );

    test(
      'a transport error that echoes the key is logged by type only',
      () async {
        transport.handlers['PUT /api/env'] = (_) =>
            throw StateError('request body was {"value": "$typedKey"}');
        await expectLater(
          client.setEnvKey('ops', 'OPENAI_API_KEY', typedKey),
          throwsStateError,
        );
        expect(logged.join('\n'), isNot(contains(typedKey)));
        expect(logged.join('\n'), contains('StateError'));
      },
    );

    test('an MCP key and a bearer token never reach the log', () async {
      transport.handlers['mcp.servers.set_api_key'] = (_) =>
          throw _rpcError(4001, 'bad credential $typedKey');
      Object? caught;
      try {
        await client.setMcpApiKey('ops', 'github', typedKey);
      } catch (error) {
        caught = error;
      }
      expect(
        (caught! as HermesAdminRejected).message,
        isNot(contains(typedKey)),
      );
      expect(logged.join('\n'), isNot(contains(typedKey)));
    });

    test('Invalid YAML text that quotes the file is scrubbed', () async {
      const yaml = 'model:\n  api_key: "hunter2-hunter2"\n  bad: [\n';
      transport.handlers['PUT /api/config/raw'] = (_) => throw _http(400, {
        'detail':
            'Invalid YAML: while parsing a flow sequence\n'
            '  api_key: "hunter2-hunter2"\n',
      });
      Object? caught;
      try {
        await client.saveRawConfig('ops', yaml);
      } catch (error) {
        caught = error;
      }
      expect(caught, isA<HermesAdminRejected>());
      expect(
        (caught! as HermesAdminRejected).message,
        isNot(contains('hunter2')),
      );
      expect(logged.join('\n'), isNot(contains('hunter2')));
    });

    test('a merged config value is scrubbed from the rejection', () async {
      transport.handlers['PUT /api/config'] = (_) =>
          throw _http(400, {'detail': 'bad value hunter2-hunter2 in model'});
      Object? caught;
      try {
        await client.mergeConfig('ops', {
          'model': {'api_key': 'hunter2-hunter2'},
        });
      } catch (error) {
        caught = error;
      }
      expect(
        (caught! as HermesAdminRejected).message,
        isNot(contains('hunter2')),
      );
    });

    test('a confirmation message that quotes the key is scrubbed', () async {
      transport.handlers['POST /api/model/set'] = (_) => {
        'ok': false,
        'confirm_required': true,
        'confirm_message': 'Using key $typedKey costs a lot.',
      };
      final result = await client.setModel(
        profile: 'ops',
        provider: 'custom',
        model: 'm',
        apiKey: typedKey,
      );
      expect(result.confirmation!.message, isNot(contains(typedKey)));
    });
  });
}
