import 'dart:convert';

import 'hermes_openui_schema.dart';

/// Desktop's bounded OpenUI v1 contract, parsed without JavaScript or a WebView.
final _schemas = (jsonDecode(hermesOpenuiSchemaJson) as Map)
    .cast<String, dynamic>();
final hermesOpenuiComponentNames = Set<String>.unmodifiable(_schemas.keys);
const hermesOpenuiFields = {
  'Input',
  'Select',
  'Checkbox',
  'TextArea',
  'NumberInput',
  'DatePicker',
  'TimePicker',
  'Slider',
  'Switch',
  'RadioGroup',
  'MultiSelect',
  'Rating',
};
const _unsafeNames = {
  '__proto__',
  'constructor',
  'prototype',
  'call',
  'functionCall',
};

final class HermesOpenuiNode {
  const HermesOpenuiNode(this.type, this.props, this.path);
  final String type;
  final Map<String, dynamic> props;
  final String path;
  List<HermesOpenuiNode> get children =>
      (props['children'] as List? ?? const []).cast<HermesOpenuiNode>();
}

/// Throws FormatException for incomplete, oversized or unsupported programs.
HermesOpenuiNode parseHermesOpenui(String source) {
  if (utf8.encode(source).length > 65536) {
    throw const FormatException('OpenUI exceeds 64 KiB.');
  }
  final parser = _Parser(source);
  parser.takeWord('root');
  parser.take('=');
  final root = parser.value(0);
  parser.optional(';');
  parser.space();
  if (parser.position != source.length ||
      root is! HermesOpenuiNode ||
      root.type != 'Stack') {
    throw const FormatException('Expected one root = Stack(...) statement.');
  }
  final forms = <String>{};
  var count = 0;
  void walk(
    HermesOpenuiNode node,
    int depth,
    String? parent,
    Set<String>? fields,
  ) {
    if (++count > 200 || depth > 16)
      throw const FormatException('UI is too large or deep.');
    const parents = {
      'Tab': 'Tabs',
      'AccordionItem': 'Accordion',
      'TimelineItem': 'Timeline',
      'Step': 'Steps',
      'AgendaItem': 'Agenda',
      'KanbanColumn': 'Kanban',
      'TaskCard': 'KanbanColumn',
    };
    const childTypes = {
      'Tabs': 'Tab',
      'Accordion': 'AccordionItem',
      'Timeline': 'TimelineItem',
      'Steps': 'Step',
      'Agenda': 'AgendaItem',
      'Kanban': 'KanbanColumn',
      'KanbanColumn': 'TaskCard',
    };
    final p = node.props;
    if (parents.containsKey(node.type) && parents[node.type] != parent) {
      throw FormatException('${node.type} requires ${parents[node.type]}.');
    }
    final requiredChild = childTypes[node.type];
    if ((requiredChild != null &&
            (node.children.isEmpty ||
                node.children.any((c) => c.type != requiredChild))) ||
        (node.type == 'Carousel' && node.children.isEmpty)) {
      throw const FormatException('Invalid container children.');
    }
    if (node.type == 'Form') {
      if (fields != null || !forms.add(p['name'] as String))
        throw const FormatException('Forms must be unique and cannot nest.');
      fields = <String>{};
    }
    if (hermesOpenuiFields.contains(node.type)) {
      final name = p['name'] as String;
      if (fields == null ||
          fields.length >= 16 ||
          _unsafeNames.contains(name) ||
          !fields.add(name)) {
        throw const FormatException(
          'Fields need unique safe names inside Form (maximum 16).',
        );
      }
    }
    if ({'Select', 'RadioGroup'}.contains(node.type)) {
      final options = p['options'] as List;
      if (!options.contains(p['initial']) ||
          options.toSet().length != options.length)
        throw const FormatException('Invalid options or initial choice.');
    }
    if (node.type == 'MultiSelect' &&
        (p['initial'] as List).any(
          (v) => !(p['options'] as List).contains(v),
        )) {
      throw const FormatException('Initial choices must be available.');
    }
    if (node.type == 'Table' &&
        (p['rows'] as List).any(
          (r) => (r as List).length != (p['columns'] as List).length,
        )) {
      throw const FormatException('Table dimensions do not match.');
    }
    if ({
          'BarChart',
          'LineChart',
          'AreaChart',
          'PieChart',
          'DonutChart',
        }.contains(node.type) &&
        (p['labels'] as List).length != (p['values'] as List).length) {
      throw const FormatException('Chart labels and values must align.');
    }
    if ({'Progress', 'Gauge'}.contains(node.type) &&
        (p['value'] as num) > (p['max'] as num))
      throw const FormatException('Value exceeds maximum.');
    if ({'Slider', 'NumberInput'}.contains(node.type) &&
        ((p['min'] as num) >= (p['max'] as num) ||
            (p['initial'] as num) < (p['min'] as num) ||
            (p['initial'] as num) > (p['max'] as num))) {
      throw const FormatException('Invalid field range.');
    }
    if (node.type == 'Heatmap' &&
        ((p['rows'] as List).length != (p['values'] as List).length ||
            (p['values'] as List).any(
              (r) => (r as List).length != (p['columns'] as List).length,
            ))) {
      throw const FormatException('Heatmap dimensions do not match.');
    }
    if (node.type == 'DefinitionList' &&
        (p['labels'] as List).length != (p['values'] as List).length)
      throw const FormatException('Definition dimensions do not match.');
    for (final child in node.children) {
      walk(child, depth + 1, node.type, fields);
    }
  }

  walk(root, 0, null, null);
  return root;
}

class _Parser {
  _Parser(this.source);
  final String source;
  int position = 0;
  int nodes = 0;
  void space() {
    while (position < source.length &&
        RegExp(r'\s').hasMatch(source[position])) {
      position++;
    }
  }

  bool optional(String token) {
    space();
    if (!source.startsWith(token, position)) return false;
    position += token.length;
    return true;
  }

  void take(String token) {
    if (!optional(token))
      throw FormatException('Expected $token at $position.');
  }

  void takeWord(String word) {
    space();
    if (_word() != word) throw FormatException('Expected $word.');
  }

  String _word() {
    space();
    final match = RegExp(r'[A-Za-z_][A-Za-z0-9_]*')
        .matchAsPrefix(source, position);
    if (match == null)
      throw FormatException('Expected component at $position.');
    position = match.end;
    return match[0]!;
  }

  dynamic value(int depth) {
    space();
    if (depth > 40 || position >= source.length)
      throw const FormatException('Incomplete or excessive nesting.');
    if (source[position] == '"') {
      final start = position++;
      var escaped = false;
      while (position < source.length) {
        final c = source[position++];
        if (!escaped && c == '"')
          // OpenUI Lang permits literal line breaks in quoted draft/code text.
          // JSON's string decoder needs those escaped, while existing escapes
          // (including literal backslashes) must remain unchanged.
          return jsonDecode(
            source
                .substring(start, position)
                .replaceAll('\r', r'\r')
                .replaceAll('\n', r'\n')
                .replaceAll('\t', r'\t'),
          );
        if (!escaped && c == r'\') {
          escaped = true;
        } else {
          escaped = false;
        }
      }
      throw const FormatException('Unclosed string.');
    }
    if (optional('[')) {
      final items = <dynamic>[];
      if (optional(']')) return items;
      do {
        if (items.length >= 60)
          throw const FormatException('Too many array items.');
        items.add(value(depth + 1));
      } while (optional(','));
      take(']');
      return items;
    }
    if (optional('{')) {
      // Plain string-keyed data, accepted only where the schema says object
      // (ImageGallery items). Bounded and never executed.
      final entries = <String, dynamic>{};
      if (optional('}')) return entries;
      do {
        if (entries.length >= 8) {
          throw const FormatException('Too many object fields.');
        }
        space();
        if (position >= source.length) {
          throw const FormatException('Incomplete object.');
        }
        final key = source[position] == '"' ? value(depth + 1) : _word();
        if (key is! String || _unsafeNames.contains(key)) {
          throw const FormatException('Invalid object field name.');
        }
        take(':');
        if (entries.containsKey(key)) {
          throw FormatException('Duplicate object field $key.');
        }
        entries[key] = value(depth + 1);
      } while (optional(','));
      take('}');
      return entries;
    }
    final number = RegExp(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)')
        .matchAsPrefix(source, position);
    if (number != null) {
      position = number.end;
      final parsed = num.tryParse(number[0]!);
      if (parsed == null || !parsed.isFinite)
        throw const FormatException('Invalid number.');
      return parsed;
    }
    final word = _word();
    if (word == 'true') return true;
    if (word == 'false') return false;
    if (word == 'null') return null;
    final schema = _schemas[word] as Map?;
    if (schema == null || ++nodes > 200)
      throw FormatException('Unknown or excessive component: $word.');
    final path = 'node-$nodes';
    take('(');
    final args = <dynamic>[];
    if (!optional(')')) {
      do {
        args.add(value(depth + 1));
      } while (optional(','));
      take(')');
    }
    final properties = schema['properties'] as Map;
    final keys = properties.keys.cast<String>().toList();
    if (args.length > keys.length)
      throw const FormatException('Too many arguments.');
    final props = <String, dynamic>{
      for (var i = 0; i < args.length; i++) keys[i]: args[i],
    };
    for (final key in schema['required'] as List? ?? const []) {
      if (!props.containsKey(key)) throw FormatException('Missing $word.$key.');
    }
    for (final entry in props.entries) {
      _validate(entry.value, properties[entry.key] as Map);
      if (entry.key == 'children' &&
          (entry.value as List).any((c) => c is! HermesOpenuiNode))
        throw const FormatException('Children must be components.');
    }
    return HermesOpenuiNode(word, Map.unmodifiable(props), path);
  }
}

void _validate(dynamic value, Map schema) {
  final type = schema['type'];
  if (type == null) return;
  bool valid;
  switch (type) {
    case 'string':
      valid =
          value is String &&
          (!schema.containsKey('minLength') ||
              value.length >= (schema['minLength'] as int)) &&
          (!schema.containsKey('maxLength') ||
              value.length <= (schema['maxLength'] as int)) &&
          (!schema.containsKey('pattern') ||
              RegExp(schema['pattern'] as String).hasMatch(value));
    case 'number':
    case 'integer':
      valid =
          value is num &&
          value.isFinite &&
          (type != 'integer' || value == value.roundToDouble()) &&
          (!schema.containsKey('minimum') ||
              value >= (schema['minimum'] as num)) &&
          (!schema.containsKey('maximum') ||
              value <= (schema['maximum'] as num)) &&
          (!schema.containsKey('exclusiveMinimum') ||
              value > (schema['exclusiveMinimum'] as num));
    case 'boolean':
      valid = value is bool;
    case 'object':
      final fields = (schema['properties'] as Map?) ?? const {};
      valid =
          value is Map &&
          value.keys.every(fields.containsKey) &&
          (schema['required'] as List? ?? const []).every(value.containsKey);
      if (valid) {
        for (final entry in value.entries) {
          _validate(entry.value, fields[entry.key] as Map);
        }
      }
    case 'array':
      valid =
          value is List &&
          (!schema.containsKey('minItems') ||
              value.length >= (schema['minItems'] as int)) &&
          (!schema.containsKey('maxItems') ||
              value.length <= (schema['maxItems'] as int));
      if (valid) {
        for (final item in value) {
          _validate(item, schema['items'] as Map? ?? const {});
        }
      }
    default:
      valid = false;
  }
  if (!valid ||
      (schema.containsKey('enum') && !(schema['enum'] as List).contains(value)))
    throw const FormatException('Argument does not match the OpenUI catalog.');
}
