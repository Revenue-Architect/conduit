import 'package:flutter/material.dart';

import '../../hermes/widgets/hermez_chat_palette.dart';
import 'sky_sheet_page.dart';

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
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This page changed somewhere else.',
            style: skyText(16, FontWeight.w600, palette.ink),
          ),
          const SizedBox(height: 2),
          Text(
            'Your draft is still safe.',
            style: skyText(14, FontWeight.w400, palette.muted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _pill(
                  palette,
                  'Review latest',
                  remoteRevision == null ? null : onReview,
                  primary: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _pill(palette, 'Keep my draft', onKeepMine)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _pill(palette, 'Use latest', onUseLatest)),
              const SizedBox(width: 8),
              Expanded(child: _pill(palette, 'Copy draft', onCopyDraft)),
            ],
          ),
        ],
      ),
    );
  }

  /// The ink pill is the one primary choice; the others are soft pills.
  Widget _pill(
    HermezChatPalette palette,
    String label,
    VoidCallback? onPressed, {
    bool primary = false,
  }) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: primary ? palette.accent : palette.raised,
      foregroundColor: primary ? palette.onAccent : palette.ink,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: const StadiumBorder(),
      textStyle: skyText(14.5, FontWeight.w500, palette.ink),
    ),
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}
