/// The advanced config editor's document logic (KTD9): masks secrets in a
/// config's YAML text, restores them on save, diffs two versions and checks a
/// document before it is written. Pure functions over text; no I/O.
///
/// - **Masking.** `GET /api/config/raw` returns the file unredacted, so every
///   scalar the shared detector ([HermesSecretRedaction]) flags is replaced in
///   the text by a placeholder, `<secret:xxxxxxxx>`. Only the value is
///   replaced, so comments, layout and quoting of everything else survive.
///   The placeholder carries a hash of its key path, which is what binds it
///   to that path.
/// - **Restoring.** A placeholder goes back to the server's value only when it
///   still sits at the path it was made for and the fresh read still has a
///   value there. One that moved, was copied, sits inside longer text or has
///   no source value blocks the save ("Re-enter this secret"). The original
///   secret is never copied to a second place.
/// - **Diffing** works on masked text, so a diff, a review and an on-device
///   backup never hold a secret. A changed secret shows as `<new secret>`.
/// - **Validating** parses the YAML, requires a mapping, checks known keys
///   against the server's schema and warns about unknown root keys.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

import 'hermes_admin_models.dart';
import 'hermes_secret_redaction.dart';

/// Roots whose changes are labelled in the diff and need a second
/// confirmation: what the bot may do without asking, and who may reach it.
const Set<String> kHermesGuardRoots = {'approvals', 'security', 'dashboard'};

/// Roots read once at start-up (plugins, MCP servers, platform adapters, the
/// dashboard itself). A change here is "restart needed"; anything else
/// applies to new chats.
const Set<String> kHermesRestartRoots = {
  'plugins',
  'mcp_servers',
  'platforms',
  'gateway',
  'dashboard',
  'proxy',
  'network',
  'profile_routes',
  'multiplex_profiles',
  'discord',
  'slack',
  'telegram',
  'whatsapp',
  'matrix',
  'mattermost',
  'signal',
};

/// What the editor says for a placeholder that cannot be restored.
const String kHermesReenterSecret = 'Re-enter this secret';

/// What a changed or added secret shows as in a diff.
const String kHermesNewSecretMask = '<new secret>';

/// Longest document the editor handles; Hermes configs run to a few KB.
const int kHermesConfigMaxChars = 512 * 1024;

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

enum HermesConfigIssueSeverity { error, warning }

/// One thing the editor tells the owner about the document.
final class HermesConfigIssue {
  const HermesConfigIssue(this.severity, this.message, {this.key, this.line});

  final HermesConfigIssueSeverity severity;

  /// Safe to show: it never holds a config value.
  final String message;

  /// The dotted key it is about, when it is about one.
  final String? key;

  /// The 1-based line it is about, when known.
  final int? line;

  @override
  String toString() => '${severity.name}: $message';
}

/// The outcome of [HermesConfigDocument.validate].
final class HermesConfigValidation {
  const HermesConfigValidation(this.issues);

  final List<HermesConfigIssue> issues;

  Iterable<HermesConfigIssue> get errors =>
      issues.where((i) => i.severity == HermesConfigIssueSeverity.error);

  Iterable<HermesConfigIssue> get warnings =>
      issues.where((i) => i.severity == HermesConfigIssueSeverity.warning);

  /// False when the document must not be written.
  bool get ok => errors.isEmpty;
}

/// A document's text with its secrets hidden.
final class HermesConfigMasked {
  const HermesConfigMasked({
    required this.text,
    required this.maskedKeys,
    required this.commentsScrubbed,
  });

  final String text;

  /// The dotted keys whose values were replaced.
  final List<String> maskedKeys;

  /// How many comments held a credential-like word. Those are hidden as `***`
  /// and stay that way if the document is saved.
  final int commentsScrubbed;
}

/// The outcome of [HermesConfigDocument.restore].
final class HermesConfigRestore {
  const HermesConfigRestore._(this.text, this.blockers);

  /// The document to write, with every placeholder replaced by the server's
  /// value. Null when [blockers] is not empty.
  final String? text;

  /// Every placeholder that cannot be restored, each "Re-enter this secret".
  final List<HermesConfigIssue> blockers;

  bool get ok => text != null;
}

enum HermesDiffKind { same, added, removed }

/// One line of a diff.
final class HermesDiffLine {
  const HermesDiffLine({
    required this.kind,
    required this.text,
    this.oldNumber,
    this.newNumber,
    this.guardRoot,
  });

  final HermesDiffKind kind;

  /// Masked text.
  final String text;
  final int? oldNumber;
  final int? newNumber;

  /// The guard root (`approvals`, `security`, `dashboard`) a changed line
  /// sits under; null for other lines.
  final String? guardRoot;
}

/// One setting under a guard root that differs between two versions.
final class HermesGuardChange {
  const HermesGuardChange({
    required this.key,
    required this.from,
    required this.to,
  });

  final String key;

  /// Display text; a secret is `<secret>`.
  final String from;
  final String to;
}

/// What changes between the server's file and the one about to be written.
final class HermesConfigDiff {
  const HermesConfigDiff({
    required this.lines,
    required this.changedRoots,
    required this.guardChanges,
  });

  final List<HermesDiffLine> lines;

  /// Root keys whose value differs.
  final Set<String> changedRoots;
  final List<HermesGuardChange> guardChanges;

  bool get hasChanges => lines.any((l) => l.kind != HermesDiffKind.same);
  int get added => lines.where((l) => l.kind == HermesDiffKind.added).length;
  int get removed =>
      lines.where((l) => l.kind == HermesDiffKind.removed).length;

  /// The guard roots that changed.
  Set<String> get guardRoots => {
    for (final change in guardChanges) change.key.split('.').first,
    for (final line in lines)
      if (line.guardRoot != null) line.guardRoot!,
  };

  /// Whether a changed root is read only at start-up.
  bool get needsRestart => changedRoots.any(kHermesRestartRoots.contains);
}

// ---------------------------------------------------------------------------
// The document
// ---------------------------------------------------------------------------

abstract final class HermesConfigDocument {
  static final RegExp _tokenPattern = RegExp(
    r'<secret:(?:[0-9a-f]{8}|unreadable)>',
  );
  static final RegExp _wholeTokenPattern = RegExp(
    r'^<secret:(?:[0-9a-f]{8}|unreadable)>$',
  );

  /// An anchor or tag in front of a scalar's text (`&a `, `!!str `).
  static final RegExp _propertyPrefix = RegExp(r'^(?:[&!]\S*\s+)+');

  /// What a plain scalar may hold inside a flow collection.
  static final RegExp _flowSafe = RegExp(r'^[A-Za-z0-9_./+=@-]+$');

  /// The placeholder for the value at [path]: `<secret:` and eight hex digits
  /// of a hash of the path. It says nothing about the value.
  static String placeholderFor(List<Object> path) =>
      '<secret:${_pathHash(path)}>';

  static String _pathHash(List<Object> path) =>
      sha256.convert(utf8.encode(jsonEncode(path))).toString().substring(0, 8);

  static String _pathKey(List<Object> path) => jsonEncode(path);

  /// `mcp_servers.fal.env.FAL_KEY`, `fallbacks[0].api_key`.
  static String _dotted(List<Object> path) {
    final out = StringBuffer();
    for (final part in path) {
      if (part is int) {
        out.write('[$part]');
      } else {
        if (out.isNotEmpty) out.write('.');
        out.write(part);
      }
    }
    return out.toString();
  }

  static bool _isToken(Object? value) =>
      value is String && _wholeTokenPattern.hasMatch(value);

  static YamlNode? _parse(String text) {
    if (text.length > kHermesConfigMaxChars) return null;
    try {
      return loadYamlNode(text);
    } on YamlException {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Masking
  // -------------------------------------------------------------------------

  /// [raw] with every secret value replaced by its placeholder. Idempotent:
  /// masking masked text changes nothing.
  static HermesConfigMasked mask(String raw) {
    final tree = _maskTree(raw, (path, _) => placeholderFor(path));
    final masked = tree ?? _maskUnparsed(raw);
    final (text, scrubbed) = _scrubComments(masked.text);
    return HermesConfigMasked(
      text: text,
      maskedKeys: masked.keys,
      commentsScrubbed: scrubbed,
    );
  }

  /// Replaces each secret scalar of [raw] by what [tokenFor] returns, or null
  /// when [raw] does not parse. Placeholders already in the text stay.
  static ({String text, List<String> keys})? _maskTree(
    String raw,
    String Function(List<Object> path, Object? value) tokenFor,
  ) {
    final root = _parse(raw);
    if (root == null) return null;
    final edits = <_Edit>[];
    final keys = <String>[];
    final seen = <int>{};
    _walk(root, const [], false, (path, node, _) {
      if (_isToken(node.value)) return;
      if (!HermesSecretRedaction.isSecretAt(path, node.value)) return;
      // An alias resolves to the anchored node: one value, one edit.
      if (!seen.add(node.span.start.offset)) return;
      edits.add(_Edit.scalar(node, tokenFor(path, node.value)));
      keys.add(_dotted(path));
    });
    return (text: _apply(raw, edits), keys: keys);
  }

  /// A document that does not parse cannot be walked, so its secrets are found
  /// line by line. Their placeholders are unreadable: they can never be
  /// restored, so saving over one means typing the secret again.
  static ({String text, List<String> keys}) _maskUnparsed(String raw) {
    final keys = <String>[];
    final lines = raw.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      final values = HermesSecretRedaction.secretValuesInYamlText(line);
      if (values.isEmpty) continue;
      final colon = line.indexOf(':');
      for (final value in values) {
        final at = line.lastIndexOf(value);
        if (at > colon) {
          line = line.replaceRange(
            at,
            at + value.length,
            '<secret:unreadable>',
          );
        }
      }
      lines[i] = line;
      keys.add('line ${i + 1}');
    }
    return (text: lines.join('\n'), keys: keys);
  }

  /// Hides credential-shaped words in comments. A comment is not a value, so
  /// it cannot be restored: it stays `***`.
  static (String, int) _scrubComments(String text) {
    if (!text.contains('#')) return (text, 0);
    var count = 0;
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      var start = -1;
      for (var c = 0; c < line.length; c++) {
        if (line[c] == '#' &&
            (c == 0 || line[c - 1] == ' ' || line[c - 1] == '\t')) {
          start = c;
          break;
        }
      }
      if (start < 0) continue;
      final comment = line.substring(start);
      final cleaned = comment.replaceAllMapped(
        RegExp(r'''[^\s"',;()\[\]{}<>]+'''),
        (m) =>
            HermesSecretRedaction.looksLikeSecretValue(m[0]!) ? '***' : m[0]!,
      );
      if (cleaned != comment) {
        lines[i] = line.substring(0, start) + cleaned;
        count++;
      }
    }
    return (lines.join('\n'), count);
  }

  // -------------------------------------------------------------------------
  // Restoring
  // -------------------------------------------------------------------------

  /// [editedText] (placeholders and all) with each placeholder replaced by the
  /// value [serverYaml] holds at the same key path. [serverYaml] is a fresh
  /// read, so a secret rotated since the editor loaded is kept as it is now.
  static HermesConfigRestore restore({
    required String editedText,
    required String serverYaml,
  }) {
    final edited = _parse(editedText);
    if (edited == null) {
      return const HermesConfigRestore._(null, [
        HermesConfigIssue(
          HermesConfigIssueSeverity.error,
          'The config is not valid YAML.',
        ),
      ]);
    }
    final server = _parse(serverYaml);
    final source = <String, YamlScalar>{};
    if (server != null) {
      _walk(server, const [], false, (path, node, _) {
        source[_pathKey(path)] = node;
      });
    }

    final edits = <_Edit>[];
    final blockers = <HermesConfigIssue>[];
    final seen = <int>{};

    void block(List<Object> path, YamlScalar node) {
      blockers.add(
        HermesConfigIssue(
          HermesConfigIssueSeverity.error,
          kHermesReenterSecret,
          key: _dotted(path),
          line: node.span.start.line + 1,
        ),
      );
    }

    _walk(
      edited,
      const [],
      false,
      (path, node, inFlow) {
        final value = node.value;
        if (value is! String || !_tokenPattern.hasMatch(value)) return;
        if (!seen.add(node.span.start.offset)) return;
        // A token must be the whole value, and made for this very path.
        final whole = _wholeTokenPattern.hasMatch(value);
        final boundHere = value == placeholderFor(path);
        final original = source[_pathKey(path)];
        final originalValue = original?.value;
        final restorable =
            whole &&
            boundHere &&
            original != null &&
            originalValue != null &&
            originalValue.toString().isNotEmpty &&
            !_isToken(originalValue);
        if (!restorable) {
          block(path, node);
          return;
        }
        edits.add(_Edit.scalar(node, _serialize(original, inFlow)));
      },
      visitKey: (path, node) {
        // A placeholder used as a key can only be a mistake.
        if (node.value is String &&
            _tokenPattern.hasMatch(node.value as String)) {
          block(path, node);
        }
      },
    );
    if (blockers.isNotEmpty) return HermesConfigRestore._(null, blockers);
    return HermesConfigRestore._(_apply(editedText, edits), const []);
  }

  /// The source text for the server's scalar, fit for where it lands.
  static String _serialize(YamlScalar original, bool targetInFlow) {
    final text = original.span.text;
    final prefix = _propertyPrefix.firstMatch(text)?.group(0) ?? '';
    final body = text.substring(prefix.length);
    final singleLine = !body.contains('\n');
    if (singleLine) {
      switch (original.style) {
        case ScalarStyle.SINGLE_QUOTED || ScalarStyle.DOUBLE_QUOTED:
          return body;
        case ScalarStyle.PLAIN when !targetInFlow || _flowSafe.hasMatch(body):
          return body;
        default:
          break;
      }
    }
    final value = original.value;
    return value is num ? value.toString() : jsonEncode(value.toString());
  }

  // -------------------------------------------------------------------------
  // Validation
  // -------------------------------------------------------------------------

  /// Checks [text] before it is written. Errors block the save; warnings
  /// don't. [schema] is `/api/config/schema` (null skips the type checks) and
  /// [knownRoots] the root keys Hermes knows (null skips the unknown-key
  /// warning).
  static HermesConfigValidation validate(
    String text, {
    HermesAdminConfigSchema? schema,
    Set<String>? knownRoots,
  }) {
    if (text.length > kHermesConfigMaxChars) {
      return const HermesConfigValidation([
        HermesConfigIssue(
          HermesConfigIssueSeverity.error,
          'The config is too large to edit here.',
        ),
      ]);
    }
    final YamlNode root;
    try {
      root = loadYamlNode(text);
    } on YamlException catch (e) {
      final line = e.span == null ? null : e.span!.start.line + 1;
      final reason = HermesSecretRedaction.redactText(e.message);
      return HermesConfigValidation([
        HermesConfigIssue(
          HermesConfigIssueSeverity.error,
          line == null
              ? 'Invalid YAML: $reason'
              : 'Invalid YAML on line $line: $reason',
          line: line,
        ),
      ]);
    }
    if (root is YamlScalar && root.value == null) {
      return const HermesConfigValidation([
        HermesConfigIssue(
          HermesConfigIssueSeverity.error,
          "The config can't be empty: it must be a mapping of settings.",
        ),
      ]);
    }
    if (root is! YamlMap) {
      return HermesConfigValidation([
        HermesConfigIssue(
          HermesConfigIssueSeverity.error,
          root is YamlList
              ? 'The config must be a mapping (key: value), not a list.'
              : 'The config must be a mapping (key: value), not a single value.',
          line: 1,
        ),
      ]);
    }

    final issues = <HermesConfigIssue>[];
    if (schema != null) {
      _checkTypes(root, _SchemaIndex(schema.fields), issues);
    }
    if (knownRoots != null) {
      for (final entry in root.nodes.entries) {
        final keyNode = entry.key as YamlNode;
        final name = keyNode is YamlScalar ? '${keyNode.value}' : '?';
        if (knownRoots.contains(name)) continue;
        final near = _closest(name, knownRoots);
        issues.add(
          HermesConfigIssue(
            HermesConfigIssueSeverity.warning,
            near == null
                ? "Unknown top-level key '$name'. Hermes may ignore it."
                : "Unknown top-level key '$name'. Did you mean '$near'?",
            key: name,
            line: keyNode.span.start.line + 1,
          ),
        );
      }
    }
    return HermesConfigValidation(issues);
  }

  static void _checkTypes(
    YamlMap root,
    _SchemaIndex schema,
    List<HermesConfigIssue> issues,
  ) {
    void error(String dotted, YamlNode node, String message) => issues.add(
      HermesConfigIssue(
        HermesConfigIssueSeverity.error,
        message,
        key: dotted,
        line: node.span.start.line + 1,
      ),
    );

    void visit(YamlMap map, String prefix) {
      for (final entry in map.nodes.entries) {
        final keyNode = entry.key as YamlNode;
        if (keyNode is! YamlScalar) continue;
        final dotted = prefix.isEmpty
            ? '${keyNode.value}'
            : '$prefix.${keyNode.value}';
        final node = entry.value;
        final type = schema.types[dotted];
        final isNull = node is YamlScalar && node.value == null;
        switch (type) {
          case 'number' when !isNull && !_isNumber(node):
            error(
              dotted,
              node,
              '$dotted must be a number, but it is ${_describe(node)}.',
            );
          case 'boolean' when !isNull && !_isBoolean(node):
            error(
              dotted,
              node,
              '$dotted must be true or false, but it is ${_describe(node)}.',
            );
          case 'list' when !isNull && node is! YamlList:
            error(
              dotted,
              node,
              '$dotted must be a list, but it is ${_describe(node)}.',
            );
          case 'string' || 'text' || 'select'
              when node is! YamlScalar && !isNull:
            error(
              dotted,
              node,
              '$dotted must be text, but it is ${_describe(node)}.',
            );
          case 'object' || 'dict' || 'map' when !isNull && node is! YamlMap:
            error(
              dotted,
              node,
              '$dotted must be a mapping, but it is ${_describe(node)}.',
            );
          case 'select'
              when node is YamlScalar &&
                  node.value is String &&
                  schema.options[dotted] != null &&
                  !schema.options[dotted]!.contains(node.value):
            issues.add(
              HermesConfigIssue(
                HermesConfigIssueSeverity.warning,
                "$dotted is '${HermesSecretRedaction.redactText('${node.value}')}', which isn't one of: ${schema.options[dotted]!.join(', ')}.",
                key: dotted,
                line: node.span.start.line + 1,
              ),
            );
          case null
              when schema.containers.contains(dotted) &&
                  !isNull &&
                  node is! YamlMap:
            error(
              dotted,
              node,
              '$dotted must be a mapping, but it is ${_describe(node)}.',
            );
          default:
            break;
        }
        if (node is YamlMap && type != 'list') visit(node, dotted);
      }
    }

    visit(root, '');
  }

  static bool _isNumber(YamlNode node) {
    if (node is! YamlScalar) return false;
    final value = node.value;
    if (value is num) return true;
    // Hermes reads YAML 1.1: an unquoted `1_000` is a number there.
    return value is String &&
        node.style == ScalarStyle.PLAIN &&
        RegExp(r'^[+-]?\d[\d_]*(\.[\d_]*)?([eE][+-]?\d+)?$').hasMatch(value);
  }

  static bool _isBoolean(YamlNode node) {
    if (node is! YamlScalar) return false;
    final value = node.value;
    if (value is bool) return true;
    // YAML 1.1 spells booleans yes/no/on/off too, when unquoted.
    return value is String &&
        node.style == ScalarStyle.PLAIN &&
        const {'yes', 'no', 'on', 'off'}.contains(value.toLowerCase());
  }

  static String _describe(YamlNode node) {
    if (node is YamlMap) return 'a mapping';
    if (node is YamlList) return 'a list';
    final value = (node as YamlScalar).value;
    if (value is bool) return 'true or false';
    if (value is num) return 'a number';
    return 'text';
  }

  /// The known root closest to [name], when it is a plausible typo.
  static String? _closest(String name, Set<String> known) {
    String? best;
    var bestDistance = 1 << 30;
    final limit = name.length > 8 ? 3 : 2;
    for (final candidate in known) {
      final distance = _editDistance(name, candidate);
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return bestDistance <= limit ? best : null;
  }

  static int _editDistance(String a, String b) {
    if ((a.length - b.length).abs() > 3) return 99;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }

  // -------------------------------------------------------------------------
  // Diff
  // -------------------------------------------------------------------------

  /// What changes when [writtenYaml] replaces [serverYaml]. Both are real
  /// text, secrets included; the result holds none. An unchanged secret shows
  /// as its placeholder on both sides, a changed or added one as
  /// [kHermesNewSecretMask].
  static HermesConfigDiff diff(String serverYaml, String writtenYaml) {
    final oldMasked = _displayMask(serverYaml, writtenYaml, newSide: false);
    final newMasked = _displayMask(writtenYaml, serverYaml, newSide: true);
    final oldLines = oldMasked.split('\n');
    final newLines = newMasked.split('\n');
    final oldRoots = _lineRoots(oldMasked, oldLines.length);
    final newRoots = _lineRoots(newMasked, newLines.length);
    final lines = _diffLines(oldLines, newLines)
        .map((line) {
          final root = switch (line.kind) {
            HermesDiffKind.removed => oldRoots[line.oldNumber! - 1],
            HermesDiffKind.added => newRoots[line.newNumber! - 1],
            HermesDiffKind.same => null,
          };
          if (root == null || !kHermesGuardRoots.contains(root)) return line;
          return HermesDiffLine(
            kind: line.kind,
            text: line.text,
            oldNumber: line.oldNumber,
            newNumber: line.newNumber,
            guardRoot: root,
          );
        })
        .toList(growable: false);

    final oldPlain = _plainRoot(serverYaml);
    final newPlain = _plainRoot(writtenYaml);
    final changedRoots = <String>{};
    final guardChanges = <HermesGuardChange>[];
    if (oldPlain != null && newPlain != null) {
      for (final root in {...oldPlain.keys, ...newPlain.keys}) {
        if (!_deepEquals(oldPlain[root], newPlain[root])) {
          changedRoots.add(root);
        }
      }
      for (final root in kHermesGuardRoots) {
        if (!changedRoots.contains(root)) continue;
        final before = <String, Object?>{};
        final after = <String, Object?>{};
        if (oldPlain.containsKey(root)) _flatten(oldPlain[root], root, before);
        if (newPlain.containsKey(root)) _flatten(newPlain[root], root, after);
        for (final key in {...before.keys, ...after.keys}) {
          final had = before.containsKey(key);
          final has = after.containsKey(key);
          if (had && has && _deepEquals(before[key], after[key])) continue;
          guardChanges.add(
            HermesGuardChange(
              key: key,
              from: had ? _display(key, before[key]) : '(not set)',
              to: has ? _display(key, after[key]) : '(removed)',
            ),
          );
        }
      }
    }
    return HermesConfigDiff(
      lines: lines,
      changedRoots: changedRoots,
      guardChanges: guardChanges,
    );
  }

  static String _displayMask(
    String raw,
    String other, {
    required bool newSide,
  }) {
    final otherValues = <String, String>{};
    final otherRoot = _parse(other);
    if (otherRoot != null) {
      _walk(otherRoot, const [], false, (path, node, _) {
        otherValues[_pathKey(path)] = '${node.value}';
      });
    }
    final tree = _maskTree(raw, (path, value) {
      final same = otherValues[_pathKey(path)] == '$value';
      return newSide && !same ? kHermesNewSecretMask : placeholderFor(path);
    });
    final text = (tree ?? _maskUnparsed(raw)).text;
    return _scrubComments(text).$1;
  }

  /// Which root key each line of [text] sits under (null above the first).
  static List<String?> _lineRoots(String text, int lineCount) {
    final roots = List<String?>.filled(lineCount, null);
    final tree = _parse(text);
    if (tree is! YamlMap) return roots;
    final starts = <(int, String)>[
      for (final entry in tree.nodes.entries)
        if (entry.key is YamlScalar)
          (
            (entry.key as YamlScalar).span.start.line,
            '${(entry.key as YamlScalar).value}',
          ),
    ];
    for (var i = 0; i < starts.length; i++) {
      final end = i + 1 < starts.length ? starts[i + 1].$1 : lineCount;
      for (var line = starts[i].$1; line < end && line < lineCount; line++) {
        roots[line] = starts[i].$2;
      }
    }
    return roots;
  }

  /// A line diff. Equal lines at both ends are peeled off; the middle is
  /// diffed by longest common subsequence (or, for an enormous one, taken as
  /// replaced).
  static List<HermesDiffLine> _diffLines(List<String> a, List<String> b) {
    final out = <HermesDiffLine>[];
    var head = 0;
    while (head < a.length && head < b.length && a[head] == b[head]) {
      out.add(
        HermesDiffLine(
          kind: HermesDiffKind.same,
          text: a[head],
          oldNumber: head + 1,
          newNumber: head + 1,
        ),
      );
      head++;
    }
    var tailA = a.length;
    var tailB = b.length;
    while (tailA > head && tailB > head && a[tailA - 1] == b[tailB - 1]) {
      tailA--;
      tailB--;
    }
    final n = tailA - head;
    final m = tailB - head;
    void removed(int i) => out.add(
      HermesDiffLine(
        kind: HermesDiffKind.removed,
        text: a[i],
        oldNumber: i + 1,
      ),
    );
    void added(int j) => out.add(
      HermesDiffLine(kind: HermesDiffKind.added, text: b[j], newNumber: j + 1),
    );

    if (n == 0 || m == 0 || n * m > 4000000) {
      for (var i = head; i < tailA; i++) {
        removed(i);
      }
      for (var j = head; j < tailB; j++) {
        added(j);
      }
    } else {
      final width = m + 1;
      final table = Int32List((n + 1) * width);
      for (var i = n - 1; i >= 0; i--) {
        for (var j = m - 1; j >= 0; j--) {
          table[i * width + j] = a[head + i] == b[head + j]
              ? table[(i + 1) * width + j + 1] + 1
              : (table[(i + 1) * width + j] >= table[i * width + j + 1]
                    ? table[(i + 1) * width + j]
                    : table[i * width + j + 1]);
        }
      }
      var i = 0;
      var j = 0;
      while (i < n && j < m) {
        if (a[head + i] == b[head + j]) {
          out.add(
            HermesDiffLine(
              kind: HermesDiffKind.same,
              text: a[head + i],
              oldNumber: head + i + 1,
              newNumber: head + j + 1,
            ),
          );
          i++;
          j++;
        } else if (table[(i + 1) * width + j] >= table[i * width + j + 1]) {
          removed(head + i++);
        } else {
          added(head + j++);
        }
      }
      while (i < n) {
        removed(head + i++);
      }
      while (j < m) {
        added(head + j++);
      }
    }
    for (var k = 0; tailA + k < a.length; k++) {
      out.add(
        HermesDiffLine(
          kind: HermesDiffKind.same,
          text: a[tailA + k],
          oldNumber: tailA + k + 1,
          newNumber: tailB + k + 1,
        ),
      );
    }
    return out;
  }

  /// Structural equality for plain YAML values (maps, lists, scalars).
  static bool _deepEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// The document as plain Dart values, or null when it is not a mapping.
  static Map<String, Object?>? _plainRoot(String text) {
    final tree = _parse(text);
    if (tree is! YamlMap) return null;
    final plain = _plain(tree);
    return plain is Map<String, Object?> ? plain : null;
  }

  static Object? _plain(Object? value) {
    if (value is YamlMap) {
      return <String, Object?>{
        for (final entry in value.entries) '${entry.key}': _plain(entry.value),
      };
    }
    if (value is YamlList) return [for (final item in value) _plain(item)];
    return value;
  }

  static void _flatten(Object? value, String prefix, Map<String, Object?> out) {
    if (value is Map && value.isNotEmpty) {
      for (final entry in value.entries) {
        _flatten(entry.value, '$prefix.${entry.key}', out);
      }
    } else {
      out[prefix] = value;
    }
  }

  /// A value for the guard list: secrets never show.
  static String _display(String dottedKey, Object? value) {
    if (value == null) return 'empty';
    if (HermesSecretRedaction.isSecretAt(dottedKey.split('.'), value) ||
        (value is Iterable &&
            value.any(
              (item) => HermesSecretRedaction.isSecretAt(const ['item'], item),
            ))) {
      return '<secret>';
    }
    final text = HermesSecretRedaction.redactText('$value');
    return text.length > 80 ? '${text.substring(0, 79)}…' : text;
  }

  // -------------------------------------------------------------------------
  // Plumbing
  // -------------------------------------------------------------------------

  static void _walk(
    YamlNode node,
    List<Object> path,
    bool inFlow,
    void Function(List<Object> path, YamlScalar node, bool inFlow) visit, {
    void Function(List<Object> path, YamlScalar node)? visitKey,
  }) {
    if (node is YamlMap) {
      final flow = inFlow || node.style == CollectionStyle.FLOW;
      for (final entry in node.nodes.entries) {
        final keyNode = entry.key as YamlNode;
        final name = keyNode is YamlScalar ? '${keyNode.value}' : '?';
        final childPath = [...path, name];
        if (visitKey != null && keyNode is YamlScalar) {
          visitKey(childPath, keyNode);
        }
        _walk(entry.value, childPath, flow, visit, visitKey: visitKey);
      }
    } else if (node is YamlList) {
      final flow = inFlow || node.style == CollectionStyle.FLOW;
      for (var i = 0; i < node.nodes.length; i++) {
        _walk(node.nodes[i], [...path, i], flow, visit, visitKey: visitKey);
      }
    } else if (node is YamlScalar) {
      visit(path, node, inFlow);
    }
  }

  static String _apply(String text, List<_Edit> edits) {
    if (edits.isEmpty) return text;
    edits.sort((a, b) => a.start.compareTo(b.start));
    final out = StringBuffer();
    var cursor = 0;
    for (final edit in edits) {
      if (edit.start < cursor) continue;
      out
        ..write(text.substring(cursor, edit.start))
        ..write(edit.replacement);
      cursor = edit.end;
    }
    out.write(text.substring(cursor));
    return out.toString();
  }
}

/// One replacement of a stretch of source text.
final class _Edit {
  const _Edit(this.start, this.end, this.replacement);

  /// Replaces a scalar's value, keeping an anchor or tag in front of it.
  factory _Edit.scalar(YamlScalar node, String replacement) {
    final prefix =
        HermesConfigDocument._propertyPrefix
            .firstMatch(node.span.text)
            ?.group(0) ??
        '';
    return _Edit(
      node.span.start.offset + prefix.length,
      node.span.end.offset,
      replacement,
    );
  }

  final int start;
  final int end;
  final String replacement;
}

/// `/api/config/schema` indexed for the type check.
final class _SchemaIndex {
  _SchemaIndex(Map<String, dynamic> fields) {
    for (final entry in fields.entries) {
      final spec = entry.value;
      if (spec is! Map) continue;
      final type = spec['type'];
      if (type is! String) continue;
      types[entry.key] = type.toLowerCase();
      final choices = spec['options'];
      if (choices is List && choices.isNotEmpty) {
        options[entry.key] = [for (final c in choices) '$c'];
      }
      final parts = entry.key.split('.');
      for (var i = 1; i < parts.length; i++) {
        containers.add(parts.sublist(0, i).join('.'));
      }
    }
  }

  /// Dotted key to its type.
  final Map<String, String> types = {};

  /// Dotted key to the options of a select.
  final Map<String, List<String>> options = {};

  /// Dotted keys that are parents of other fields.
  final Set<String> containers = {};
}
