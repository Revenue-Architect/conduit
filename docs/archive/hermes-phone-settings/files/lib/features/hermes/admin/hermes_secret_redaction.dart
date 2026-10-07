/// The one secret detector for the Hermes admin surface (KTD9).
///
/// The admin client scrubs server error text with it, and the advanced config
/// editor masks values, diffs and on-device backups with it. It mirrors what
/// Hermes 0.21.5 redacts itself, so the app never shows a value Hermes would
/// have hidden:
///
/// - `_SECRET_CONFIG_KEYS` plus the suffix rule `_SECRET_CONFIG_KEY_SUFFIXES`
///   (`hermes_cli/config.py`), judged on the leaf key, lower-cased, with `-`
///   folded to `_` so header names such as `X-Api-Key` match;
/// - the substring pattern `_SECRET_KEY_RE` (`hermes_cli/plugin_packs.py`);
/// - every non-empty scalar under an `env` or `headers` mapping, like
///   `_redact_mcp_env` (`hermes_cli/web_server_mcp.py`);
/// - the vendor token prefixes of `agent/redact.py`.
///
/// `cookie` is added on top, per KTD9.
///
/// Deliberate difference: the substring pattern contains `auth`, which would
/// mask `mcp_servers.<name>.auth: oauth`. That value is a mode, not a secret,
/// and Hermes' own `_SECRET_CONFIG_KEYS` excludes bare `auth` for the same
/// reason. A bare `auth` key holding a known mode is therefore left readable.
/// Anything else that merely contains `auth` (`author`, `oauth_client`) is
/// still masked: over-masking is safe, a leak is not.
library;

/// The mask shown where a secret value was.
const String kHermesMaskedValue = '********';

/// Hermes `_SECRET_CONFIG_KEYS`, plus `cookie` (KTD9).
const Set<String> kHermesSecretConfigKeys = {
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
};

/// Hermes `_SECRET_CONFIG_KEY_SUFFIXES`.
const List<String> kHermesSecretConfigKeySuffixes = [
  '_api_key',
  '_token',
  '_secret',
  '_password',
  '_key',
  '_access_key',
];

/// Hermes `_NON_SECRET_KEY_SUFFIXES`; they only clear env-routed keys.
const List<String> kHermesNonSecretKeySuffixes = [
  '_url',
  '_host',
  '_user',
  '_id',
  '_domain',
  '_scheme',
];

/// Values an `auth` key holds when it names a mode instead of a credential.
const Set<String> kHermesAuthModes = {'oauth', 'header', 'bearer', 'none'};

/// Parent keys whose scalar children are all treated as secret.
const Set<String> _kSecretMappingKeys = {'env', 'headers', 'extra_headers'};

/// Hermes `_SECRET_KEY_RE`.
final RegExp _secretKeyPattern = RegExp(
  r'(token|secret|passw(or)?d|api[_-]?key|private[_-]?key|credential|auth)',
  caseSensitive: false,
);

final RegExp _envReferencePattern = RegExp(r'^\$\{[A-Za-z_][A-Za-z0-9_]*\}$');

/// `agent/redact.py` `_PREFIX_PATTERNS`, verbatim. Each is wrapped so it
/// only matches a whole token, as Hermes does.
const List<String> _vendorPrefixPatterns = [
  r'sk-[A-Za-z0-9_-](?:\.?[A-Za-z0-9_-]){9,}',
  r'ghp_[A-Za-z0-9]{10,}',
  r'github_pat_[A-Za-z0-9_]{10,}',
  r'gho_[A-Za-z0-9]{10,}',
  r'ghu_[A-Za-z0-9]{10,}',
  r'ghs_[A-Za-z0-9]{10,}',
  r'ghr_[A-Za-z0-9]{10,}',
  r'xapp-\d+-[A-Za-z0-9-]{10,}',
  r'xox[baprs]-[A-Za-z0-9-]{10,}',
  r'AIza[A-Za-z0-9_-]{30,}',
  r'pplx-[A-Za-z0-9]{10,}',
  r'fal_[A-Za-z0-9_-]{10,}',
  r'fc-[A-Za-z0-9]{10,}',
  r'bb_live_[A-Za-z0-9_-]{10,}',
  r'gAAAA[A-Za-z0-9_=-]{20,}',
  r'AKIA[A-Z0-9]{16}',
  r'sk_live_[A-Za-z0-9]{10,}',
  r'sk_test_[A-Za-z0-9]{10,}',
  r'rk_live_[A-Za-z0-9]{10,}',
  r'SG\.[A-Za-z0-9_-]{10,}',
  r'hf_[A-Za-z0-9]{10,}',
  r'r8_[A-Za-z0-9]{10,}',
  r'npm_[A-Za-z0-9]{10,}',
  r'pypi-[A-Za-z0-9_-]{10,}',
  r'dop_v1_[A-Za-z0-9]{10,}',
  r'doo_v1_[A-Za-z0-9]{10,}',
  r'am_(?:org_)?[A-Za-z0-9]{20,}',
  r'sk_[A-Za-z0-9_]{10,}',
  r'tvly-[A-Za-z0-9]{10,}',
  r'exa_[A-Za-z0-9]{10,}',
  r'gsk_[A-Za-z0-9]{10,}',
  r'syt_[A-Za-z0-9]{10,}',
  r'retaindb_[A-Za-z0-9]{10,}',
  r'hsk-[A-Za-z0-9]{10,}',
  r'mem0_[A-Za-z0-9]{10,}',
  r'brv_[A-Za-z0-9]{10,}',
  r'xai-[A-Za-z0-9]{30,}',
  r'ntn_[A-Za-z0-9]{10,}',
  r'fw-[A-Za-z0-9]{30,}',
  r'fw_[A-Za-z0-9]{30,}',
  r'fpk_[A-Za-z0-9]{30,}',
  r'glpat-[A-Za-z0-9_\-]{10,}',
  r'gloas-[A-Za-z0-9_\-]{10,}',
  r'gldt-[A-Za-z0-9_\-]{10,}',
  r'glrt-[A-Za-z0-9_.\-]{10,}',
  r'glrtr-[A-Za-z0-9_.\-]{10,}',
  r'glcbt-[A-Za-z0-9_\-]{10,}',
  r'glptt-[A-Za-z0-9_\-]{10,}',
  r'glft-[A-Za-z0-9_\-]{10,}',
  r'glimt-[A-Za-z0-9_\-]{10,}',
  r'glagent-[A-Za-z0-9_\-]{10,}',
  r'glsoat-[A-Za-z0-9_\-]{10,}',
  r'glffct-[A-Za-z0-9_\-]{10,}',
  r'glwt-[A-Za-z0-9_\-]{10,}',
  r'GR1348941[A-Za-z0-9_\-]{10,}',
  r'pk-lf-[A-Za-z0-9\-]{8,}',
];

final RegExp _vendorTokenPattern = RegExp(
  '(?<![A-Za-z0-9_-])(?:${_vendorPrefixPatterns.join('|')})(?![A-Za-z0-9_-])',
);

/// `_JWT_RE`.
final RegExp _jwtPattern = RegExp(
  r'eyJ[A-Za-z0-9_-]{10,}(?:\.[A-Za-z0-9_=-]{4,}){0,2}',
);

/// `_PRIVATE_KEY_RE`: a PEM private-key block (or an unterminated start).
final RegExp _privateKeyPattern = RegExp(
  r'-----BEGIN [A-Z ]*PRIVATE KEY-----(?:[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----|[\s\S]*$)',
);

/// `_TELEGRAM_RE`.
final RegExp _telegramPattern = RegExp(
  r'(?<!\d)(?:bot)?\d{8,}:[-A-Za-z0-9_]{30,}',
);

/// `scheme://user:password@host`.
final RegExp _urlUserinfoPattern = RegExp(
  r'([A-Za-z][A-Za-z0-9+.\-]*://)[^\s/@:]+:[^\s/@]+@',
);

final RegExp _bearerPattern = RegExp(
  r'(bearer\s+)[A-Za-z0-9._~+/=\-]{8,}',
  caseSensitive: false,
);

/// `secret_key: value` / `secret_key=value` inside free text, such as the
/// YAML parser text Hermes echoes back in an `Invalid YAML` error.
final RegExp _assignmentPattern = RegExp(
  r'''([A-Za-z0-9_.\-]*(?:token|secret|passw(?:or)?d|api[_-]?key|private[_-]?key|credential|authorization|cookie)[A-Za-z0-9_.\-]*["']?\s*[:=]\s*)("[^"\n]*"|'[^'\n]*'|[^\s,;}\]]+)''',
  caseSensitive: false,
);

/// Shortest exact value that is scrubbed from text by value. Shorter ones
/// would shred ordinary words.
const int _minScrubbedValueLength = 4;

/// Secret detection and masking. Pure functions; no I/O.
abstract final class HermesSecretRedaction {
  /// Whether [key] names a secret, judged on its leaf segment as Hermes
  /// does. [value] only matters for a bare `auth` key, which holds a mode, and
  /// for numbers: a number is masked only by Hermes' own key rules, never by
  /// the loose substring pattern, so `max_tokens: 4096` stays readable.
  static bool isSecretKey(String key, {Object? value}) {
    final leaf = _leaf(key);
    if (leaf.isEmpty) return false;
    if (leaf == 'auth' &&
        value is String &&
        kHermesAuthModes.contains(value.trim().toLowerCase())) {
      return false;
    }
    if (_isEnvRouted(key) &&
        kHermesNonSecretKeySuffixes.any(key.toLowerCase().endsWith)) {
      return false;
    }
    return kHermesSecretConfigKeys.contains(leaf) ||
        kHermesSecretConfigKeySuffixes.any(leaf.endsWith) ||
        _isEnvRouted(key) ||
        (value is! num && _secretKeyPattern.hasMatch(leaf));
  }

  /// Whether [value] is shaped like a credential, wherever it sits.
  static bool looksLikeSecretValue(String value) {
    if (value.isEmpty) return false;
    return _vendorTokenPattern.hasMatch(value) ||
        _jwtPattern.hasMatch(value) ||
        _privateKeyPattern.hasMatch(value) ||
        _telegramPattern.hasMatch(value);
  }

  /// Whether the scalar [value] at [path] must be masked. [path] holds
  /// map keys (as strings) and list indexes (as ints), outermost first.
  static bool isSecretAt(List<Object> path, Object? value) {
    if (value == null || value is bool) return false;
    if (value is! String && value is! num) return false;
    if (value is String && value.isEmpty) return false;
    if (_underSecretMapping(path)) return true;
    final key = _lastKey(path);
    if (key != null && isSecretKey(key, value: value)) {
      // A `${VAR}` reference is the safe form: it names the secret without
      // holding it (Hermes' redact_config_value skips it too).
      return !(value is String && _envReferencePattern.hasMatch(value));
    }
    return value is String && looksLikeSecretValue(value);
  }

  /// Every scalar path in [tree] that [isSecretAt] flags.
  static List<List<Object>> findSecretPaths(Object? tree) {
    final found = <List<Object>>[];
    _walk(tree, const [], (path, value) {
      if (isSecretAt(path, value)) found.add(path);
    });
    return found;
  }

  /// The secret values themselves, for scrubbing text by value.
  static Set<String> secretValuesIn(Object? tree) {
    final values = <String>{};
    _walk(tree, const [], (path, value) {
      if (isSecretAt(path, value)) values.add(value.toString());
    });
    return values;
  }

  /// A copy of [tree] with every secret scalar replaced. [masker] returns the
  /// replacement for the value at a path; the default is [kHermesMaskedValue].
  static Object? mask(
    Object? tree, {
    String Function(List<Object> path, Object value)? masker,
  }) => _maskNode(tree, const [], masker);

  /// The secret values in YAML source text, found line by line without a YAML
  /// parser. Used only to scrub error text; the config editor parses properly.
  static Set<String> secretValuesInYamlText(String text) {
    final values = <String>{};
    final line = RegExp(
      r'''^\s*(?:-\s+)?["']?([A-Za-z0-9_.\-]+)["']?\s*:\s*(?:"([^"\n]*)"|'([^'\n]*)'|([^\s#][^#\n]*?))\s*(?:#.*)?$''',
    );
    for (final raw in text.split('\n')) {
      final match = line.firstMatch(raw);
      if (match == null) continue;
      final value = (match.group(2) ?? match.group(3) ?? match.group(4) ?? '')
          .trim();
      if (value.isEmpty || _envReferencePattern.hasMatch(value)) continue;
      if (isSecretKey(match.group(1)!, value: value) ||
          looksLikeSecretValue(value)) {
        values.add(value);
      }
    }
    return values;
  }

  /// Free [text] with credential-shaped content removed. Use it on anything
  /// the server echoes back before it reaches a log line or the screen.
  /// [secrets] are exact values the caller knows it just sent. Text beyond
  /// 20,000 characters is cut first, which also bounds the pattern work.
  static String redactText(String text, {Iterable<String> secrets = const []}) {
    var out = text.length > 20000 ? text.substring(0, 20000) : text;
    for (final secret in secrets) {
      if (secret.length >= _minScrubbedValueLength) {
        out = out.replaceAll(secret, '***');
      }
    }
    out = out
        .replaceAll(_privateKeyPattern, '***')
        .replaceAllMapped(_urlUserinfoPattern, (m) => '${m.group(1)}***@')
        .replaceAllMapped(_bearerPattern, (m) => '${m.group(1)}***')
        .replaceAllMapped(_assignmentPattern, (m) => '${m.group(1)}***')
        .replaceAll(_vendorTokenPattern, '***')
        .replaceAll(_jwtPattern, '***')
        .replaceAll(_telegramPattern, '***');
    return out;
  }

  /// What may be shown of a saved value: never more than its last four
  /// characters, and nothing for a short one.
  static String preview(String value) =>
      value.length >= 12 ? '****${value.substring(value.length - 4)}' : '****';

  static String _leaf(String key) =>
      key.split('.').last.toLowerCase().replaceAll('-', '_');

  /// Hermes `_is_env_config_key`: a dotless key that looks like an env var.
  static bool _isEnvRouted(String key) {
    if (key.contains('.')) return false;
    final upper = key.toUpperCase();
    return upper.endsWith('_API_KEY') ||
        upper.endsWith('_TOKEN') ||
        upper.endsWith('_SECRET') ||
        upper.startsWith('TERMINAL_SSH');
  }

  static String? _lastKey(List<Object> path) {
    for (var i = path.length - 1; i >= 0; i--) {
      if (path[i] is String) return path[i] as String;
    }
    return null;
  }

  /// Whether any ancestor of the scalar at [path] is an `env` or `headers`
  /// mapping.
  static bool _underSecretMapping(List<Object> path) {
    for (var i = 0; i < path.length - 1; i++) {
      final key = path[i];
      if (key is String && _kSecretMappingKeys.contains(key.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  static void _walk(
    Object? node,
    List<Object> path,
    void Function(List<Object> path, Object? value) visit,
  ) {
    if (node is Map) {
      for (final entry in node.entries) {
        _walk(entry.value, [...path, entry.key.toString()], visit);
      }
    } else if (node is List) {
      for (var i = 0; i < node.length; i++) {
        _walk(node[i], [...path, i], visit);
      }
    } else {
      visit(path, node);
    }
  }

  static Object? _maskNode(
    Object? node,
    List<Object> path,
    String Function(List<Object> path, Object value)? masker,
  ) {
    if (node is Map) {
      return {
        for (final entry in node.entries)
          entry.key: _maskNode(entry.value, [
            ...path,
            entry.key.toString(),
          ], masker),
      };
    }
    if (node is List) {
      return [
        for (var i = 0; i < node.length; i++)
          _maskNode(node[i], [...path, i], masker),
      ];
    }
    if (node != null && isSecretAt(path, node)) {
      return masker == null ? kHermesMaskedValue : masker(path, node);
    }
    return node;
  }
}
