import 'dart:async';
import 'dart:convert';

import 'package:conduit/features/hermes/admin/hermes_admin_client.dart';
import 'package:conduit/features/hermes/admin/hermes_admin_providers.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_transport.dart';
import 'package:conduit/features/hermes/settings/pages/hermes_models_providers_page.dart';
import 'package:conduit/features/hermes/settings/widgets/hermes_secret_field.dart';
import 'package:conduit/features/hermes/sheets/hermez_modal_sheet.dart';
import 'package:conduit/features/hermes/widgets/hermez_segments.dart';
import 'package:conduit/features/hermes/widgets/hermez_skeleton.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// A fake Hermes admin connection
// ---------------------------------------------------------------------------

/// One call the page made through the transport.
final class _Call {
  _Call(this.kind, this.name, {this.path, this.query, this.body, this.params});

  final String kind;
  final String name;
  final String? path;
  final Map<String, dynamic>? query;
  final Map<String, Object?>? body;
  final Map<String, dynamic>? params;

  /// `GET /api/env` for REST, the method for RPC.
  String get route => kind == 'rest' ? '$name $path' : name;

  @override
  String toString() => '$route $query $body $params';
}

typedef _Handler = FutureOr<Object?> Function(_Call call);

Map<String, Object?> _envRow(
  String provider,
  String label, {
  bool set = false,
  String? preview,
  bool password = true,
  String category = 'provider',
  bool channel = false,
}) => {
  'is_set': set,
  'redacted_value': preview,
  'description': '$label key',
  'category': category,
  'is_password': password,
  'provider': provider,
  'provider_label': label,
  'channel_managed': channel,
};

/// A Hermes with three bots (ops, alpha, beta), a model catalog, a config,
/// each bot's own `.env`, and two sign-in providers.
final class _Fake implements HermesAdminTransport {
  final calls = <_Call>[];

  /// Keyed by RPC method or `VERB /path`; wins over the defaults below.
  final overrides = <String, _Handler>{};

  List<String> profiles = ['ops', 'alpha', 'beta'];

  String model = 'gpt-5';
  String provider = 'openai';
  Map<String, dynamic> config = {
    'agent': {'reasoning_effort': 'medium'},
    'fallback_providers': <Object?>[],
  };

  /// The bots' `.env` rows, by profile.
  final Map<String, Map<String, Map<String, Object?>>> env = {};

  bool nousSignedIn = false;
  String? nousSession;

  Map<String, Map<String, Object?>> envOf(String profile) =>
      env.putIfAbsent(profile, () {
        return {
          'OPENAI_API_KEY': _envRow(
            'openai',
            'OpenAI',
            set: true,
            preview: 'sk-...wxyz',
          ),
          'ANTHROPIC_API_KEY': _envRow('anthropic', 'Anthropic'),
          'OPENAI_BASE_URL': _envRow('openai', 'OpenAI', password: false),
          'TELEGRAM_BOT_TOKEN': _envRow(
            '',
            '',
            category: 'messaging',
            channel: true,
          ),
        };
      });

  Iterable<_Call> where(String route) => calls.where((c) => c.route == route);

  /// Every `PUT /api/env`, as `profile:KEY`.
  List<String> get keyWrites => [
    for (final call in where('PUT /api/env'))
      '${call.query?['profile']}:${call.body?['key']}',
  ];

  /// The `fallback_providers` of each `PUT /api/config`, in order.
  List<Object?> get fallbackWrites => [
    for (final call in where('PUT /api/config'))
      if ((call.body?['config'] as Map?)?.containsKey('fallback_providers') ??
          false)
        (call.body!['config']! as Map)['fallback_providers'],
  ];

  Future<Object?> _answer(_Call call) async {
    calls.add(call);
    final handler = overrides[call.route];
    if (handler != null) return handler(call);
    return _default(call);
  }

  Object? _default(_Call call) {
    final profile = call.query?['profile'] as String? ?? '';
    switch (call.route) {
      case 'profiles.list':
        return {
          'profiles': [
            for (final name in profiles) {'name': name},
          ],
        };
      case 'model.options':
        return {
          'model': model,
          'provider': provider,
          'providers': [
            {
              'slug': 'openai',
              'name': 'OpenAI',
              'authenticated': true,
              'models': ['gpt-5', 'gpt-5-pro'],
            },
            {
              'slug': 'anthropic',
              'name': 'Anthropic',
              'authenticated': true,
              'models': ['claude-opus', 'claude-sonnet'],
            },
            {
              'slug': 'google',
              'name': 'Google',
              'authenticated': false,
              'models': ['gemini-pro'],
            },
          ],
        };
      case 'POST /api/model/set':
        model = call.body!['model']! as String;
        provider = call.body!['provider']! as String;
        return {'ok': true};
      case 'GET /api/config':
        return config;
      case 'PUT /api/config':
        final patch = Map<String, dynamic>.from(call.body!['config']! as Map);
        for (final entry in patch.entries) {
          final current = config[entry.key];
          if (current is Map && entry.value is Map) {
            config[entry.key] = {...current, ...entry.value as Map};
          } else {
            config[entry.key] = entry.value;
          }
        }
        return {'ok': true};
      case 'GET /api/env':
        return envOf(profile);
      case 'PUT /api/env':
        final value = call.body!['value']! as String;
        envOf(profile)[call.body!['key']! as String] = _envRow(
          'x',
          'x',
          set: true,
          preview: 'sk-...${value.substring(value.length - 4)}',
        );
        return {'ok': true};
      case 'DELETE /api/env':
        final row = envOf(profile)[call.body!['key']! as String];
        if (row != null) {
          row['is_set'] = false;
          row['redacted_value'] = null;
        }
        return {'ok': true};
      case 'POST /api/providers/validate':
        return {'ok': true, 'reachable': true, 'message': ''};
      case 'GET /api/providers/oauth':
        return {
          'providers': [
            {
              'id': 'nous',
              'name': 'Nous Portal',
              'flow': 'device_code',
              'disconnectable': true,
              'status': {'logged_in': nousSignedIn},
            },
            {
              'id': 'anthropic',
              'name': 'Anthropic',
              'flow': 'external',
              'cli_command': 'hermes login anthropic',
              'status': {'logged_in': false},
            },
          ],
        };
      case 'POST /api/providers/oauth/nous/start':
        nousSession = 'sess-1';
        return {
          'session_id': 'sess-1',
          'user_code': 'ABCD-EFGH',
          'verification_url': 'https://portal.example/device',
          'expires_in': 600,
          'poll_interval': 1,
        };
      case 'GET /api/providers/oauth/nous/poll/sess-1':
        nousSignedIn = true;
        return {'status': 'approved'};
      case 'DELETE /api/providers/oauth/nous':
        nousSignedIn = false;
        return {'ok': true};
      case 'DELETE /api/providers/oauth/sessions/sess-1':
        return {'ok': true};
    }
    throw UnimplementedError(call.route);
  }

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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

DioException _http(int status, Object body) {
  final options = RequestOptions(path: '/api/x');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<List<int>>(
      requestOptions: options,
      statusCode: status,
      data: utf8.encode(jsonEncode(body)),
    ),
  );
}

DioException _offline() => DioException(
  requestOptions: RequestOptions(path: '/api/x'),
  type: DioExceptionType.connectionError,
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<_Fake> _pump(
  WidgetTester tester, {
  void Function(_Fake fake)? prepare,
  bool settle = true,
  bool noClient = false,
  String scope = 'ops',
}) async {
  final fake = _Fake();
  prepare?.call(fake);
  tester.view
    ..physicalSize = const Size(900, 4200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hermesAdminClientProvider.overrideWithValue(
          noClient ? null : HermesAdminClient(fake),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: HermesModelsProvidersPage(scope: scope, botTitle: 'Ops bot'),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return fake;
}

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder matching) =>
    find.descendant(of: _key(key), matching: matching);

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

/// The text field inside the key form.
Finder get _keyInput => _in('key-field', find.byType(TextField));

Future<void> _typeKey(WidgetTester tester, String value) async {
  await tester.enterText(_keyInput, value);
  await tester.pump();
}

/// Everything typed into any editable field on screen.
List<String> _allFieldText(WidgetTester tester) => [
  for (final editable in tester.widgetList<EditableText>(
    find.byType(EditableText),
  ))
    editable.controller.text,
];

/// All the text drawn by [Text] widgets (not the input fields).
String _shownText(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
].join('\n');

Future<void> _pickModel(WidgetTester tester, String slugAndModel) async {
  await tester.tap(_key('model-$slugAndModel'));
  await tester.pumpAndSettle();
}

String _modelShown(WidgetTester tester) =>
    tester.widget<Text>(_key('model-current')).data!;

void main() {
  group('loading, errors and unavailable parts', () {
    testWidgets('shows a skeleton while a read is in flight', (tester) async {
      final gate = Completer<void>();
      final fake = await _pump(
        tester,
        settle: false,
        prepare: (f) => f.overrides['model.options'] = (_) async {
          await gate.future;
          return {'model': 'gpt-5', 'provider': 'openai', 'providers': []};
        },
      );
      await tester.pump();
      expect(_key('model-loading'), findsOneWidget);
      expect(tester.widget(_key('model-loading')), isA<HermezSkeleton>());
      // The other parts load on their own.
      await tester.pumpAndSettle();
      expect(_key('model-loading'), findsOneWidget);
      expect(_key('keys-loading'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(_key('model-loading'), findsNothing);
      expect(_key('model-current'), findsOneWidget);
      expect(fake.where('model.options'), hasLength(1));
    });

    testWidgets('a failed read shows the error inline, and Retry reloads', (
      tester,
    ) async {
      var fail = true;
      final fake = await _pump(
        tester,
        prepare: (f) => f.overrides['model.options'] = (call) {
          if (fail) throw _http(500, {'detail': 'The model catalog is down.'});
          return f._default(call);
        },
      );
      expect(_key('model-error'), findsOneWidget);
      expect(find.text('The model catalog is down.'), findsOneWidget);
      // The rest of the page still works.
      expect(_key('keys-error'), findsNothing);
      expect(_key('key-card-OPENAI_API_KEY'), findsOneWidget);

      fail = false;
      await _tapKey(tester, 'model-retry');
      expect(_key('model-error'), findsNothing);
      expect(_modelShown(tester), 'gpt-5');
      expect(fake.where('model.options'), hasLength(2));
    });

    testWidgets('an unavailable part is disabled, with its reason', (
      tester,
    ) async {
      await _pump(
        tester,
        prepare: (f) {
          f.overrides['model.options'] = (_) => throw HermesDesktopRpcException(
            'unknown method: model.options',
            code: -32601,
          );
          f.overrides['GET /api/config'] = (_) =>
              throw _http(404, {'detail': 'No such API endpoint: /api/config'});
          f.overrides['GET /api/providers/oauth'] = (_) =>
              throw _http(405, {'detail': 'Method Not Allowed'});
        },
      );
      for (final id in ['model', 'reasoning', 'fallbacks', 'signins']) {
        expect(_key('$id-unavailable'), findsOneWidget, reason: id);
      }
      expect(find.text('Not available on this Hermes server.'), findsWidgets);
      final change = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Change model'),
      );
      expect(change.onPressed, isNull);
      final add = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Add fallback'),
      );
      expect(add.onPressed, isNull);
      // Keys still work.
      expect(_key('key-card-OPENAI_API_KEY'), findsOneWidget);
    });

    testWidgets('without a Desktop Gateway every part says why', (
      tester,
    ) async {
      await _pump(tester, noClient: true);
      for (final id in ['model', 'reasoning', 'fallbacks', 'keys', 'signins']) {
        expect(_key('$id-unavailable'), findsOneWidget, reason: id);
      }
      expect(
        find.text(
          'Models and providers need a connection to a Hermes Desktop Gateway.',
        ),
        findsWidgets,
      );
    });

    testWidgets('a new bot scope reloads every part for that bot', (
      tester,
    ) async {
      final fake = _Fake();
      final scope = ValueNotifier('ops');
      addTearDown(scope.dispose);
      tester.view
        ..physicalSize = const Size(900, 4200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermesAdminClientProvider.overrideWithValue(
              HermesAdminClient(fake),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<String>(
                valueListenable: scope,
                builder: (_, name, _) => HermesModelsProvidersPage(scope: name),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      scope.value = 'alpha';
      await tester.pumpAndSettle();
      expect(fake.where('model.options').map((c) => c.params?['profile']), [
        'ops',
        'alpha',
      ]);
      expect(fake.where('GET /api/env').map((c) => c.query?['profile']), [
        'ops',
        'alpha',
      ]);
    });
  });

  group('default model', () {
    testWidgets('a guarded model asks first, and confirming saves it', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        prepare: (f) => f.overrides['POST /api/model/set'] = (call) {
          if (call.body!['confirm_expensive_model'] != true) {
            return {
              'confirm_required': true,
              'confirm_message': 'GPT-5 Pro costs about 10x more per chat.',
            };
          }
          return f._default(call);
        },
      );
      expect(_modelShown(tester), 'gpt-5');

      await _tapKey(tester, 'model-change');
      await _pickModel(tester, 'openai/gpt-5-pro');

      // Nothing is saved until the owner agrees.
      expect(fake.model, 'gpt-5');
      expect(find.byType(HermezModalSheet), findsOneWidget);
      expect(
        tester.widget<Text>(_key('confirm-message')).data,
        'GPT-5 Pro costs about 10x more per chat.',
      );
      expect(fake.where('POST /api/model/set'), hasLength(1));

      await _tapKey(tester, 'confirm-ok');
      final sets = fake.where('POST /api/model/set').toList();
      expect(sets, hasLength(2));
      expect(sets.last.body, containsPair('confirm_expensive_model', true));
      expect(sets.last.body, containsPair('model', 'gpt-5-pro'));
      expect(sets.last.query, {'profile': 'ops'});
      expect(_modelShown(tester), 'gpt-5-pro');
      expect(_key('model-note'), findsOneWidget);
    });

    testWidgets('declining the confirmation leaves the model alone', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        prepare: (f) => f.overrides['POST /api/model/set'] = (_) => {
          'confirm_required': true,
          'confirm_message': 'Expensive.',
        },
      );
      await _tapKey(tester, 'model-change');
      await _pickModel(tester, 'openai/gpt-5-pro');
      await _tapKey(tester, 'confirm-cancel');
      expect(fake.where('POST /api/model/set'), hasLength(1));
      expect(_modelShown(tester), 'gpt-5');
      expect(find.text('The default model was not changed.'), findsOneWidget);
    });

    testWidgets('an ordinary model saves straight away for this bot', (
      tester,
    ) async {
      final fake = await _pump(tester);
      await _tapKey(tester, 'model-change');
      // Only providers that are signed in are offered.
      expect(_key('model-google/gemini-pro'), findsNothing);
      await _pickModel(tester, 'anthropic/claude-sonnet');
      expect(find.byType(HermezModalSheet), findsNothing);
      final set = fake.where('POST /api/model/set').single;
      expect(set.body, containsPair('provider', 'anthropic'));
      expect(set.body, containsPair('model', 'claude-sonnet'));
      expect(set.body, containsPair('scope', 'main'));
      expect(set.query, {'profile': 'ops'});
      expect(_modelShown(tester), 'claude-sonnet');
    });
  });

  group('fallbacks', () {
    testWidgets(
      'adding, moving and removing write the merged config in order',
      (tester) async {
        final fake = await _pump(tester);
        expect(_key('fallbacks-empty'), findsOneWidget);

        await _tapKey(tester, 'fallback-add');
        await _pickModel(tester, 'openai/gpt-5');
        await _tapKey(tester, 'fallback-add');
        await _pickModel(tester, 'anthropic/claude-sonnet');
        expect(_key('fallback-row-1'), findsOneWidget);

        await _tapKey(tester, 'fallback-up-1');
        await _tapKey(tester, 'fallback-remove-0');

        const openai = {'provider': 'openai', 'model': 'gpt-5'};
        const sonnet = {'provider': 'anthropic', 'model': 'claude-sonnet'};
        expect(fake.fallbackWrites, [
          [openai],
          [openai, sonnet],
          [sonnet, openai],
          [openai],
        ]);
        // The legacy single-entry key is cleared in the same merge, and the
        // writes are for this bot.
        final first = fake.where('PUT /api/config').first;
        expect((first.body!['config']! as Map)['fallback_model'], isNull);
        expect(first.body, containsPair('profile', 'ops'));
        expect(_key('fallback-row-1'), findsNothing);
        expect(fake.model, 'gpt-5');
      },
    );

    testWidgets('a failed save puts the list back and says so', (tester) async {
      final fake = await _pump(tester);
      fake.overrides['PUT /api/config'] = (_) =>
          throw _http(500, {'detail': 'disk full'});
      await _tapKey(tester, 'fallback-add');
      await _pickModel(tester, 'openai/gpt-5');
      expect(_key('fallback-row-0'), findsNothing);
      expect(find.text('disk full'), findsOneWidget);
    });

    testWidgets('lists the fallbacks Hermes already has', (tester) async {
      await _pump(
        tester,
        prepare: (f) => f.config = {
          'agent': {'reasoning_effort': ''},
          'fallback_providers': [
            {'provider': 'anthropic', 'model': 'claude-opus'},
          ],
        },
      );
      expect(_in('fallback-row-0', find.text('claude-opus')), findsOneWidget);
      expect(_in('fallback-row-0', find.text('Anthropic')), findsOneWidget);
      expect(
        tester.widget<IconButton>(_key('fallback-up-0')).onPressed,
        isNull,
      );
    });
  });

  group('reasoning', () {
    testWidgets('changing the effort saves the bot default through config', (
      tester,
    ) async {
      final fake = await _pump(tester);
      expect(
        tester.widget<HermezSegments>(_key('reasoning-segments')).index,
        2,
      );
      await tester.tap(_in('reasoning-segments', find.text('High')).first);
      await tester.pumpAndSettle();
      final put = fake.where('PUT /api/config').single;
      expect(put.body, {
        'config': {
          'agent': {'reasoning_effort': 'high'},
        },
        'profile': 'ops',
      });
      // `model/set` only reaches auxiliary slots on 0.21.5.
      expect(fake.where('POST /api/model/set'), isEmpty);
      expect(
        tester.widget<HermezSegments>(_key('reasoning-segments')).index,
        3,
      );
      expect(
        find.text('Reasoning set to High. New chats use it.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed save returns the control to where it was', (
      tester,
    ) async {
      await _pump(
        tester,
        prepare: (f) =>
            f.overrides['PUT /api/config'] = (_) =>
                throw _http(500, {'detail': 'not now'}),
      );
      await tester.tap(_in('reasoning-segments', find.text('Max')).first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<HermezSegments>(_key('reasoning-segments')).index,
        2,
      );
      expect(find.text('not now'), findsOneWidget);
    });

    testWidgets('a level the control does not list is still shown', (
      tester,
    ) async {
      await _pump(
        tester,
        prepare: (f) => f.config = {
          'agent': {'reasoning_effort': 'xhigh'},
          'fallback_providers': <Object?>[],
        },
      );
      final segments = tester.widget<HermezSegments>(
        _key('reasoning-segments'),
      );
      expect(segments.labels, contains('Extra high'));
      expect(segments.labels[segments.index], 'Extra high');
    });
  });

  group('provider keys', () {
    testWidgets('AE6: a saved key shows masked with only Replace and Remove', (
      tester,
    ) async {
      final fake = await _pump(tester);
      expect(find.text('sk-...wxyz'), findsOneWidget);
      final card = _key('key-card-OPENAI_API_KEY');
      expect(
        find.descendant(of: card, matching: find.byType(TextField)),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.byType(TextButton)),
        findsNWidgets(2),
      );
      expect(_key('key-replace-OPENAI_API_KEY'), findsOneWidget);
      expect(_key('key-remove-OPENAI_API_KEY'), findsOneWidget);
      // No value field anywhere until Replace or Add is used.
      expect(find.byType(EditableText), findsNothing);
      // Only provider keys appear; a channel token or base URL does not.
      expect(find.textContaining('TELEGRAM'), findsNothing);
      expect(find.textContaining('OPENAI_BASE_URL'), findsNothing);
      expect(find.textContaining('reveal'), findsNothing);
      expect(fake.calls.any((c) => c.route.contains('reveal')), isFalse);
    });

    testWidgets('replacing a key tests it, saves it, and clears the input', (
      tester,
    ) async {
      final fake = await _pump(tester);
      await _tapKey(tester, 'key-replace-OPENAI_API_KEY');
      expect(_key('key-replace-OPENAI_API_KEY'), findsNothing);
      await _typeKey(tester, 'sk-new-secret-value-9876');
      await _tapKey(tester, 'key-save');

      final test = fake.where('POST /api/providers/validate').single;
      expect(test.body, containsPair('key', 'OPENAI_API_KEY'));
      expect(fake.keyWrites, ['ops:OPENAI_API_KEY']);
      expect(fake.where('PUT /api/env').single.body, {
        'key': 'OPENAI_API_KEY',
        'value': 'sk-new-secret-value-9876',
      });
      // Back to the masked card; the input is gone and holds nothing.
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('sk-...9876'), findsOneWidget);
      expect(find.textContaining('sk-new-secret'), findsNothing);
      expect(find.text('Saved OpenAI.'), findsOneWidget);

      await _tapKey(tester, 'key-replace-OPENAI_API_KEY');
      expect(_allFieldText(tester), ['']);
      expect(find.textContaining('sk-new-secret'), findsNothing);
      expect(fake.calls.any((c) => c.route.contains('reveal')), isFalse);
    });

    testWidgets('adding a key for another provider', (tester) async {
      final fake = await _pump(tester);
      await _tapKey(tester, 'key-add');
      await _tapKey(tester, 'key-provider-picker');
      await tester.tap(find.text('Anthropic').last);
      await tester.pumpAndSettle();
      await _typeKey(tester, 'sk-ant-abcdef-1234');
      await _tapKey(tester, 'key-save');
      expect(fake.keyWrites, ['ops:ANTHROPIC_API_KEY']);
      expect(_key('key-card-ANTHROPIC_API_KEY'), findsOneWidget);
      expect(_key('key-masked-ANTHROPIC_API_KEY'), findsOneWidget);
    });

    testWidgets('a key the provider rejects is not saved', (tester) async {
      final fake = await _pump(
        tester,
        prepare: (f) => f.overrides['POST /api/providers/validate'] = (_) => {
          'ok': false,
          'reachable': true,
          'message': 'That API key was rejected.',
        },
      );
      await _tapKey(tester, 'key-replace-OPENAI_API_KEY');
      await _typeKey(tester, 'sk-wrong-wrong-0000');
      await _tapKey(tester, 'key-save');
      expect(find.text('That API key was rejected.'), findsOneWidget);
      expect(fake.where('PUT /api/env'), isEmpty);
      // A rejection is final; Save anyway is only for an untested key.
      expect(_key('key-save-anyway'), findsNothing);
    });

    testWidgets('a network error while testing offers Save anyway', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        prepare: (f) =>
            f.overrides['POST /api/providers/validate'] = (_) =>
                throw _offline(),
      );
      await _tapKey(tester, 'key-replace-OPENAI_API_KEY');
      await _typeKey(tester, 'sk-offline-key-4321');
      await _tapKey(tester, 'key-save');
      expect(_key('key-warning'), findsOneWidget);
      expect(fake.where('PUT /api/env'), isEmpty);

      await _tapKey(tester, 'key-save-anyway');
      expect(fake.keyWrites, ['ops:OPENAI_API_KEY']);
      // Skipping the test does not test it later.
      expect(fake.where('POST /api/providers/validate'), hasLength(1));
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('a probe that could not run also offers Save anyway', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        prepare: (f) => f.overrides['POST /api/providers/validate'] = (_) => {
          'ok': false,
          'reachable': false,
          'message': 'No probe for this provider.',
        },
      );
      await _tapKey(tester, 'key-replace-OPENAI_API_KEY');
      await _typeKey(tester, 'sk-no-probe-key-5555');
      await _tapKey(tester, 'key-save');
      expect(_key('key-save-anyway'), findsOneWidget);
      await _tapKey(tester, 'key-save-anyway');
      expect(fake.keyWrites, ['ops:OPENAI_API_KEY']);
    });

    testWidgets('Apply to all bots writes to each bot and reports failures', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        prepare: (f) => f.overrides['PUT /api/env'] = (call) {
          if (call.query?['profile'] == 'beta') {
            throw _http(500, {'detail': 'beta is read-only'});
          }
          return f._default(call);
        },
      );
      await _tapKey(tester, 'key-replace-OPENAI_API_KEY');
      expect(
        find.text(
          'Also saves this key for 2 other bots. Each bot keeps '
          'its own copy.',
        ),
        findsOneWidget,
      );
      await _typeKey(tester, 'sk-shared-key-7777');
      await tester.tap(_key('apply-all-bots'));
      await tester.pump();
      await _tapKey(tester, 'key-save');

      expect(fake.keyWrites, [
        'ops:OPENAI_API_KEY',
        'alpha:OPENAI_API_KEY',
        'beta:OPENAI_API_KEY',
      ]);
      // The test ran once, not once per bot.
      expect(fake.where('POST /api/providers/validate'), hasLength(1));
      expect(
        tester.widget<Text>(_in('keys-note', find.byType(Text))).data,
        allOf(
          contains('Saved OpenAI for ops, alpha'),
          contains('save it for beta'),
        ),
      );
      expect(find.textContaining('sk-shared'), findsNothing);
    });

    testWidgets('Apply to all bots is off by default and writes one bot', (
      tester,
    ) async {
      final fake = await _pump(tester);
      await _tapKey(tester, 'key-replace-OPENAI_API_KEY');
      expect(
        tester.widget<CheckboxListTile>(_key('apply-all-bots')).value,
        isFalse,
      );
      await _typeKey(tester, 'sk-just-one-bot-1111');
      await _tapKey(tester, 'key-save');
      expect(fake.keyWrites, ['ops:OPENAI_API_KEY']);
    });

    testWidgets('a failed save shows no part of the key', (tester) async {
      await _pump(
        tester,
        prepare: (f) => f.overrides['PUT /api/env'] = (_) => throw _http(400, {
          'detail': 'Bad value sk-live-ABCDEFGHIJKL1234 for OPENAI_API_KEY',
        }),
      );
      await _tapKey(tester, 'key-replace-OPENAI_API_KEY');
      await _typeKey(tester, 'sk-live-ABCDEFGHIJKL1234');
      await _tapKey(tester, 'key-save');
      // The field still holds what was typed; nothing else shows any of it.
      expect(_shownText(tester), isNot(contains('ABCDEFGHIJKL')));
      expect(find.textContaining('Bad value'), findsOneWidget);
    });

    testWidgets('an empty key is not sent anywhere', (tester) async {
      final fake = await _pump(tester);
      await _tapKey(tester, 'key-replace-OPENAI_API_KEY');
      await _typeKey(tester, '   ');
      await _tapKey(tester, 'key-save');
      expect(find.text('Paste the key first.'), findsOneWidget);
      expect(fake.where('POST /api/providers/validate'), isEmpty);
      expect(fake.where('PUT /api/env'), isEmpty);
    });

    testWidgets('removing a key asks first, and only for this bot', (
      tester,
    ) async {
      final fake = await _pump(tester);
      await _tapKey(tester, 'key-remove-OPENAI_API_KEY');
      await _tapKey(tester, 'confirm-cancel');
      expect(fake.where('DELETE /api/env'), isEmpty);

      await _tapKey(tester, 'key-remove-OPENAI_API_KEY');
      await _tapKey(tester, 'confirm-ok');
      final delete = fake.where('DELETE /api/env').single;
      expect(delete.query, {'profile': 'ops'});
      expect(delete.body, {'key': 'OPENAI_API_KEY'});
      expect(_key('key-card-OPENAI_API_KEY'), findsNothing);
      expect(find.text('Removed OpenAI.'), findsOneWidget);
    });
  });

  group('secret field', () {
    testWidgets('hides the text, with a toggle, and keeps keyboards out', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HermesSecretField(controller: controller)),
        ),
      );
      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(field().obscureText, isTrue);
      expect(field().autocorrect, isFalse);
      expect(field().enableSuggestions, isFalse);
      expect(field().enableIMEPersonalizedLearning, isFalse);
      expect(field().keyboardType, TextInputType.visiblePassword);

      await tester.tap(_key('secret-field-toggle'));
      await tester.pump();
      expect(field().obscureText, isFalse);
      await tester.tap(_key('secret-field-toggle'));
      await tester.pump();
      expect(field().obscureText, isTrue);
    });

    testWidgets('trims pasted whitespace', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HermesSecretField(controller: controller)),
        ),
      );
      await tester.enterText(find.byType(TextField), '  sk-abc\n  def \t');
      expect(controller.text, 'sk-abcdef');
      expect(HermesSecretField.normalize(' a b\nc '), 'abc');
    });
  });

  group('sign-ins', () {
    testWidgets('a device-code sign-in shows the code and completes on poll', (
      tester,
    ) async {
      final fake = await _pump(tester);
      expect(_key('signin-start-nous'), findsOneWidget);
      expect(find.text('Not signed in'), findsWidgets);

      await tester.tap(_key('signin-start-nous'));
      await tester.pump();
      await tester.pump();
      expect(fake.where('POST /api/providers/oauth/nous/start').single.query, {
        'profile': 'ops',
      });
      expect(
        tester.widget<SelectableText>(_key('signin-code')).data,
        'ABCD-EFGH',
      );
      expect(_key('signin-url'), findsOneWidget);
      expect(_key('signin-open'), findsOneWidget);
      expect(_key('signin-waiting'), findsOneWidget);

      // The poll runs at Hermes' interval.
      await tester.pump(const Duration(milliseconds: 500));
      expect(fake.where('GET /api/providers/oauth/nous/poll/sess-1'), isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final poll = fake
          .where('GET /api/providers/oauth/nous/poll/sess-1')
          .single;
      expect(poll.query, {'profile': 'ops'});
      expect(_key('signin-progress'), findsNothing);
      expect(find.text('Signed in to Nous Portal.'), findsOneWidget);
      expect(find.text('Signed in'), findsOneWidget);
      expect(_key('signin-disconnect-nous'), findsOneWidget);
    });

    testWidgets('keeps polling while pending, and cancels on request', (
      tester,
    ) async {
      final fake = await _pump(
        tester,
        prepare: (f) =>
            f.overrides['GET /api/providers/oauth/nous/poll/sess-1'] = (_) => {
              'status': 'pending',
            },
      );
      await tester.tap(_key('signin-start-nous'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(
        fake.where('GET /api/providers/oauth/nous/poll/sess-1').length,
        greaterThanOrEqualTo(2),
      );
      expect(_key('signin-progress'), findsOneWidget);

      await tester.tap(_key('signin-cancel'));
      await tester.pumpAndSettle();
      expect(_key('signin-progress'), findsNothing);
      expect(
        fake.where('DELETE /api/providers/oauth/sessions/sess-1'),
        hasLength(1),
      );
      final polls = fake
          .where('GET /api/providers/oauth/nous/poll/sess-1')
          .length;
      await tester.pump(const Duration(seconds: 5));
      expect(
        fake.where('GET /api/providers/oauth/nous/poll/sess-1'),
        hasLength(polls),
      );
    });

    testWidgets('a denied sign-in says so and stops', (tester) async {
      await _pump(
        tester,
        prepare: (f) =>
            f.overrides['GET /api/providers/oauth/nous/poll/sess-1'] = (_) => {
              'status': 'denied',
              'error_message': 'You said no.',
            },
      );
      await tester.tap(_key('signin-start-nous'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(_key('signin-progress'), findsNothing);
      expect(find.text('You said no.'), findsOneWidget);
      expect(_key('signin-start-nous'), findsOneWidget);
    });

    testWidgets('Anthropic gets API-key guidance, not a sign-in', (
      tester,
    ) async {
      final fake = await _pump(tester);
      expect(_key('signin-anthropic'), findsOneWidget);
      expect(_key('signin-start-anthropic'), findsNothing);
      expect(
        _in('signin-anthropic', find.widgetWithText(FilledButton, 'Sign in')),
        findsNothing,
      );
      final guidance = tester.widget<Text>(_key('signin-guidance-anthropic'));
      expect(guidance.data, contains('Add an API key'));
      expect(guidance.data, contains('can’t sign in from the app'));
      expect(fake.where('POST /api/providers/oauth/anthropic/start'), isEmpty);
    });

    testWidgets('disconnecting asks first', (tester) async {
      final fake = await _pump(tester, prepare: (f) => f.nousSignedIn = true);
      await _tapKey(tester, 'signin-disconnect-nous');
      expect(find.byType(HermezModalSheet), findsOneWidget);
      await _tapKey(tester, 'confirm-ok');
      expect(fake.where('DELETE /api/providers/oauth/nous').single.query, {
        'profile': 'ops',
      });
      expect(find.text('Disconnected Nous Portal.'), findsOneWidget);
      expect(_key('signin-start-nous'), findsOneWidget);
    });
  });
}
