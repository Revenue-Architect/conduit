import 'package:flutter/material.dart';

import '../../hermes/widgets/hermez_chat_palette.dart';
import '../../hermes/widgets/hermez_surfaces.dart';
import '../services/page_draft_controller.dart';

/// Saved / Unsaved / Saving / Not saved / Conflict, always visible.
class PageAutosaveStatus extends StatelessWidget {
  const PageAutosaveStatus({
    super.key,
    required this.status,
    required this.revision,
  });

  final PageSaveStatus status;
  final int revision;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final (label, color, icon) = switch (status) {
      PageSaveStatus.saved => (
        'Saved',
        palette.muted,
        Icons.cloud_done_outlined,
      ),
      PageSaveStatus.dirty => ('Unsaved', palette.muted, Icons.edit_outlined),
      PageSaveStatus.saving => (
        'Saving…',
        palette.muted,
        Icons.cloud_upload_outlined,
      ),
      PageSaveStatus.error => (
        'Not saved',
        palette.accent,
        Icons.error_outline_rounded,
      ),
      PageSaveStatus.conflict => (
        'Changed elsewhere',
        palette.accent,
        Icons.call_split_rounded,
      ),
    };
    return Semantics(
      liveRegion: true,
      label: 'Page $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: HermezType.technical(color),
            ),
          ),
        ],
      ),
    );
  }
}
