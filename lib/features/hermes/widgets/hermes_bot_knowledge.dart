import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hermes_config.dart';
import '../motion/hermez_motion.dart';
import '../providers/hermes_providers.dart';
import '../services/hermes_desktop_api_service.dart';
import '../sheets/hermez_modal_sheet.dart';
import 'hermez_bot_mark.dart';
import 'hermez_chat_palette.dart';
import 'hermez_sheet_parts.dart';
import 'hermez_surfaces.dart';

/// One chunk of a bot's curated memory. [aboutUser] chunks come from USER.md
/// (what it knows about the user); the rest from MEMORY.md (its own notes).
@immutable
class HermesMemoryCard {
  const HermesMemoryCard({
    required this.aboutUser,
    required this.title,
    required this.body,
  });

  final bool aboutUser;
  final String title;
  final String body;
}

/// A skill the bot wrote itself or has used.
@immutable
class HermesLearnedSkill {
  const HermesLearnedSkill({
    required this.name,
    required this.category,
    required this.useCount,
    required this.writtenByBot,
  });

  final String name;
  final String? category;
  final int useCount;
  final bool writtenByBot;
}

/// What one bot has learned, from Hermes' learning graph. Read-only.
@immutable
class HermesBotKnowledge {
  const HermesBotKnowledge({
    required this.aboutUser,
    required this.notes,
    required this.skills,
  });

  static const empty = HermesBotKnowledge(aboutUser: [], notes: [], skills: []);

  final List<HermesMemoryCard> aboutUser;
  final List<HermesMemoryCard> notes;
  final List<HermesLearnedSkill> skills;

  bool get isEmpty => aboutUser.isEmpty && notes.isEmpty && skills.isEmpty;

  /// Parses `GET /api/learning/graph`. Unknown or malformed rows are skipped;
  /// strings are bounded so a large memory file cannot swamp the UI.
  factory HermesBotKnowledge.fromGraph(Map<String, dynamic> graph) {
    String? text(Object? value, int max) {
      if (value is! String) return null;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return trimmed.length > max ? '${trimmed.substring(0, max)}…' : trimmed;
    }

    final aboutUser = <HermesMemoryCard>[];
    final notes = <HermesMemoryCard>[];
    final memory = graph['memory'];
    if (memory is List) {
      for (final row in memory.take(400)) {
        if (row is! Map) continue;
        final body = text(row['body'], 1200);
        if (body == null) continue;
        final card = HermesMemoryCard(
          aboutUser: row['source'] == 'profile',
          title: text(row['title'], 80) ?? body.split('\n').first,
          body: body,
        );
        (card.aboutUser ? aboutUser : notes).add(card);
      }
    }
    final skills = <HermesLearnedSkill>[];
    final nodes = graph['nodes'];
    if (nodes is List) {
      for (final row in nodes.take(800)) {
        if (row is! Map || row['kind'] != 'skill') continue;
        final name = text(row['label'] ?? row['id'], 80);
        if (name == null) continue;
        final uses = row['useCount'];
        skills.add(
          HermesLearnedSkill(
            name: name,
            category: text(row['category'], 40),
            useCount: uses is num && uses >= 0 ? uses.toInt() : 0,
            writtenByBot: row['createdBy'] == 'agent',
          ),
        );
      }
      skills.sort((a, b) => b.useCount.compareTo(a.useCount));
    }
    return HermesBotKnowledge(
      aboutUser: aboutUser,
      notes: notes,
      skills: skills,
    );
  }
}

final hermesBotKnowledgeProvider = FutureProvider.autoDispose
    .family<HermesBotKnowledge, String>((ref, profile) async {
      final service = ref.watch(hermesApiServiceProvider);
      if (service is! HermesDesktopApiService ||
          !HermesConfig.isValidDesktopProfile(profile)) {
        return HermesBotKnowledge.empty;
      }
      return HermesBotKnowledge.fromGraph(await service.learningGraph(profile));
    });

/// Bot Detail's "What kai knows": facts about the user, the bot's own notes,
/// and the skills it has learned. Each row grows into a sheet listing them.
class HermesBotKnowledgeSection extends ConsumerWidget {
  const HermesBotKnowledgeSection({
    super.key,
    required this.profile,
    required this.botTitle,
  });

  final String profile;
  final String botTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final knowledge = ref.watch(hermesBotKnowledgeProvider(profile));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HermezSectionLabel('WHAT ${botTitle.toUpperCase()} KNOWS'),
        const SizedBox(height: 10),
        knowledge.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => Text(
            'Memory is not available from this Hermes server.',
            style: HermezType.meta(palette),
          ),
          data: (data) => data.isEmpty
              ? Text(
                  '$botTitle has not saved anything yet.',
                  style: HermezType.meta(palette),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    children: [
                      _KnowledgeRow(
                        icon: Icons.person_outline_rounded,
                        title: 'About you',
                        count: data.aboutUser.length,
                        preview: data.aboutUser.firstOrNull?.title,
                        onOpen: (origin) => _openMemory(
                          context,
                          origin,
                          title: 'About you',
                          cards: data.aboutUser,
                          empty: '$botTitle has not noted anything about you.',
                        ),
                      ),
                      Divider(height: 1, color: palette.border),
                      _KnowledgeRow(
                        icon: Icons.sticky_note_2_outlined,
                        title: 'Notes',
                        count: data.notes.length,
                        preview: data.notes.firstOrNull?.title,
                        onOpen: (origin) => _openMemory(
                          context,
                          origin,
                          title: 'Notes',
                          cards: data.notes,
                          empty: '$botTitle has no notes yet.',
                        ),
                      ),
                      Divider(height: 1, color: palette.border),
                      _KnowledgeRow(
                        icon: Icons.auto_awesome_outlined,
                        title: 'Learned skills',
                        count: data.skills.length,
                        preview: data.skills.firstOrNull?.name,
                        onOpen: (origin) =>
                            _openSkills(context, origin, data.skills),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _mark() => SizedBox.square(
    dimension: 44,
    child: HermezBotMark(
      identity: hermezIdentityForName(profile),
      size: 44,
      label: botTitle,
    ),
  );

  void _openMemory(
    BuildContext context,
    HermezMorphOrigin? origin, {
    required String title,
    required List<HermesMemoryCard> cards,
    required String empty,
  }) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    showHermezSheet<void>(
      context,
      origin: origin,
      title: title,
      leading: _mark(),
      subtitle: Text(
        'Saved by $botTitle · read-only',
        style: HermezType.meta(palette),
      ),
      body: cards.isEmpty
          ? Text(empty, style: HermezType.meta(palette))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final card in cards) ...[
                  _MemoryTile(card: card),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  void _openSkills(
    BuildContext context,
    HermezMorphOrigin? origin,
    List<HermesLearnedSkill> skills,
  ) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    showHermezSheet<void>(
      context,
      origin: origin,
      title: 'Learned skills',
      leading: _mark(),
      subtitle: Text(
        'Written or used by $botTitle',
        style: HermezType.meta(palette),
      ),
      body: skills.isEmpty
          ? Text(
              '$botTitle has not learned a skill yet.',
              style: HermezType.meta(palette),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final skill in skills)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          skill.writtenByBot
                              ? Icons.edit_note_rounded
                              : Icons.bolt_rounded,
                          color: skill.writtenByBot
                              ? palette.accent
                              : palette.ink,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                skill.name,
                                style: HermezType.section(palette)
                                    .copyWith(fontSize: 15),
                              ),
                              Text(
                                [
                                  if (skill.writtenByBot)
                                    'written by $botTitle',
                                  ?skill.category,
                                  if (skill.useCount > 0)
                                    skill.useCount == 1
                                        ? 'used once'
                                        : 'used ${skill.useCount} times',
                                ].join(' · '),
                                style: HermezType.meta(palette),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _KnowledgeRow extends StatelessWidget {
  const _KnowledgeRow({
    required this.icon,
    required this.title,
    required this.count,
    required this.preview,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final int count;
  final String? preview;
  final ValueChanged<HermezMorphOrigin?> onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezMotionSurface(
      weight: HermezMotionWeight.light,
      semanticLabel: '$title, $count',
      originRadius: 20,
      originColor: palette.surface,
      onOpen: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon, color: palette.ink),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: HermezType.section(palette).copyWith(fontSize: 15),
                  ),
                  if (preview != null)
                    Text(
                      preview!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HermezType.meta(palette),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('$count', style: HermezType.numeric(palette.ink)),
            Icon(Icons.chevron_right_rounded, color: palette.muted),
          ],
        ),
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({required this.card});

  final HermesMemoryCard card;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final rest = card.body.startsWith(card.title)
        ? card.body.substring(card.title.length).trim()
        : card.body;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.title,
              style: HermezType.section(palette).copyWith(fontSize: 15),
            ),
            if (rest.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(rest, style: HermezType.body(palette)),
            ],
          ],
        ),
      ),
    );
  }
}
