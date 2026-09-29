import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
// GenUI's public CatalogItem API uses this transitive schema-builder type but
// does not re-export it; GenUI is pinned and the builder is locked transitively.
// ignore: depend_on_referenced_packages
import 'package:json_schema_builder/json_schema_builder.dart';

import 'hermes_visual_structure.dart';
import 'hermez_visual_theme.dart';

/// Extends GenUI's safe, no-asset basic catalog with app-owned data widgets.
/// No component in this catalog performs network or filesystem access.
Catalog createHermesVisualCatalog() {
  return BasicCatalogItems.asNoAssetCatalog().copyWith(
    newItems: [
      _hermezCard,
      _hermezButton,
      _statusBadge,
      _metricTile,
      _miniChart,
      ...hermesStructureCatalogItems,
    ],
  );
}

/// Keep the v0.9 basic catalog schema while rendering its common containers
/// with the same spacing as the rest of Hermez.
final _hermezCard = CatalogItem(
  name: 'Card',
  dataSchema: BasicCatalogItems.card.dataSchema,
  widgetBuilder: (itemContext) {
    final data = itemContext.data;
    final child = data is Map ? data['child'] : null;
    if (child is! String) {
      return BasicCatalogItems.card.widgetBuilder(itemContext);
    }
    final scheme = Theme.of(itemContext.buildContext).colorScheme;
    return Card(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: itemContext.buildChild(child),
      ),
    );
  },
  exampleData: BasicCatalogItems.card.exampleData,
);

/// GenUI's default Button explicitly paints itself surface-colored, bypassing
/// the app's button theme. Reuse its action and validation implementation with
/// a local color scheme for the default variant; primary/borderless keep their
/// documented behavior. No agent-provided color or executable UI is accepted.
final _hermezButton = CatalogItem(
  name: 'Button',
  dataSchema: BasicCatalogItems.button.dataSchema,
  widgetBuilder: (itemContext) {
    final data = itemContext.data;
    if (data is Map && data['variant'] != null) {
      return BasicCatalogItems.button.widgetBuilder(itemContext);
    }
    return Builder(
      builder: (context) {
        final base = Theme.of(context);
        final scheme = base.colorScheme;
        return Theme(
          data: base.copyWith(
            colorScheme: scheme.copyWith(
              surface: scheme.primary,
              onSurface: scheme.onPrimary,
            ),
          ),
          child: Builder(
            builder: (innerContext) => BasicCatalogItems.button.widgetBuilder(
              CatalogItemContext(
                data: itemContext.data,
                id: itemContext.id,
                type: itemContext.type,
                buildChild: itemContext.buildChild,
                dispatchEvent: itemContext.dispatchEvent,
                buildContext: innerContext,
                dataContext: itemContext.dataContext,
                getComponent: itemContext.getComponent,
                getCatalogItem: itemContext.getCatalogItem,
                surfaceId: itemContext.surfaceId,
                reportError: itemContext.reportError,
              ),
            ),
          ),
        );
      },
    );
  },
  exampleData: BasicCatalogItems.button.exampleData,
);

final _statusBadge = CatalogItem(
  name: 'StatusBadge',
  dataSchema: S.object(
    description:
        'A compact service state with an icon and a visible state word.',
    properties: {
      'label': S.string(description: 'Short service or subsystem name.'),
      'state': S.string(
        enumValues: ['ok', 'warning', 'error', 'unknown'],
        description: 'The observed state; use unknown when not checked.',
      ),
      'detail': S.string(description: 'Optional short evidence or detail.'),
    },
    required: ['label', 'state'],
  ),
  widgetBuilder: (context) => _buildStatusBadge(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"StatusBadge","label":"Hermes","state":"ok","detail":"Gateway connected"}
      ]
    ''',
  ],
);

final _metricTile = CatalogItem(
  name: 'MetricTile',
  dataSchema: S.object(
    description:
        'A prominent numeric value with an explicit unit and optional range.',
    properties: {
      'label': S.string(description: 'Short metric name.'),
      'value': S.number(description: 'Observed numeric value.'),
      'unit': S.string(description: 'Unit such as %, GiB, or ms.'),
      'min': S.number(description: 'Optional lower end of a meaningful range.'),
      'max': S.number(description: 'Optional upper end of a meaningful range.'),
      'state': S.string(
        enumValues: ['ok', 'warning', 'error', 'unknown'],
        description: 'Optional observed state for this metric.',
      ),
      'asOf': S.string(description: 'ISO 8601 observation time.'),
      'source': S.string(description: 'Short source or check description.'),
    },
    required: ['label', 'value'],
  ),
  widgetBuilder: (context) => _buildMetricTile(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"MetricTile","label":"Storage used","value":86,"unit":"%","min":0,"max":100,"state":"warning","asOf":"2026-09-24T18:04:00Z","source":"Filesystem check"}
      ]
    ''',
  ],
);

final _miniChart = CatalogItem(
  name: 'MiniChart',
  dataSchema: S.object(
    description:
        'A native, data-only line or bar chart for observed numeric samples.',
    properties: {
      'label': S.string(description: 'Short series title.'),
      'kind': S.string(enumValues: ['line', 'bar']),
      'points': S.list(
        items: S.object(
          properties: {
            'label': S.string(description: 'Short time or category label.'),
            'value': S.number(description: 'Observed value.'),
          },
          required: ['label', 'value'],
        ),
        minItems: 0,
        maxItems: 60,
        description: 'Ordered observations. Values are never invented.',
      ),
      'unit': S.string(description: 'Optional unit shown with values.'),
      'asOf': S.string(description: 'ISO 8601 time of the latest sample.'),
      'source': S.string(description: 'Short source for these observations.'),
    },
    required: ['label', 'kind', 'points'],
  ),
  widgetBuilder: (context) => _buildMiniChart(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"MiniChart","label":"Storage used","kind":"line","unit":"%","points":[{"label":"Sep 22","value":80},{"label":"Sep 23","value":83},{"label":"Sep 24","value":86}],"asOf":"2026-09-24T18:04:00Z","source":"Daily filesystem samples"}
      ]
    ''',
  ],
);

Widget _buildStatusBadge(CatalogItemContext context) {
  final data = _properties(context);
  final label = _boundedText(data['label'], maxLength: 64);
  final detail = _boundedText(data['detail'], maxLength: 120);
  final state = _VisualState.parse(data['state']);
  if (label == null ||
      state == null ||
      !_optionalTextIsValid(data, 'detail', maxLength: 120)) {
    return _invalidVisual(context.buildContext);
  }

  final theme = Theme.of(context.buildContext);
  final color = _stateColor(theme, state);
  final stateLabel = state.label;
  final semanticLabel = [label, stateLabel, ?detail].join('. ');

  final icon = Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Icon(state.icon, color: color, size: 22),
  );

  return Semantics(
    label: semanticLabel,
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isBounded = constraints.hasBoundedWidth;
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isBounded ? label : _shortDisplayText(label, 18),
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    stateLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      isBounded ? detail : _shortDisplayText(detail, 20),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              );
              return isBounded
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icon,
                        const SizedBox(width: 10),
                        Expanded(child: details),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [icon, const SizedBox(height: 6), details],
                    );
            },
          ),
        ),
      ),
    ),
  );
}

Widget _buildMetricTile(CatalogItemContext context) {
  final data = _properties(context);
  final label = _boundedText(data['label'], maxLength: 64);
  final value = _finiteNumber(data['value']);
  final state = data.containsKey('state')
      ? _VisualState.parse(data['state'])
      : null;
  if (label == null ||
      value == null ||
      (data.containsKey('state') && state == null) ||
      !_optionalTextIsValid(data, 'unit', maxLength: 16) ||
      !_optionalTextIsValid(data, 'source', maxLength: 100) ||
      !_optionalTimestampIsValid(data)) {
    return _invalidVisual(context.buildContext);
  }

  final unit = _boundedText(data['unit'], maxLength: 16);
  final source = _boundedText(data['source'], maxLength: 100);
  final asOf = _boundedText(data['asOf'], maxLength: 40);
  final min = _finiteNumber(data['min']);
  final max = _finiteNumber(data['max']);
  if ((data.containsKey('min') && min == null) ||
      (data.containsKey('max') && max == null) ||
      (min == null) != (max == null)) {
    return _invalidVisual(context.buildContext);
  }
  final hasRange = min != null && max != null && max > min;
  final inRange = hasRange && value >= min && value <= max;
  final outsideRange = hasRange && !inRange;
  final theme = Theme.of(context.buildContext);
  final color = outsideRange
      ? theme.colorScheme.error
      : _stateColor(theme, state ?? _VisualState.unknown);
  final displayValue = _formatNumber(value);
  final valueText = '$displayValue${unit == null ? '' : ' $unit'}';
  final rangeText = outsideRange ? 'Outside expected range' : state?.label;
  final semantics = [
    label,
    valueText,
    if (hasRange)
      'Range ${_formatNumber(min)} to ${_formatNumber(max)}${unit == null ? '' : ' $unit'}',
    ?rangeText,
    ?_withPrefix(source, 'Source: '),
    ?_withPrefix(asOf, 'As of '),
  ].join('. ');

  return LayoutBuilder(
    builder: (context, constraints) {
      final isBounded = constraints.hasBoundedWidth;
      return Semantics(
        label: semantics,
        child: ExcludeSemantics(
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isBounded ? label : _shortDisplayText(label, 18),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    valueText,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (hasRange && inRange && constraints.hasBoundedWidth) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: ((value - min) / (max - min))
                          .clamp(0.0, 1.0)
                          .toDouble(),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                      color: color,
                    ),
                  ],
                  if (hasRange) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_formatNumber(min)} – ${_formatNumber(max)}${unit == null ? '' : ' $unit'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (rangeText != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      isBounded ? rangeText : _shortDisplayText(rangeText, 18),
                      style: theme.textTheme.bodySmall?.copyWith(color: color),
                    ),
                  ],
                  if (source != null || asOf != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      [
                        if (source != null)
                          isBounded ? source : _shortDisplayText(source, 12),
                        if (asOf != null)
                          isBounded ? asOf : _shortDisplayText(asOf, 12),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

Widget _buildMiniChart(CatalogItemContext context) {
  final data = _properties(context);
  final label = _boundedText(data['label'], maxLength: 64);
  final kind = data['kind'];
  final rawPoints = data['points'];
  if (label == null ||
      (kind != 'line' && kind != 'bar') ||
      rawPoints is! List ||
      rawPoints.length > 60) {
    return _invalidVisual(context.buildContext);
  }

  final points = <_ChartPoint>[];
  for (final rawPoint in rawPoints) {
    if (rawPoint is! Map) return _invalidVisual(context.buildContext);
    final pointLabel = _boundedText(rawPoint['label'], maxLength: 64);
    final value = _finiteNumber(rawPoint['value']);
    if (pointLabel == null || value == null) {
      return _invalidVisual(context.buildContext);
    }
    points.add(_ChartPoint(pointLabel, value));
  }

  final unit = _boundedText(data['unit'], maxLength: 16);
  final source = _boundedText(data['source'], maxLength: 100);
  final asOf = _boundedText(data['asOf'], maxLength: 40);
  if (!_optionalTextIsValid(data, 'unit', maxLength: 16) ||
      !_optionalTextIsValid(data, 'source', maxLength: 100) ||
      !_optionalTimestampIsValid(data)) {
    return _invalidVisual(context.buildContext);
  }
  final theme = Theme.of(context.buildContext);
  final color = theme.colorScheme.primary;
  if (points.isEmpty) {
    return _chartFallback(context.buildContext, label, 'No observations yet.');
  }
  if (points.length == 1) {
    return _chartFallback(
      context.buildContext,
      label,
      'One sample: ${_formatNumber(points.single.value)}${unit == null ? '' : ' $unit'}. Add another observation to show a trend.',
    );
  }

  final values = points.map((point) => point.value).toList(growable: false);
  final minimum = values.reduce((a, b) => math.min(a, b).toDouble());
  final maximum = values.reduce((a, b) => math.max(a, b).toDouble());
  final summary =
      '$label, ${points.length} observations, from ${points.first.label} ${_formatNumber(points.first.value)}${unit == null ? '' : ' $unit'} to ${points.last.label} ${_formatNumber(points.last.value)}${unit == null ? '' : ' $unit'}, range ${_formatNumber(minimum)} to ${_formatNumber(maximum)}${unit == null ? '' : ' $unit'}.';

  return LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.hasBoundedWidth) {
        final compactMessage = [
          '${points.length} samples',
          'Latest ${_formatNumber(points.last.value)}${unit == null ? '' : ' $unit'}',
          if (source != null) 'Source: ${_shortDisplayText(source, 12)}',
          if (asOf != null) 'As of ${_shortDisplayText(asOf, 12)}',
        ].join('\n');
        return Semantics(
          label: [
            summary,
            if (source != null) 'Source: $source',
            if (asOf != null) 'As of $asOf',
          ].join(' '),
          child: ExcludeSemantics(
            child: _chartFallback(
              context,
              _shortDisplayText(label, 18),
              compactMessage,
            ),
          ),
        );
      }
      return Semantics(
        label: [
          summary,
          if (source != null) 'Source: $source',
          if (asOf != null) 'As of $asOf',
        ].join(' '),
        child: ExcludeSemantics(
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 52,
                        height: 132,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatAxisNumber(maximum),
                              style: theme.textTheme.labelSmall,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _formatAxisNumber(minimum),
                              style: theme.textTheme.labelSmall,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 132,
                          child: CustomPaint(
                            key: const ValueKey<String>('hermes-mini-chart'),
                            painter: _MiniChartPainter(
                              points: points,
                              kind: kind as String,
                              color: color,
                              gridColor: theme.colorScheme.outlineVariant,
                              baseline: math.min(0, minimum),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          points.first.label,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      if (points.length > 2)
                        Text(
                          '${points.length} samples',
                          style: theme.textTheme.labelSmall,
                        ),
                      Expanded(
                        child: Text(
                          points.last.label,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                  if (unit != null || source != null || asOf != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      [?unit, ?source, ?asOf].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

Widget _chartFallback(BuildContext context, String label, String message) {
  final theme = Theme.of(context);
  return Semantics(
    label: '$label. $message',
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(message, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    ),
  );
}

Widget _invalidVisual(BuildContext context) {
  return _chartFallback(
    context,
    'Visual unavailable',
    'The supplied values could not be displayed safely.',
  );
}

Map<String, Object?> _properties(CatalogItemContext context) =>
    context.data is Map<String, Object?>
    ? context.data as Map<String, Object?>
    : const <String, Object?>{};

String? _boundedText(Object? value, {required int maxLength}) {
  if (value == null) return null;
  if (value is! String || value.length > maxLength) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _shortDisplayText(String value, int maxCharacters) =>
    value.length <= maxCharacters
    ? value
    : '${value.substring(0, maxCharacters - 1)}…';

bool _optionalTextIsValid(
  Map<String, Object?> data,
  String key, {
  required int maxLength,
}) =>
    !data.containsKey(key) ||
    _boundedText(data[key], maxLength: maxLength) != null;

String? _withPrefix(String? value, String prefix) =>
    value == null ? null : '$prefix$value';

bool _optionalTimestampIsValid(Map<String, Object?> data) {
  if (!data.containsKey('asOf')) return true;
  final value = _boundedText(data['asOf'], maxLength: 40);
  return value != null && DateTime.tryParse(value) != null;
}

double? _finiteNumber(Object? value) {
  if (value is! num) return null;
  final number = value.toDouble();
  return number.isFinite ? number : null;
}

String _formatNumber(double value) {
  final magnitude = value.abs();
  if (magnitude >= 100000 || (magnitude > 0 && magnitude < 0.01)) {
    return _formatScientific(value);
  }
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _formatAxisNumber(double value) =>
    value.abs() >= 1000 ? _formatScientific(value) : _formatNumber(value);

String _formatScientific(double value) => value
    .toStringAsExponential(1)
    .replaceFirst('.0e', 'e')
    .replaceFirst('e+', 'e');

Color _stateColor(ThemeData theme, _VisualState state) => switch (state) {
  _VisualState.ok =>
    theme.extension<HermezStatusColors>()?.success ?? theme.colorScheme.primary,
  _VisualState.warning =>
    theme.extension<HermezStatusColors>()?.warning ??
        theme.colorScheme.tertiary,
  _VisualState.error =>
    theme.extension<HermezStatusColors>()?.danger ?? theme.colorScheme.error,
  _VisualState.unknown => theme.colorScheme.onSurfaceVariant,
};

enum _VisualState {
  ok('OK', Icons.check_circle_outline),
  warning('Warning', Icons.warning_amber_outlined),
  error('Error', Icons.error_outline),
  unknown('Unknown', Icons.help_outline);

  const _VisualState(this.label, this.icon);

  final String label;
  final IconData icon;

  static _VisualState? parse(Object? value) => switch (value) {
    'ok' => ok,
    'warning' => warning,
    'error' => error,
    'unknown' => unknown,
    _ => null,
  };
}

class _ChartPoint {
  const _ChartPoint(this.label, this.value);

  final String label;
  final double value;
}

class _MiniChartPainter extends CustomPainter {
  const _MiniChartPainter({
    required this.points,
    required this.kind,
    required this.color,
    required this.gridColor,
    required this.baseline,
  });

  final List<_ChartPoint> points;
  final String kind;
  final Color color;
  final Color gridColor;
  final double baseline;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;
    final values = points.map((point) => point.value).toList(growable: false);
    final minimum = values.reduce((a, b) => math.min(a, b).toDouble());
    final maximum = values.reduce((a, b) => math.max(a, b).toDouble());
    final rawMin = math.min(minimum, baseline).toDouble();
    final rawMax = maximum;
    // Normalize before subtracting: two finite values at opposite extremes
    // can have an infinite difference even though each sample is valid.
    final scale = math.max(rawMin.abs(), rawMax.abs()).toDouble();
    final safeScale = scale == 0 ? 1.0 : scale;
    final normalizedMin = rawMin / safeScale;
    final normalizedMax = rawMax / safeScale;
    final spread = normalizedMax - normalizedMin;
    final padding = spread == 0 ? 0.08 : spread * 0.08;
    final minValue = normalizedMin - padding;
    final maxValue = normalizedMax + padding;
    final valueRange = maxValue - minValue;
    double yFor(double value) =>
        size.height -
        ((value / safeScale - minValue) / valueRange * size.height);
    double xFor(int index) => points.length == 1
        ? size.width / 2
        : index * size.width / (points.length - 1);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var index = 1; index <= 3; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final dataPaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (kind == 'bar') {
      final barPaint = Paint()..color = color;
      final slotWidth = size.width / points.length;
      final barWidth = math.min(24.0, slotWidth * 0.62).toDouble();
      final baselineY = yFor(baseline);
      for (var index = 0; index < points.length; index++) {
        final x = (index + 0.5) * slotWidth;
        final y = yFor(points[index].value);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              x - barWidth / 2,
              math.min(y, baselineY),
              x + barWidth / 2,
              math.max(y, baselineY),
            ),
            const Radius.circular(3),
          ),
          barPaint,
        );
      }
      return;
    }

    final path = Path()..moveTo(xFor(0), yFor(points.first.value));
    for (var index = 1; index < points.length; index++) {
      path.lineTo(xFor(index), yFor(points[index].value));
    }
    canvas.drawPath(path, dataPaint);
    final pointPaint = Paint()..color = color;
    for (var index = 0; index < points.length; index++) {
      canvas.drawCircle(
        Offset(xFor(index), yFor(points[index].value)),
        3.5,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.kind != kind ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.baseline != baseline;
}
