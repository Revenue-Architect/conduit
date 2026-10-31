import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../../push/models/approval.dart';
import '../../push/providers/push_providers.dart' show approvalsPendingProvider;
import '../models/hermes_bot.dart';
import '../models/hermes_job.dart';
import '../models/hermes_session.dart';
import '../motion/hermez_card_route.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../services/hermes_pending_decision_store.dart';
import '../sheets/hermes_active_work_sheet.dart' show hermesSummaryForSession;
import '../views/hermes_attention_page.dart'
    show hermesAttentionFailedJobsProvider, hermesAttentionPreparedProvider;
import 'hermes_home_avatar.dart';
import 'hermes_home_presence.dart' show hermesHomePendingDecisionsProvider;
import 'hermes_session_tile.dart' show openHermesSession;
import 'hermez_bot_mark.dart';
import 'hermez_chat_palette.dart';
import 'hermez_surfaces.dart';

/// Rows Needs you shows before it offers See all.
const hermesNeedsYouVisibleRows = 4;

enum HermesNeedsYouKind { decision, approval, prepared, failedJob }

/// One thing that waits on the owner, whichever source it came from.
@immutable
class HermesNeedsYouItem {
  const HermesNeedsYouItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.source,
    required this.actionable,
    required this.at,
    this.profile,
    this.sessionId,
    this.approvalId,
  });

  /// Unique across sources: the key the merge deduplicates on.
  final String id;
  final HermesNeedsYouKind kind;
  final String title;

  /// The muted line under the title: who, and what they want.
  final String source;

  /// True when the owner is asked to decide something now (a decision or an
  /// approval); false for work that is only ready to look at.
  final bool actionable;

  /// When it was asked or last moved. Orders rows; never shown.
  final DateTime at;

  /// The bot it belongs to.
  final String? profile;

  /// The chat that holds it, for a decision or prepared work.
  final String? sessionId;

  /// The gateway approval it opens, for an approval.
  final String? approvalId;
}

/// Merges every source of "waiting on you" into one list.
///
/// - Deduplicated: a decision by its session and request id, an approval by
///   its id, prepared work by its session id, a failed run by its bot and job
///   id. An approval and a decision with the same id are one request, and the
///   approval wins, because it has the one canonical review screen. Prepared
///   work in a chat that already holds a decision is shown by the decision.
/// - Actionable rows (decisions, approvals that can still be decided) come
///   first, then work that is only ready to look at; newest first within each.
///
/// [botNames] maps a profile id to the name the owner gave it; unknown
/// profiles show as [hermesProfileDisplayName] does. [ownProfile] is the
/// profile a decision belongs to when it records none.
List<HermesNeedsYouItem> mergeHermesNeedsYou({
  required DateTime now,
  Iterable<HermesPendingDesktopDecision> decisions = const [],
  Iterable<Approval> approvals = const [],
  Iterable<HermesSessionSummary> prepared = const [],
  Iterable<(String, HermesJob)> failedJobs = const [],
  Map<String, String> botNames = const {},
  String ownProfile = 'default',
}) {
  String who(String? profile) =>
      botNames[profile ?? ownProfile] ??
      hermesProfileDisplayName(profile ?? ownProfile);

  final items = <String, HermesNeedsYouItem>{};

  // Approvals first, so a decision that is the same request can defer to one.
  final liveApprovals = [
    for (final approval in approvals)
      // An overdue request can no longer be decided; the server expires it
      // within seconds.
      if (approval.isPending && !approval.isOverdue(now)) approval,
  ];
  final approvalIds = {for (final approval in liveApprovals) approval.id};
  for (final approval in liveApprovals) {
    final profile = approval.originProfile ?? _requester(approval.requestedBy);
    items.putIfAbsent(
      'approval:${approval.id}',
      () => HermesNeedsYouItem(
        id: 'approval:${approval.id}',
        kind: HermesNeedsYouKind.approval,
        title: _oneLine(approval.description).isEmpty
            ? 'Approval requested'
            : _oneLine(approval.description),
        source: '${profile == null ? 'Hermes' : who(profile)} · approval',
        actionable: true,
        at: approval.createdAt,
        profile: profile,
        approvalId: approval.id,
        sessionId: approval.originSessionId,
      ),
    );
  }

  final decisionSessions = <String>{};
  for (final decision in decisions) {
    if (approvalIds.contains(decision.requestId)) continue;
    final id = 'decision:${decision.storedSessionId}:${decision.requestId}';
    decisionSessions.add(decision.storedSessionId);
    final prompt = _oneLine(decision.prompt);
    items.putIfAbsent(
      id,
      () => HermesNeedsYouItem(
        id: id,
        kind: HermesNeedsYouKind.decision,
        title: prompt.isEmpty ? _decisionTitle(decision.kind) : prompt,
        source: '${who(decision.profile)} · ${_decisionPhrase(decision.kind)}',
        actionable: true,
        // The store renews a record's expiry each time Hermes asks again, so
        // its lifetime back from there is when it was last asked.
        at: decision.expiresAt.subtract(HermesPendingDecisionStore.ttl),
        profile: decision.profile ?? ownProfile,
        sessionId: decision.storedSessionId,
      ),
    );
  }

  for (final session in prepared) {
    if (decisionSessions.contains(session.id)) continue;
    final id = 'prepared:${session.id}';
    final title = _oneLine(session.title);
    items.putIfAbsent(
      id,
      () => HermesNeedsYouItem(
        id: id,
        kind: HermesNeedsYouKind.prepared,
        title: title.isEmpty || title == 'Untitled session'
            ? 'Prepared work'
            : title,
        source: '${who(session.profile)} · ready for review',
        actionable: false,
        at: session.updatedAt ?? _epoch,
        profile: session.profile ?? ownProfile,
        sessionId: session.id,
      ),
    );
  }

  for (final (profile, job) in failedJobs) {
    final id = 'job:$profile:${job.id}';
    items.putIfAbsent(
      id,
      () => HermesNeedsYouItem(
        id: id,
        kind: HermesNeedsYouKind.failedJob,
        title: job.displayName,
        source: '${who(profile)} · run failed',
        actionable: false,
        at: job.lastRun ?? _epoch,
        profile: profile,
      ),
    );
  }

  return items.values.toList()..sort((a, b) {
    if (a.actionable != b.actionable) return a.actionable ? -1 : 1;
    final byTime = b.at.compareTo(a.at);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

String _oneLine(String? text) =>
    (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// The profile that asked, when the gateway recorded a usable one.
String? _requester(String requestedBy) {
  final name = requestedBy.trim();
  if (name.isEmpty || name == 'unknown' || name.contains(':')) return null;
  return name;
}

String _decisionTitle(HermesPendingDesktopDecisionKind kind) => switch (kind) {
  HermesPendingDesktopDecisionKind.approval => 'Tool approval requested',
  HermesPendingDesktopDecisionKind.clarification => 'Hermes asked a question',
  HermesPendingDesktopDecisionKind.sudo => 'Admin access required',
  HermesPendingDesktopDecisionKind.secret => 'Credential required',
  HermesPendingDesktopDecisionKind.mcpSetup => 'Connector needs setup',
  HermesPendingDesktopDecisionKind.connectorOperation =>
    'Connector access requested',
};

String _decisionPhrase(HermesPendingDesktopDecisionKind kind) => switch (kind) {
  HermesPendingDesktopDecisionKind.approval => 'needs your approval',
  HermesPendingDesktopDecisionKind.clarification => 'has a question',
  HermesPendingDesktopDecisionKind.sudo => 'needs admin access',
  HermesPendingDesktopDecisionKind.secret => 'needs a credential',
  HermesPendingDesktopDecisionKind.mcpSetup => 'connector setup',
  HermesPendingDesktopDecisionKind.connectorOperation => 'connector access',
};

/// Everything waiting on the owner, merged from the live providers. Rebuilds
/// as any source changes; a source that is loading or has failed contributes
/// what it last had (nothing at first), so the list never claims more than
/// Hermes reported.
List<HermesNeedsYouItem> watchHermesNeedsYou(WidgetRef ref) {
  final bots = ref.watch(hermesBotsProvider).value ?? const <HermesBot>[];
  final service = ref.watch(hermesApiServiceProvider);
  return mergeHermesNeedsYou(
    now: DateTime.now(),
    decisions:
        ref.watch(hermesHomePendingDecisionsProvider).value ??
        const <HermesPendingDesktopDecision>[],
    approvals: ref.watch(approvalsPendingProvider).value ?? const <Approval>[],
    prepared:
        ref.watch(hermesAttentionPreparedProvider).value ??
        const <HermesSessionSummary>[],
    failedJobs:
        ref.watch(hermesAttentionFailedJobsProvider).value ??
        const <(String, HermesJob)>[],
    botNames: {for (final bot in bots) bot.name: hermesBotDisplayTitle(bot)},
    ownProfile: service is HermesDesktopApiService
        ? service.config.desktopProfile
        : 'default',
  );
}

/// Refreshes every source Needs you reads.
void invalidateHermesNeedsYou(WidgetRef ref) {
  ref
    ..invalidate(hermesHomePendingDecisionsProvider)
    ..invalidate(approvalsPendingProvider)
    ..invalidate(hermesAttentionPreparedProvider)
    ..invalidate(hermesAttentionFailedJobsProvider);
}

/// Home's one headed section: what waits on the owner. Gone entirely when
/// nothing does.
class HermesNeedsYouSection extends ConsumerWidget {
  const HermesNeedsYouSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final items = watchHermesNeedsYou(ref);
    final shown = items.take(hermesNeedsYouVisibleRows).toList();
    return HermezReveal(
      visible: items.isNotEmpty,
      weight: HermezMotionWeight.medium,
      revealKey: const ValueKey('hermes-needs-you'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        // One object: See all grows the whole block into the Attention page
        // and Back returns it here.
        child: Builder(
          builder: (blockContext) => RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HermezSectionBar(
                  label: 'NEEDS YOU · ${items.length}',
                  actionLabel: items.length > hermesNeedsYouVisibleRows
                      ? 'See all'
                      : null,
                  onAction: items.length > hermesNeedsYouVisibleRows
                      ? () => context.pushNamed(
                          RouteNames.hermesAttention,
                          extra: HermezMorphOrigin.of(
                            blockContext,
                            radius: 18,
                            color: palette.canvas,
                            snapshot: HermezMorphOrigin.capture(blockContext),
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 4),
                HermezMotionGroup(
                  children: [
                    for (final item in shown)
                      HermesNeedsYouRow(key: ValueKey(item.id), item: item),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of Needs you: who, what they want, and where it opens.
class HermesNeedsYouRow extends ConsumerWidget {
  const HermesNeedsYouRow({super.key, required this.item});

  final HermesNeedsYouItem item;

  void _open(BuildContext context, WidgetRef ref, HermezMorphOrigin? origin) {
    final approvalId = item.approvalId;
    final sessionId = item.sessionId;
    switch (item.kind) {
      case HermesNeedsYouKind.approval when approvalId != null:
        context.pushNamed(
          RouteNames.hermesApproval,
          pathParameters: {'approvalId': approvalId},
          extra: origin,
        );
      case HermesNeedsYouKind.prepared when sessionId != null:
        // m03: Review grows the draft card; the draft opens from there.
        unawaited(_showDraftCard(context, ref, item, sessionId));
      case HermesNeedsYouKind.decision when sessionId != null:
        final known = hermesSummaryForSession(ref, sessionId, 'Conversation');
        openHermesSession(
          context,
          ref,
          known.profile == null && item.profile != null
              ? HermesSessionSummary(
                  id: known.id,
                  title: known.title,
                  preview: known.preview,
                  source: known.source,
                  updatedAt: known.updatedAt,
                  profile: item.profile,
                  messageCount: known.messageCount,
                )
              : known,
        );
      case HermesNeedsYouKind.failedJob:
        context.pushNamed(RouteNames.hermesJobs, extra: origin);
      default:
        context.pushNamed(RouteNames.hermesAttention, extra: origin);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezMotionSurface(
      weight: HermezMotionWeight.medium,
      semanticLabel: '${item.title}. ${item.source}',
      originRadius: 14,
      originColor: palette.canvas,
      onOpen: (origin) => _open(context, ref, origin),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              // What kind of thing it is, not who sent it: the source line
              // already names the bot, and one face repeated down a list says
              // nothing.
              SizedBox.square(
                dimension: HermesHomeAvatar.extent(28),
                child: Icon(
                  switch (item.kind) {
                    HermesNeedsYouKind.decision => Icons.help_outline_rounded,
                    HermesNeedsYouKind.approval => Icons.verified_user_outlined,
                    HermesNeedsYouKind.prepared => Icons.inbox_outlined,
                    HermesNeedsYouKind.failedJob => Icons.error_outline_rounded,
                  },
                  size: 21,
                  color: item.kind == HermesNeedsYouKind.failedJob
                      ? Theme.of(context).colorScheme.error
                      : item.actionable
                      ? palette.accent
                      : palette.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HermezType.body(palette)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      item.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HermezType.meta(palette),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The draft card (m03): the bot's prepared reply, grown out of its Review
/// row. Sending or changing it happens where the draft's own controls are,
/// so "Open the draft" grows this card into its chat (m11).
Future<void> _showDraftCard(
  BuildContext context,
  WidgetRef ref,
  HermesNeedsYouItem item,
  String sessionId,
) async {
  final summary = hermesSummaryForSession(ref, sessionId, item.title);
  final known = summary.profile == null && item.profile != null
      ? HermesSessionSummary(
          id: summary.id,
          title: summary.title,
          preview: summary.preview,
          source: summary.source,
          updatedAt: summary.updatedAt,
          profile: item.profile,
          messageCount: summary.messageCount,
        )
      : summary;
  final bots = ref.read(hermesBotsProvider).value ?? const <HermesBot>[];
  final bot = bots.where((b) => b.name == known.profile).firstOrNull;
  final palette = HermezChatPalette.forBrightness(Theme.of(context).brightness);
  final preview = known.preview?.trim();
  await pushHermezCard<void>(
    context,
    semanticLabel: 'Draft',
    builder: (cardContext) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (bot != null) ...[
                ClipOval(
                  child: SizedBox.square(
                    dimension: 28,
                    child: HermezBotMark(
                      identity: hermezIdentityForBot(bot),
                      botName: bot.name,
                      size: 28,
                      label: bot.title,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  bot == null ? 'Draft' : '${bot.title}’s draft',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: palette.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(cardContext),
                icon: Icon(Icons.close_rounded, color: palette.ink),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ready for review · not sent',
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
          if (preview != null && preview.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              preview,
              maxLines: 12,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, height: 1.45, color: palette.ink),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'Nothing is sent until you press Send on the draft.',
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () async {
              // m11: the card becomes the chat the draft lives in.
              await growHermezCardToScreen(cardContext);
              if (!context.mounted) return;
              await openHermesSession(context, ref, known, bot: bot);
            },
            child: const Text('Open the draft'),
          ),
        ],
      ),
    ),
  );
}
