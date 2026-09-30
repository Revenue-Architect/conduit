import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
// GenUI's public CatalogItem API uses this transitive schema-builder type but
// does not re-export it; GenUI is pinned and the builder is locked transitively.
// ignore: depend_on_referenced_packages
import 'package:json_schema_builder/json_schema_builder.dart';

import 'hermes_visual_structure.dart' show hermezOutline, hermezStatusColorsOf;
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';

/// Personal-assistant components for visual answers: real progress, recent
/// activity, a timed item, and a message preview.
///
/// Data-only like the rest of the catalog: they render what the response
/// supplies and never fetch, open, reply, or invent values (no derived
/// timestamps, no guessed progress). Each is a static object with a complete
/// outline; state recolors that whole outline, never a side strip, and is
/// always carried by a word or glyph as well as color.
final List<CatalogItem> hermesPersonalCatalogItems = [
  _progressMeter,
  _activityFeed,
  _scheduleTile,
  _messagePreview,
];

const _stateValues = ['ok', 'warning', 'error', 'unknown'];
const _iconValues = [
  'check',
  'warning',
  'error',
  'info',
  'clock',
  'calendar',
  'person',
  'bot',
  'file',
  'link',
  'storage',
  'server',
  'chart',
  'task',
];

// ── Schemas ──────────────────────────────────────────────────────────────

final _progressMeter = CatalogItem(
  name: 'ProgressMeter',
  dataSchema: S.object(
    description:
        'Real counted progress (current of total), such as a migration or '
        'validation. Only for actual counts; never for "almost done".',
    properties: {
      'label': S.string(description: 'What is progressing (≤ 80).'),
      'current': S.number(description: 'Completed count, ≥ 0.'),
      'total': S.number(description: 'Total count, > 0.'),
      'unit': S.string(description: 'Optional unit such as products (≤ 24).'),
      'detail': S.string(description: 'Optional one-line detail (≤ 120).'),
      'state': S.string(enumValues: _stateValues),
      'segmented': S.boolean(description: 'Draw the bar as 20 segments.'),
    },
    required: ['label', 'current', 'total'],
  ),
  widgetBuilder: (context) => _buildProgressMeter(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"ProgressMeter","label":"Migration","current":412,"total":600,"unit":"products"}
      ]
    ''',
  ],
);

final _activityFeed = CatalogItem(
  name: 'ActivityFeed',
  dataSchema: S.object(
    description:
        'What happened, in order: events Hermes actually observed. Not a plan '
        '(use StepRail for stages). Omit time when it is not known.',
    properties: {
      'items': S.list(
        items: S.object(
          properties: {
            'title': S.string(description: 'The event (≤ 80).'),
            'detail': S.string(description: 'Optional detail (≤ 140).'),
            'time': S.string(description: 'Optional observed time (≤ 40).'),
            'icon': S.string(enumValues: _iconValues),
            'state': S.string(enumValues: _stateValues),
          },
          required: ['title'],
        ),
        minItems: 1,
        maxItems: 20,
      ),
      'compact': S.boolean(description: 'Tighter rows.'),
    },
    required: ['items'],
  ),
  widgetBuilder: (context) => _buildActivityFeed(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"ActivityFeed","items":[{"time":"11:42","title":"Browser opened Shopify"},{"time":"11:44","title":"412 products validated","state":"ok"},{"time":"11:45","title":"3 records need review","state":"warning"}]}
      ]
    ''',
  ],
);

final _scheduleTile = CatalogItem(
  name: 'ScheduleTile',
  dataSchema: S.object(
    description:
        'One timed item: a calendar event, appointment, reminder, or '
        'scheduled agent. Presentation only.',
    properties: {
      'title': S.string(description: 'What it is (≤ 80).'),
      'start': S.string(description: 'Start time as the user reads it (≤ 40).'),
      'end': S.string(description: 'Optional end time (≤ 40).'),
      'date': S.string(description: 'Optional date (≤ 40).'),
      'location': S.string(description: 'Optional place (≤ 100).'),
      'detail': S.string(description: 'Optional detail (≤ 120).'),
      'owner': S.string(description: 'Optional person or bot (≤ 60).'),
      'state': S.string(enumValues: _stateValues),
      'icon': S.string(enumValues: _iconValues),
    },
    required: ['title', 'start'],
  ),
  widgetBuilder: (context) => _buildScheduleTile(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"ScheduleTile","title":"Dentist","start":"14:30","end":"15:15","location":"Downtown"}
      ]
    ''',
  ],
);

final _messagePreview = CatalogItem(
  name: 'MessagePreview',
  dataSchema: S.object(
    description:
        'A brief preview of one message (email, Teams, AgentMail). Never the '
        'full message; it does not open, fetch, or reply.',
    properties: {
      'sender': S.string(description: 'Who sent it (≤ 80).'),
      'title': S.string(description: 'Optional subject (≤ 100).'),
      'preview': S.string(description: 'A short excerpt (≤ 240).'),
      'timestamp': S.string(description: 'Optional time (≤ 40).'),
      'channel': S.string(
        enumValues: ['email', 'teams', 'agentmail', 'message', 'unknown'],
      ),
      'unread': S.boolean(),
      'importance': S.string(enumValues: ['normal', 'important']),
    },
    required: ['sender', 'preview'],
  ),
  widgetBuilder: (context) => _buildMessagePreview(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"MessagePreview","channel":"email","sender":"Georgia","title":"Follow-up","preview":"Just have a few follow-up questions.","timestamp":"10:42 AM","unread":true}
      ]
    ''',
  ],
);

// ── ProgressMeter ────────────────────────────────────────────────────────

Widget _buildProgressMeter(CatalogItemContext context) {
  final data = _props(context);
  final label = _text(data['label'], 80);
  final current = _finite(data['current']);
  final total = _finite(data['total']);
  if (label == null ||
      current == null ||
      total == null ||
      current < 0 ||
      total <= 0 ||
      !_optionalText(data, 'unit', 24) ||
      !_optionalText(data, 'detail', 120) ||
      !_optionalEnum(data, 'state', _stateValues) ||
      !_optionalBool(data, 'segmented')) {
    return _invalid(context.buildContext);
  }
  final unit = _text(data['unit'], 24);
  final detail = _text(data['detail'], 120);
  final state = _State.parse(data['state']);
  final segmented = data['segmented'] == true;
  final build = context.buildContext;
  final palette = _palette(build);
  final semantic = _semanticColor(build, state);
  final color = semantic ?? palette.accent;
  // Real values, shown as given; the percentage is only their ratio. A count
  // over its total is shown as it is (over 100%), never clamped away.
  final ratio = current / total;
  final percent = ratio * 100;
  final over = current > total;
  final countText =
      '${_number(current)} / ${_number(total)}'
      '${unit == null ? '' : ' ${unit.toUpperCase()}'}';
  final semantics = [
    label,
    '${_number(current)} of ${_number(total)}${unit == null ? '' : ' $unit'}',
    '${_oneDecimal(percent)} percent',
    if (over) 'Over the total',
    ?state?.label,
    ?detail,
  ].join('. ');
  return Semantics(
    container: true,
    label: semantics,
    child: ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey('hermez-progress-meter'),
        decoration: hermezOutline(palette, semantic),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${label.toUpperCase()} / ${percent.round()}%',
                    style: HermezType.technical(palette.muted),
                  ),
                  if (over) Text('OVER', style: HermezType.technical(color)),
                  if (state != null && state != _State.ok)
                    Text(
                      state.label.toUpperCase(),
                      style: HermezType.technical(color),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                countText,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              _ProgressBar(
                ratio: ratio,
                segmented: segmented,
                color: color,
                track: palette.border,
              ),
              if (detail != null) ...[
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: TextStyle(color: palette.muted, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.ratio,
    required this.segmented,
    required this.color,
    required this.track,
  });

  final double ratio;
  final bool segmented;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final filled = ratio.clamp(0.0, 1.0);
    if (segmented) {
      const count = 20;
      final lit = (filled * count).floor();
      return Row(
        key: const ValueKey('hermez-progress-segments'),
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: i < lit ? color : track,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track),
            FractionallySizedBox(
              key: const ValueKey('hermez-progress-fill'),
              alignment: AlignmentDirectional.centerStart,
              widthFactor: filled,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ── ActivityFeed ─────────────────────────────────────────────────────────

Widget _buildActivityFeed(CatalogItemContext context) {
  final data = _props(context);
  final raw = data['items'];
  if (raw is! List ||
      raw.isEmpty ||
      raw.length > 20 ||
      !_optionalBool(data, 'compact')) {
    return _invalid(context.buildContext);
  }
  final items = <_Activity>[];
  for (final entry in raw) {
    if (entry is! Map) return _invalid(context.buildContext);
    final item = Map<String, Object?>.from(entry);
    final title = _text(item['title'], 80);
    if (title == null ||
        !_optionalText(item, 'detail', 140) ||
        !_optionalText(item, 'time', 40) ||
        !_optionalEnum(item, 'icon', _iconValues) ||
        !_optionalEnum(item, 'state', _stateValues)) {
      return _invalid(context.buildContext);
    }
    items.add(
      _Activity(
        title: title,
        detail: _text(item['detail'], 140),
        time: _text(item['time'], 40),
        icon: _iconFor(item['icon']),
        state: _State.parse(item['state']),
      ),
    );
  }
  final compact = data['compact'] == true;
  final build = context.buildContext;
  final palette = _palette(build);
  return Semantics(
    container: true,
    label: [
      'Activity',
      for (final item in items)
        [?item.time, item.title, ?item.state?.label, ?item.detail].join(', '),
    ].join('. '),
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: hermezOutline(palette, null),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ACTIVITY', style: HermezType.technical(palette.muted)),
              const SizedBox(height: 6),
              for (final item in items)
                Padding(
                  padding: EdgeInsets.only(bottom: compact ? 6 : 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          top: item.time == null ? 2 : 16,
                        ),
                        child: _ActivityMark(item: item, palette: palette),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.time != null)
                              Text(
                                item.time!,
                                style: HermezType.technical(palette.muted),
                              ),
                            Text(
                              item.title,
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                            if (item.detail != null)
                              Text(
                                item.detail!,
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ActivityMark extends StatelessWidget {
  const _ActivityMark({required this.item, required this.palette});

  final _Activity item;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) {
    final state = item.state;
    final color = _semanticColor(context, state) ?? palette.muted;
    final glyph = switch (state) {
      _State.ok => Icons.check_rounded,
      _State.warning => Icons.priority_high_rounded,
      _State.error => Icons.close_rounded,
      _ => item.icon,
    };
    if (glyph == null) {
      return SizedBox(
        width: 16,
        height: 16,
        child: Center(
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      );
    }
    return Icon(glyph, size: 16, color: color);
  }
}

// ── ScheduleTile ─────────────────────────────────────────────────────────

Widget _buildScheduleTile(CatalogItemContext context) {
  final data = _props(context);
  final title = _text(data['title'], 80);
  final start = _text(data['start'], 40);
  if (title == null ||
      start == null ||
      !_optionalText(data, 'end', 40) ||
      !_optionalText(data, 'date', 40) ||
      !_optionalText(data, 'location', 100) ||
      !_optionalText(data, 'detail', 120) ||
      !_optionalText(data, 'owner', 60) ||
      !_optionalEnum(data, 'state', _stateValues) ||
      !_optionalEnum(data, 'icon', _iconValues)) {
    return _invalid(context.buildContext);
  }
  final end = _text(data['end'], 40);
  final date = _text(data['date'], 40);
  final location = _text(data['location'], 100);
  final detail = _text(data['detail'], 120);
  final owner = _text(data['owner'], 60);
  final state = _State.parse(data['state']);
  final icon = _iconFor(data['icon']);
  final build = context.buildContext;
  final palette = _palette(build);
  final semantic = _semanticColor(build, state);
  final meta = [?date, ?location, ?owner].join(' · ');
  return Semantics(
    container: true,
    label: [
      '$title, starts $start',
      if (end != null) 'ends $end',
      ?date,
      ?location,
      ?owner,
      ?state?.label,
      ?detail,
    ].join(', '),
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: hermezOutline(palette, semantic),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 56, maxWidth: 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      start,
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (end != null)
                      Text(
                        end,
                        style: TextStyle(color: palette.muted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (icon != null) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(icon, size: 16, color: palette.muted),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
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
                    if (state != null && state != _State.ok)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _StateWord(state: state, palette: palette),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ── MessagePreview ───────────────────────────────────────────────────────

Widget _buildMessagePreview(CatalogItemContext context) {
  final data = _props(context);
  final sender = _text(data['sender'], 80);
  final preview = _text(data['preview'], 240);
  const channels = ['email', 'teams', 'agentmail', 'message', 'unknown'];
  if (sender == null ||
      preview == null ||
      !_optionalText(data, 'title', 100) ||
      !_optionalText(data, 'timestamp', 40) ||
      !_optionalEnum(data, 'channel', channels) ||
      !_optionalBool(data, 'unread') ||
      !_optionalEnum(data, 'importance', ['normal', 'important'])) {
    return _invalid(context.buildContext);
  }
  final title = _text(data['title'], 100);
  final timestamp = _text(data['timestamp'], 40);
  final channel = data['channel'] as String? ?? 'unknown';
  final unread = data['unread'] == true;
  final important = data['importance'] == 'important';
  final build = context.buildContext;
  final palette = _palette(build);
  final channelLabel = switch (channel) {
    'email' => 'Email',
    'teams' => 'Teams',
    'agentmail' => 'AgentMail',
    'message' => 'Message',
    _ => 'Message',
  };
  final channelIcon = switch (channel) {
    'email' => Icons.mail_outline_rounded,
    'teams' => Icons.forum_outlined,
    'agentmail' => Icons.alternate_email_rounded,
    _ => Icons.chat_bubble_outline_rounded,
  };
  return Semantics(
    container: true,
    label: [
      '${unread ? 'Unread ' : ''}${channelLabel.toLowerCase()} from $sender',
      ?title,
      if (important) 'Important',
      ?timestamp,
      preview,
    ].join(', '),
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: hermezOutline(palette, important ? palette.accent : null),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(channelIcon, size: 14, color: palette.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        Text(
                          channelLabel.toUpperCase(),
                          style: HermezType.technical(palette.muted),
                        ),
                        if (unread)
                          Text(
                            '● UNREAD',
                            style: HermezType.technical(palette.accent),
                          ),
                        if (important)
                          Text(
                            '! IMPORTANT',
                            style: HermezType.technical(palette.accent),
                          ),
                      ],
                    ),
                  ),
                  if (timestamp != null)
                    Text(
                      timestamp,
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                sender,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 15,
                  // Unread is typography plus the mark, not color alone.
                  fontWeight: unread ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
              if (title != null)
                Text(
                  title,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 14,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.muted, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ── Helpers ──────────────────────────────────────────────────────────────

class _Activity {
  const _Activity({
    required this.title,
    this.detail,
    this.time,
    this.icon,
    this.state,
  });

  final String title;
  final String? detail;
  final String? time;
  final IconData? icon;
  final _State? state;
}

enum _State {
  ok('OK'),
  warning('Warning'),
  error('Error'),
  unknown('Unknown');

  const _State(this.label);

  final String label;

  static _State? parse(Object? value) => switch (value) {
    'ok' => ok,
    'warning' => warning,
    'error' => error,
    'unknown' => unknown,
    _ => null,
  };
}

class _StateWord extends StatelessWidget {
  const _StateWord({required this.state, required this.palette});

  final _State state;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) {
    final color = _semanticColor(context, state) ?? palette.muted;
    final icon = switch (state) {
      _State.ok => Icons.check_circle_outline,
      _State.warning => Icons.warning_amber_outlined,
      _State.error => Icons.error_outline,
      _State.unknown => Icons.help_outline,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(state.label.toUpperCase(), style: HermezType.technical(color)),
      ],
    );
  }
}

/// Success, warning and danger from the theme; never the accent. Null for no
/// state or unknown (the quiet outline).
Color? _semanticColor(BuildContext context, _State? state) {
  final status = hermezStatusColorsOf(context);
  return switch (state) {
    _State.ok => status.success,
    _State.warning => status.warning,
    _State.error => status.danger,
    _ => null,
  };
}

IconData? _iconFor(Object? name) => switch (name) {
  'check' => Icons.check_rounded,
  'warning' => Icons.warning_amber_rounded,
  'error' => Icons.error_outline_rounded,
  'info' => Icons.info_outline_rounded,
  'clock' => Icons.schedule_rounded,
  'calendar' => Icons.event_outlined,
  'person' => Icons.person_outline_rounded,
  'bot' => Icons.smart_toy_outlined,
  'file' => Icons.insert_drive_file_outlined,
  'link' => Icons.link_rounded,
  'storage' => Icons.storage_rounded,
  'server' => Icons.dns_outlined,
  'chart' => Icons.show_chart_rounded,
  'task' => Icons.task_alt_rounded,
  _ => null,
};

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

double? _finite(Object? value) {
  if (value is! num) return null;
  final number = value.toDouble();
  return number.isFinite ? number : null;
}

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

String _oneDecimal(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

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
