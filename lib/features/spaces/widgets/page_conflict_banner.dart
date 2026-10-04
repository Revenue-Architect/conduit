import 'package:flutter/material.dart';

import '../../hermes/widgets/hermez_chat_palette.dart';
import '../../hermes/widgets/hermez_surfaces.dart';

/// Shown while the Page changed somewhere else. The draft is never touched
/// until the user picks what to do.
class PageConflictBanner extends StatelessWidget {
  const PageConflictBanner({
    super.key,
    required this.remoteRevision,
    required this.onReview,
    required this.onKeepMine,
    required this.onUseLatest,
    required this.onCopyDraft,
  });

  final int? remoteRevision;
  final VoidCallback onReview;
  final VoidCallback onKeepMine;
  final VoidCallback onUseLatest;
  final VoidCallback onCopyDraft;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.accent, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This Page changed somewhere else.',
            style: HermezType.body(palette)
                .copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text('Your draft is still safe.', style: HermezType.meta(palette)),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: remoteRevision == null ? null : onReview,
                child: const Text('Review latest'),
              ),
              TextButton(
                onPressed: onKeepMine,
                child: const Text('Keep my draft'),
              ),
              TextButton(
                onPressed: onUseLatest,
                child: const Text('Use latest'),
              ),
              TextButton(
                onPressed: onCopyDraft,
                child: const Text('Copy draft'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
