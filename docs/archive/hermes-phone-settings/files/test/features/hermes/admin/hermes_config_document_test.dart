import 'package:conduit/core/persistence/preferences_store.dart';
import 'package:conduit/features/hermes/admin/hermes_admin_models.dart';
import 'package:conduit/features/hermes/admin/hermes_config_backups.dart';
import 'package:conduit/features/hermes/admin/hermes_config_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A server config with the secret shapes KTD9 names, a comment, and a Steel
/// `browser` block.
const _server = '''
# Hermes config
model: sonnet
api_key: sk-123
apikey: x
notes: sk-abcdefghijklmnop123
mcp_servers:
  fal:
    command: npx
    auth: oauth
    env:
      FAL_KEY: y
browser:
  provider: steel
  steel:
    base_url: https://api.steel.dev
    session_timeout: 300
    api_key: steel-live-secret-value
terminal:
  max_tokens: 4096
  timeout: 30
security:
  redact_secrets: true
''';

HermesAdminConfigSchema _schema(Map<String, Object?> fields) =>
    HermesAdminConfigSchema(fields: fields, categoryOrder: const []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('masking', () {
    test('a secret value shows as a placeholder bound to its key path', () {
      final masked = HermesConfigDocument.mask(_server);
      expect(masked.text, isNot(contains('sk-123')));
      expect(
        masked.text,
        contains(
          'api_key: ${HermesConfigDocument.placeholderFor(const ['api_key'])}',
        ),
      );
      expect(masked.maskedKeys, contains('api_key'));
      // Everything that is not a secret, comments included, stays put.
      expect(masked.text, contains('# Hermes config'));
      expect(masked.text, contains('model: sonnet'));
      expect(masked.text, contains('command: npx'));
    });

    test('apikey, an MCP env value and an sk- value under a plain key are '
        'all masked', () {
      final masked = HermesConfigDocument.mask(_server).text;
      expect(masked, isNot(contains('apikey: x\n')));
      expect(masked, isNot(contains('FAL_KEY: y')));
      expect(masked, isNot(contains('sk-abcdefghijklmnop123')));
      expect(masked, isNot(contains('steel-live-secret-value')));
      expect(
        HermesConfigDocument.mask(_server).maskedKeys,
        containsAll(<String>[
          'apikey',
          'mcp_servers.fal.env.FAL_KEY',
          'notes',
          'browser.steel.api_key',
        ]),
      );
    });

    test('modes, numbers and env references are not masked', () {
      final masked = HermesConfigDocument.mask(
        '$_server'
        'extra:\n  token_ref: \${MY_TOKEN}\n',
      ).text;
      expect(masked, contains('auth: oauth'));
      expect(masked, contains('max_tokens: 4096'));
      expect(masked, contains('token_ref: \${MY_TOKEN}'));
    });

    test('masking is idempotent', () {
      final once = HermesConfigDocument.mask(_server).text;
      expect(HermesConfigDocument.mask(once).text, once);
    });

    test('a multi-line secret and an anchored secret keep their structure', () {
      const raw =
          'key_a: &a sk-abcdefghijklmnop12\n'
          'key_b: *a\n'
          'private_key: |\n'
          '  -----BEGIN PRIVATE KEY-----\n'
          '  abc\n'
          '  -----END PRIVATE KEY-----\n'
          'after: 1\n';
      final masked = HermesConfigDocument.mask(raw).text;
      expect(masked, isNot(contains('sk-abcdefghijklmnop12')));
      expect(masked, isNot(contains('BEGIN PRIVATE KEY')));
      expect(masked, contains('key_a: &a <secret:'));
      expect(masked, contains('after: 1'));
      // The masked text is still valid YAML.
      expect(HermesConfigDocument.validate(masked).ok, isTrue);
    });

    test('a credential in a comment is hidden', () {
      final masked = HermesConfigDocument.mask(
        'model: x # old key ghp_abcdefghijklmnop1234\n',
      );
      expect(masked.text, isNot(contains('ghp_abcdefghijklmnop1234')));
      expect(masked.text, contains('model: x'));
      expect(masked.commentsScrubbed, 1);
    });

    test('text that does not parse is masked line by line and cannot be '
        'restored', () {
      final masked = HermesConfigDocument.mask('api_key: sk-123\nbroken: [1\n');
      expect(masked.text, isNot(contains('sk-123')));
      expect(masked.text, contains('<secret:unreadable>'));
    });
  });

  group('restoring placeholders', () {
    test('an unedited document restores byte for byte', () {
      final restored = HermesConfigDocument.restore(
        editedText: HermesConfigDocument.mask(_server).text,
        serverYaml: _server,
      );
      expect(restored.blockers, isEmpty);
      expect(restored.text, _server);
    });

    test('saving restores the original value in the written text', () {
      final edited = HermesConfigDocument.mask(_server).text
          .replaceFirst('model: sonnet', 'model: opus');
      final restored = HermesConfigDocument.restore(
        editedText: edited,
        serverYaml: _server,
      );
      expect(restored.text, contains('api_key: sk-123'));
      expect(restored.text, contains('FAL_KEY: y'));
      expect(restored.text, contains('model: opus'));
      expect(restored.text, _server.replaceFirst('sonnet', 'opus'));
    });

    test('the Steel browser block round-trips unchanged apart from the '
        'edited keys', () {
      final edited = HermesConfigDocument.mask(_server).text
          .replaceFirst('session_timeout: 300', 'session_timeout: 600');
      final written = HermesConfigDocument.restore(
        editedText: edited,
        serverYaml: _server,
      ).text!;
      expect(
        written,
        _server.replaceFirst('session_timeout: 300', 'session_timeout: 600'),
      );
      expect(written, contains('api_key: steel-live-secret-value'));
    });

    test('quoting of the original secret is kept', () {
      const server = "api_key: 'it''s a secret'\nmodel: a\n";
      final restored = HermesConfigDocument.restore(
        editedText: HermesConfigDocument.mask(server).text,
        serverYaml: server,
      );
      expect(restored.text, server);
    });

    test('a secret that cannot sit in a flow mapping is quoted', () {
      const server = 'api_key: a,b c\nmodel: a\n';
      final token = HermesConfigDocument.placeholderFor(const ['api_key']);
      final restored = HermesConfigDocument.restore(
        editedText: 'model: a\napi_key: $token\n',
        serverYaml: server,
      );
      expect(restored.text, 'model: a\napi_key: a,b c\n');
    });

    test('deleting a placeholder line removes that secret', () {
      final edited = HermesConfigDocument.mask(_server).text
          .split('\n')
          .where((line) => !line.startsWith('api_key:'))
          .join('\n');
      final restored = HermesConfigDocument.restore(
        editedText: edited,
        serverYaml: _server,
      );
      expect(restored.blockers, isEmpty);
      expect(restored.text, isNot(contains('sk-123')));
      expect(restored.text, isNot(contains('\napi_key: sk-123')));
      expect(restored.text, contains('apikey: x'));
    });

    test('a duplicated block with a placeholder blocks the save and never '
        'copies the secret', () {
      final masked = HermesConfigDocument.mask(_server).text;
      final edited = masked.replaceFirst(
        '  fal:\n    command: npx\n    auth: oauth\n    env:\n'
            '      FAL_KEY: ${HermesConfigDocument.placeholderFor(const ['mcp_servers', 'fal', 'env', 'FAL_KEY'])}\n',
        '  fal:\n    command: npx\n    auth: oauth\n    env:\n'
            '      FAL_KEY: ${HermesConfigDocument.placeholderFor(const ['mcp_servers', 'fal', 'env', 'FAL_KEY'])}\n'
            '  fal2:\n    command: npx\n    auth: oauth\n    env:\n'
            '      FAL_KEY: ${HermesConfigDocument.placeholderFor(const ['mcp_servers', 'fal', 'env', 'FAL_KEY'])}\n',
      );
      expect(edited, isNot(masked));
      final restored = HermesConfigDocument.restore(
        editedText: edited,
        serverYaml: _server,
      );
      expect(restored.text, isNull);
      expect(restored.blockers, hasLength(1));
      expect(restored.blockers.single.message, 'Re-enter this secret');
      expect(restored.blockers.single.key, 'mcp_servers.fal2.env.FAL_KEY');
    });

    test('a placeholder moved to another key is blocked', () {
      final token = HermesConfigDocument.placeholderFor(const ['api_key']);
      final restored = HermesConfigDocument.restore(
        editedText: 'model: a\nother_token: $token\n',
        serverYaml: _server,
      );
      expect(restored.text, isNull);
      expect(restored.blockers.single.key, 'other_token');
    });

    test('a placeholder inside a longer string is blocked, never written', () {
      final token = HermesConfigDocument.placeholderFor(const ['api_key']);
      final restored = HermesConfigDocument.restore(
        editedText: 'api_key: "Bearer $token"\n',
        serverYaml: 'api_key: sk-123\n',
      );
      expect(restored.text, isNull);
      expect(restored.blockers.single.message, 'Re-enter this secret');
    });

    test('restoring a backup whose secret was removed on the server blocks '
        'the save', () {
      final backup = HermesConfigDocument.mask(_server).text;
      final serverNow = _server.replaceFirst('api_key: sk-123\n', '');
      final restored = HermesConfigDocument.restore(
        editedText: backup,
        serverYaml: serverNow,
      );
      expect(restored.text, isNull);
      expect(restored.blockers.map((b) => b.key), contains('api_key'));
      expect(
        restored.blockers.every((b) => b.message == 'Re-enter this secret'),
        isTrue,
      );
    });

    test('an unreadable placeholder always blocks', () {
      final restored = HermesConfigDocument.restore(
        editedText: 'api_key: <secret:unreadable>\n',
        serverYaml: 'api_key: sk-123\n',
      );
      expect(restored.text, isNull);
    });

    test('a newly typed secret is written as typed', () {
      final restored = HermesConfigDocument.restore(
        editedText: 'api_key: sk-new-456\n',
        serverYaml: 'api_key: sk-123\n',
      );
      expect(restored.text, 'api_key: sk-new-456\n');
    });

    test('a changed secret on the server is kept, not overwritten by the '
        'value that was loaded', () {
      final edited = HermesConfigDocument.mask(_server).text;
      final rotated = _server.replaceFirst('sk-123', 'sk-rotated-999');
      final restored = HermesConfigDocument.restore(
        editedText: edited,
        serverYaml: rotated,
      );
      expect(restored.text, rotated);
    });
  });

  group('validation', () {
    test('invalid YAML is refused with its line', () {
      final result = HermesConfigDocument.validate('model: [a\nother: 1\n');
      expect(result.ok, isFalse);
      expect(result.errors.single.message, contains('Invalid YAML'));
      expect(result.errors.single.line, isNotNull);
    });

    test('a top-level list is refused as "must be a mapping"', () {
      final result = HermesConfigDocument.validate('- a\n- b\n');
      expect(result.ok, isFalse);
      expect(result.errors.single.message, contains('must be a mapping'));
    });

    test('an empty config is refused', () {
      expect(HermesConfigDocument.validate('  \n').ok, isFalse);
    });

    test('a known numeric key set to text is refused with the key named', () {
      final schema = _schema({
        'agent.max_turns': {'type': 'number'},
      });
      final result = HermesConfigDocument.validate(
        'agent:\n  max_turns: sk-secret-value-123\n',
        schema: schema,
      );
      expect(result.ok, isFalse);
      expect(result.errors.single.key, 'agent.max_turns');
      expect(result.errors.single.message, contains('agent.max_turns'));
      expect(result.errors.single.message, contains('number'));
      // The offending value is never echoed.
      expect(result.errors.single.message, isNot(contains('sk-secret')));
    });

    test('values of the right type pass', () {
      final schema = _schema({
        'agent.max_turns': {'type': 'number'},
        'agent.verbose': {'type': 'boolean'},
        'agent.name': {'type': 'string'},
        'agent.tags': {'type': 'list'},
      });
      expect(
        HermesConfigDocument.validate(
          'agent:\n  max_turns: 12\n  verbose: no\n  name: 7\n  tags: [a]\n',
          schema: schema,
        ).ok,
        isTrue,
      );
      expect(
        HermesConfigDocument.validate(
          'agent:\n  max_turns: 1.5\n  verbose: false\n  tags:\n',
          schema: schema,
        ).ok,
        isTrue,
      );
    });

    test('other wrong types are refused too', () {
      final schema = _schema({
        'agent.verbose': {'type': 'boolean'},
        'agent.tags': {'type': 'list'},
        'agent.name': {'type': 'string'},
      });
      for (final bad in [
        'agent:\n  verbose: "maybe"\n',
        'agent:\n  verbose: [1]\n',
        'agent:\n  tags: nope\n',
        'agent:\n  name: {a: 1}\n',
        'agent: 5\n',
      ]) {
        expect(
          HermesConfigDocument.validate(bad, schema: schema).ok,
          isFalse,
          reason: bad,
        );
      }
    });

    test('a select value outside its options only warns', () {
      final schema = _schema({
        'agent.effort': {
          'type': 'select',
          'options': ['low', 'high'],
        },
      });
      final result = HermesConfigDocument.validate(
        'agent:\n  effort: medium\n',
        schema: schema,
      );
      expect(result.ok, isTrue);
      expect(result.warnings, hasLength(1));
    });

    test('platform_toolsets and mcp_servers do not warn, a misspelled root '
        'does', () {
      final known = {'model', 'terminal', ...kHermesExtraKnownRootKeys};
      final fine = HermesConfigDocument.validate(
        'model: a\nplatform_toolsets:\n  cli: [web]\nmcp_servers: {}\n',
        knownRoots: known,
      );
      expect(fine.ok, isTrue);
      expect(fine.warnings, isEmpty);

      final typo = HermesConfigDocument.validate(
        'modle: a\n',
        knownRoots: known,
      );
      expect(typo.ok, isTrue);
      expect(typo.warnings.single.key, 'modle');
      expect(typo.warnings.single.message, contains('model'));
    });

    test('without a known-roots list nothing is flagged unknown', () {
      expect(HermesConfigDocument.validate('whatever: 1\n').warnings, isEmpty);
    });
  });

  group('diff', () {
    test('secrets never appear in the diff', () {
      final edited = HermesConfigDocument.mask(_server).text
          .replaceFirst('model: sonnet', 'model: opus');
      final written = HermesConfigDocument.restore(
        editedText: edited,
        serverYaml: _server,
      ).text!;
      final diff = HermesConfigDocument.diff(_server, written);
      final text = diff.lines.map((l) => l.text).join('\n');
      expect(text, isNot(contains('sk-123')));
      expect(text, isNot(contains('steel-live-secret-value')));
      expect(text, isNot(contains('FAL_KEY: y')));
      expect(text, isNot(contains('apikey: x\n')));
      expect(text, isNot(contains('sk-abcdefghijklmnop123')));
      expect(diff.hasChanges, isTrue);
      expect(diff.added, 1);
      expect(diff.removed, 1);
      expect(diff.changedRoots, {'model'});
      // Unchanged secrets produce no diff line.
      final changed = diff.lines.where((l) => l.kind != HermesDiffKind.same);
      expect(changed.map((l) => l.text), ['model: sonnet', 'model: opus']);
    });

    test('a changed secret shows as new, a typed value is never shown', () {
      final written = _server.replaceFirst('sk-123', 'sk-typed-value-9');
      final diff = HermesConfigDocument.diff(_server, written);
      final changed = diff.lines
          .where((l) => l.kind != HermesDiffKind.same)
          .map((l) => l.text)
          .toList();
      expect(changed, hasLength(2));
      expect(changed.last, 'api_key: <new secret>');
      expect(changed.join(), isNot(contains('sk-typed-value-9')));
      expect(changed.join(), isNot(contains('sk-123')));
    });

    test('identical documents have no changes', () {
      final diff = HermesConfigDocument.diff(_server, _server);
      expect(diff.hasChanges, isFalse);
      expect(diff.changedRoots, isEmpty);
      expect(diff.guardChanges, isEmpty);
    });

    test('a change under security is labelled as a guard change', () {
      final written = _server.replaceFirst(
        'redact_secrets: true',
        'redact_secrets: false',
      );
      final diff = HermesConfigDocument.diff(_server, written);
      expect(diff.guardChanges, hasLength(1));
      expect(diff.guardChanges.single.key, 'security.redact_secrets');
      expect(diff.guardChanges.single.from, 'true');
      expect(diff.guardChanges.single.to, 'false');
      expect(diff.guardRoots, {'security'});
      expect(
        diff.lines
            .where((l) => l.kind != HermesDiffKind.same)
            .every((l) => l.guardRoot == 'security'),
        isTrue,
      );
    });

    test('a change outside the guard roots is not labelled', () {
      final diff = HermesConfigDocument.diff(
        _server,
        _server.replaceFirst('timeout: 30', 'timeout: 60'),
      );
      expect(diff.guardChanges, isEmpty);
      expect(diff.guardRoots, isEmpty);
      expect(diff.lines.every((l) => l.guardRoot == null), isTrue);
    });

    test('a changed guard secret is described without its value', () {
      final written =
          '$_server'
          'approvals:\n  token: sk-guard-secret-1\n';
      final diff = HermesConfigDocument.diff(_server, written);
      expect(diff.guardChanges.single.key, 'approvals.token');
      expect(diff.guardChanges.single.to, '<secret>');
    });

    test('restart-needed roots are reported', () {
      final diff = HermesConfigDocument.diff(
        _server,
        _server.replaceFirst('command: npx', 'command: uvx'),
      );
      expect(diff.changedRoots, {'mcp_servers'});
      expect(diff.needsRestart, isTrue);
      expect(
        HermesConfigDocument.diff(
          _server,
          _server.replaceFirst('model: sonnet', 'model: opus'),
        ).needsRestart,
        isFalse,
      );
    });
  });

  group('on-device backups', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      PreferencesStore.debugOverride(await SharedPreferences.getInstance());
    });
    tearDown(PreferencesStore.debugReset);

    test('a backup is stored masked, newest first, 10 per scope', () async {
      const store = HermesPreferencesConfigBackupStore();
      for (var i = 0; i < 12; i++) {
        await store.add(
          'ops',
          _server.replaceFirst('timeout: 30', 'timeout: $i'),
          now: DateTime.utc(2026, 10, 6, 12, i),
        );
      }
      final backups = store.list('ops');
      expect(backups, hasLength(kHermesConfigBackupLimit));
      expect(backups.first.yaml, contains('timeout: 11'));
      expect(backups.last.yaml, contains('timeout: 2'));
      expect(backups.first.savedAt.isAfter(backups.last.savedAt), isTrue);

      // Nothing the detector flags is on the device in clear text.
      final stored = PreferencesStore.instance
          .getKeys()
          .map((k) => PreferencesStore.instance.getString(k) ?? '')
          .join('\n');
      expect(stored, isNot(contains('sk-123')));
      expect(stored, isNot(contains('steel-live-secret-value')));
      expect(stored, isNot(contains('FAL_KEY: y')));
      expect(stored, isNot(contains('apikey: x')));
      expect(stored, isNot(contains('sk-abcdefghijklmnop123')));
      expect(backups.first.yaml, contains('<secret:'));
    });

    test('a backup is masked even when the caller forgot to', () async {
      const store = HermesPreferencesConfigBackupStore();
      await store.add(null, _server);
      expect(store.list(null).single.yaml, isNot(contains('sk-123')));
    });

    test('scopes do not mix, and the root is its own scope', () async {
      const store = HermesPreferencesConfigBackupStore();
      await store.add(null, 'a: 1\n');
      await store.add('ops', 'b: 1\n');
      expect(store.list(null).single.yaml, 'a: 1\n');
      expect(store.list('ops').single.yaml, 'b: 1\n');
      expect(store.list('other'), isEmpty);
    });

    test('a backup that cannot be stored throws instead of silently '
        'dropping', () async {
      PreferencesStore.debugReset();
      await expectLater(
        const HermesPreferencesConfigBackupStore().add('ops', 'a: 1\n'),
        throwsStateError,
      );
    });
  });
}
