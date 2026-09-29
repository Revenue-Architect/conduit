import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
// GenUI's public CatalogItem API uses this transitive schema-builder type but
// does not re-export it; GenUI is pinned and the builder is locked transitively.
// ignore: depend_on_referenced_packages
import 'package:json_schema_builder/json_schema_builder.dart';

import '../feedback/hermez_feedback.dart';
import 'hermes_a2ui_interaction_lock.dart';
import 'hermez_bot_mark.dart';
import 'hermez_chat_palette.dart';
import 'hermez_expandable_section.dart';
import 'hermez_surfaces.dart';

/// Structural Hermez components for visual answers: rows, a step rail, a
/// next-action callout, file and bot identity, and an in-place compartment.
///
/// All are bounded, deterministic, and data-only: they render what the
/// response supplies and never fetch, read files, or invent state. The only
/// events come from ordinary child components (a `Button` referenced as
/// `actionChild`); opening an `ExpandableSection` is local presentation and
/// sends nothing to Hermes. Invalid data renders a safe fallback.
final List<CatalogItem> hermesStructureCatalogItems = [
  _infoRow,
  _stepRail,
  _actionCallout,
  _artifactTile,
  _botBadge,
  _expandableSection,
];

// ── Schemas ──────────────────────────────────────────────────────────────

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

final _infoRow = CatalogItem(
  name: 'InfoRow',
  dataSchema: S.object(
    description:
        'One compact row: a title with optional detail, meta, icon, and an '
        'observed state (icon + word). Use instead of small Markdown tables.',
    properties: {
      'title': S.string(description: 'Short title (≤ 80 chars).'),
      'detail': S.string(description: 'Optional one-line detail (≤ 160).'),
      'meta': S.string(description: 'Optional technical label (≤ 60).'),
      'icon': S.string(enumValues: _iconValues),
      'state': S.string(
        enumValues: _stateValues,
        description: 'Optional observed state; never inferred.',
      ),
      'compact': S.boolean(description: 'Tighter vertical spacing.'),
    },
    required: ['title'],
  ),
  widgetBuilder: (context) => _buildInfoRow(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"InfoRow","title":"Research","detail":"7 of 8 claims verified","state":"ok","icon":"check"}
      ]
    ''',
  ],
);

final _stepRail = CatalogItem(
  name: 'StepRail',
  dataSchema: S.object(
    description:
        'A vertical rail of stages for plans, rollouts, and run summaries. '
        'Each state must come from real information.',
    properties: {
      'steps': S.list(
        items: S.object(
          properties: {
            'label': S.string(description: 'Stage name (≤ 60).'),
            'detail': S.string(description: 'Optional detail (≤ 120).'),
            'meta': S.string(description: 'Optional date or owner (≤ 40).'),
            'state': S.string(
              enumValues: ['done', 'current', 'upcoming', 'warning', 'error'],
            ),
          },
          required: ['label', 'state'],
        ),
        minItems: 1,
        maxItems: 10,
      ),
    },
    required: ['steps'],
  ),
  widgetBuilder: (context) => _buildStepRail(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"StepRail","steps":[{"label":"Discovery","state":"done"},{"label":"Validation","state":"current","detail":"1 item left"},{"label":"Release","state":"upcoming","meta":"Nov 23"}]}
      ]
    ''',
  ],
);

final _actionCallout = CatalogItem(
  name: 'ActionCallout',
  dataSchema: S.object(
    description:
        'The next action, a block, or something that needs the user. It '
        'performs nothing itself; put a Button in actionChild for a reply.',
    properties: {
      'eyebrow': S.string(description: 'Short label such as NEXT (≤ 32).'),
      'title': S.string(description: 'The action (≤ 100).'),
      'detail': S.string(description: 'Optional context (≤ 200).'),
      'tone': S.string(
        enumValues: ['neutral', 'attention', 'success', 'error'],
      ),
      'icon': S.string(enumValues: _iconValues),
      'actionChild': A2uiSchemas.componentReference(
        description: 'Optional component id, normally a Button.',
      ),
    },
    required: ['title'],
  ),
  widgetBuilder: (context) => _buildActionCallout(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"ActionCallout","eyebrow":"NEEDS YOU","title":"Confirm the rollback owner","tone":"attention"}
      ]
    ''',
  ],
);

final _artifactTile = CatalogItem(
  name: 'ArtifactTile',
  dataSchema: S.object(
    description:
        'A file shown by name and kind only. Presentation-only: it never '
        'opens or fetches anything. Real files still travel as MEDIA: paths.',
    properties: {
      'name': S.string(description: 'File name (≤ 80).'),
      'kind': S.string(
        enumValues: [
          'document',
          'image',
          'spreadsheet',
          'audio',
          'video',
          'file',
        ],
      ),
      'sizeLabel': S.string(description: 'Optional size such as 2 KB (≤ 24).'),
      'detail': S.string(description: 'Optional one-line detail (≤ 120).'),
      'actionChild': A2uiSchemas.componentReference(
        description: 'Optional component id, normally a Button.',
      ),
    },
    required: ['name', 'kind'],
  ),
  widgetBuilder: (context) => _buildArtifactTile(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"ArtifactTile","name":"launch-brief.md","kind":"document","sizeLabel":"2 KB","detail":"Markdown"}
      ]
    ''',
  ],
);

final _botBadge = CatalogItem(
  name: 'BotBadge',
  dataSchema: S.object(
    description:
        'A Hermez bot mark with its name. Presentation only; it proves no '
        'ownership or permission.',
    properties: {
      'label': S.string(description: 'Bot or workstream name (≤ 40).'),
      'identity': S.string(
        enumValues: ['neutral', 'kai', 'local', 'autopilot', 'fast', 'strong'],
      ),
      'detail': S.string(description: 'Optional short detail (≤ 80).'),
    },
    required: ['label', 'identity'],
  ),
  widgetBuilder: (context) => _buildBotBadge(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"BotBadge","label":"Kai","identity":"kai","detail":"Inventory migration"}
      ]
    ''',
  ],
);

final _expandableSection = CatalogItem(
  name: 'ExpandableSection',
  dataSchema: S.object(
    description:
        'Secondary detail that opens in place and pushes what follows down. '
        'Opening it is local and sends no message to Hermes.',
    properties: {
      'title': S.string(description: 'Section name such as DETAILS (≤ 60).'),
      'subtitle': S.string(description: 'Optional summary (≤ 120).'),
      'count': S.integer(description: 'Optional real item count.'),
      'child': A2uiSchemas.componentReference(
        description: 'The component revealed inside.',
      ),
      'initiallyExpanded': S.boolean(description: 'Defaults to false.'),
    },
    required: ['title', 'child'],
  ),
  widgetBuilder: (context) => _buildExpandableSection(context),
  exampleData: [
    () => '''
      [
        {"id":"root","component":"ExpandableSection","title":"DETAILS","count":2,"child":"rows"},
        {"id":"rows","component":"Column","children":["a","b"]},
        {"id":"a","component":"InfoRow","title":"Hermes","state":"ok"},
        {"id":"b","component":"InfoRow","title":"NVR","state":"warning","detail":"Disk at 91%"}
      ]
    ''',
  ],
);

// ── Builders ─────────────────────────────────────────────────────────────

Widget _buildInfoRow(CatalogItemContext context) {
  final data = _props(context);
  final title = _text(data['title'], 80);
  if (title == null ||
      !_optionalText(data, 'detail', 160) ||
      !_optionalText(data, 'meta', 60) ||
      !_optionalEnum(data, 'icon', _iconValues) ||
      !_optionalEnum(data, 'state', _stateValues) ||
      (data.containsKey('compact') && data['compact'] is! bool)) {
    return _invalid(context.buildContext);
  }
  final detail = _text(data['detail'], 160);
  final meta = _text(data['meta'], 60);
  final state = _RowState.parse(data['state']);
  final icon = _iconFor(data['icon']);
  final compact = data['compact'] == true;
  final build = context.buildContext;
  final palette = _palette(build);
  final stateColor = state == null ? null : _rowStateColor(palette, state);
  return Semantics(
    container: true,
    label: [title, ?detail, ?meta, ?state?.label].join('. '),
    child: ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 5 : 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 18, color: palette.muted),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if (detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        detail,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ),
                  if (meta != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        meta.toUpperCase(),
                        style: HermezType.technical(palette.muted),
                      ),
                    ),
                ],
              ),
            ),
            if (state != null && stateColor != null) ...[
              const SizedBox(width: 10),
              // Icon plus the word: state is never color alone.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(state.icon, size: 16, color: stateColor),
                  const SizedBox(width: 4),
                  Text(
                    state.label,
                    style: TextStyle(
                      color: stateColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _buildStepRail(CatalogItemContext context) {
  final data = _props(context);
  final raw = data['steps'];
  if (raw is! List || raw.isEmpty || raw.length > 10) {
    return _invalid(context.buildContext);
  }
  final steps = <_Step>[];
  for (final entry in raw) {
    if (entry is! Map) return _invalid(context.buildContext);
    final step = Map<String, Object?>.from(entry);
    final label = _text(step['label'], 60);
    final state = _StepState.parse(step['state']);
    if (label == null ||
        state == null ||
        !_optionalText(step, 'detail', 120) ||
        !_optionalText(step, 'meta', 40)) {
      return _invalid(context.buildContext);
    }
    steps.add(
      _Step(label, _text(step['detail'], 120), _text(step['meta'], 40), state),
    );
  }
  final palette = _palette(context.buildContext);
  return Semantics(
    container: true,
    label: [
      for (final step in steps)
        '${step.label}, ${step.state.label}'
            '${step.detail == null ? '' : ', ${step.detail}'}',
    ].join('. '),
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < steps.length; i++)
            _StepRow(
              step: steps[i],
              last: i == steps.length - 1,
              palette: palette,
            ),
        ],
      ),
    ),
  );
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.last,
    required this.palette,
  });

  final _Step step;
  final bool last;
  final HermezChatPalette palette;

  @override
  Widget build(BuildContext context) {
    final color = switch (step.state) {
      _StepState.done => palette.ink,
      _StepState.current => palette.accent,
      _StepState.upcoming => palette.muted,
      _StepState.warning => const Color(0xFFB7791F),
      _StepState.error => const Color(0xFFC53030),
    };
    final filled =
        step.state == _StepState.done || step.state == _StepState.current;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? color : Colors.transparent,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: switch (step.state) {
                    _StepState.warning || _StepState.error => Icon(
                      Icons.priority_high_rounded,
                      size: 8,
                      color: color,
                    ),
                    _ => null,
                  },
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: palette.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        step.label,
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 15,
                          fontWeight: step.state == _StepState.current
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      Text(
                        step.state.label.toUpperCase(),
                        style: HermezType.technical(color),
                      ),
                    ],
                  ),
                  if (step.detail != null)
                    Text(
                      step.detail!,
                      style: TextStyle(color: palette.muted, fontSize: 13),
                    ),
                  if (step.meta != null)
                    Text(
                      step.meta!,
                      style: HermezType.technical(palette.muted),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildActionCallout(CatalogItemContext context) {
  final data = _props(context);
  final title = _text(data['title'], 100);
  const tones = ['neutral', 'attention', 'success', 'error'];
  if (title == null ||
      !_optionalText(data, 'eyebrow', 32) ||
      !_optionalText(data, 'detail', 200) ||
      !_optionalEnum(data, 'tone', tones) ||
      !_optionalEnum(data, 'icon', _iconValues) ||
      !_optionalText(data, 'actionChild', 128)) {
    return _invalid(context.buildContext);
  }
  final eyebrow = _text(data['eyebrow'], 32);
  final detail = _text(data['detail'], 200);
  final action = _text(data['actionChild'], 128);
  final icon = _iconFor(data['icon']);
  final palette = _palette(context.buildContext);
  final tone = data['tone'] as String? ?? 'neutral';
  final edge = switch (tone) {
    'attention' => palette.accent,
    'success' => const Color(0xFF2F855A),
    'error' => const Color(0xFFC53030),
    _ => palette.ink,
  };
  return DecoratedBox(
    decoration: BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: palette.border),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The tone is a signal edge plus the eyebrow word, not color alone.
            Container(width: 4, color: edge),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          eyebrow.toUpperCase(),
                          style: HermezType.technical(edge),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 18, color: edge),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          detail,
                          style: TextStyle(color: palette.muted, fontSize: 13),
                        ),
                      ),
                    if (action != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: context.buildChild(action),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildArtifactTile(CatalogItemContext context) {
  final data = _props(context);
  final name = _text(data['name'], 80);
  const kinds = ['document', 'image', 'spreadsheet', 'audio', 'video', 'file'];
  final kind = data['kind'];
  if (name == null ||
      kind is! String ||
      !kinds.contains(kind) ||
      !_optionalText(data, 'sizeLabel', 24) ||
      !_optionalText(data, 'detail', 120) ||
      !_optionalText(data, 'actionChild', 128)) {
    return _invalid(context.buildContext);
  }
  final size = _text(data['sizeLabel'], 24);
  final detail = _text(data['detail'], 120);
  final action = _text(data['actionChild'], 128);
  final palette = _palette(context.buildContext);
  final icon = switch (kind) {
    'document' => Icons.description_outlined,
    'image' => Icons.image_outlined,
    'spreadsheet' => Icons.table_chart_outlined,
    'audio' => Icons.graphic_eq_rounded,
    'video' => Icons.movie_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
  final kindLabel = '${kind[0].toUpperCase()}${kind.substring(1)}';
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: palette.border),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.canvas,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: palette.accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                [kindLabel, ?size, ?detail].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 8),
          context.buildChild(action),
        ],
      ],
    ),
  );
}

Widget _buildBotBadge(CatalogItemContext context) {
  final data = _props(context);
  final label = _text(data['label'], 40);
  final identity = switch (data['identity']) {
    'neutral' => HermezBotIdentity.neutral,
    'kai' => HermezBotIdentity.kai,
    'local' => HermezBotIdentity.local,
    'autopilot' => HermezBotIdentity.autopilot,
    'fast' => HermezBotIdentity.fast,
    'strong' => HermezBotIdentity.strong,
    _ => null,
  };
  if (label == null || identity == null || !_optionalText(data, 'detail', 80)) {
    return _invalid(context.buildContext);
  }
  final detail = _text(data['detail'], 80);
  final palette = _palette(context.buildContext);
  return Semantics(
    container: true,
    label: [label, ?detail].join('. '),
    child: ExcludeSemantics(
      child: Row(
        children: [
          HermezBotMark(identity: identity, size: 30),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted, fontSize: 12.5),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildExpandableSection(CatalogItemContext context) {
  final data = _props(context);
  final title = _text(data['title'], 60);
  final child = _text(data['child'], 128);
  final count = data['count'];
  if (title == null ||
      child == null ||
      !_optionalText(data, 'subtitle', 120) ||
      (data.containsKey('count') &&
          (count is! int || count < 0 || count > 9999)) ||
      (data.containsKey('initiallyExpanded') &&
          data['initiallyExpanded'] is! bool)) {
    return _invalid(context.buildContext);
  }
  return _A2uiCompartment(
    // State belongs to this component in this surface.
    key: ValueKey('a2ui-compartment-${context.surfaceId}-${context.id}'),
    title: title,
    subtitle: _text(data['subtitle'], 120),
    count: count is int ? count : null,
    initiallyExpanded: data['initiallyExpanded'] == true,
    child: context.buildChild(child),
  );
}

/// Local presentation state only: opening reveals content already in the
/// response and dispatches no A2UI event, so no Hermes turn is sent.
class _A2uiCompartment extends StatefulWidget {
  const _A2uiCompartment({
    super.key,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.initiallyExpanded,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final int? count;
  final bool initiallyExpanded;
  final Widget child;

  @override
  State<_A2uiCompartment> createState() => _A2uiCompartmentState();
}

class _A2uiCompartmentState extends State<_A2uiCompartment> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final heading = widget.count == null
        ? widget.title.toUpperCase()
        : '${widget.title.toUpperCase()} / ${widget.count}';
    // The header is local and stays usable on a locked surface; anything
    // inside that could submit keeps the surface's lock.
    final locked = HermesA2uiInteractionLock.lockedOf(context);
    return HermesA2uiLocalControl(
      child: HermezExpandableSection(
        expanded: _expanded,
        onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
        semanticLabel: widget.subtitle == null
            ? widget.title
            : '${widget.title}. ${widget.subtitle}',
        openFeedback: HermezFeedbackCue.compartmentOpen,
        closeFeedback: HermezFeedbackCue.compartmentClose,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading, style: HermezType.technical(palette.muted)),
            if (widget.subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  widget.subtitle!,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        child: IgnorePointer(ignoring: locked, child: widget.child),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────

class _Step {
  const _Step(this.label, this.detail, this.meta, this.state);

  final String label;
  final String? detail;
  final String? meta;
  final _StepState state;
}

enum _StepState {
  done('Done'),
  current('Current'),
  upcoming('Upcoming'),
  warning('Warning'),
  error('Error');

  const _StepState(this.label);

  final String label;

  static _StepState? parse(Object? value) => switch (value) {
    'done' => done,
    'current' => current,
    'upcoming' => upcoming,
    'warning' => warning,
    'error' => error,
    _ => null,
  };
}

enum _RowState {
  ok('OK', Icons.check_circle_outline),
  warning('Warning', Icons.warning_amber_outlined),
  error('Error', Icons.error_outline),
  unknown('Unknown', Icons.help_outline);

  const _RowState(this.label, this.icon);

  final String label;
  final IconData icon;

  static _RowState? parse(Object? value) => switch (value) {
    'ok' => ok,
    'warning' => warning,
    'error' => error,
    'unknown' => unknown,
    _ => null,
  };
}

Color _rowStateColor(HermezChatPalette palette, _RowState state) =>
    switch (state) {
      _RowState.ok => const Color(0xFF2F855A),
      _RowState.warning => const Color(0xFFB7791F),
      _RowState.error => const Color(0xFFC53030),
      _RowState.unknown => palette.muted,
    };

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

Widget _invalid(BuildContext context) {
  final palette = _palette(context);
  return Semantics(
    label: 'Visual unavailable',
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        'Visual unavailable: the supplied values could not be displayed '
        'safely.',
        style: TextStyle(color: palette.muted, fontSize: 13),
      ),
    ),
  );
}
