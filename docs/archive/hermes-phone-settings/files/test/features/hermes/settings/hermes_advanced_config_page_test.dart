import 'dart:async';

import 'package:conduit/core/persistence/preferences_store.dart';
import 'package:conduit/features/desktop/hermez_desktop.dart';
import 'package:conduit/features/hermes/admin/hermes_admin_client.dart';
import 'package:conduit/features/hermes/admin/hermes_admin_providers.dart';
import 'package:conduit/features/hermes/admin/hermes_config_backups.dart';
import 'package:conduit/features/hermes/admin/hermes_config_document.dart';
import 'package:conduit/features/hermes/settings/pages/hermes_advanced_config_page.dart';
import 'package:conduit/features/hermes/sheets/hermez_modal_sheet.dart';
import 'package:conduit/features/hermes/widgets/hermez_skeleton.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _yaml = '''
# Hermes config
model: sonnet
providers:
  openrouter:
    api_key: sk-123
mcp_servers:
  fal:
    command: npx
    env:
      FAL_KEY: y
security:
  redact_secrets: true
agent:
  max_turns: 40
terminal:
  timeout: 30
''';

final _editor = find.byKey(const ValueKey('advanced-config-editor'));

RequestOptions get _request => RequestOptions(path: '/api/config/raw');

DioException _http(int status, Object body) => DioException(
  requestOptions: _request,
  type: DioExceptionType.badResponse,
  response: Response<Object>(
    requestOptions: _request,
    statusCode: status,
    data: body,
  ),
);

/// A Hermes admin connection that serves one config file and records writes.
final class _FakeTransport implements HermesAdminTransport {
  _FakeTransport(this.yaml);

  /// The file on the "server", secrets and all.
  String yaml;

  /// Every `yaml_text` written, in order.
  final puts = <String>[];
  int rawReads = 0;

  /// Held until completed, when set: the first read of the file waits.
  Completer<void>? gate;

  /// Throws on a read while greater than zero, counting down.
  int failReads = 0;

  /// Answers every config route as a Hermes without them.
  bool missing = false;

  /// Makes the write fail with this error.
  Object? putError;

  Map<String, Object?> schema = {
    'fields': {
      'agent.max_turns': {'type': 'number'},
      'terminal.timeout': {'type': 'number'},
      'security.redact_secrets': {'type': 'boolean'},
      'model': {'type': 'string'},
    },
    'category_order': <String>[],
  };

  @override
  Future<Object?> rest(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, Object?>? body,
  }) async {
    if (missing) throw _http(404, {'detail': 'No such API endpoint: $path'});
    switch ('$method $path') {
      case 'GET /api/config/raw':
        rawReads++;
        final wait = gate;
        if (wait != null) {
          gate = null;
          await wait.future;
        }
        if (failReads > 0) {
          failReads--;
          throw _http(500, {'detail': 'boom'});
        }
        return {'yaml': yaml, 'path': '/opt/data/config.yaml'};
      case 'PUT /api/config/raw':
        final error = putError;
        if (error != null) throw error;
        puts.add(body!['yaml_text']! as String);
        yaml = body['yaml_text']! as String;
        return {'ok': true};
      case 'GET /api/config/schema':
        return schema;
      case 'GET /api/config/defaults':
        return {
          'model': '',
          'agent': {},
          'terminal': {},
          'security': {},
          'approvals': {},
          'dashboard': {},
          'providers': {},
        };
    }
    throw UnimplementedError('$method $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<_FakeTransport> _pump(
  WidgetTester tester, {
  String? scope = 'ops',
  String yaml = _yaml,
  void Function(_FakeTransport transport)? prepare,
  bool settle = true,
  Widget Function(Widget page)? wrap,
  bool? desktop,
}) async {
  final transport = _FakeTransport(yaml);
  prepare?.call(transport);
  tester.view
    ..physicalSize = const Size(1000, 1500)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (desktop != null) HermezDesktop.debugIsActiveOverride = desktop;
  addTearDown(HermezDesktop.debugResetOverride);
  final page = HermesAdvancedConfigPage(scope: scope, botTitle: 'Ops bot');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hermesAdminClientProvider.overrideWithValue(
          HermesAdminClient(transport),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: wrap?.call(page) ?? page)),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return transport;
}

String _editorText(WidgetTester tester) =>
    tester.widget<TextField>(_editor).controller!.text;

Future<void> _edit(
  WidgetTester tester,
  String Function(String text) change,
) async {
  await tester.enterText(_editor, change(_editorText(tester)));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Type button, String label) async {
  // The sheet is the last thing in the tree: it wins over the page behind it.
  await tester.tap(find.widgetWithText(button, label).last);
  await tester.pumpAndSettle();
}

/// [matching] inside the open sheet only.
Finder _inSheet(Finder matching) =>
    find.descendant(of: find.byType(HermezModalSheet), matching: matching);

String _backupsOnDevice() => PreferencesStore.instance
    .getKeys()
    .map((k) => PreferencesStore.instance.getString(k) ?? '')
    .join('\n');

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PreferencesStore.debugOverride(await SharedPreferences.getInstance());
  });
  tearDown(PreferencesStore.debugReset);

  group('loading and states', () {
    testWidgets('shows the config with secrets as placeholders', (
      tester,
    ) async {
      await _pump(tester);
      final text = _editorText(tester);
      expect(text, contains('model: sonnet'));
      expect(text, contains('# Hermes config'));
      expect(text, contains('api_key: <secret:'));
      expect(text, isNot(contains('sk-123')));
      expect(text, isNot(contains('FAL_KEY: y')));
      expect(find.textContaining('sk-123'), findsNothing);
    });

    testWidgets('the scope label says which config this is', (tester) async {
      await _pump(tester, scope: null);
      expect(
        find.textContaining('root config. This does not change existing bots'),
        findsOneWidget,
      );
    });

    testWidgets('a bot scope is named', (tester) async {
      await _pump(tester, scope: 'ops');
      expect(find.textContaining('Ops bot’s config (ops)'), findsOneWidget);
    });

    testWidgets('shows a skeleton while the file loads', (tester) async {
      final gate = Completer<void>();
      await _pump(tester, prepare: (t) => t.gate = gate, settle: false);
      await tester.pump();
      expect(find.byType(HermezSkeleton), findsOneWidget);
      expect(_editor, findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HermezSkeleton), findsNothing);
      expect(_editor, findsOneWidget);
    });

    testWidgets('a failed load shows the error inline with Retry', (
      tester,
    ) async {
      await _pump(tester, prepare: (t) => t.failReads = 1);
      expect(find.byKey(const ValueKey('advanced-config-error')), findsOne);
      expect(find.textContaining('boom'), findsOneWidget);
      expect(_editor, findsNothing);

      await _tap(tester, OutlinedButton, 'Retry');
      expect(_editor, findsOneWidget);
      expect(_editorText(tester), contains('model: sonnet'));
    });

    testWidgets('a Hermes without the route says so and offers no Retry', (
      tester,
    ) async {
      await _pump(tester, prepare: (t) => t.missing = true);
      expect(
        find.byKey(const ValueKey('advanced-config-unavailable')),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
      expect(_editor, findsNothing);
    });

    testWidgets('no admin connection is unavailable, not an error', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [hermesAdminClientProvider.overrideWithValue(null)],
          child: const MaterialApp(
            home: Scaffold(body: HermesAdvancedConfigPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('advanced-config-unavailable')),
        findsOneWidget,
      );
    });
  });

  group('saving', () {
    testWidgets('Save always opens the diff review, and the diff and review '
        'hold no secret', (tester) async {
      final transport = await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst('model: sonnet', 'model: opus'),
      );
      await _tap(tester, FilledButton, 'Save');

      expect(find.byType(HermezModalSheet), findsOneWidget);
      expect(find.text('Review changes'), findsOneWidget);
      expect(find.text('model: sonnet'), findsOneWidget);
      expect(find.text('model: opus'), findsOneWidget);
      expect(find.textContaining('sk-123'), findsNothing);
      expect(find.textContaining('FAL_KEY: y'), findsNothing);
      expect(transport.puts, isEmpty);
    });

    testWidgets('Cancel writes nothing and keeps the edits', (tester) async {
      final transport = await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst('model: sonnet', 'model: opus'),
      );
      await _tap(tester, FilledButton, 'Save');
      await _tap(tester, TextButton, 'Cancel');

      expect(find.byType(HermezModalSheet), findsNothing);
      expect(transport.puts, isEmpty);
      expect(_editorText(tester), contains('model: opus'));
    });

    testWidgets('Confirm writes the original secrets back, keeps a masked '
        'backup, and reloads as written', (tester) async {
      final transport = await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst('model: sonnet', 'model: opus'),
      );
      await _tap(tester, FilledButton, 'Save');
      await _tap(tester, FilledButton, 'Confirm');

      expect(transport.puts, hasLength(1));
      expect(transport.puts.single, contains('api_key: sk-123'));
      expect(transport.puts.single, contains('FAL_KEY: y'));
      expect(transport.puts.single, contains('model: opus'));
      expect(
        transport.puts.single,
        _yaml.replaceFirst('model: sonnet', 'model: opus'),
      );
      expect(find.text('Saved. Applies to new chats.'), findsOneWidget);
      expect(_editorText(tester), contains('model: opus'));
      expect(_editorText(tester), isNot(contains('sk-123')));

      final backups = ref(tester).read(hermesConfigBackupStoreProvider);
      expect(backups.list('ops'), hasLength(1));
      expect(backups.list('ops').single.yaml, contains('model: sonnet'));
      expect(_backupsOnDevice(), isNot(contains('sk-123')));
      expect(_backupsOnDevice(), isNot(contains('FAL_KEY: y')));
    });

    testWidgets('a change that needs a restart says so', (tester) async {
      await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst('command: npx', 'command: uvx'),
      );
      await _tap(tester, FilledButton, 'Save');
      expect(
        find.text('These changes need a restart to take effect.'),
        findsOne,
      );
      await _tap(tester, FilledButton, 'Confirm');
      expect(find.textContaining('Restart needed'), findsOneWidget);
    });

    testWidgets('deleting a placeholder line removes that secret', (
      tester,
    ) async {
      final transport = await _pump(tester);
      await _edit(
        tester,
        (t) =>
            t.split('\n').where((line) => !line.contains('FAL_KEY')).join('\n'),
      );
      await _tap(tester, FilledButton, 'Save');
      await _tap(tester, FilledButton, 'Confirm');
      expect(transport.puts.single, isNot(contains('FAL_KEY')));
      expect(transport.puts.single, contains('api_key: sk-123'));
    });

    testWidgets('a duplicated block with a placeholder blocks the save', (
      tester,
    ) async {
      final transport = await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst(
          '  fal:\n',
          '  fal2:\n    command: npx\n    env:\n      FAL_KEY: '
              '${HermesConfigDocument.placeholderFor(const ['mcp_servers', 'fal', 'env', 'FAL_KEY'])}\n'
              '  fal:\n',
        ),
      );
      await _tap(tester, FilledButton, 'Save');

      expect(find.textContaining('Re-enter this secret'), findsOneWidget);
      expect(find.textContaining('mcp_servers.fal2.env.FAL_KEY'), findsOne);
      expect(find.byType(HermezModalSheet), findsNothing);
      expect(transport.puts, isEmpty);
    });

    testWidgets('a write error is shown without the secrets it quotes', (
      tester,
    ) async {
      final transport = await _pump(
        tester,
        prepare: (t) => t.putError = _http(400, {
          'detail': 'Invalid YAML: while parsing "api_key: sk-123 FAL_KEY: y"',
        }),
      );
      await _edit(
        tester,
        (t) => t.replaceFirst('model: sonnet', 'model: opus'),
      );
      await _tap(tester, FilledButton, 'Save');
      await _tap(tester, FilledButton, 'Confirm');

      expect(find.textContaining('Invalid YAML'), findsOneWidget);
      expect(find.textContaining('sk-123'), findsNothing);
      expect(transport.puts, isEmpty);
      // The edits are still there to fix.
      expect(_editorText(tester), contains('model: opus'));
    });

    testWidgets('without a stored backup nothing is written', (tester) async {
      PreferencesStore.debugReset();
      final transport = await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst('model: sonnet', 'model: opus'),
      );
      await _tap(tester, FilledButton, 'Save');
      await _tap(tester, FilledButton, 'Confirm');
      expect(find.textContaining('nothing was saved'), findsOneWidget);
      expect(transport.puts, isEmpty);
    });
  });

  group('validation (AE5, AE9)', () {
    testWidgets('invalid YAML is refused and no write call is made', (
      tester,
    ) async {
      final transport = await _pump(tester);
      final reads = transport.rawReads;
      await _edit(tester, (_) => 'model: [a\nother: 1\n');
      await _tap(tester, FilledButton, 'Save');

      expect(find.textContaining('Invalid YAML'), findsOneWidget);
      expect(find.byType(HermezModalSheet), findsNothing);
      expect(transport.puts, isEmpty);
      // Refused locally: the server was not even asked.
      expect(transport.rawReads, reads);
    });

    testWidgets('a known numeric key set to text is refused with the key '
        'named', (tester) async {
      final transport = await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst('max_turns: 40', 'max_turns: plenty'),
      );
      await _tap(tester, FilledButton, 'Save');

      expect(find.textContaining('agent.max_turns must be a number'), findsOne);
      expect(find.byType(HermezModalSheet), findsNothing);
      expect(transport.puts, isEmpty);
    });

    testWidgets('a top-level list is refused as must be a mapping', (
      tester,
    ) async {
      final transport = await _pump(tester);
      await _edit(tester, (_) => '- a\n- b\n');
      await _tap(tester, FilledButton, 'Save');
      expect(find.textContaining('must be a mapping'), findsOneWidget);
      expect(transport.puts, isEmpty);
    });

    testWidgets('platform_toolsets and mcp_servers do not warn, a '
        'misspelled root does', (tester) async {
      await _pump(
        tester,
        yaml: 'model: a\nplatform_toolsets:\n  cli: [web]\nmcp_servers: {}\n',
      );
      await _edit(tester, (t) => '${t}x: 1\n');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining("Unknown top-level key 'x'"), findsOne);
      expect(find.textContaining("'platform_toolsets'"), findsNothing);
      expect(find.textContaining("'mcp_servers'"), findsNothing);

      await _edit(tester, (t) => t.replaceFirst('x: 1\n', 'modle: a\n'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining("Did you mean 'model'"), findsOneWidget);
    });

    testWidgets('errors show as you type, before Save', (tester) async {
      await _pump(tester);
      await _edit(tester, (_) => 'model: [a\n');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Invalid YAML'), findsOneWidget);
    });
  });

  group('changed on the server', () {
    testWidgets('the review diffs against the latest version with Reload and '
        'Overwrite, and Overwrite keeps the server secrets', (tester) async {
      final transport = await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst('model: sonnet', 'model: opus'),
      );
      // Someone else edits the file, and rotates a secret.
      transport.yaml = _yaml
          .replaceFirst('timeout: 30', 'timeout: 99')
          .replaceFirst('sk-123', 'sk-rotated-999');
      await _tap(tester, FilledButton, 'Save');

      expect(
        find.byKey(const ValueKey('review-changed-banner')),
        findsOneWidget,
      );
      expect(
        _inSheet(find.widgetWithText(OutlinedButton, 'Reload')),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Overwrite'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Confirm'), findsNothing);
      // The diff is against the latest version: it shows what the owner's
      // text would undo as well as their own change.
      expect(find.textContaining('timeout: 99'), findsOneWidget);
      expect(find.textContaining('sk-rotated-999'), findsNothing);

      await _tap(tester, FilledButton, 'Overwrite');
      expect(transport.puts, hasLength(1));
      expect(transport.puts.single, contains('model: opus'));
      expect(transport.puts.single, contains('api_key: sk-rotated-999'));
    });

    testWidgets('Reload discards the edits and loads the latest', (
      tester,
    ) async {
      final transport = await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst('model: sonnet', 'model: opus'),
      );
      transport.yaml = _yaml.replaceFirst('timeout: 30', 'timeout: 99');
      await _tap(tester, FilledButton, 'Save');
      await _tap(tester, OutlinedButton, 'Reload');

      expect(transport.puts, isEmpty);
      expect(_editorText(tester), contains('timeout: 99'));
      expect(_editorText(tester), contains('model: sonnet'));
    });

    testWidgets('a file that moves while the review is open is reviewed '
        'again before it is overwritten', (tester) async {
      final transport = await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst('model: sonnet', 'model: opus'),
      );
      await _tap(tester, FilledButton, 'Save');
      expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);

      transport.yaml = _yaml.replaceFirst('timeout: 30', 'timeout: 99');
      await _tap(tester, FilledButton, 'Confirm');

      expect(transport.puts, isEmpty);
      expect(find.byKey(const ValueKey('review-changed-banner')), findsOne);
      await _tap(tester, FilledButton, 'Overwrite');
      expect(transport.puts, hasLength(1));
    });
  });

  group('guard keys', () {
    testWidgets('security.redact_secrets: false is labelled and needs a '
        'second confirmation', (tester) async {
      final transport = await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst('redact_secrets: true', 'redact_secrets: false'),
      );
      await _tap(tester, FilledButton, 'Save');

      expect(find.byKey(const ValueKey('review-guard-banner')), findsOneWidget);
      expect(
        find.textContaining('security.redact_secrets: true → false'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('diff-guard-label')), findsWidgets);

      // The first confirmation only asks again.
      await _tap(tester, FilledButton, 'Confirm');
      expect(transport.puts, isEmpty);
      expect(
        find.byKey(const ValueKey('review-guard-confirm-text')),
        findsOneWidget,
      );

      // Back returns to the review, and nothing is written.
      await _tap(tester, TextButton, 'Back');
      expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);
      expect(transport.puts, isEmpty);

      await _tap(tester, FilledButton, 'Confirm');
      await _tap(tester, FilledButton, 'Confirm guarded change');
      expect(transport.puts, hasLength(1));
      expect(transport.puts.single, contains('redact_secrets: false'));
    });

    testWidgets('a change elsewhere has no guard label and one '
        'confirmation', (tester) async {
      final transport = await _pump(tester);
      await _edit(tester, (t) => t.replaceFirst('timeout: 30', 'timeout: 60'));
      await _tap(tester, FilledButton, 'Save');
      expect(find.byKey(const ValueKey('review-guard-banner')), findsNothing);
      expect(find.byKey(const ValueKey('diff-guard-label')), findsNothing);
      await _tap(tester, FilledButton, 'Confirm');
      expect(transport.puts, hasLength(1));
    });
  });

  group('backups', () {
    Future<void> saveOnce(WidgetTester tester) async {
      await _edit(
        tester,
        (t) => t.replaceFirst('model: sonnet', 'model: opus'),
      );
      await _tap(tester, FilledButton, 'Save');
      await _tap(tester, FilledButton, 'Confirm');
    }

    testWidgets('lists a backup per save and restoring one goes through the '
        'review', (tester) async {
      final transport = await _pump(tester);
      await saveOnce(tester);
      expect(transport.puts, hasLength(1));

      await _tap(tester, OutlinedButton, 'Backups');
      expect(find.text('Backups'), findsWidgets);
      expect(find.widgetWithText(TextButton, 'Restore'), findsOneWidget);
      await _tap(tester, TextButton, 'Restore');

      // The backup (model: sonnet) is now the edit, and Save's review opened.
      expect(find.text('Review changes'), findsOneWidget);
      expect(find.text('model: opus'), findsOneWidget);
      expect(find.text('model: sonnet'), findsOneWidget);
      expect(transport.puts, hasLength(1));

      await _tap(tester, FilledButton, 'Confirm');
      expect(transport.puts, hasLength(2));
      expect(transport.puts.last, _yaml);
      // Both saves left a backup.
      expect(
        ref(tester).read(hermesConfigBackupStoreProvider).list('ops'),
        hasLength(2),
      );
    });

    testWidgets('an empty list says so', (tester) async {
      await _pump(tester);
      await _tap(tester, OutlinedButton, 'Backups');
      expect(find.textContaining('No backups yet'), findsOneWidget);
    });

    testWidgets('restoring a backup whose secret was removed on the server '
        'is blocked', (tester) async {
      final transport = await _pump(tester);
      await saveOnce(tester);
      // The secret is removed on the server afterwards.
      transport.yaml = transport.yaml.replaceFirst('    api_key: sk-123\n', '');
      await _tap(tester, OutlinedButton, 'Backups');
      await _tap(tester, TextButton, 'Restore');

      expect(find.textContaining('Re-enter this secret'), findsOneWidget);
      expect(find.textContaining('providers.openrouter.api_key'), findsOne);
      expect(find.byType(HermezModalSheet), findsNothing);
      expect(transport.puts, hasLength(1));
    });

    testWidgets('the root scope keeps its own backups', (tester) async {
      await _pump(tester, scope: null);
      await saveOnce(tester);
      final store = ref(tester).read(hermesConfigBackupStoreProvider);
      expect(store.list(null), hasLength(1));
      expect(store.list('ops'), isEmpty);
    });
  });

  group('the editor', () {
    testWidgets('uses a monospace font', (tester) async {
      await _pump(tester);
      final style = tester.widget<TextField>(_editor).style!;
      expect(style.fontFamily, isNotNull);
      expect(style.fontFamilyFallback, contains('monospace'));
    });

    testWidgets('Tab inserts spaces and keeps focus', (tester) async {
      await _pump(tester);
      await tester.tap(_editor);
      await tester.pump();
      final controller = tester.widget<TextField>(_editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(controller.text, startsWith('  # Hermes config'));
      expect(controller.selection.baseOffset, 2);
      expect(tester.widget<TextField>(_editor).focusNode!.hasFocus, isTrue);
    });

    testWidgets('Escape leaves the editor', (tester) async {
      await _pump(tester);
      await tester.tap(_editor);
      await tester.pump();
      final focus = tester.widget<TextField>(_editor).focusNode!;
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(focus.hasFocus, isFalse);
    });

    testWidgets('Ctrl+Tab leaves the editor', (tester) async {
      await _pump(tester);
      await tester.tap(_editor);
      await tester.pump();
      final focus = tester.widget<TextField>(_editor).focusNode!;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      expect(focus.hasFocus, isFalse);
    });

    testWidgets('Save is off until there is an edit', (tester) async {
      await _pump(tester);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await _edit(tester, (t) => '$t# note\n');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNotNull,
      );
    });
  });

  group('unsaved edits', () {
    testWidgets('survive hiding to the tray and coming back', (tester) async {
      await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst('model: sonnet', 'model: opus'),
      );
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(_editorText(tester), contains('model: opus'));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('reports being dirty to the shell', (tester) async {
      final flags = <bool>[];
      final transport = _FakeTransport(_yaml);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermesAdminClientProvider.overrideWithValue(
              HermesAdminClient(transport),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: HermesAdvancedConfigPage(
                scope: 'ops',
                onDirtyChanged: flags.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _edit(tester, (t) => '$t# note\n');
      expect(flags, [true]);
      await _edit(tester, (t) => t.replaceFirst('# note\n', ''));
      expect(flags, [true, false]);
    });

    testWidgets('leaving asks first, and Keep editing stays', (tester) async {
      final transport = _FakeTransport(_yaml);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermesAdminClientProvider.overrideWithValue(
              HermesAdminClient(transport),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: HermesAdvancedConfigPage(scope: 'ops'),
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // No edits: Back leaves at once.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _edit(tester, (t) => '$t# note\n');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);

      await _tap(tester, TextButton, 'Keep editing');
      expect(_editor, findsOneWidget);
      expect(_editorText(tester), endsWith('# note\n'));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _tap(tester, FilledButton, 'Leave');
      expect(find.text('open'), findsOneWidget);
      expect(_editor, findsNothing);
    });

    testWidgets('Reload with edits asks before discarding them', (
      tester,
    ) async {
      final transport = await _pump(tester);
      await _edit(tester, (t) => '$t# note\n');
      await _tap(tester, OutlinedButton, 'Reload');
      expect(find.text('Discard your edits?'), findsOneWidget);
      await _tap(tester, TextButton, 'Keep editing');
      expect(_editorText(tester), endsWith('# note\n'));

      final reads = transport.rawReads;
      await _tap(tester, OutlinedButton, 'Reload');
      await _tap(tester, FilledButton, 'Discard and reload');
      expect(transport.rawReads, greaterThan(reads));
      expect(_editorText(tester), isNot(endsWith('# note\n')));
    });
  });

  group('the diff on each platform', () {
    testWidgets('a phone gets a single column', (tester) async {
      await _pump(tester);
      await _edit(
        tester,
        (t) => t.replaceFirst('model: sonnet', 'model: opus'),
      );
      await _tap(tester, FilledButton, 'Save');
      expect(find.byKey(const ValueKey('diff-single-column')), findsOne);
      expect(find.byKey(const ValueKey('diff-side-by-side')), findsNothing);
    });

    testWidgets('the desktop gets old beside new when the window is wide', (
      tester,
    ) async {
      await _pump(tester, desktop: true);
      await _edit(
        tester,
        (t) => t.replaceFirst('model: sonnet', 'model: opus'),
      );
      await _tap(tester, FilledButton, 'Save');
      expect(find.byKey(const ValueKey('diff-side-by-side')), findsOne);
      expect(find.text('model: sonnet'), findsOneWidget);
      expect(find.text('model: opus'), findsOneWidget);
    });
  });
}

/// The container of the page under test.
ProviderContainer ref(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(HermesAdvancedConfigPage)),
);
