import 'dart:async';

import 'package:conduit/features/hermes/admin/hermes_admin_client.dart';
import 'package:conduit/features/hermes/admin/hermes_admin_providers.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/views/hermes_settings_sections.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/features/hermes/settings/pages/hermes_tools_extensions_page.dart';
import 'package:conduit/features/hermes/sheets/hermez_modal_sheet.dart';
import 'package:conduit/features/hermes/widgets/hermez_skeleton.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as mui;

RequestOptions _options(String path) => RequestOptions(path: path);

DioException _http(int status, Object body, [String path = '/api/x']) =>
    DioException(
      requestOptions: _options(path),
      type: DioExceptionType.badResponse,
      response: Response<Object>(
        requestOptions: _options(path),
        statusCode: status,
        data: body,
      ),
    );

/// One call the page made to Hermes.
typedef _Call = ({
  String kind,
  String name,
  Map<String, dynamic>? query,
  Object? body,
});

/// A Hermes admin connection that serves one bot's tools and extensions and
/// records every call. The gateway restart is never allowed to happen.
final class _FakeTransport implements HermesAdminTransport {
  final calls = <_Call>[];

  var toolsets = <Map<String, Object?>>[
    {
      'name': 'web',
      'label': 'Web',
      'description': 'Search and read pages',
      'enabled': true,
      'configured': true,
      'tools': ['search', 'fetch'],
    },
    {
      'name': 'images',
      'label': 'Image generation',
      'description': 'Make images',
      'enabled': false,
      'configured': false,
      'tools': ['draw'],
    },
  ];

  var skills = <Map<String, dynamic>>[
    {
      'name': 'research',
      'description': 'Find things out',
      'enabled': true,
      'provenance': 'bundled',
    },
    {
      'name': 'poetry',
      'description': 'Write verse',
      'enabled': false,
      'provenance': 'agent',
    },
  ];

  var servers = <Map<String, Object?>>[
    {
      'name': 'github',
      'url': 'https://mcp.example/github',
      'enabled': true,
      'tools': ['issues'],
    },
  ];

  var plugins = <Map<String, Object?>>[
    {
      'key': 'tools/spotify',
      'name': 'spotify',
      'version': '1.2',
      'description': 'Play music',
      'source': 'user',
      'status': 'disabled',
    },
  ];

  /// What `reload.mcp` answers without a confirm.
  Map<String, Object?> reloadAnswer = {'status': 'ok'};

  /// Per call-name errors, thrown once the call is made.
  final failures = <String, Object>{};

  /// Held until completed, when set: the first toolset read waits.
  Completer<void>? gate;

  /// When set, every write waits for it.
  Future<void>? holdWrites;

  int count(String name) => calls.where((call) => call.name == name).length;

  _Call call(String name) => calls.firstWhere((call) => call.name == name);

  Never _unexpected(String what) =>
      throw StateError('Unexpected Hermes call: $what');

  @override
  Future<Object?> rest(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, Object?>? body,
  }) async {
    final name = '$method $path';
    calls.add((kind: 'rest', name: name, query: query, body: body));
    final failure = failures[name];
    if (failure != null) throw failure;
    if (path == '/api/gateway/restart') _unexpected(name);
    switch (name) {
      case 'GET /api/tools/toolsets':
        final wait = gate;
        if (wait != null) {
          gate = null;
          await wait.future;
        }
        return toolsets;
      case 'PUT /api/tools/toolsets/web' || 'PUT /api/tools/toolsets/images':
        await holdWrites;
        final row = toolsets.firstWhere((t) => path.endsWith('/${t['name']}'));
        row['enabled'] = body!['enabled'];
        return {'ok': true};
      case 'PUT /api/skills/toggle':
        final row = skills.firstWhere((s) => s['name'] == body!['name']);
        row['enabled'] = body!['enabled'];
        return {'ok': true};
      case 'PUT /api/mcp/servers/github/enabled':
        servers.first['enabled'] = body!['enabled'];
        return {'ok': true};
    }
    _unexpected(name);
  }

  @override
  Future<Object?> rpc(String method, Map<String, dynamic> params) async {
    calls.add((kind: 'rpc', name: method, query: params, body: null));
    final failure = failures[method];
    if (failure != null) throw failure;
    switch (method) {
      case 'plugins.manage':
        if (params['action'] == 'list') return {'plugins': plugins};
        if (params['action'] == 'toggle') {
          final toggleFailure = failures['plugins.toggle'];
          if (toggleFailure != null) throw toggleFailure;
          final row = plugins.firstWhere((p) => p['key'] == params['key']);
          row['status'] = params['enable'] == true ? 'enabled' : 'disabled';
          return {'ok': true};
        }
      case 'reload.mcp':
        return params['confirm'] == true ? {'status': 'ok'} : reloadAnswer;
    }
    _unexpected(method);
  }

  @override
  Future<Map<String, dynamic>> mcp(
    String method,
    Map<String, dynamic> params,
  ) async {
    calls.add((kind: 'mcp', name: method, query: params, body: null));
    final failure = failures[method];
    if (failure != null) throw failure;
    switch (method) {
      case 'mcp.servers.list':
        return {'servers': servers};
      case 'mcp.servers.add':
        servers = [
          ...servers,
          {'name': params['name'], 'enabled': true, 'tools': <String>[]},
        ];
        return {'ok': true};
    }
    _unexpected(method);
  }

  @override
  Future<List<Map<String, dynamic>>> skillCatalog(String profile) async {
    calls.add((
      kind: 'catalog',
      name: 'skills',
      query: {'profile': profile},
      body: null,
    ));
    final failure = failures['skills'];
    if (failure != null) throw failure;
    return skills;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<_FakeTransport> _pump(
  WidgetTester tester, {
  HermesToolsExtensionsTab tab = HermesToolsExtensionsTab.toolsets,
  void Function(_FakeTransport transport)? prepare,
  bool settle = true,
  Size size = const Size(900, 1400),
}) async {
  final transport = _FakeTransport();
  prepare?.call(transport);
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hermesAdminClientProvider.overrideWithValue(
          HermesAdminClient(transport),
        ),
      ],
      child: MaterialApp(
        // The add-server sheet is built with material_ui's fields.
        localizationsDelegates: mui.GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: HermesToolsExtensionsPage(
            scope: 'ops',
            botTitle: 'Ops bot',
            initialTab: tab,
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return transport;
}

Future<void> _openTab(WidgetTester tester, HermesToolsExtensionsTab tab) async {
  final rect = tester.getRect(find.byKey(const ValueKey('tools-tabs')));
  final count = HermesToolsExtensionsTab.values.length;
  await tester.tapAt(
    Offset(rect.left + rect.width * (tab.index + 0.5) / count, rect.center.dy),
  );
  await tester.pumpAndSettle();
}

Finder _switch(String rowKey) => find.byKey(ValueKey('switch-$rowKey'));

bool _isOn(WidgetTester tester, String rowKey) =>
    tester.widget<Switch>(_switch(rowKey)).value;

bool _isEnabled(WidgetTester tester, String rowKey) =>
    tester.widget<Switch>(_switch(rowKey)).onChanged != null;

Future<void> _flip(WidgetTester tester, String rowKey) async {
  await tester.tap(_switch(rowKey));
  await tester.pumpAndSettle();
}

void main() {
  group('toolsets', () {
    testWidgets('names the bot and lists its toolsets', (tester) async {
      await _pump(tester);
      expect(
        find.textContaining('Ops bot’s tools and extensions (ops)'),
        findsOneWidget,
      );
      expect(find.text('Web'), findsOneWidget);
      expect(find.text('Image generation'), findsOneWidget);
      expect(_isOn(tester, 'toolset-web'), isTrue);
      expect(_isOn(tester, 'toolset-images'), isFalse);
      expect(find.textContaining('Needs setup'), findsOneWidget);
    });

    testWidgets('toggling a toolset calls the bot\'s route and refreshes the '
        'list', (tester) async {
      final transport = await _pump(tester);
      expect(transport.count('GET /api/tools/toolsets'), 1);

      await _flip(tester, 'toolset-web');

      final write = transport.call('PUT /api/tools/toolsets/web');
      expect(write.query, {'profile': 'ops'});
      expect(write.body, {'enabled': false, 'profile': 'ops'});
      expect(transport.count('GET /api/tools/toolsets'), 2);
      expect(_isOn(tester, 'toolset-web'), isFalse);
      expect(find.byKey(const ValueKey('pending')), findsNothing);
      // Nothing else was touched, and no other bot.
      expect(
        transport.calls.where((c) => c.name.startsWith('PUT')),
        hasLength(1),
      );
    });

    testWidgets('the switch moves at once and the row spins until Hermes '
        'answers', (tester) async {
      final transport = await _pump(tester);
      final answer = Completer<void>();
      transport.holdWrites = answer.future;
      await tester.tap(_switch('toolset-images'));
      await tester.pump();
      expect(_isOn(tester, 'toolset-images'), isTrue);
      expect(find.byKey(const ValueKey('pending')), findsOneWidget);
      expect(_isEnabled(tester, 'toolset-images'), isFalse);
      answer.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pending')), findsNothing);
      expect(_isOn(tester, 'toolset-images'), isTrue);
    });

    testWidgets('a failed toggle reverts the switch and shows the error', (
      tester,
    ) async {
      final transport = await _pump(
        tester,
        prepare: (t) => t.failures['PUT /api/tools/toolsets/web'] = _http(400, {
          'detail': 'Toolset is locked by policy',
        }),
      );
      await _flip(tester, 'toolset-web');
      expect(_isOn(tester, 'toolset-web'), isTrue);
      expect(find.byKey(const ValueKey('pending')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('error-toolset-web')),
          matching: find.textContaining('Toolset is locked by policy'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing was changed'), findsOneWidget);
      // A failed write does not pretend to refresh.
      expect(transport.count('GET /api/tools/toolsets'), 1);
    });

    testWidgets('a connection failure reverts without showing server text', (
      tester,
    ) async {
      await _pump(
        tester,
        prepare: (t) =>
            t.failures['PUT /api/tools/toolsets/web'] = DioException(
              requestOptions: _options('/x'),
              type: DioExceptionType.connectionError,
              message: 'sk-secret-123456789 refused',
            ),
      );
      await _flip(tester, 'toolset-web');
      expect(_isOn(tester, 'toolset-web'), isTrue);
      expect(find.textContaining('Couldn’t reach Hermes'), findsOneWidget);
      expect(find.textContaining('sk-secret'), findsNothing);
    });

    testWidgets('a write route this Hermes lacks switches the tab off with the '
        'reason', (tester) async {
      await _pump(
        tester,
        prepare: (t) => t.failures['PUT /api/tools/toolsets/web'] = _http(405, {
          'detail': 'Method Not Allowed',
        }),
      );
      await _flip(tester, 'toolset-web');
      expect(_isOn(tester, 'toolset-web'), isTrue);
      expect(
        find.byKey(const ValueKey('tools-write-disabled')),
        findsOneWidget,
      );
      expect(find.textContaining("can't change toolsets"), findsOneWidget);
      expect(_isEnabled(tester, 'toolset-web'), isFalse);
      expect(_isEnabled(tester, 'toolset-images'), isFalse);
    });
  });

  group('states', () {
    testWidgets('shows a skeleton while a tab loads', (tester) async {
      final gate = Completer<void>();
      await _pump(tester, prepare: (t) => t.gate = gate, settle: false);
      await tester.pump();
      expect(find.byType(HermezSkeleton), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HermezSkeleton), findsNothing);
      expect(find.byType(Switch), findsNWidgets(2));
    });

    testWidgets('a failed load shows an inline error and Retry reloads', (
      tester,
    ) async {
      final transport = await _pump(
        tester,
        prepare: (t) => t.failures['GET /api/tools/toolsets'] = _http(500, {
          'detail': 'database is locked',
        }),
      );
      expect(
        find.byKey(const ValueKey('tools-error-toolsets')),
        findsOneWidget,
      );
      expect(find.textContaining('database is locked'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);

      transport.failures.clear();
      await tester.tap(find.byKey(const ValueKey('tools-retry-toolsets')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tools-error-toolsets')), findsNothing);
      expect(find.byType(Switch), findsNWidgets(2));
      expect(transport.count('GET /api/tools/toolsets'), 2);
    });

    testWidgets('an unknown error never shows its text', (tester) async {
      await _pump(
        tester,
        prepare: (t) => t.failures['GET /api/tools/toolsets'] = StateError(
          'token=sk-live-abcdefghijkl',
        ),
      );
      expect(find.textContaining('Couldn’t load toolsets'), findsOneWidget);
      expect(find.textContaining('sk-live'), findsNothing);
    });

    testWidgets('a feature the server does not expose shows disabled with its '
        'reason', (tester) async {
      await _pump(
        tester,
        tab: HermesToolsExtensionsTab.skills,
        prepare: (t) => t.failures['skills'] = _http(404, {
          'detail': 'No such API endpoint: /api/skills',
        }),
      );
      expect(
        find.byKey(const ValueKey('tools-unavailable-skills')),
        findsOneWidget,
      );
      expect(find.textContaining("can't manage skills"), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.byKey(const ValueKey('tools-retry-skills')), findsNothing);
    });

    testWidgets('a missing bot says so', (tester) async {
      await _pump(
        tester,
        prepare: (t) => t.failures['GET /api/tools/toolsets'] = _http(404, {
          'detail': "Profile 'ops' does not exist.",
        }),
      );
      expect(find.textContaining('can’t find this bot'), findsOneWidget);
    });

    testWidgets('tabs load when first opened, not before', (tester) async {
      final transport = await _pump(tester);
      expect(transport.count('mcp.servers.list'), 0);
      expect(transport.count('skills'), 0);
      await _openTab(tester, HermesToolsExtensionsTab.mcp);
      expect(transport.count('mcp.servers.list'), 1);
      expect(transport.call('mcp.servers.list').query, {'profile': 'ops'});
      await _openTab(tester, HermesToolsExtensionsTab.toolsets);
      await _openTab(tester, HermesToolsExtensionsTab.mcp);
      expect(transport.count('mcp.servers.list'), 1);
    });
  });

  group('skills', () {
    testWidgets('toggling a skill for the bot writes its skill toggle', (
      tester,
    ) async {
      final transport = await _pump(
        tester,
        tab: HermesToolsExtensionsTab.skills,
      );
      expect(transport.call('skills').query, {'profile': 'ops'});
      expect(_isOn(tester, 'skill-research'), isTrue);
      expect(_isOn(tester, 'skill-poetry'), isFalse);

      await _flip(tester, 'skill-research');

      final write = transport.call('PUT /api/skills/toggle');
      expect(write.query, {'profile': 'ops'});
      expect(write.body, {
        'name': 'research',
        'enabled': false,
        'profile': 'ops',
      });
      expect(transport.count('skills'), 2);
      expect(_isOn(tester, 'skill-research'), isFalse);
    });

    testWidgets('a failed skill toggle reverts and says why', (tester) async {
      await _pump(
        tester,
        tab: HermesToolsExtensionsTab.skills,
        prepare: (t) => t.failures['PUT /api/skills/toggle'] = _http(500, {
          'detail': 'could not write config',
        }),
      );
      await _flip(tester, 'skill-poetry');
      expect(_isOn(tester, 'skill-poetry'), isFalse);
      expect(find.textContaining('could not write config'), findsOneWidget);
    });
  });

  group('MCP', () {
    testWidgets('toggling a server uses the bot\'s route, then reloads', (
      tester,
    ) async {
      final transport = await _pump(tester, tab: HermesToolsExtensionsTab.mcp);
      await _flip(tester, 'mcp-github');
      final write = transport.call('PUT /api/mcp/servers/github/enabled');
      expect(write.query, {'profile': 'ops'});
      expect(write.body, {'enabled': false, 'profile': 'ops'});
      expect(transport.call('reload.mcp').query, {'confirm': false});
      expect(find.text('MCP reloaded.'), findsOneWidget);
      expect(_isOn(tester, 'mcp-github'), isFalse);
    });

    testWidgets('adding a server passes the bot\'s profile, then reloads MCP', (
      tester,
    ) async {
      final transport = await _pump(tester, tab: HermesToolsExtensionsTab.mcp);
      await tester.tap(find.byKey(const ValueKey('mcp-add')));
      await tester.pumpAndSettle();
      expect(find.byType(HermezModalSheet), findsOneWidget);

      final fields = find.descendant(
        of: find.byType(HermezModalSheet),
        matching: find.byType(mui.TextField),
      );
      await tester.enterText(fields.at(0), 'notes');
      await tester.enterText(fields.at(1), 'https://mcp.example/notes');
      await tester.enterText(fields.at(4), 'sk-test-key');
      await tester.tap(find.widgetWithText(mui.FilledButton, 'Add'));
      await tester.pumpAndSettle();

      final add = transport.call('mcp.servers.add');
      expect(add.query!['profile'], 'ops');
      expect(add.query!['name'], 'notes');
      expect((add.query!['config'] as Map)['url'], 'https://mcp.example/notes');
      expect(add.query!['bearer_token'], 'sk-test-key');
      // The add came first, the reload after it, and the list was refreshed.
      final names = transport.calls.map((c) => c.name).toList();
      expect(
        names.indexOf('reload.mcp'),
        greaterThan(names.indexOf('mcp.servers.add')),
      );
      expect(transport.call('reload.mcp').query, {'confirm': false});
      expect(transport.count('mcp.servers.list'), 2);
      expect(find.text('notes'), findsOneWidget);
      expect(find.text('MCP reloaded.'), findsOneWidget);
      expect(find.textContaining('sk-test-key'), findsNothing);
    });

    testWidgets('cancelling the add sheet sends nothing', (tester) async {
      final transport = await _pump(tester, tab: HermesToolsExtensionsTab.mcp);
      await tester.tap(find.byKey(const ValueKey('mcp-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(mui.TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(transport.count('mcp.servers.add'), 0);
      expect(transport.count('reload.mcp'), 0);
    });

    testWidgets('a refused add says so and reloads nothing', (tester) async {
      final transport = await _pump(
        tester,
        tab: HermesToolsExtensionsTab.mcp,
        prepare: (t) => t.failures['mcp.servers.add'] = _http(400, {
          'detail': 'name already used',
        }),
      );
      await tester.tap(find.byKey(const ValueKey('mcp-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(HermezModalSheet),
              matching: find.byType(mui.TextField),
            )
            .first,
        'github',
      );
      await tester.tap(find.widgetWithText(mui.FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mcp-action-error')), findsOneWidget);
      expect(find.textContaining('name already used'), findsOneWidget);
      expect(transport.count('reload.mcp'), 0);
    });

    testWidgets('when Hermes asks before reloading, nothing reloads until the '
        'owner says so', (tester) async {
      final transport = await _pump(
        tester,
        tab: HermesToolsExtensionsTab.mcp,
        prepare: (t) => t.reloadAnswer = {
          'status': 'confirm_required',
          'message': 'Reloading clears the prompt cache.',
        },
      );
      await _flip(tester, 'mcp-github');
      expect(
        find.textContaining('Reloading clears the prompt cache'),
        findsOneWidget,
      );
      expect(find.textContaining('every running chat'), findsOneWidget);
      expect(
        transport.calls
            .where((c) => c.name == 'reload.mcp')
            .map((c) => c.query!['confirm']),
        [false],
      );

      await tester.tap(find.byKey(const ValueKey('mcp-reload-confirm')));
      await tester.pumpAndSettle();
      expect(
        transport.calls
            .where((c) => c.name == 'reload.mcp')
            .map((c) => c.query!['confirm']),
        [false, true],
      );
      expect(find.text('MCP reloaded.'), findsOneWidget);
    });

    testWidgets('Later leaves the question unanswered and reloads nothing', (
      tester,
    ) async {
      final transport = await _pump(
        tester,
        tab: HermesToolsExtensionsTab.mcp,
        prepare: (t) => t.reloadAnswer = {
          'status': 'confirm_required',
          'message': 'Reloading clears the prompt cache.',
        },
      );
      await _flip(tester, 'mcp-github');
      await tester.tap(find.byKey(const ValueKey('mcp-reload-later')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mcp-reload-confirm')), findsNothing);
      expect(transport.count('reload.mcp'), 1);
    });

    testWidgets('a failed reload says the change is saved and offers a retry', (
      tester,
    ) async {
      final transport = await _pump(
        tester,
        tab: HermesToolsExtensionsTab.mcp,
        prepare: (t) => t.failures['reload.mcp'] = StateError('boom'),
      );
      await _flip(tester, 'mcp-github');
      expect(
        find.textContaining('Saved, but Hermes couldn’t reload MCP'),
        findsOneWidget,
      );
      transport.failures.clear();
      await tester.tap(find.byKey(const ValueKey('mcp-reload-retry')));
      await tester.pumpAndSettle();
      expect(find.text('MCP reloaded.'), findsOneWidget);
    });

    testWidgets('a plugin-provided server cannot be switched and says why', (
      tester,
    ) async {
      final transport = await _pump(
        tester,
        tab: HermesToolsExtensionsTab.mcp,
        prepare: (t) => t.failures['PUT /api/mcp/servers/github/enabled'] =
            _http(409, {'detail': 'provided by plugin'}),
      );
      await _flip(tester, 'mcp-github');
      expect(_isOn(tester, 'mcp-github'), isTrue);
      expect(_isEnabled(tester, 'mcp-github'), isFalse);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('reason-mcp-github')),
          matching: find.textContaining('Provided by a plugin'),
        ),
        findsOneWidget,
      );
      expect(transport.count('reload.mcp'), 0);
    });
  });

  group('plugins', () {
    testWidgets('toggling a plugin shows the restart notice and calls the '
        'bot\'s toggle', (tester) async {
      final transport = await _pump(
        tester,
        tab: HermesToolsExtensionsTab.plugins,
      );
      expect(
        find.text('Restart Hermes to apply plugin changes.'),
        findsNothing,
      );

      await _flip(tester, 'plugin-tools/spotify');

      final toggle = transport.calls.lastWhere(
        (c) => c.name == 'plugins.manage' && c.query!['action'] == 'toggle',
      );
      expect(toggle.query, {
        'action': 'toggle',
        'key': 'tools/spotify',
        'enable': true,
        'profile': 'ops',
      });
      expect(
        find.text('Restart Hermes to apply plugin changes.'),
        findsOneWidget,
      );
      expect(find.text('Restart needed'), findsOneWidget);
      expect(_isOn(tester, 'plugin-tools/spotify'), isTrue);
    });

    testWidgets('restart asks first, and Cancel restarts nothing', (
      tester,
    ) async {
      final transport = await _pump(
        tester,
        tab: HermesToolsExtensionsTab.plugins,
      );
      await _flip(tester, 'plugin-tools/spotify');
      await tester.tap(find.byKey(const ValueKey('plugins-restart-start')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('running chats are interrupted'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('plugins-restart-cancel')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('plugins-restart-confirm')),
        findsNothing,
      );
      expect(
        transport.calls.where((c) => c.name.contains('/api/gateway/restart')),
        isEmpty,
      );
      // The notice is still there: the plugin has not taken effect.
      expect(
        find.text('Restart Hermes to apply plugin changes.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed plugin toggle reverts and shows no restart notice', (
      tester,
    ) async {
      await _pump(
        tester,
        tab: HermesToolsExtensionsTab.plugins,
        prepare: (t) => t.failures['plugins.toggle'] = _http(400, {
          'detail': 'plugin is not installed',
        }),
      );
      await _flip(tester, 'plugin-tools/spotify');
      expect(_isOn(tester, 'plugin-tools/spotify'), isFalse);
      expect(find.textContaining('plugin is not installed'), findsOneWidget);
      expect(
        find.text('Restart Hermes to apply plugin changes.'),
        findsNothing,
      );
    });
  });

  group('links into the editor', () {
    testWidgets('the settings toolsets section lists bots, not switches, and '
        'opens the chosen bot’s editor', (tester) async {
      final opened = <(String, HermesToolsExtensionsTab, String?)>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermesConfigProvider.overrideWith(
              () => _FixedConfig(
                const HermesConfig(
                  enabled: true,
                  baseUrl: 'https://hermes.example',
                  mode: HermesBackendMode.desktopGateway,
                ),
              ),
            ),
            hermesBotsProvider.overrideWith(
              (ref) async => const [
                HermesBot(name: 'ops', title: 'Ops bot'),
                HermesBot(name: 'qa', title: 'qa'),
              ],
            ),
            hermesToolsExtensionsOpenerProvider.overrideWithValue(
              (
                context, {
                required profile,
                tab = HermesToolsExtensionsTab.toolsets,
                botTitle,
              }) => opened.add((profile, tab, botTitle)),
            ),
          ],
          child: mui.MaterialApp(
            localizationsDelegates: conduitLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const mui.Scaffold(body: HermesToolsetsSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(mui.Switch), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('hermes-toolsets-per-bot-note')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('hermes-toolsets-bot-ops')),
      );
      await tester.pump();
      expect(opened, [('ops', HermesToolsExtensionsTab.toolsets, 'Ops bot')]);
    });

    test('the tab a route names is parsed, and an unknown one is Toolsets', () {
      expect(
        HermesToolsExtensionsTab.parse('mcp'),
        HermesToolsExtensionsTab.mcp,
      );
      expect(
        HermesToolsExtensionsTab.parse('nope'),
        HermesToolsExtensionsTab.toolsets,
      );
      expect(
        HermesToolsExtensionsTab.parse(null),
        HermesToolsExtensionsTab.toolsets,
      );
    });
  });
}

final class _FixedConfig extends HermesConfigController {
  _FixedConfig(this.config);

  final HermesConfig config;

  @override
  HermesConfig build() => config;
}
