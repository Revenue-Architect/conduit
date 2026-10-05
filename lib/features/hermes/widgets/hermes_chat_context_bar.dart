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
import '../sheets/hermes_plan_sheet.dart';
import 'hermes_plan_view.dart';
import 'hermez_chat_palette.dart';
import 'hermez_live.dart';

/// Above the composer in every Hermes chat: what this chat is working on
/// and with what. [Page] [Plan 3/7] [2 delegates] [Model · Effort].
/// Each opens its own sheet; none of them changes anything by itself.
class HermesChatContextBar extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = this.sessionId;
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
          label: page!.title,
          semanticLabel: 'Open the Page ${page!.title}',
          onTap: () => NavigationService.router.pushNamed(
            RouteNames.spacePage,
            pathParameters: {'spaceId': page!.spaceId, 'pageId': page!.id},
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
          semanticLabel:
              '${hermesPlanStatus(plan, running: running)}. Open the plan',
          onOpen: (origin) => showHermesPlanSheet(
            context,
            sessionId: sessionId,
            origin: origin,
          ),
        ),
      if (workers.isNotEmpty && sessionId != null)
        _ContextPill(
          key: const ValueKey('ctx-delegates'),
          leading: liveWorkers > 0
              ? const HermezLiveDot(state: HermezLiveState.working, size: 6)
              : null,
          icon: Icons.call_split_rounded,
          label: liveWorkers > 0 ? '$liveWorkers' : '${workers.length}',
          prefix: liveWorkers > 0 ? 'Delegates' : 'Delegated',
          tabular: true,
          semanticLabel: '${hermesDelegatesSummary(workers)}. Open delegates',
          onOpen: (origin) => showHermesDelegatesSheet(
            context,
            sessionId: sessionId,
            origin: origin,
          ),
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
    return SizedBox(
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
    this.onTap,
    this.onOpen,
  });

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
    final labelStyle = TextStyle(
      color: palette.ink,
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
      child: Container(
        constraints: const BoxConstraints(minHeight: 34, maxWidth: 230),
        padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.border.withValues(alpha: 0.9)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 2),
            ] else ...[
              Icon(icon, size: 15, color: palette.ink),
              const SizedBox(width: 6),
            ],
            if (prefix != null) ...[
              Text(
                prefix!,
                style: labelStyle.copyWith(
                  color: palette.muted,
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
            if (suffix.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                suffix,
                style: labelStyle.copyWith(
                  color: palette.muted,
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
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 17,
                color: palette.muted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
