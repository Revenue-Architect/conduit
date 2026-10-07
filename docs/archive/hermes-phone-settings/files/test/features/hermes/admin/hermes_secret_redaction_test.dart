import 'package:conduit/features/hermes/admin/hermes_secret_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSecretKey', () {
    test('mirrors Hermes _SECRET_CONFIG_KEYS and adds cookie', () {
      for (final key in const [
        'api_key',
        'apikey',
        'key',
        'token',
        'access_token',
        'refresh_token',
        'id_token',
        'secret',
        'client_secret',
        'password',
        'passwd',
        'authorization',
        'private_key',
        'bearer',
        'jwt',
        'cookie',
        'Cookie',
        'API_KEY',
      ]) {
        expect(HermesSecretRedaction.isSecretKey(key), isTrue, reason: key);
      }
    });

    test('applies the 0.21.5 suffix rule to the leaf, folding - to _', () {
      for (final key in const [
        'openrouter_api_key',
        'github_token',
        'client_secret',
        'db_password',
        'signing_key',
        'aws_access_key',
        'X-Api-Key',
        'x-auth-token',
        'servers.github.my-token',
      ]) {
        expect(HermesSecretRedaction.isSecretKey(key), isTrue, reason: key);
      }
    });

    test('matches the plugin-pack substring pattern', () {
      for (final key in const [
        'api-key-header',
        'privateKey',
        'credentials',
        'passwordHash',
        'oauth_client',
        'author',
      ]) {
        expect(HermesSecretRedaction.isSecretKey(key), isTrue, reason: key);
      }
    });

    test('leaves ordinary keys alone', () {
      for (final key in const [
        'model',
        'provider',
        'base_url',
        'timeout',
        'enabled',
        'name',
        'transport',
      ]) {
        expect(HermesSecretRedaction.isSecretKey(key), isFalse, reason: key);
      }
    });

    test('does not mask a bare auth key that names a mode', () {
      expect(
        HermesSecretRedaction.isSecretKey('auth', value: 'oauth'),
        isFalse,
      );
      expect(
        HermesSecretRedaction.isSecretKey('auth', value: 'header'),
        isFalse,
      );
      expect(
        HermesSecretRedaction.isSecretKey('auth', value: 'bearer'),
        isFalse,
      );
      expect(
        HermesSecretRedaction.isSecretKey('auth', value: 'OAuth'),
        isFalse,
      );
      // The same key holding anything else is treated as a credential.
      expect(
        HermesSecretRedaction.isSecretKey('auth', value: 'hunter2hunter2'),
        isTrue,
      );
      expect(HermesSecretRedaction.isSecretKey('auth'), isTrue);
    });

    test(
      'env-routed keys are secret unless they end in a non-secret suffix',
      () {
        expect(HermesSecretRedaction.isSecretKey('TERMINAL_SSH_KEY'), isTrue);
        expect(HermesSecretRedaction.isSecretKey('TERMINAL_SSH_HOST'), isFalse);
        expect(HermesSecretRedaction.isSecretKey('FOO_API_KEY'), isTrue);
        expect(HermesSecretRedaction.isSecretKey('SERVICE_TOKEN'), isTrue);
      },
    );
  });

  group('isSecretAt and mask', () {
    test('masks the secret scalars of a config tree and nothing else', () {
      final tree = {
        'model': {
          'default': 'gpt-5',
          'provider': 'openai',
          'api_key': 'abc123',
        },
        'mcp_servers': {
          'github': {
            'url': 'https://example.test/mcp',
            'auth': 'oauth',
            'enabled': true,
          },
          'slack': {
            'command': 'npx',
            'env': {
              'SLACK_BOT_TOKEN': 'xoxb-1234567890-abcdef',
              'REGION': 'eu',
            },
            'headers': {'X-Api-Key': 'k', 'Content-Type': 'json'},
          },
        },
        'agent': {'max_tokens': 4096, 'reasoning_effort': 'high'},
      };
      final masked = HermesSecretRedaction.mask(tree)! as Map<Object?, Object?>;
      final model = masked['model']! as Map;
      expect(model['default'], 'gpt-5');
      expect(model['provider'], 'openai');
      expect(model['api_key'], kHermesMaskedValue);

      final servers = masked['mcp_servers']! as Map;
      final github = servers['github']! as Map;
      expect(github['auth'], 'oauth', reason: 'a mode is not a secret');
      expect(github['url'], 'https://example.test/mcp');
      expect(github['enabled'], true);

      final slack = servers['slack']! as Map;
      expect(slack['command'], 'npx');
      // Every scalar under env and headers is masked, like _redact_mcp_env.
      expect((slack['env']! as Map).values, everyElement(kHermesMaskedValue));
      expect(
        (slack['headers']! as Map).values,
        everyElement(kHermesMaskedValue),
      );

      final agent = masked['agent']! as Map;
      expect(agent['max_tokens'], 4096, reason: 'a count is not a credential');
      expect(agent['reasoning_effort'], 'high');
    });

    test('leaves env references, empty values, booleans and null readable', () {
      final tree = {
        'api_key': r'${OPENAI_API_KEY}',
        'token': '',
        'secret': null,
        'password': false,
      };
      expect(HermesSecretRedaction.findSecretPaths(tree), isEmpty);
    });

    test('masks a vendor token wherever it sits', () {
      final tree = {
        'notes': 'ghp_abcdefghijklmnopqrstuvwxyz0123456789',
        'list': ['sk-proj-abcdefghijklmnop', 'plain'],
      };
      final paths = HermesSecretRedaction.findSecretPaths(tree);
      expect(paths, [
        ['notes'],
        ['list', 0],
      ]);
    });

    test('a masker can bind a placeholder to the key path', () {
      final masked =
          HermesSecretRedaction.mask({
                'a': {'api_key': 'one'},
                'b': {'api_key': 'two'},
              }, masker: (path, value) => '<<${path.join('.')}>>')!
              as Map;
      expect((masked['a']! as Map)['api_key'], '<<a.api_key>>');
      expect((masked['b']! as Map)['api_key'], '<<b.api_key>>');
    });

    test(
      'a number under a Hermes secret key is masked, a loose match is not',
      () {
        expect(
          HermesSecretRedaction.isSecretAt(const ['password'], 123456),
          isTrue,
        );
        expect(
          HermesSecretRedaction.isSecretAt(const ['max_tokens'], 4096),
          isFalse,
        );
      },
    );

    test('secretValuesIn collects the values to scrub by value', () {
      expect(
        HermesSecretRedaction.secretValuesIn({
          'model': {'api_key': 'secret-one'},
          'name': 'visible',
        }),
        {'secret-one'},
      );
    });
  });

  group('vendor token patterns', () {
    test('match the agent/redact.py prefixes as whole tokens', () {
      for (final token in const [
        'sk-abcdefghijklmnop',
        'sk-ant-api03-abcdefghijklmnop',
        'ghp_abcdefghijklmnopqrstuvwxyz',
        'github_pat_abcdefghijklmnop',
        'xoxb-1234567890-abcdef',
        'AKIAABCDEFGHIJKLMNOP',
        'hf_abcdefghijklmnop',
        'glpat-abcdefghijklmnop',
        'pk-lf-abcdefgh',
        'xai-abcdefghijklmnopqrstuvwxyz0123456789',
      ]) {
        expect(
          HermesSecretRedaction.looksLikeSecretValue(token),
          isTrue,
          reason: token,
        );
      }
    });

    test('match JWTs, PEM private keys and Telegram bot tokens', () {
      expect(
        HermesSecretRedaction.looksLikeSecretValue(
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcd1234',
        ),
        isTrue,
      );
      expect(
        HermesSecretRedaction.looksLikeSecretValue(
          '-----BEGIN RSA PRIVATE KEY-----\nMIIE\n-----END RSA PRIVATE KEY-----',
        ),
        isTrue,
      );
      expect(
        HermesSecretRedaction.looksLikeSecretValue(
          '123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw0',
        ),
        isTrue,
      );
    });

    test('ordinary words and short strings are not tokens', () {
      for (final value in const ['hello', 'sk-short', 'gpt-5', 'main', '']) {
        expect(
          HermesSecretRedaction.looksLikeSecretValue(value),
          isFalse,
          reason: value,
        );
      }
    });
  });

  group('redactText', () {
    test('scrubs exact values, vendor tokens and credential assignments', () {
      const typed = 'hunter2-typed-value';
      final out = HermesSecretRedaction.redactText(
        'Rejected $typed; sk-abcdefghijklmnop leaked; api_key: abc12345; '
        'Authorization: Bearer abcdefgh12345678; '
        'postgres://user:pa55word@db.example/x',
        secrets: const [typed],
      );
      expect(out, isNot(contains(typed)));
      expect(out, isNot(contains('sk-abcdefghijklmnop')));
      expect(out, isNot(contains('abc12345')));
      expect(out, isNot(contains('abcdefgh12345678')));
      expect(out, isNot(contains('pa55word')));
      expect(out, contains('db.example'));
    });

    test('keeps ordinary error text readable', () {
      const message = "Profile 'ops' does not exist.";
      expect(HermesSecretRedaction.redactText(message), message);
    });

    test('does not shred text with a very short secret', () {
      expect(
        HermesSecretRedaction.redactText(
          'a plain sentence',
          secrets: const ['a'],
        ),
        'a plain sentence',
      );
    });

    test('scrubs parser text that quotes a config line', () {
      final out = HermesSecretRedaction.redactText(
        'Invalid YAML: while scanning, in "<unicode string>", line 4:\n'
        '    api_key: "sk-proj-abcdefghijklmnop"\n',
      );
      expect(out, isNot(contains('sk-proj-abcdefghijklmnop')));
      expect(out, contains('Invalid YAML'));
    });
  });

  group('secretValuesInYamlText', () {
    test('finds the values under secret keys without parsing the document', () {
      const yaml = '''
model:
  default: gpt-5
  api_key: "sk-proj-abcdefghijklmnop"
mcp_servers:
  github:
    auth: oauth
    headers:
      Authorization: Bearer abc123def456
  other:
    token: \${REFERENCE}
''';
      expect(
        HermesSecretRedaction.secretValuesInYamlText(yaml),
        containsAll(['sk-proj-abcdefghijklmnop', 'Bearer abc123def456']),
      );
      expect(
        HermesSecretRedaction.secretValuesInYamlText(yaml),
        isNot(contains('oauth')),
      );
      expect(
        HermesSecretRedaction.secretValuesInYamlText(yaml),
        isNot(contains(r'${REFERENCE}')),
      );
    });
  });

  test('preview shows at most the last four characters', () {
    expect(HermesSecretRedaction.preview('sk-abcdefghijklmnop'), '****mnop');
    expect(HermesSecretRedaction.preview('short'), '****');
  });
}
