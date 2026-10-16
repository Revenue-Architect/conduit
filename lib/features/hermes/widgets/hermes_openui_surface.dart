import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/hermes_openui_parser.dart';
import 'hermes_openui_images.dart';
import 'hermez_visual_theme.dart';

/// The same bounded 70-component OpenUI v1 catalog as Hermes Desktop, in Dart.
/// Local edits never send; explicit buttons use the parent's scoped chat path.
class HermesOpenuiSurface extends StatefulWidget {
  const HermesOpenuiSurface({
    super.key,
    required this.payload,
    required this.surfaceId,
    this.onInteraction,
    this.isBusy = false,
    this.superseded = false,
    this.mediaPreview,
    this.remoteImageProvider,
  });
  final String payload;
  final String surfaceId;
  final FutureOr<void> Function(String prompt)? onInteraction;
  final bool isBusy;

  /// A newer user turn already answered this reply. Explicit send buttons are
  /// disabled; tabs, selections and other local edits keep working.
  final bool superseded;

  /// Previews of images declared with MEDIA: in the same reply, or null for a
  /// path that was not declared. Image sources never gain file access.
  final Widget? Function(String path)? mediaPreview;

  /// Replaces the http(s) image provider; tests use it to avoid the network.
  final ImageProvider Function(String url)? remoteImageProvider;
  @override
  State<HermesOpenuiSurface> createState() => _HermesOpenuiSurfaceState();
}

class _HermesOpenuiSurfaceState extends State<HermesOpenuiSurface> {
  HermesOpenuiNode? _root;
  final _values = <String, Map<String, dynamic>>{};
  final _pages = <String, int>{};
  final _checks = <String, Set<int>>{};
  final _invalidFields = <String, String>{};
  bool _sending = false;
  String? _error;
  bool get _locked => widget.isBusy || widget.onInteraction == null || _sending;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant HermesOpenuiSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload != widget.payload ||
        oldWidget.surfaceId != widget.surfaceId) {
      _parse();
    }
  }

  void _parse() {
    _values.clear();
    _invalidFields.clear();
    _pages.clear();
    _checks.clear();
    _error = null;
    _root = null;
    try {
      _root = parseHermesOpenui(widget.payload);
      void initial(HermesOpenuiNode node, String? form) {
        if (node.type == 'Form') {
          form = node.props['name'] as String;
          _values[form] = {};
        }
        if (hermesOpenuiFields.contains(node.type)) {
          _values[form]![node.props['name'] as String] = node.props['initial'];
        }
        for (final child in node.children) {
          initial(child, form);
        }
      }

      initial(_root!, null);
    } on FormatException catch (e) {
      _error = e.message;
    }
  }

  Future<void> _send(HermesOpenuiNode node, String? form) async {
    final callback = widget.onInteraction;
    if (_locked || widget.superseded || callback == null || _root == null) {
      return;
    }
    if (form != null && _invalidFields.values.contains(form)) {
      setState(
        () => _error = 'Correct the highlighted form fields before sending.',
      );
      return;
    }
    final values = form == null ? null : _values[form];
    // Same bounds as Desktop's interaction serializer. Keep oversized edits
    // visible and explain the refusal rather than truncating the user's input.
    if (values != null &&
        values.values.any((v) => v is String && v.length > 2048))
      return;
    final prompt =
        '[A2UI_INTERACTION]\n${jsonEncode({
          'version': 'v0.9',
          'action': {
            'surfaceId': widget.surfaceId,
            'name': 'openui.continue',
            'sourceComponentId': 'openui-button',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'context': {'renderer': 'openui', 'message': node.props['message'], if (form != null) 'form': form, if (values != null) 'values': values},
          },
        })}';
    if (utf8.encode(prompt).length > 65536) {
      setState(
        () => _error = 'These form values are too long to send. Shorten them and try again.',
      );
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await callback(prompt);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The request could not be sent. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: hermezVisualTheme(Theme.of(context)),
    // A native/custom chat need not have a Scaffold or Material ancestor.
    // Bare form controls, chips and ListTiles still need an ink host even
    // when the generated program does not place them inside a Card.
    child: Material(
      type: MaterialType.transparency,
      child: Builder(
        builder: (context) {
          if (_root == null)
            return _panel(context, [
              const Text(
                'This OpenUI could not be displayed. Ask Hermes to regenerate it.',
              ),
              ExpansionTile(
                title: const Text('View source'),
                children: [SelectableText(widget.payload)],
              ),
            ]);
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _column([
              _node(context, _root!, null),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ]),
          );
        },
      ),
    ),
  );

  Widget _column(List<Widget> children) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        children[i],
      ],
    ],
  );
  Widget _panel(BuildContext c, List<Widget> children) => SizedBox(
    width: double.infinity,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _column(children),
      ),
    ),
  );
  Widget _title(BuildContext c, String title, [String subtitle = '']) =>
      _column([
        Text(title, style: Theme.of(c).textTheme.titleMedium),
        if (subtitle.isNotEmpty)
          Text(subtitle, style: Theme.of(c).textTheme.bodySmall),
      ]);
  Widget _badge(BuildContext c, String text, [String tone = 'accent']) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: _color(c, tone).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Text(
            text,
            style: TextStyle(
              color: _color(c, tone),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
  Color _color(BuildContext c, String tone) {
    final theme = Theme.of(c);
    final status = theme.extension<HermezStatusColors>()!;
    return switch (tone) {
      'success' => status.success,
      'warning' => status.warning,
      'error' => status.danger,
      'neutral' => theme.colorScheme.onSurface,
      _ => theme.colorScheme.primary,
    };
  }

  Widget _pairs(BuildContext c, List<dynamic> labels, List<dynamic> values) =>
      _column([
        for (var i = 0; i < labels.length; i++)
          LayoutBuilder(
            builder: (c, b) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: math.min(100, b.maxWidth * .35),
                  child: Text(
                    '${labels[i]}',
                    style: Theme.of(c).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('${values[i]}')),
              ],
            ),
          ),
      ]);
  Widget _grid(BuildContext c, List<Widget> children, int columns) =>
      LayoutBuilder(
        builder: (c, b) {
          final count = b.maxWidth < 320
              ? 1
              : math.min(columns, b.maxWidth < 600 ? 2 : 3);
          final width = math.max(0.0, (b.maxWidth - 12 * (count - 1)) / count);
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final child in children)
                SizedBox(width: width, child: child),
            ],
          );
        },
      );

  HermesOpenuiImageEnvironment get _imageEnvironment =>
      HermesOpenuiImageEnvironment(
        remoteImageProvider: widget.remoteImageProvider,
        mediaPreview: widget.mediaPreview,
      );

  HermesOpenuiImageSpec _imageSpec(Map<String, dynamic> p) =>
      HermesOpenuiImageSpec(
        src: p['src'] as String? ?? '',
        alt: p['alt'] as String? ?? '',
        details: p['details'] as String? ?? '',
      );

  Widget _node(BuildContext c, HermesOpenuiNode node, String? form) {
    final p = node.props;
    final type = node.type;
    String s(String k, [String fallback = '']) => p[k] as String? ?? fallback;
    List<dynamic> list(String k) => p[k] as List? ?? const [];
    List<Widget> children([String? scope]) => [
      for (final n in node.children) _node(c, n, scope ?? form),
    ];
    final theme = Theme.of(c);
    if (hermesOpenuiFields.contains(type)) return _field(c, node, form!);
    switch (type) {
      case 'Stack':
      case 'Tab':
      case 'Timeline':
      case 'Steps':
      case 'Accordion':
        return _column(children());
      case 'Row':
        return Wrap(spacing: 12, runSpacing: 12, children: children());
      case 'Grid':
        return _grid(c, children(), (p['columns'] as num?)?.toInt() ?? 2);
      case 'Card':
        return _panel(c, [
          _title(c, s('title'), s('description')),
          ...children(),
        ]);
      case 'Section':
        return _column([_title(c, s('title')), ...children()]);
      case 'Heading':
        return _title(c, s('title'), s('subtitle'));
      case 'Text':
        return Text(
          s('text'),
          style: TextStyle(color: _color(c, s('tone', 'neutral'))),
        );
      case 'Metric':
        return _panel(c, [
          Text(s('label'), style: theme.textTheme.bodySmall),
          Text(
            s('value'),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          if (s('caption').isNotEmpty)
            Text(s('caption'), style: theme.textTheme.bodySmall),
        ]);
      case 'Badge':
        return _badge(c, s('label'), s('tone', 'accent'));
      case 'Image':
      case 'ImageBlock':
        return HermesOpenuiImage(
          spec: _imageSpec(p),
          compact: type == 'Image',
          environment: _imageEnvironment,
        );
      case 'ImageGallery':
        return HermesOpenuiImageGallery(
          items: [
            for (final image in list('images'))
              _imageSpec((image as Map).cast<String, dynamic>()),
          ],
          environment: _imageEnvironment,
        );
      case 'Button':
        final action = _locked || widget.superseded
            ? null
            : () => _send(node, form);
        return s('variant') == 'secondary'
            ? OutlinedButton(onPressed: action, child: Text(s('label')))
            : FilledButton.icon(
                onPressed: action,
                icon: const Icon(Icons.north_east, size: 16),
                label: Text(s('label')),
              );
      case 'Form':
        return _column(children(s('name')));
      case 'Divider':
        return Row(
          children: [
            const Expanded(child: Divider()),
            if (s('label').isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(s('label'), style: theme.textTheme.bodySmall),
              ),
            const Expanded(child: Divider()),
          ],
        );
      case 'CodeBlock':
        return _panel(c, [
          _badge(c, s('language'), 'neutral'),
          SelectableText(
            s('code'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ]);
      case 'Quote':
        return _panel(c, [
          const Icon(Icons.format_quote, size: 24),
          Text(s('quote'), style: theme.textTheme.bodyLarge),
          Text(s('source'), style: theme.textTheme.bodySmall),
        ]);
      case 'Callout':
      case 'Status':
        final severity = s('severity');
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _color(c, severity).withValues(alpha: .08),
            border: Border(
              left: BorderSide(color: _color(c, severity), width: 3),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _column([
            _badge(c, severity, severity),
            _title(c, s(type == 'Status' ? 'label' : 'title')),
            Text(s(type == 'Status' ? 'detail' : 'message')),
          ]),
        );
      case 'KeyValue':
        return _pairs(c, [s('label')], [s('value')]);
      case 'DefinitionList':
        return _pairs(c, list('labels'), list('values'));
      case 'List':
      case 'NumberedList':
        return _column([
          for (var i = 0; i < list('items').length; i++)
            Text('${type == 'List' ? '•' : '${i + 1}.'} ${list('items')[i]}'),
        ]);
      case 'Checklist':
        final checked = _checks.putIfAbsent(node.path, () => {});
        return _column([
          for (var i = 0; i < list('items').length; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('${list('items')[i]}'),
              value: checked.contains(i),
              onChanged: (value) => setState(() {
                if (value == true) {
                  checked.add(i);
                } else {
                  checked.remove(i);
                }
              }),
            ),
        ]);
      case 'TimelineItem':
      case 'AgendaItem':
        return _panel(c, [
          _badge(c, s('time'), 'neutral'),
          _title(c, s('title')),
          Text(s('detail')),
        ]);
      case 'Agenda':
        return _column([_title(c, s('date')), ...children()]);
      case 'Step':
        return _panel(c, [
          Wrap(
            spacing: 8,
            children: [
              Icon(
                s('status') == 'done'
                    ? Icons.check_circle_outline
                    : Icons.radio_button_checked,
                color: _color(c, s('status') == 'done' ? 'success' : 'accent'),
                size: 20,
              ),
              _badge(c, s('status')),
            ],
          ),
          _title(c, s('title')),
          Text(s('detail')),
        ]);
      case 'Details':
      case 'AccordionItem':
        return Card(
          child: ExpansionTile(
            key: ValueKey('${widget.surfaceId}:${node.path}'),
            maintainState: true,
            initiallyExpanded: p['open'] == true,
            title: Text(s('title')),
            childrenPadding: const EdgeInsets.all(16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [_column(children())],
          ),
        );
      case 'Tabs':
      case 'Carousel':
        final page = _pages[node.path] ?? 0;
        return _column([
          if (type == 'Tabs')
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < node.children.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(node.children[i].props['title'] as String),
                        selected: page == i,
                        onSelected: (_) =>
                            setState(() => _pages[node.path] = i),
                      ),
                    ),
                ],
              ),
            ),
          IndexedStack(
            index: page,
            alignment: Alignment.topLeft,
            children: children(),
          ),
          if (type == 'Carousel')
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Previous',
                  onPressed: page == 0
                      ? null
                      : () => setState(() => _pages[node.path] = page - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${page + 1} / ${node.children.length}'),
                IconButton(
                  tooltip: 'Next',
                  onPressed: page == node.children.length - 1
                      ? null
                      : () => setState(() => _pages[node.path] = page + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ]);
      case 'TagGroup':
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final v in list('tags')) _badge(c, '$v')],
        );
      case 'Breadcrumbs':
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < list('items').length; i++)
              Text(
                '${i == 0 ? '' : '› '}${list('items')[i]}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        );
      case 'Avatar':
        final initials = s('name')
            .trim()
            .split(RegExp(r'\s+'))
            .where((v) => v.isNotEmpty)
            .take(2)
            .map((v) => v.characters.first)
            .join();
        return Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withValues(alpha: .12),
              foregroundColor: theme.colorScheme.primary,
              child: Text(initials),
            ),
            const SizedBox(width: 12),
            Expanded(child: _title(c, s('name'), s('detail'))),
          ],
        );
      case 'EmptyState':
        return _panel(c, [
          Icon(
            Icons.inbox_outlined,
            color: theme.colorScheme.primary,
            size: 32,
          ),
          _title(c, s('title'), s('description')),
        ]);
      case 'Notification':
        return _panel(c, [
          _title(c, s('title'), s('source')),
          Text(s('message')),
          _badge(c, s('time'), 'neutral'),
        ]);
      case 'Table':
        return _table(c, list('columns'), list('rows').cast<List<dynamic>>());
      case 'Heatmap':
        final columns = list('columns'),
            rows = list('rows'),
            values = list('values');
        final peak = math.max(
          1.0,
          values
              .expand((v) => v as List)
              .cast<num>()
              .fold<double>(0, (a, b) => math.max(a, b.toDouble())),
        );
        return _panel(c, [
          _title(c, s('title')),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const FixedColumnWidth(90),
              border: TableBorder.all(color: theme.colorScheme.outlineVariant),
              children: [
                TableRow(
                  children: [
                    const SizedBox(),
                    for (final label in columns)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('$label'),
                      ),
                  ],
                ),
                for (var i = 0; i < rows.length; i++)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('${rows[i]}'),
                      ),
                      for (final value in values[i] as List)
                        Container(
                          color: theme.colorScheme.primary.withValues(
                            alpha: .04 + .24 * (value as num) / peak,
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Text('$value'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ]);
      case 'BarChart':
      case 'LineChart':
      case 'AreaChart':
      case 'PieChart':
      case 'DonutChart':
      case 'Sparkline':
        return _chart(c, node);
      case 'Progress':
        return _column([
          _pairs(c, [s('label')], ['${p['value']} / ${p['max']}']),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: (p['value'] as num) / (p['max'] as num),
              color: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: .12),
            ),
          ),
        ]);
      case 'Gauge':
        return _panel(c, [
          Center(
            child: SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      strokeWidth: 10,
                      value: (p['value'] as num) / (p['max'] as num),
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: .12,
                      ),
                    ),
                  ),
                  _column([
                    Text(
                      '${p['value']}',
                      style: theme.textTheme.headlineMedium,
                    ),
                    Text(s('unit')),
                  ]),
                ],
              ),
            ),
          ),
          _title(c, s('label'), '${p['value']} / ${p['max']} ${s('unit')}'),
        ]);
      case 'Comparison':
        return _grid(c, [
          _panel(c, [_title(c, s('leftTitle')), Text(s('left'))]),
          _panel(c, [_title(c, s('rightTitle')), Text(s('right'))]),
        ], 2);
      case 'Citation':
        return _panel(c, [
          _badge(c, 'Source'),
          _title(c, s('source'), s('location')),
          SelectableText('“${s('excerpt')}”', style: theme.textTheme.bodyLarge),
          if (s('finding').isNotEmpty) Text(s('finding')),
        ]);
      case 'DraftReview':
        return _panel(c, [
          _badge(c, 'Draft · not sent', 'warning'),
          _pairs(c, ['To', 'Subject'], [s('recipient'), s('subject')]),
          SelectableText(s('body')),
        ]);
      case 'TaskCard':
        return _panel(c, [
          _title(c, s('title')),
          Text(s('detail')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _badge(c, s('status')),
              _badge(c, s('assignee'), 'neutral'),
            ],
          ),
        ]);
      case 'KanbanColumn':
        return _column([
          _title(c, '${s('title')} · ${node.children.length}'),
          ...children(),
        ]);
      case 'Kanban':
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final child in children())
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(width: 260, child: child),
                ),
            ],
          ),
        );
      case 'Scorecard':
        return _panel(c, [
          _title(c, s('label')),
          Text(
            '${p['score']} / 100',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          LinearProgressIndicator(value: (p['score'] as num) / 100),
          Text(s('explanation')),
        ]);
      case 'Price':
        return _panel(c, [
          Text(
            '${s('currency')} ${s('amount')}',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          Text(s('period')),
          Text(s('note'), style: theme.textTheme.bodySmall),
        ]);
      case 'ContactCard':
        return _panel(c, [
          const Icon(Icons.person_outline),
          _title(c, s('name'), s('role')),
          Text(s('email')),
          Text(s('phone')),
        ]);
      case 'FileCard':
        return _panel(c, [
          Icon(Icons.description_outlined, color: theme.colorScheme.primary),
          _title(c, s('name'), '${s('type')} · ${s('size')}'),
          Text(s('description')),
        ]);
      default:
        throw StateError('Missing native renderer for $type');
    }
  }

  Widget _field(BuildContext c, HermesOpenuiNode node, String form) {
    final p = node.props, name = node.props['name'] as String;
    final value = _values[form]![name];
    final label = p['label'] as String;
    void set(dynamic v) => setState(() => _values[form]![name] = v);
    final key = ValueKey('${widget.surfaceId}:${node.path}');
    switch (node.type) {
      case 'Input':
      case 'TextArea':
        return TextFormField(
          key: key,
          initialValue: value as String,
          enabled: !_locked,
          maxLength: 2000,
          maxLines: node.type == 'TextArea' ? 4 : 1,
          decoration: InputDecoration(
            labelText: label,
            hintText: p['placeholder'] as String,
            counterText: '',
          ),
          onChanged: set,
        );
      case 'NumberInput':
        return TextFormField(
          key: key,
          initialValue: '$value',
          enabled: !_locked,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(
            labelText: label,
            helperText: '${p['min']} – ${p['max']}',
          ),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) {
            final parsed = num.tryParse(v ?? '');
            return parsed == null ||
                    !parsed.isFinite ||
                    parsed < (p['min'] as num) ||
                    parsed > (p['max'] as num)
                ? 'Enter a number within the range.'
                : null;
          },
          onChanged: (text) {
            final parsed = num.tryParse(text);
            if (parsed != null &&
                parsed.isFinite &&
                parsed >= (p['min'] as num) &&
                parsed <= (p['max'] as num)) {
              _invalidFields.remove(node.path);
              set(parsed);
            } else {
              setState(() => _invalidFields[node.path] = form);
            }
          },
        );
      case 'Select':
        return DropdownButtonFormField<String>(
          key: key,
          initialValue: value as String,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final option in p['options'] as List)
              DropdownMenuItem(value: option as String, child: Text(option)),
          ],
          onChanged: _locked
              ? null
              : (v) {
                  if (v != null) set(v);
                },
        );
      case 'Checkbox':
        return CheckboxListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(label),
          value: value as bool,
          onChanged: _locked ? null : (v) => set(v ?? false),
        );
      case 'Switch':
        return SwitchListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value as bool,
          onChanged: _locked ? null : set,
        );
      case 'Slider':
        return _column([
          Text('$label: $value'),
          Slider(
            key: key,
            value: (value as num).toDouble(),
            min: (p['min'] as num).toDouble(),
            max: (p['max'] as num).toDouble(),
            onChanged: _locked ? null : set,
          ),
        ]);
      case 'RadioGroup':
        return RadioGroup<String>(
          groupValue: value as String,
          onChanged: (v) {
            if (!_locked && v != null) set(v);
          },
          child: _column([
            Text(label),
            for (final option in p['options'] as List)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: Text(option as String),
                value: option,
                enabled: !_locked,
              ),
          ]),
        );
      case 'MultiSelect':
        return _column([
          Text(label),
          for (final option in p['options'] as List)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(option as String),
              value: (value as List).contains(option),
              onChanged: _locked
                  ? null
                  : (checked) => set(
                      checked == true
                          ? [...value, option]
                          : value.where((v) => v != option).toList(),
                    ),
            ),
        ]);
      case 'Rating':
        return _column([
          Text('$label: $value / 5'),
          Wrap(
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i of 5',
                  onPressed: _locked ? null : () => set(i),
                  color: Theme.of(c).colorScheme.primary,
                  icon: Icon(
                    i <= (value as num)
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                  ),
                ),
            ],
          ),
        ]);
      case 'DatePicker':
      case 'TimePicker':
        return OutlinedButton.icon(
          key: key,
          icon: Icon(
            node.type == 'DatePicker'
                ? Icons.calendar_today_outlined
                : Icons.schedule,
          ),
          label: Text('$label: ${value == '' ? 'Choose' : value}'),
          onPressed: _locked
              ? null
              : () async {
                  if (node.type == 'DatePicker') {
                    var initial =
                        DateTime.tryParse(value as String) ?? DateTime.now();
                    if (initial.year < 1 || initial.year > 9999) {
                      initial = DateTime.now();
                    }
                    final chosen = await showDatePicker(
                      context: c,
                      initialDate: initial,
                      firstDate: DateTime(1),
                      lastDate: DateTime(9999, 12, 31),
                    );
                    if (chosen != null && mounted)
                      set(
                        '${chosen.year.toString().padLeft(4, '0')}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}',
                      );
                  } else {
                    final parts = (value as String).split(':');
                    final chosen = await showTimePicker(
                      context: c,
                      initialTime: parts.length == 2
                          ? TimeOfDay(
                              hour: int.parse(parts[0]),
                              minute: int.parse(parts[1]),
                            )
                          : TimeOfDay.now(),
                    );
                    if (chosen != null && mounted)
                      set(
                        '${chosen.hour.toString().padLeft(2, '0')}:${chosen.minute.toString().padLeft(2, '0')}',
                      );
                  }
                },
        );
      default:
        throw StateError('Unsupported field');
    }
  }

  Widget _table(
    BuildContext c,
    List<dynamic> columns,
    List<List<dynamic>> rows,
  ) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Table(
      defaultColumnWidth: const FixedColumnWidth(200),
      border: TableBorder.all(color: Theme.of(c).colorScheme.outlineVariant),
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: Theme.of(c).colorScheme.primary.withValues(alpha: .07),
          ),
          children: [
            for (final label in columns)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('$label', style: Theme.of(c).textTheme.titleSmall),
              ),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              for (final cell in row)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText('$cell'),
                ),
            ],
          ),
      ],
    ),
  );

  Widget _chart(BuildContext c, HermesOpenuiNode node) {
    final p = node.props;
    final values = (p['values'] as List)
        .cast<num>()
        .map((v) => v.toDouble())
        .toList();
    final labels =
        (p['labels'] as List?)?.cast<String>() ??
        [for (var i = 0; i < values.length; i++) '${i + 1}'];
    final unit = p['unit'] as String? ?? '';
    final title = p['title'] as String? ?? p['label'] as String;
    final peak = math.max(1.0, values.reduce(math.max));
    return _panel(c, [
      _title(c, title),
      if (node.type == 'BarChart') ...[
        for (var i = 0; i < values.length; i++)
          _column([
            _pairs(c, [labels[i]], ['${values[i]} $unit']),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: values[i] / peak,
                backgroundColor: Theme.of(c).colorScheme.primary
                    .withValues(alpha: .1),
              ),
            ),
          ]),
      ] else
        Semantics(
          label:
              '$title: ${[for (var i = 0; i < values.length; i++) '${labels[i]} ${values[i]} $unit'].join(', ')}',
          child: SizedBox(
            height: node.type == 'Sparkline' ? 90 : 180,
            width: double.infinity,
            child: CustomPaint(
              painter: _OpenuiChartPainter(
                values,
                node.type,
                Theme.of(c).colorScheme.primary,
              ),
            ),
          ),
        ),
      if (node.type != 'BarChart')
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (var i = 0; i < values.length; i++)
              Text(
                '${labels[i]}: ${values[i]} $unit',
                style: Theme.of(c).textTheme.bodySmall,
              ),
          ],
        ),
    ]);
  }
}

class _OpenuiChartPainter extends CustomPainter {
  _OpenuiChartPainter(this.values, this.type, this.color);
  final List<double> values;
  final String type;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    if (type == 'PieChart' || type == 'DonutChart') {
      final total = values.fold<double>(0, (a, b) => a + b);
      final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: math.min(size.height, size.width) / 2 - 16,
      );
      const palette = [
        Color(0xff5486b4),
        Color(0xff799e6e),
        Color(0xffaa8bba),
        Color(0xffc9a05b),
        Color(0xff7e929a),
      ];
      var start = -math.pi / 2;
      if (total == 0) {
        canvas.drawOval(rect, paint..color = color.withValues(alpha: .15));
      }
      for (var i = 0; i < values.length && total > 0; i++) {
        final sweep = values[i] / total * math.pi * 2;
        canvas.drawArc(
          rect,
          start,
          sweep,
          type == 'PieChart',
          paint
            ..style = (type == 'DonutChart'
                ? PaintingStyle.stroke
                : PaintingStyle.fill)
            ..strokeWidth = 22
            ..color = (i == 0 ? color : palette[(i - 1) % palette.length]),
        );
        start += sweep;
      }
      if (type == 'DonutChart') {
        final text = TextPainter(
          text: TextSpan(
            text:
                '${total.toStringAsFixed(total == total.roundToDouble() ? 0 : 1)}',
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width);
        text.paint(
          canvas,
          Offset(
            (size.width - text.width) / 2,
            (size.height - text.height) / 2,
          ),
        );
      }
      return;
    }
    final peak = math.max(1.0, values.reduce(math.max));
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(
          8 + (size.width - 16) * i / math.max(1, values.length - 1),
          size.height - 8 - (size.height - 16) * values[i] / peak,
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (type == 'AreaChart') {
      final fill = Path.from(path)
        ..lineTo(points.last.dx, size.height - 8)
        ..lineTo(points.first.dx, size.height - 8)
        ..close();
      canvas.drawPath(fill, paint..color = color.withValues(alpha: .12));
    }
    canvas.drawPath(
      path,
      paint
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 3, paint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _OpenuiChartPainter old) =>
      old.type != type ||
      old.color != color ||
      old.values.toString() != values.toString();
}
