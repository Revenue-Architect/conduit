import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:genui/genui.dart';
// GenUI's public CatalogItem API uses this transitive schema-builder type but
// does not re-export it; GenUI is pinned and the builder is locked transitively.
// ignore: depend_on_referenced_packages
import 'package:json_schema_builder/json_schema_builder.dart';

import '../feedback/hermez_feedback.dart';
import '../motion/hermez_motion.dart';
import 'hermes_a2ui_interaction_lock.dart';
import 'hermes_visual_structure.dart' show hermezOutline, hermezStatusColorsOf;
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';
import 'hermez_visual_theme.dart' show HermezStatusColors;

/// Work and technical components for visual answers: a command to review
/// and copy, a task, a small fact grid, and one option's facts to compare.
///
/// Data-only: nothing here runs a command, reads a file, or queries a task
/// system. The one interaction is CommandBlock's Copy, which is local (the
/// clipboard) like opening an ExpandableSection: it sends no event and no
/// Hermes turn, and it stays usable on a locked surface.
final List<CatalogItem> hermesTechnicalCatalogItems = [
  _commandBlock,
  _taskTile,
  _keyValueGrid,
  _comparisonCard,
];

const _stateValues = ['ok', 'warning', 'error', 'unknown'];

// ── Schemas ──────────────────────────────────────────────────────────────

final _commandBlock = CatalogItem(
  name: 'CommandBlock',
  dataSchema: S.object(
    description:
        'One short command or snippet to review and copy (shell, SQL, JSON, '
        'YAML). Never executed. For long or multi-file code use Markdown.',
    properties: {
      'content': S.string(description: 'The command text (≤ 4000).'),
      'label': S.string(description: 'Optional label such as COMMAND (≤ 40).'),
      'language': S.string(
        enumValues: ['shell', 'sql', 'json', 'yaml', 'text'],
      ),
      'copyable': S.boolean(description: 'Show Copy. Defaults to true.'),
    },
    required: ['content'],
  ),
  widgetBuilder: (context) => _buildCommandBlock(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"CommandBlock","label":"Command","language":"shell","content":"docker compose restart nvr"}
      ]
    ''',
  ],
);

final _taskTile = CatalogItem(
  name: 'TaskTile',
  dataSchema: S.object(
    description:
        'One task or action item as it stands. Presentation only; it is not '
        'bound to any task system.',
    properties: {
      'title': S.string(description: 'The task (≤ 100).'),
      'status': S.string(
        enumValues: ['todo', 'in_progress', 'blocked', 'done', 'unknown'],
      ),
      'assignee': S.string(description: 'Optional owner (≤ 60).'),
      'due': S.string(description: 'Optional due date (≤ 40).'),
      'priority': S.string(enumValues: ['low', 'normal', 'high', 'urgent']),
      'detail': S.string(description: 'Optional detail (≤ 160).'),
      'countLabel': S.string(description: 'Optional count such as 3/5 (≤ 40).'),
    },
    required: ['title', 'status'],
  ),
  widgetBuilder: (context) => _buildTaskTile(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"TaskTile","title":"Trail certificates","status":"in_progress","assignee":"Kai","due":"Nov 11","detail":"Generate and email donor certificates"}
      ]
    ''',
  ],
);

final _keyValueGrid = CatalogItem(
  name: 'KeyValueGrid',
  dataSchema: S.object(
    description:
        'Up to 8 facts about one object (model, profile, uptime). The layout '
        'adapts to the width; do not choose columns.',
    properties: {
      'title': S.string(description: 'Optional heading (≤ 60).'),
      'items': S.list(
        items: S.object(
          properties: {
            'label': S.string(description: 'Fact name (≤ 40).'),
            'value': S.string(description: 'Fact value (≤ 120).'),
          },
          required: ['label', 'value'],
        ),
        minItems: 1,
        maxItems: 8,
      ),
      'compact': S.boolean(description: 'Tighter rows.'),
    },
    required: ['items'],
  ),
  widgetBuilder: (context) => _buildKeyValueGrid(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"KeyValueGrid","title":"Server","items":[{"label":"Model","value":"Qwen 27B"},{"label":"Profile","value":"Local"},{"label":"Uptime","value":"14h 22m"}]}
      ]
    ''',
  ],
);

final _comparisonCard = CatalogItem(
  name: 'ComparisonCard',
  dataSchema: S.object(
    description:
        'The facts of one option. Put two or more in a Column to compare. It '
        'states facts only: no winner, rank, score, or recommendation.',
    properties: {
      'title': S.string(description: 'The option (≤ 80).'),
      'subtitle': S.string(description: 'Optional subtitle (≤ 120).'),
      'badge': S.string(description: 'Optional short tag (≤ 40).'),
      'facts': S.list(
        items: S.object(
          properties: {
            'label': S.string(description: 'Fact name (≤ 40).'),
            'value': S.string(description: 'Fact value (≤ 100).'),
            'state': S.string(enumValues: _stateValues),
          },
          required: ['label', 'value'],
        ),
        minItems: 1,
        maxItems: 8,
      ),
      'detail': S.string(description: 'Optional detail (≤ 160).'),
    },
    required: ['title', 'facts'],
  ),
  widgetBuilder: (context) => _buildComparisonCard(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"ComparisonCard","title":"Option A","facts":[{"label":"Cost","value":"\$12"},{"label":"Local","value":"Yes","state":"ok"}]}
      ]
    ''',
  ],
);

// ── CommandBlock ─────────────────────────────────────────────────────────

Widget _buildCommandBlock(CatalogItemContext context) {
  final data = _props(context);
  final content = data['content'];
  const languages = ['shell', 'sql', 'json', 'yaml', 'text'];
  if (content is! String ||
      content.trim().isEmpty ||
      content.length > 4000 ||
      !_optionalText(data, 'label', 40) ||
      !_optionalEnum(data, 'language', languages) ||
      !_optionalBool(data, 'copyable')) {
    return _invalid(context.buildContext);
  }
  final language = data['language'] as String? ?? 'text';
  return _CommandBlock(
    content: content.trimRight(),
    label: _text(data['label'], 40),
    language: language,
    copyable: data['copyable'] != false,
  );
}

class _CommandBlock extends StatefulWidget {
  const _CommandBlock({
    required this.content,
    required this.label,
    required this.language,
    required this.copyable,
  });

  final String content;
  final String? label;
  final String language;
  final bool copyable;

  @override
  State<_CommandBlock> createState() => _CommandBlockState();
}

class _CommandBlockState extends State<_CommandBlock> {
  bool _copied = false;

  String get _languageName => switch (widget.language) {
    'shell' => 'Shell command',
    'sql' => 'SQL',
    'json' => 'JSON',
    'yaml' => 'YAML',
    _ => 'Text',
  };

  Future<void> _copy() async {
    // Local only: the clipboard. No A2UI event, no Hermes turn.
    await Clipboard.setData(ClipboardData(text: widget.content));
    HermezFeedback.play(HermezFeedbackCue.controlSelect);
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final heading = (widget.label ?? _languageName).toUpperCase();
    return Semantics(
      container: true,
      label: '$_languageName. ${widget.content}',
      child: DecoratedBox(
        decoration: hermezOutline(palette, null),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        heading,
                        style: HermezType.technical(palette.muted),
                      ),
                    ),
                  ),
                  if (widget.copyable)
                    HermesA2uiLocalControl(
                      child: Semantics(
                        button: true,
                        label: _copied ? 'Copied' : 'Copy command',
                        excludeSemantics: true,
                        child: HermezMotionSurface(
                          key: const ValueKey('hermez-command-copy'),
                          weight: HermezMotionWeight.light,
                          haptic: false,
                          onTap: () => _copy(),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 44,
                              minWidth: 64,
                            ),
                            child: Center(
                              child: Text(
                                _copied ? 'COPIED' : 'COPY',
                                style: HermezType.technical(palette.accent),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: palette.canvas,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.border),
                ),
                child: ExcludeSemantics(
                  child: SelectableText(
                    widget.content,
                    style: TextStyle(
                      color: palette.ink,
                      fontFamily: 'monospace',
                      fontFamilyFallback: const ['Roboto Mono', 'Menlo'],
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── TaskTile ─────────────────────────────────────────────────────────────

Widget _buildTaskTile(CatalogItemContext context) {
  final data = _props(context);
  final title = _text(data['title'], 100);
  const statuses = ['todo', 'in_progress', 'blocked', 'done', 'unknown'];
  final status = data['status'];
  if (title == null ||
      status is! String ||
      !statuses.contains(status) ||
      !_optionalText(data, 'assignee', 60) ||
      !_optionalText(data, 'due', 40) ||
      !_optionalEnum(data, 'priority', ['low', 'normal', 'high', 'urgent']) ||
      !_optionalText(data, 'detail', 160) ||
      !_optionalText(data, 'countLabel', 40)) {
    return _invalid(context.buildContext);
  }
  final assignee = _text(data['assignee'], 60);
  final due = _text(data['due'], 40);
  final priority = data['priority'] as String?;
  final detail = _text(data['detail'], 160);
  final count = _text(data['countLabel'], 40);
  final build = context.buildContext;
  final palette = _palette(build);
  final statusColors = hermezStatusColorsOf(build);
  final (statusLabel, statusIcon, statusColor) = switch (status) {
    'todo' => ('TO DO', Icons.radio_button_unchecked_rounded, palette.muted),
    'in_progress' => ('IN PROGRESS', Icons.timelapse_rounded, palette.accent),
    'blocked' => ('BLOCKED', Icons.block_rounded, statusColors.danger),
    'done' => ('DONE', Icons.check_circle_rounded, statusColors.success),
    _ => ('UNKNOWN', Icons.help_outline_rounded, palette.muted),
  };
  // Only a blocked task outlines itself; everyday tasks stay neutral.
  final semantic = status == 'blocked' ? statusColors.danger : null;
  final urgent = priority == 'urgent' || priority == 'high';
  final meta = [
    ?assignee,
    if (due != null) 'Due $due',
    if (priority != null && priority != 'normal') priority.toUpperCase(),
  ].join(' · ');
  return Semantics(
    container: true,
    label: [
      title,
      statusLabel.toLowerCase(),
      if (assignee != null) 'assigned to $assignee',
      if (due != null) 'due $due',
      if (priority != null) '$priority priority',
      ?count,
      ?detail,
    ].join(', '),
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: hermezOutline(palette, semantic),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 15, color: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: HermezType.technical(statusColor),
                      ),
                    ],
                  ),
                  if (count != null)
                    Text(count, style: HermezType.technical(palette.muted)),
                  if (urgent)
                    Text(
                      '! ${priority!.toUpperCase()}',
                      style: HermezType.technical(statusColors.warning),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  decoration: status == 'done'
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: palette.muted,
                ),
              ),
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    meta,
                    style: TextStyle(color: palette.muted, fontSize: 13),
                  ),
                ),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    detail,
                    style: TextStyle(color: palette.muted, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ── KeyValueGrid ─────────────────────────────────────────────────────────

Widget _buildKeyValueGrid(CatalogItemContext context) {
  final data = _props(context);
  final raw = data['items'];
  if (raw is! List ||
      raw.isEmpty ||
      raw.length > 8 ||
      !_optionalText(data, 'title', 60) ||
      !_optionalBool(data, 'compact')) {
    return _invalid(context.buildContext);
  }
  final items = <(String, String)>[];
  for (final entry in raw) {
    if (entry is! Map) return _invalid(context.buildContext);
    final label = _text(entry['label'], 40);
    final value = _text(entry['value'], 120);
    if (label == null || value == null) return _invalid(context.buildContext);
    items.add((label, value));
  }
  final title = _text(data['title'], 60);
  final compact = data['compact'] == true;
  final palette = _palette(context.buildContext);
  return Semantics(
    container: true,
    label: [
      ?title,
      for (final (label, value) in items) '$label: $value',
    ].join('. '),
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: hermezOutline(palette, null),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: _FactList(
            title: title,
            facts: [for (final (l, v) in items) _Fact(l, v, null)],
            compact: compact,
            palette: palette,
          ),
        ),
      ),
    ),
  );
}

// ── ComparisonCard ───────────────────────────────────────────────────────

Widget _buildComparisonCard(CatalogItemContext context) {
  final data = _props(context);
  final title = _text(data['title'], 80);
  final raw = data['facts'];
  if (title == null ||
      raw is! List ||
      raw.isEmpty ||
      raw.length > 8 ||
      !_optionalText(data, 'subtitle', 120) ||
      !_optionalText(data, 'badge', 40) ||
      !_optionalText(data, 'detail', 160)) {
    return _invalid(context.buildContext);
  }
  final facts = <_Fact>[];
  for (final entry in raw) {
    if (entry is! Map) return _invalid(context.buildContext);
    final fact = Map<String, Object?>.from(entry);
    final label = _text(fact['label'], 40);
    final value = _text(fact['value'], 100);
    if (label == null ||
        value == null ||
        !_optionalEnum(fact, 'state', _stateValues)) {
      return _invalid(context.buildContext);
    }
    facts.add(_Fact(label, value, fact['state'] as String?));
  }
  final subtitle = _text(data['subtitle'], 120);
  final badge = _text(data['badge'], 40);
  final detail = _text(data['detail'], 160);
  final palette = _palette(context.buildContext);
  return Semantics(
    container: true,
    label: [
      title,
      ?subtitle,
      ?badge,
      for (final fact in facts)
        '${fact.label}: ${fact.value}'
            '${fact.state == null ? '' : ', ${fact.state}'}',
      ?detail,
    ].join('. '),
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: hermezOutline(palette, null),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: HermezType.technical(palette.ink),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: palette.border),
                      ),
                      child: Text(
                        badge.toUpperCase(),
                        style: HermezType.technical(palette.muted),
                      ),
                    ),
                ],
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    style: TextStyle(color: palette.muted, fontSize: 13),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: palette.border),
              ),
              _FactList(
                title: null,
                facts: facts,
                compact: false,
                palette: palette,
              ),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    detail,
                    style: TextStyle(color: palette.muted, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ── Shared fact list ─────────────────────────────────────────────────────

class _Fact {
  const _Fact(this.label, this.value, this.state);

  final String label;
  final String value;
  final String? state;
}

/// Label and value side by side when there is room, stacked otherwise: the
/// renderer decides from the available width and the text scale.
class _FactList extends StatelessWidget {
  const _FactList({
    required this.title,
    required this.facts,
    required this.compact,
    required this.palette,
  });

  final String? title;
  final List<_Fact> facts;
  final bool compact;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final status = hermezStatusColorsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn = constraints.maxWidth / scale >= 280;
        return Column(
          key: ValueKey(
            twoColumn ? 'hermez-facts-columns' : 'hermez-facts-stacked',
          ),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  title!.toUpperCase(),
                  style: HermezType.technical(palette.muted),
                ),
              ),
            for (final fact in facts)
              Padding(
                padding: EdgeInsets.symmetric(vertical: compact ? 3 : 5),
                child: _factRow(fact, twoColumn, status),
              ),
          ],
        );
      },
    );
  }

  Widget _factRow(_Fact fact, bool twoColumn, HermezStatusColors status) {
    final stateColor = switch (fact.state) {
      'ok' => status.success,
      'warning' => status.warning,
      'error' => status.danger,
      _ => null,
    };
    final label = Text(
      fact.label.toUpperCase(),
      style: HermezType.technical(palette.muted),
    );
    final value = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            fact.value,
            style: TextStyle(
              color: palette.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
        if (stateColor != null) ...[
          const SizedBox(width: 6),
          Icon(
            switch (fact.state) {
              'ok' => Icons.check_rounded,
              'warning' => Icons.priority_high_rounded,
              _ => Icons.close_rounded,
            },
            size: 15,
            color: stateColor,
          ),
        ],
      ],
    );
    if (!twoColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [label, const SizedBox(height: 1), value],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Padding(padding: const EdgeInsets.only(top: 2), child: label),
        ),
        const SizedBox(width: 10),
        Expanded(child: value),
      ],
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────

HermezChatPalette _palette(BuildContext context) =>
    HermezChatPalette.forBrightness(Theme.of(context).brightness);

Map<String, Object?> _props(CatalogItemContext context) =>
    context.data is Map<String, Object?>
    ? context.data as Map<String, Object?>
    : const <String, Object?>{};

String? _text(Object? value, int maxLength) {
  if (value is! String || value.length > maxLength) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _optionalText(Map<String, Object?> data, String key, int maxLength) =>
    !data.containsKey(key) || _text(data[key], maxLength) != null;

bool _optionalEnum(
  Map<String, Object?> data,
  String key,
  List<String> values,
) => !data.containsKey(key) || values.contains(data[key]);

bool _optionalBool(Map<String, Object?> data, String key) =>
    !data.containsKey(key) || data[key] is bool;

Widget _invalid(BuildContext context) {
  final palette = _palette(context);
  return Semantics(
    label: 'Visual unavailable',
    child: DecoratedBox(
      decoration: hermezOutline(palette, null, radius: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Visual unavailable: the supplied values could not be displayed '
          'safely.',
          style: TextStyle(color: palette.muted, fontSize: 13),
        ),
      ),
    ),
  );
}
