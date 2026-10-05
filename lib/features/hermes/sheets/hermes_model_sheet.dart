import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback/hermez_feedback.dart';
import '../models/hermes_model.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_backend_service.dart';
import '../services/hermes_desktop_api_service.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_live.dart';
import '../widgets/hermez_surfaces.dart';
import 'hermez_modal_sheet.dart';

/// Hermes' reasoning levels, low to high, plus "off".
const hermesEffortLevels = <(String, String)>[
  ('none', 'Off'),
  ('minimal', 'Minimal'),
  ('low', 'Low'),
  ('medium', 'Medium'),
  ('high', 'High'),
  ('xhigh', 'Extra high'),
  ('max', 'Max'),
  ('ultra', 'Ultra'),
];

/// "Off", "Med", "High" for the pill.
String hermesEffortShort(String? effort) => switch (effort?.trim()) {
  'none' => 'Off',
  'minimal' => 'Min',
  'low' => 'Low',
  'medium' => 'Med',
  'high' => 'High',
  'xhigh' => 'XHigh',
  'max' => 'Max',
  'ultra' => 'Ultra',
  _ => '',
};

/// A model id as people say it: "gpt-6.1-sol" stays, "qwen/qwen3-max" loses
/// its vendor path.
String hermesModelShortName(String model) {
  final slash = model.lastIndexOf('/');
  return slash >= 0 && slash < model.length - 1
      ? model.substring(slash + 1)
      : model;
}

/// Switch this chat's model or thinking effort. Applies to this chat's
/// Hermes session only; the profile's default stays as configured.
Future<void> showHermesModelSheet(
  BuildContext context, {
  required String? sessionId,
  required String? profile,
  String? profileTitle,
  HermezMorphOrigin? origin,
}) => pushHermezSheetRoute<void>(
  context,
  origin: origin,
  heightFactor: 0.86,
  builder: (_) => _HermesModelSheet(
    sessionId: sessionId,
    profile: profile,
    profileTitle: profileTitle,
  ),
);

class _HermesModelSheet extends ConsumerStatefulWidget {
  const _HermesModelSheet({
    required this.sessionId,
    required this.profile,
    required this.profileTitle,
  });

  final String? sessionId;
  final String? profile;
  final String? profileTitle;

  @override
  ConsumerState<_HermesModelSheet> createState() => _HermesModelSheetState();
}

class _HermesModelSheetState extends ConsumerState<_HermesModelSheet> {
  int _tab = 0;
  String _query = '';
  String? _busyKey;
  String? _notice;
  bool _noticeIsError = false;

  HermesModelCatalogKey get _key =>
      (storedId: widget.sessionId, profile: widget.profile);

  Future<void> _apply(HermesSessionModelChoice choice, String busyKey) async {
    if (_busyKey != null) return;
    setState(() {
      _busyKey = busyKey;
      _notice = null;
    });
    HermezFeedback.play(HermezFeedbackCue.controlSelect);
    final sessionId = widget.sessionId;
    String notice;
    var error = false;
    try {
      if (sessionId == null) {
        final draft = ref.read(hermesDraftModelChoiceProvider);
        ref
            .read(hermesDraftModelChoiceProvider.notifier)
            .set(
              (draft ?? const HermesSessionModelChoice()).copyWith(
                model: choice.model,
                provider: choice.provider,
                reasoningEffort: choice.reasoningEffort,
                fast: choice.fast,
              ),
            );
        notice = 'Used when you send your first message.';
      } else {
        final service = ref.read(hermesApiServiceProvider);
        if (service is! HermesDesktopApiService) {
          throw StateError('Hermes is not connected.');
        }
        final outcome = await service.switchSessionModel(sessionId, choice);
        notice = switch (outcome) {
          HermesModelSwitchOutcome.applied => 'Switched for this chat.',
          HermesModelSwitchOutcome.nextTurn =>
            'Switches when this reply finishes.',
          HermesModelSwitchOutcome.pending =>
            'Used when you send your next message.',
        };
      }
      HermezFeedback.play(HermezFeedbackCue.approvalAccepted);
    } on HermesModelSwitchNeedsConfirmation catch (needs) {
      notice = needs.message;
      error = true;
    } catch (_) {
      notice = 'Could not switch. Check the connection and try again.';
      error = true;
      HermezFeedback.play(HermezFeedbackCue.runFailed);
    }
    if (!mounted) return;
    setState(() {
      _busyKey = null;
      _notice = notice;
      _noticeIsError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final catalog = ref.watch(hermesModelCatalogProvider(_key));
    final info = widget.sessionId == null
        ? null
        : ref.watch(hermesAgenticStateProvider(widget.sessionId!)).value?.info;
    final draft = widget.sessionId == null
        ? ref.watch(hermesDraftModelChoiceProvider)
        : null;
    final current = catalog.value;
    final currentModel = draft?.model ?? info?.model ?? current?.currentModel;
    final currentProvider = draft?.model != null
        ? draft?.provider
        : info?.provider ?? current?.currentProvider;
    final currentEffort = draft?.reasoningEffort ?? info?.reasoningEffort;
    final service = ref.watch(hermesApiServiceProvider);
    final picked =
        widget.sessionId != null && service is HermesDesktopApiService
        ? service.sessionModelChoice(widget.sessionId!)?.model
        : null;
    final fellBack =
        picked != null && info?.model != null && info!.model != picked;
    final fast = draft?.fast ?? info?.fast ?? false;
    final selected = current?.options
        .where(
          (option) =>
              option.id == currentModel &&
              (currentProvider == null || option.provider == currentProvider),
        )
        .firstOrNull;
    return HermezModalSheet(
      eyebrow: widget.profileTitle == null
          ? 'THIS CHAT'
          : 'THIS CHAT · ${widget.profileTitle!.toUpperCase()}',
      title: currentModel == null
          ? 'Model'
          : hermesModelShortName(currentModel),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6, right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [
                if (currentProvider != null)
                  current?.providerLabel(currentProvider) ?? currentProvider,
                if (hermesEffortShort(currentEffort).isNotEmpty)
                  '${hermesEffortShort(currentEffort)} effort',
                if (fast) 'Fast',
              ].join(' · '),
              style: HermezType.meta(palette),
            ),
            if (fellBack) ...[
              const SizedBox(height: 6),
              Text(
                '${hermesModelShortName(picked)} failed on the last message, '
                'so Hermes used its fallback, ${hermesModelShortName(info.model!)}.',
                style: HermezType.meta(palette).copyWith(color: palette.accent),
              ),
            ],
            const SizedBox(height: 12),
            _Tabs(
              index: _tab,
              labels: const ['Model', 'Effort'],
              onSelect: (index) => setState(() => _tab = index),
            ),
          ],
        ),
      ),
      body: catalog.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Text(
                'Could not load this profile\'s models.',
                style: HermezType.body(palette),
              ),
              TextButton(
                onPressed: () =>
                    ref.invalidate(hermesModelCatalogProvider(_key)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        // The tab's indicator travels; the panel under it swaps at once.
        data: (catalog) => AnimatedSwitcher(
          duration: Duration.zero,
          transitionBuilder: HermezSwitch.unroll,
          layoutBuilder: HermezSwitch.column,
          child: _tab == 0
              ? _ModelList(
                  key: const ValueKey('models'),
                  catalog: catalog,
                  query: _query,
                  onQuery: (value) => setState(() => _query = value),
                  currentModel: currentModel,
                  currentProvider: currentProvider,
                  busyKey: _busyKey,
                  onPick: (option) => _apply(
                    HermesSessionModelChoice(
                      model: option.id,
                      provider: option.provider,
                    ),
                    '${option.provider}\u0000${option.id}',
                  ),
                )
              : _EffortPanel(
                  key: const ValueKey('effort'),
                  supportsReasoning: selected?.supportsReasoning ?? true,
                  supportsFast: selected?.supportsFast ?? false,
                  effort: currentEffort,
                  fast: fast,
                  busyKey: _busyKey,
                  onEffort: (value) => _apply(
                    HermesSessionModelChoice(reasoningEffort: value),
                    'effort:$value',
                  ),
                  onFast: (value) =>
                      _apply(HermesSessionModelChoice(fast: value), 'fast'),
                ),
        ),
      ),
      footer: HermezReveal(
        visible: _notice != null,
        revealKey: ValueKey('model-notice-$_notice'),
        child: Row(
          children: [
            HermezLiveDot(
              state: _noticeIsError
                  ? HermezLiveState.failed
                  : HermezLiveState.done,
              size: 6,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_notice ?? '', style: HermezType.meta(palette)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.index,
    required this.labels,
    required this.onSelect,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: HermezMotion.settleFor(HermezMotionWeight.light),
                curve: HermezMotion.curveMedium,
                left: index * width,
                top: 0,
                bottom: 0,
                width: width,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: palette.border),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (i, label) in labels.indexed)
                    Expanded(
                      child: Semantics(
                        selected: i == index,
                        button: true,
                        label: label,
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (i == index) return;
                            HermezFeedback.play(
                              HermezFeedbackCue.controlSelect,
                            );
                            onSelect(i);
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: HermezMotion.settleFor(
                                HermezMotionWeight.light,
                              ),
                              style: TextStyle(
                                color: i == index ? palette.ink : palette.muted,
                                fontSize: 13.5,
                                fontWeight: i == index
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                              child: Text(label),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModelList extends StatelessWidget {
  const _ModelList({
    super.key,
    required this.catalog,
    required this.query,
    required this.onQuery,
    required this.currentModel,
    required this.currentProvider,
    required this.busyKey,
    required this.onPick,
  });

  final HermesModelCatalog catalog;
  final String query;
  final ValueChanged<String> onQuery;
  final String? currentModel;
  final String? currentProvider;
  final String? busyKey;
  final ValueChanged<HermesDesktopModelOption> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final needle = query.trim().toLowerCase();
    final groups = <String, List<HermesDesktopModelOption>>{};
    for (final option in catalog.options) {
      if (option.provider == 'moa') continue;
      if (needle.isNotEmpty &&
          !option.id.toLowerCase().contains(needle) &&
          !option.name.toLowerCase().contains(needle) &&
          !catalog
              .providerLabel(option.provider)
              .toLowerCase()
              .contains(needle)) {
        continue;
      }
      groups.putIfAbsent(option.provider, () => []).add(option);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (catalog.options.length > 10) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border.withValues(alpha: 0.8)),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 18, color: palette.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: onQuery,
                    style: HermezType.body(palette),
                    decoration: InputDecoration(
                      hintText: 'Find a model',
                      hintStyle: HermezType.body(palette)
                          .copyWith(color: palette.muted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              catalog.options.isEmpty
                  ? 'No connected providers for this profile.'
                  : 'Nothing matches.',
              style: HermezType.body(palette).copyWith(color: palette.muted),
            ),
          ),
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Text(
              catalog.providerLabel(entry.key).toUpperCase(),
              style: HermezType.technical(palette.muted),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                for (final (index, option) in entry.value.indexed) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: palette.border.withValues(alpha: 0.6),
                    ),
                  _ModelRow(
                    option: option,
                    selected:
                        option.id == currentModel &&
                        (currentProvider == null ||
                            option.provider == currentProvider),
                    busy: busyKey == '${option.provider}\u0000${option.id}',
                    onTap: busyKey == null ? () => onPick(option) : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.option,
    required this.selected,
    required this.busy,
    this.onTap,
  });

  final HermesDesktopModelOption option;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezMotionSurface(
      weight: HermezMotionWeight.light,
      semanticLabel: '${option.name}${selected ? ', current' : ''}',
      onTap: selected ? null : onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hermesModelShortName(option.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HermezType.body(palette).copyWith(
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    if (option.supportsFast || !option.supportsReasoning)
                      Text(
                        [
                          if (option.supportsFast) 'Fast available',
                          if (!option.supportsReasoning) 'No thinking',
                        ].join(' · '),
                        style: HermezType.meta(palette)
                            .copyWith(fontSize: 11.5),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox.square(
                dimension: 24,
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(3),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : HermezIconSwap(
                        icon: selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: selected ? palette.accent : palette.border,
                        size: 22,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EffortPanel extends StatelessWidget {
  const _EffortPanel({
    super.key,
    required this.supportsReasoning,
    required this.supportsFast,
    required this.effort,
    required this.fast,
    required this.busyKey,
    required this.onEffort,
    required this.onFast,
  });

  final bool supportsReasoning;
  final bool supportsFast;
  final String? effort;
  final bool fast;
  final String? busyKey;
  final ValueChanged<String> onEffort;
  final ValueChanged<bool> onFast;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final current = (effort == null || effort!.isEmpty) ? 'medium' : effort!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          supportsReasoning
              ? 'How long Hermes thinks before it answers. Higher is slower and more careful.'
              : 'This model answers without a separate thinking step.',
          style: HermezType.body(palette).copyWith(color: palette.muted),
        ),
        const SizedBox(height: 14),
        if (supportsReasoning)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in hermesEffortLevels)
                _EffortChip(
                  label: label,
                  selected: value == current,
                  busy: busyKey == 'effort:$value',
                  onTap: busyKey == null && value != current
                      ? () => onEffort(value)
                      : null,
                ),
            ],
          ),
        if (supportsFast) ...[
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, color: palette.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fast mode',
                        style: HermezType.body(palette)
                            .copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Priority processing from the provider.',
                        style: HermezType.meta(palette),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: fast,
                  onChanged: busyKey == null ? onFast : null,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EffortChip extends StatelessWidget {
  const _EffortChip({
    required this.label,
    required this.selected,
    required this.busy,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezMotionSurface(
      weight: HermezMotionWeight.light,
      semanticLabel: '$label effort${selected ? ', current' : ''}',
      onTap: onTap,
      child: AnimatedContainer(
        duration: HermezMotion.settleFor(HermezMotionWeight.light),
        curve: HermezMotion.curveLight,
        constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? palette.ink : palette.canvas,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? palette.ink
                : palette.border.withValues(alpha: 0.8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) ...[
              SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: selected ? palette.surface : palette.ink,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? palette.surface : palette.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
