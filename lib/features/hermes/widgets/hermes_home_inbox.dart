import 'package:flutter/foundation.dart' show mapEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/navigation_service.dart';
import '../models/hermes_bot.dart';
import '../models/hermes_session.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_agentic_providers.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import 'hermes_home_lines.dart';
import 'hermes_home_working.dart';
import 'hermes_session_tile.dart';
import 'hermes_tab_dock.dart';
import 'hermez_chat_palette.dart';
import 'hermez_skeleton.dart';
import 'hermez_surfaces.dart';

/// Conversations Home shows before it offers All chats.
const hermesInboxVisibleRows = 8;

/// The profile that is the owner's chief of staff.
const hermesChiefProfile = 'default';

/// One row of the Home inbox.
@immutable
class HermesInboxRow {
  const HermesInboxRow({
    required this.session,
    this.name,
    this.pinned = false,
    this.listed = true,
    this.liveLine,
    this.needsYou = false,
  });

  /// What the row opens.
  final HermesSessionSummary session;

  /// A display name that replaces the session's title (Chief's row is named
  /// for Chief, not for the chat).
  final String? name;

  /// Chief's row, which stays first.
  final bool pinned;

  /// False when the session is not in the session list (a bot's canonical
  /// chat is created hidden), so the row offers no fork, rename or delete.
  final bool listed;

  /// What an agent in this conversation is saying while it works; null when
  /// none is.
  final String? liveLine;

  /// Hermes is waiting on the owner in this conversation.
  final bool needsYou;
}

/// A delegated worker's own session: it lives inside the conversation that
/// delegated to it, not beside it. Hermes marks it with the `subagent` source;
/// the session summary carries no parent id, so that mark is what there is.
bool hermesIsDelegatedChild(HermesSessionSummary session) =>
    session.source?.trim().toLowerCase() == 'subagent';

/// Sessions Hermes runs on its own (scheduled routines, one-off checks, health
/// alerts, objective work): they are not conversations with the owner, and on
/// a busy server they outnumber them many times over. Home's inbox leaves them
/// to Chats; what needs the owner from them already shows under Needs you.
const _backgroundSources = {
  'subagent',
  'cron',
  'oneshot',
  'health_alert',
  'initiative_objective',
};

bool hermesIsBackgroundSession(HermesSessionSummary session) =>
    _backgroundSources.contains(session.source?.trim().toLowerCase());

/// The conversations Home lists: Chief's first, then the rest newest first,
/// at most [limit] in all.
///
/// Chief's row is its canonical chat, else its newest conversation. Delegated
/// workers' own sessions are left out. [workingLines] maps a session id to
/// what its agent is saying right now and [needsYouIds] holds the sessions
/// waiting on the owner; pass nothing for either when live state is stale.
List<HermesInboxRow> buildHermesInbox({
  required List<HermesSessionSummary> sessions,
  List<HermesBot> bots = const [],
  Map<String, String> workingLines = const {},
  Set<String> needsYouIds = const {},
  int limit = hermesInboxVisibleRows,
  String chiefProfile = hermesChiefProfile,
}) {
  final conversations = [
    for (final session in sessions)
      if (!hermesIsBackgroundSession(session)) session,
  ];
  final chief = bots.where((bot) => bot.name == chiefProfile).firstOrNull;
  final chiefName = hermesProfileDisplayName(chiefProfile);

  HermesInboxRow row(
    HermesSessionSummary session, {
    String? name,
    bool pinned = false,
    bool listed = true,
  }) => HermesInboxRow(
    session: session,
    name: name,
    pinned: pinned,
    listed: listed,
    liveLine: workingLines[session.id],
    needsYou: needsYouIds.contains(session.id),
  );

  HermesInboxRow? pinned;
  final canonical = chief?.chatSessionId;
  if (canonical != null) {
    final listed = conversations.where((s) => s.id == canonical).firstOrNull;
    pinned = listed != null
        ? row(listed, name: chiefName, pinned: true)
        : row(
            // Not in the list: what the bot itself reports of its chat.
            HermesSessionSummary(
              id: canonical,
              title: chiefName,
              preview: chief?.preview,
              updatedAt: chief?.lastActive,
              profile: chiefProfile,
            ),
            name: chiefName,
            pinned: true,
            listed: false,
          );
  } else {
    final newest = conversations
        .where((session) => session.profile == chiefProfile)
        .firstOrNull;
    if (newest != null) pinned = row(newest, name: chiefName, pinned: true);
  }

  return [
    ?pinned,
    for (final session in conversations)
      if (session.id != pinned?.session.id) row(session),
  ].take(limit).toList(growable: false);
}

/// The live state the inbox draws, apart from the poll that carries it: two
/// polls that say the same thing are equal, so the rows do not rebuild.
@immutable
class _InboxLive {
  const _InboxLive(this.lines, this.needsYou);

  static const none = _InboxLive({}, {});

  /// Session id to what its agent is saying, for sessions really working.
  final Map<String, String> lines;

  /// Sessions Hermes is holding for the owner.
  final Set<String> needsYou;

  static _InboxLive of(AsyncValue<List<HermesLiveSession>> work) {
    final live = work.value;
    if (work.hasError || live == null) return none;
    return _InboxLive(
      {
        for (final session in live)
          if (session.working) session.storedId: hermesWorkingLine(session),
      },
      {
        for (final session in live)
          if (session.needsYou) session.storedId,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _InboxLive &&
      mapEquals(lines, other.lines) &&
      setEquals(needsYou, other.needsYou);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      lines.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAllUnordered(needsYou),
  );
}

/// Home's conversations: a messenger inbox. While an agent in a conversation
/// is really working, its line replaces the preview in accent colour, the way
/// "typing…" does. Live state is Hermes' own and is dropped the moment any of
/// it is stale.
class HermesHomeInbox extends ConsumerWidget {
  const HermesHomeInbox({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final sessionsAsync = ref.watch(hermesSessionsProvider);
    final sessions = sessionsAsync.value;
    final bots = ref.watch(hermesBotsProvider).value ?? const <HermesBot>[];
    final stale = watchHermesHomeStale(ref);
    final live = stale
        ? _InboxLive.none
        : ref.watch(hermesActiveWorkProvider.select(_InboxLive.of));
    final rows = sessions == null
        ? const <HermesInboxRow>[]
        : buildHermesInbox(
            sessions: sessions,
            bots: bots,
            workingLines: live.lines,
            needsYouIds: live.needsYou,
          );

    if (sessions == null) {
      // The lines above report an unreachable Hermes; nothing to draw here.
      return sessionsAsync.hasError
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HermezSkeleton.rows(count: 4),
            );
    }
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          bots.any((bot) => bot.name == hermesChiefProfile)
              ? 'Start with Chief'
              : 'No conversations yet.',
          style: HermezType.body(palette).copyWith(color: palette.muted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HermezMotionGroup(
          children: [
            for (final row in rows)
              HermesSessionTile(
                key: ValueKey(row.session.id),
                session: row.session,
                inbox: true,
                name: row.name,
                liveLine: row.liveLine,
                needsYou: row.needsYou,
                menu: row.listed,
              ),
          ],
        ),
        const _AllChatsRow(),
      ],
    );
  }
}

/// Switches to the Chats tab (or opens Conversations where there is no dock).
class _AllChatsRow extends StatelessWidget {
  const _AllChatsRow();

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezMotionSurface(
      weight: HermezMotionWeight.medium,
      semanticLabel: 'All chats',
      onTap: () {
        final dock = HermesDockScope.maybeOf(context);
        if (dock != null) {
          dock.select(1);
        } else {
          context.pushNamed(RouteNames.hermesConversations);
        }
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'All chats',
                style: HermezType.meta(palette)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.muted),
          ],
        ),
      ),
    );
  }
}
