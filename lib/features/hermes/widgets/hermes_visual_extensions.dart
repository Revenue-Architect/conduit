import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
// ignore: depend_on_referenced_packages
import 'package:json_schema_builder/json_schema_builder.dart';

import 'hermes_visual_extension_schemas.dart';
import 'hermes_a2ui_media_scope.dart';
import 'hermes_a2ui_interaction_lock.dart';
import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';
import 'hermez_expandable_section.dart';
import 'hermes_visual_structure.dart' show hermezOutline;

final hermesVisualExtensionSchemas = (jsonDecode(
  hermesVisualExtensionSchemasJson,
) as Map).cast<String, dynamic>();

/// Data-only widgets. Their controls change local presentation, never dispatch
/// a turn, fetch assets, send a draft, apply a change, or infer missing facts.
final List<CatalogItem> hermesExtensionCatalogItems = [
  for (final entry in hermesVisualExtensionSchemas.entries)
    CatalogItem(
      name: entry.key,
      dataSchema: Schema.fromMap(Map<String, Object?>.from(entry.value as Map)),
      widgetBuilder: (ctx) {
        final data = Map<String, dynamic>.from(ctx.data as Map);
        return ExtensionVisual(
          key: ValueKey('${entry.key}:${jsonEncode(data)}'),
          kind: entry.key,
          data: data,
          action: data['actionChild'] is String
              ? ctx.buildChild(data['actionChild'] as String)
              : null,
        );
      },
    ),
];

/// Semantic checks that JSON schema alone cannot express. Fail closed before
/// drawing a misleading chart, geometry, tree, or truncated table.
bool validExtensionSemantics(String kind, Map<String, dynamic> d) {
  List<Map<String, dynamic>> maps(String key) =>
      (d[key] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  switch (kind) {
    case 'DataTable':
      return (d['rows'] as List).every(
        (r) => (r as List).length == (d['columns'] as List).length,
      );
    case 'MultiSeriesChart':
      return maps('series').every(
        (s) => (s['values'] as List).length == (d['labels'] as List).length,
      );
    case 'ScenarioSlider':
      final lo = (d['min'] as num).toDouble(),
          hi = (d['max'] as num).toDouble(),
          v = (d['value'] as num).toDouble();
      final m = (d['multiplier'] as num).toDouble(),
          b = (d['offset'] as num).toDouble();
      return lo < hi &&
          v >= lo &&
          v <= hi &&
          (lo * m + b).isFinite &&
          (hi * m + b).isFinite;
    case 'Agenda':
    case 'CalendarGrid':
      final events = maps('events');
      final dates = events.map((e) => e['date'] as String).toSet().toList()
        ..sort();
      for (final date in dates) {
        final parsed = DateTime.tryParse(date);
        if (parsed == null ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
            parsed.toIso8601String().substring(0, 10) != date) {
          return false;
        }
      }
      return kind != 'CalendarGrid' ||
          DateTime.parse(dates.last)
                  .difference(DateTime.parse(dates.first))
                  .inDays <=
              6;
    case 'DecisionTree':
      final nodes = maps('nodes');
      final ids = nodes.map((e) => e['id'] as String).toSet();
      if (ids.length != nodes.length || !ids.contains(d['start'])) return false;
      final byId = {for (final n in nodes) n['id'] as String: n};
      final visited = <String>{}, active = <String>{};
      bool walk(String id, int depth) {
        if (depth > 12 || active.contains(id) || !ids.contains(id)) {
          return false;
        }
        if (visited.contains(id)) return true;
        active.add(id);
        for (final o in byId[id]!['options'] as List) {
          if (!walk(o['target'] as String, depth + 1)) return false;
        }
        active.remove(id);
        visited.add(id);
        return true;
      }
      return walk(d['start'] as String, 0) && visited.length == nodes.length;
    case 'RelationshipMap':
      final nodes = maps('nodes'), ids = nodes.map((e) => e['id']).toSet();
      return ids.length == nodes.length &&
          maps('edges').every(
            (e) => ids.contains(e['source']) && ids.contains(e['target']),
          );
    case 'BeforeAfterViewer':
      return d.containsKey('beforeMedia') == d.containsKey('afterMedia');
    case 'RoomMap':
      final rooms = maps('rooms');
      return rooms.map((r) => r['id']).toSet().length == rooms.length &&
          rooms.every(
            (r) =>
                (r['x'] as num) + (r['width'] as num) <= 1.000001 &&
                (r['y'] as num) + (r['height'] as num) <= 1.000001,
          );
  }
  return true;
}

class ExtensionVisual extends StatefulWidget {
  const ExtensionVisual({
    super.key,
    required this.kind,
    required this.data,
    this.action,
  });
  final String kind;
  final Map<String, dynamic> data;
  final Widget? action;
  @override
  State<ExtensionVisual> createState() => _ExtensionVisualState();
}

class _ExtensionVisualState extends State<ExtensionVisual> {
  int selected = 0;
  double? scenario;
  String? branch;
  bool after = false;
  bool columnView = false;
  HermezChatPalette get palette =>
      HermezChatPalette.forBrightness(Theme.of(context).brightness);
  Map<String, dynamic> get d => widget.data;
  List<Map<String, dynamic>> rows(String key) =>
      (d[key] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Widget text(Object? value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      '$value',
      style: strong ? HermezType.section(palette) : HermezType.body(palette),
    ),
  );
  Widget detail(String title, String body) =>
      _ExtensionDetail(title: title, body: body);
  Widget field(String label, Object? value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: HermezType.technical(palette.muted)),
        const SizedBox(height: 4),
        SelectableText('$value', style: HermezType.body(palette)),
      ],
    ),
  );
  Widget choice(String label, bool active, VoidCallback onTap) => Semantics(
    button: true,
    selected: active,
    child: HermezMotionSurface(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: hermezOutline(
          palette,
          active ? palette.accent : null,
          radius: 12,
        ),
        child: Text(
          label,
          style: HermezType.body(palette).copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (!validExtensionSemantics(widget.kind, d)) {
      return const Text('Visual unavailable: inconsistent data');
    }
    return HermesA2uiLocalControl(
      child: HermezSurface(
        kind: HermezSurfaceKind.utility,
        motif: HermezMotif.etched,
        border: Border.all(color: palette.border),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text(d['title'], strong: true),
              ...body(),
              if (widget.action != null) ...[
                const SizedBox(height: 12),
                // Local controls bypass the surface pointer lock. A conversational
                // child must explicitly restore it, including while busy/read-only.
                IgnorePointer(
                  ignoring: HermesA2uiInteractionLock.lockedOf(context),
                  child: widget.action!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> body() {
    switch (widget.kind) {
      case 'CitationCard':
      case 'SourceExcerpt':
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.description_outlined, color: palette.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(child: field('Source · ${d['location']}', d['source'])),
            ],
          ),
          field('Source excerpt', d['excerpt']),
          if (d['finding'] != null) ...[
            const Divider(),
            field('Finding', d['finding']),
          ],
        ];
      case 'DraftReview':
        return [
          Text('DRAFT / NOT SENT', style: HermezType.technical(palette.muted)),
          const SizedBox(height: 16),
          field('To', d['recipient']),
          field('Subject', d['subject']),
          const Divider(),
          field('Message', d['body']),
        ];
      case 'DataTable':
        final columns = (d['columns'] as List).cast<String>();
        return [
          Text(
            '${(d['rows'] as List).length} RECORDS / ${columns.length} FIELDS',
            style: HermezType.technical(palette.muted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              choice(
                'Records',
                !columnView,
                () => setState(() => columnView = false),
              ),
              choice(
                'Compare columns',
                columnView,
                () => setState(() => columnView = true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (columnView)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(160),
                border: TableBorder.all(color: palette.border),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: palette.canvas),
                    children: [
                      for (final label in columns)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            label,
                            style: HermezType.section(palette),
                          ),
                        ),
                    ],
                  ),
                  for (final row in d['rows'] as List)
                    TableRow(
                      children: [
                        for (final value in row as List)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              '$value',
                              style: HermezType.body(palette),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            )
          else
            for (var r = 0; r < (d['rows'] as List).length; r++) ...[
              if (r != 0) const Divider(height: 24),
              Text(
                'RECORD ${r + 1}',
                style: HermezType.technical(palette.muted),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < columns.length; i++)
                field(columns[i], d['rows'][r][i]),
            ],
        ];
      case 'ChangeDiff':
        final before = (d['before'] as String).split('\n'),
            after = (d['after'] as String).split('\n');
        // Linear prefix/suffix comparison preserves line order, including
        // repeats. The changed span is intentionally not a minimal patch.
        var prefix = 0;
        while (prefix < before.length &&
            prefix < after.length &&
            before[prefix] == after[prefix]) {
          prefix++;
        }
        var suffix = 0;
        while (suffix < before.length - prefix &&
            suffix < after.length - prefix &&
            before[before.length - 1 - suffix] ==
                after[after.length - 1 - suffix]) {
          suffix++;
        }
        final removed = before.sublist(prefix, before.length - suffix);
        final added = after.sublist(prefix, after.length - suffix);
        return [
          text('Preview only · changed span, not an applicable patch'),
          for (final line in removed) text('− $line'),
          for (final line in added) text('+ $line'),
          detail('Full before', d['before'] as String),
          detail('Full after', d['after'] as String),
        ];
      case 'BeforeAfterViewer':
        return [
          Wrap(
            spacing: 8,
            children: [
              choice('Before', !after, () => setState(() => after = false)),
              choice('After', after, () => setState(() => after = true)),
            ],
          ),
          const SizedBox(height: 8),
          if (d[after ? 'afterMedia' : 'beforeMedia'] case final String path)
            HermesA2uiMediaScope.image(context, path),
          SelectableText(
            d[after ? 'after' : 'before'] as String,
            style: HermezType.body(palette),
          ),
        ];
      case 'Agenda':
      case 'CalendarGrid':
        final events = rows('events');
        final dates = events.map((e) => e['date'] as String).toSet().toList()
          ..sort();
        final first = DateTime.parse(dates.first);
        final choices = widget.kind == 'CalendarGrid'
            ? [
                for (var i = 0; i < 7; i++)
                  first
                      .add(Duration(days: i))
                      .toIso8601String()
                      .substring(0, 10),
              ]
            : dates;
        return [
          text('Timezone: ${d['timezone']}'),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < choices.length; i++)
                choice(
                  choices[i],
                  selected == i,
                  () => setState(() => selected = i),
                ),
            ],
          ),
          for (final e in events.where((e) => e['date'] == choices[selected]))
            detail('${e['time']} · ${e['label']}', e['detail'] as String),
          if (!events.any((e) => e['date'] == choices[selected]))
            text('No supplied events for this day'),
        ];
      case 'DecisionTree':
        final nodes = rows('nodes'),
            current = nodes.firstWhere(
              (e) => e['id'] == (branch ?? d['start']),
            );
        return [
          text(current['label'], strong: true),
          text(current['detail']),
          for (final option in current['options'] as List)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: OutlinedButton(
                onPressed: () =>
                    setState(() => branch = option['target'] as String),
                child: Text(option['label'] as String),
              ),
            ),
          TextButton(
            onPressed: () => setState(() => branch = null),
            child: const Text('Reset choices'),
          ),
        ];
      case 'ScenarioSlider':
        final lo = (d['min'] as num).toDouble(),
            hi = (d['max'] as num).toDouble(),
            value = scenario ?? (d['value'] as num).toDouble();
        final output = value * (d['multiplier'] as num) + (d['offset'] as num);
        return [
          text('${d['inputLabel']}: ${value.toStringAsFixed(2)}'),
          Slider(
            value: value,
            min: lo,
            max: hi,
            label: value.toStringAsFixed(2),
            onChanged: (v) => setState(() => scenario = v),
          ),
          text(
            'Estimate: ${output.toStringAsFixed(2)} ${d['unit']}',
            strong: true,
          ),
          text('Formula: input × ${d['multiplier']} + ${d['offset']}'),
          text('Assumptions: ${d['assumptions']}'),
        ];
      case 'MultiSeriesChart':
        final series = rows('series'),
            labels = (d['labels'] as List).cast<String>();
        final values = [
          for (final s in series) ...(s['values'] as List).cast<num>(),
        ];
        final minV = values.reduce(math.min).toDouble(),
            maxV = values.reduce(math.max).toDouble();
        final colors = [
          palette.accent,
          palette.ink,
          palette.muted,
          Theme.of(context).colorScheme.tertiary,
        ];
        return [
          text('${labels.first} → ${labels.last} · ${d['unit']}'),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(
              painter: _SeriesPainter(
                series,
                minV,
                maxV,
                colors,
                palette.border,
              ),
            ),
          ),
          text('Scale: $minV – $maxV ${d['unit']}'),
          for (var i = 0; i < series.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(width: 12, height: 12, color: colors[i]),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${i + 1}. ${series[i]['label']}')),
                ],
              ),
            ),
          for (var i = 0; i < series.length; i++)
            detail(
              'Series ${i + 1}: ${series[i]['label']}',
              [
                for (var j = 0; j < labels.length; j++)
                  '${labels[j]}: ${series[i]['values'][j]} ${d['unit']}',
              ].join('\n'),
            ),
        ];
      case 'RelationshipMap':
        final nodes = rows('nodes'), edges = rows('edges');
        return [
          SizedBox(
            height: 220,
            width: double.infinity,
            child: CustomPaint(
              painter: _RelationshipPainter(
                nodes,
                edges,
                palette.accent,
                palette.onAccent,
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < nodes.length; i++)
                choice(
                  '${i + 1}. ${nodes[i]['label']}',
                  selected == i,
                  () => setState(() => selected = i),
                ),
            ],
          ),
          text(nodes[selected]['detail']),
          for (final e in edges)
            text(
              '${nodes.firstWhere((n) => n['id'] == e['source'])['label']} → ${nodes.firstWhere((n) => n['id'] == e['target'])['label']}: ${e['label']}',
            ),
        ];
      case 'RoomMap':
        final rooms = rows('rooms');
        return [
          text(d['provenance']),
          if (d['backgroundMedia'] case final String path)
            HermesA2uiMediaScope.image(context, path),
          SizedBox(
            height: 220,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (ctx, box) => Stack(
                children: [
                  for (var i = 0; i < rooms.length; i++)
                    Positioned(
                      left: (rooms[i]['x'] as num) * box.maxWidth,
                      top: (rooms[i]['y'] as num) * 220,
                      width: (rooms[i]['width'] as num) * box.maxWidth,
                      height: (rooms[i]['height'] as num) * 220,
                      child: Semantics(
                        label: rooms[i]['label'] as String,
                        button: true,
                        child: InkWell(
                          onTap: () => setState(() => selected = i),
                          child: Container(
                            decoration: BoxDecoration(
                              color: palette.surface,
                              border: Border.all(
                                color: selected == i
                                    ? palette.accent
                                    : palette.border,
                                width: selected == i ? 1.4 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${i + 1}',
                              style: HermezType.section(palette),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < rooms.length; i++)
                choice(
                  '${i + 1}. ${rooms[i]['label']}',
                  selected == i,
                  () => setState(() => selected = i),
                ),
            ],
          ),
          text(rooms[selected]['detail']),
        ];
      case 'JourneyMap':
        return [
          for (final s in rows('stages'))
            detail(
              '${s['time']} · ${s['label']}',
              '${s['place']}\nCost: ${s['cost']}\n${s['detail']}',
            ),
        ];
      case 'EvidenceTrail':
        return [
          for (final e in rows('items'))
            detail(
              '${e['source']} · ${e['location']}',
              'FACT\n${e['fact']}\n\nINTERPRETATION\n${e['interpretation']}\n\nUNCERTAINTY\n${e['uncertainty']}',
            ),
        ];
    }
    return const [];
  }
}

class _ExtensionDetail extends StatefulWidget {
  const _ExtensionDetail({required this.title, required this.body});
  final String title, body;
  @override
  State<_ExtensionDetail> createState() => _ExtensionDetailState();
}

class _ExtensionDetailState extends State<_ExtensionDetail> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: HermezExpandableSection(
        expanded: expanded,
        onExpansionChanged: (value) => setState(() => expanded = value),
        semanticLabel: widget.title,
        header: Text(
          widget.title,
          style: HermezType.body(palette).copyWith(fontWeight: FontWeight.w700),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(widget.body, style: HermezType.body(palette)),
        ),
      ),
    );
  }
}

class _SeriesPainter extends CustomPainter {
  _SeriesPainter(
    this.series,
    this.minV,
    this.maxV,
    this.colors,
    this.axisColor,
  );
  final List<Map<String, dynamic>> series;
  final double minV, maxV;
  final List<Color> colors;
  final Color axisColor;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()..color = axisColor,
    );
    for (var i = 0; i < series.length; i++) {
      final values = (series[i]['values'] as List).cast<num>(), path = Path();
      for (var j = 0; j < values.length; j++) {
        final x = values.length == 1
            ? size.width / 2
            : j * size.width / (values.length - 1);
        final y = maxV == minV
            ? size.height / 2
            : size.height - (values[j] - minV) / (maxV - minV) * size.height;
        if (j == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        canvas.drawCircle(Offset(x, y), 3, Paint()..color = colors[i]);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[i]
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter old) => true;
}

class _RelationshipPainter extends CustomPainter {
  _RelationshipPainter(this.nodes, this.edges, this.color, this.onColor);
  final List<Map<String, dynamic>> nodes, edges;
  final Color color, onColor;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2),
        radius = math.min(size.width, size.height) * .38;
    final points = {
      for (var i = 0; i < nodes.length; i++)
        nodes[i]['id']:
            center +
            Offset(
              math.cos(i * 2 * math.pi / nodes.length - math.pi / 2) * radius,
              math.sin(i * 2 * math.pi / nodes.length - math.pi / 2) * radius,
            ),
    };
    for (final e in edges) {
      canvas.drawLine(
        points[e['source']]!,
        points[e['target']]!,
        Paint()
          ..color = color.withValues(alpha: .4)
          ..strokeWidth = 2,
      );
    }
    for (var i = 0; i < nodes.length; i++) {
      final p = points[nodes[i]['id']]!;
      canvas.drawCircle(p, 14, Paint()..color = color);
      final t = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: onColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      t.paint(canvas, p - Offset(t.width / 2, t.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RelationshipPainter old) => true;
}
