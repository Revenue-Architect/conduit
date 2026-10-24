import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/navigation_service.dart';
import '../../spaces/models/spaces_models.dart';
import '../models/hermes_config.dart';
import '../models/hermes_subagent.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../sheets/hermes_delegates_sheet.dart';
import '../sheets/hermes_model_sheet.dart';
import '../sheets/hermes_plan_sheet.dart' show HermesPlanInline;
import 'hermes_inline_delegation.dart'
    show HermesDelegationProgress, HermesInlineDelegation;
import 'hermes_turn_delegation.dart' show HermesDelegationScope;
import 'hermes_plan_view.dart';
import 'hermez_chat_palette.dart';
import 'hermez_live.dart';

/// Above the composer in every Hermes chat: what this chat is working on
/// and with what. [Page] [Plan 3/7] [2 delegates] [Model · Effort].
/// The plan and the delegates unfold in place above the row, attached to the
/// composer; the model is a picker. None of them changes anything by itself.
class HermesChatContextBar extends ConsumerStatefulWidget {
  const HermesChatContextBar({
    super.key,
    required this.sessionId,
    required this.profile,
    this.profileTitle,
    this.page,
  });

  /// The chat's Hermes session; null for a new chat that has not sent yet.
  final String? sessionId;
  final String? profile;
  final String? profileTitle;
  final HermesPageSummary? page;

  @override
  ConsumerState<HermesChatContextBar> createState() =>
      _HermesChatContextBarState();
}

class _HermesChatContextBarState extends ConsumerState<HermesChatContextBar> {
  /// Which tray is unfolded above the pills: 'plan', 'delegates' or none.
  String? _open;

  void _toggle(String tray) =>
      setState(() => _open = _open == tray ? null : tray);

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.sessionId;
    final profile = widget.profile;
    final profileTitle = widget.profileTitle;
    final page = widget.page;
    final snapshot = sessionId == null
        ? null
        : ref.watch(hermesAgenticStateProvider(sessionId)).value;
    final running =
        sessionId != null &&
        ref.watch(hermesSessionTurnStateProvider(sessionId)).value ==
            HermesDesktopTurnState.running;
    final draft = sessionId == null
        ? ref.watch(hermesDraftModelChoiceProvider)
        : null;
    final info = snapshot?.info;
    final service = ref.watch(hermesApiServiceProvider);
    final picked = sessionId != null && service is HermesDesktopApiService
        ? service.sessionModelChoice(sessionId)?.model
        : null;
    // Hermes reports the model that really served the last turn. When that
    // is not this chat's pick, its fallback chain stepped in.
    final fellBack =
        picked != null && info?.model != null && info!.model != picked;
    final model =
        draft?.model ??
        info?.model ??
        // No live session info yet (a new chat): what the profile runs on.
        ref
            .watch(
              hermesModelCatalogProvider((
                storedId: sessionId,
                profile: profile,
              )),
            )
            .value
            ?.currentModel;
    final effort = hermesEffortShort(
      draft?.reasoningEffort ?? info?.reasoningEffort,
    );
    final fast = draft?.fast ?? info?.fast ?? false;
    final plan = snapshot?.todo;
    final workers = snapshot?.subagents ?? const <HermesSubagentState>[];
    final liveWorkers = workers.live;
    final pills = <Widget>[
      if (page != null)
        _ContextPill(
          key: const ValueKey('ctx-page'),
          icon: Icons.article_outlined,
          label: page.title,
          semanticLabel: 'Open the Page ${page.title}',
          onTap: () => NavigationService.router.pushNamed(
            RouteNames.spacePage,
            pathParameters: {'spaceId': page.spaceId, 'pageId': page.id},
          ),
        ),
      if (plan != null && !plan.isEmpty && sessionId != null)
        _ContextPill(
          key: const ValueKey('ctx-plan'),
          leading: running && plan.active > 0
              ? const HermezLiveDot(state: HermezLiveState.working, size: 6)
              : null,
          icon: Icons.checklist_rounded,
          label: '${plan.completed}/${plan.total}',
          prefix: plan.hasActiveWork && !running ? 'Paused' : 'Plan',
          tabular: true,
          // Real progress: steps Hermes marked done out of the plan's steps.
          progress: plan.total == 0 ? null : plan.completed / plan.total,
          selected: _open == 'plan',
          semanticLabel:
              '${hermesPlanStatus(plan, running: running)}. '
              '${_open == 'plan' ? 'Hide' : 'Show'} the plan',
          onTap: () => _toggle('plan'),
        ),
      // Delegates appear while they work only: once each has replied, its
      // branch in the conversation is the record.
      if (liveWorkers > 0 && sessionId != null)
        _ContextPill(
          key: const ValueKey('ctx-delegates'),
          leading: const HermezLiveDot(state: HermezLiveState.working, size: 6),
          icon: Icons.call_split_rounded,
          label: '$liveWorkers',
          prefix: 'Working',
          tabular: true,
          selected: _open == 'delegates',
          semanticLabel:
              '${hermesDelegatesSummary(workers)}. '
              '${_open == 'delegates' ? 'Hide' : 'Show'} delegates',
          onTap: () => _toggle('delegates'),
        ),
      _ContextPill(
        key: const ValueKey('ctx-model'),
        icon: Icons.auto_awesome_rounded,
        label: model == null ? 'Model' : hermesModelShortName(model),
        suffix: [if (effort.isNotEmpty) effort, if (fast) 'Fast'].join(' · '),
        flag: fellBack ? 'Fallback' : null,
        chevron: true,
        semanticLabel:
            'Model ${model ?? 'default'}${effort.isEmpty ? '' : ', $effort effort'}'
            '${fellBack ? ', a fallback for $picked' : ''}. Change for this chat',
        onOpen: (origin) => showHermesModelSheet(
          context,
          sessionId: sessionId,
          profile: profile,
          profileTitle: profileTitle,
          origin: origin,
        ),
      ),
    ];
    final showPlan =
        _open == 'plan' && sessionId != null && plan != null && !plan.isEmpty;
    final showDelegates =
        _open == 'delegates' && sessionId != null && liveWorkers > 0;
    final tray = showPlan
        ? HermesPlanInline(
            key: const ValueKey('ctx-plan-tray'),
            sessionId: sessionId,
            onClose: () => setState(() => _open = null),
          )
        : showDelegates
        ? HermesDelegationScope(
            key: const ValueKey('ctx-delegates-tray'),
            parentSessionId: sessionId,
            parentLabel: 'Parent',
            workers: workers,
            builder: (load, open, artifact) => HermesInlineDelegation(
              workers: workers,
              parentSessionId: sessionId,
              parentLabel: 'Parent',
              turnKey: 'tray',
              loadConversation: load,
              onOpenSession: open,
              loadArtifact: artifact,
            ),
          )
        : null;
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final row = SizedBox(
      height: 40,
      child: ShaderMask(
        // The row's trailing edge dissolves instead of clipping a pill.
        shaderCallback: (bounds) => const LinearGradient(
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.94, 1],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.only(start: 2, end: 18),
          itemCount: pills.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, index) => Center(child: pills[index]),
        ),
      ),
    );
    // The tray grows up out of the row, over the conversation, and folds back
    // into its pill. It scrolls on its own when the plan is long.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HermezReveal(
          visible: tray != null,
          revealKey: ValueKey('ctx-tray-${_open ?? ''}'),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.42,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: tray ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        row,
      ],
    );
  }
}

class _ContextPill extends StatelessWidget {
  const _ContextPill({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    this.prefix,
    this.suffix = '',
    this.flag,
    this.leading,
    this.chevron = false,
    this.tabular = false,
    this.progress,
    this.selected = false,
    this.onTap,
    this.onOpen,
  });

  /// Its tray is unfolded: the pill turns to ink, like a pressed key.
  final bool selected;

  /// A small bar after the label, for a real done/total fraction.
  final double? progress;

  final IconData icon;
  final String label;
  final String? prefix;
  final String suffix;

  /// A short accent tag after the label ("Fallback").
  final String? flag;
  final Widget? leading;
  final bool chevron;
  final bool tabular;
  final String semanticLabel;
  final VoidCallback? onTap;
  final ValueChanged<HermezMorphOrigin?>? onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    // On the ink fill of an open tray, the pill's words turn light.
    final ink = selected ? palette.surface : palette.ink;
    final muted = selected
        ? palette.surface.withValues(alpha: 0.72)
        : palette.muted;
    final labelStyle = TextStyle(
      color: ink,
      fontSize: 13,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      fontFeatures: tabular
          ? const [FontFeature.tabularFigures()]
          : const <FontFeature>[],
    );
    return HermezMotionSurface(
      weight: HermezMotionWeight.light,
      semanticLabel: semanticLabel,
      originRadius: 17,
      originColor: palette.surface,
      originBorderColor: palette.border,
      onTap: onTap,
      onOpen: onOpen,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 34, maxWidth: 230),
        padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 6),
        // A quiet fill, no outline: these are controls, not cards.
        decoration: BoxDecoration(
          color: selected ? palette.ink : palette.surface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 2),
            ] else ...[
              Icon(icon, size: 15, color: ink),
              const SizedBox(width: 6),
            ],
            if (prefix != null) ...[
              Text(
                prefix!,
                style: labelStyle.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
            if (progress != null) ...[
              const SizedBox(width: 7),
              SizedBox(
                width: 36,
                child: HermesDelegationProgress(value: progress!),
              ),
            ],
            if (suffix.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                suffix,
                style: labelStyle.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (flag != null) ...[
              const SizedBox(width: 6),
              Text(flag!, style: labelStyle.copyWith(color: palette.accent)),
            ],
            if (chevron) ...[
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: muted),
            ],
          ],
        ),
      ),
    );
  }
}
