import 'package:flutter/material.dart';

import '../services/page_draft_controller.dart';
import '../../hermes/views/hermes_sky_sheet_page.dart';

/// Saved / Unsaved / Saving / Not saved / Conflict, always visible: the
/// editor's band title, with the Space the Page is in under it.
class PageAutosaveStatus extends StatelessWidget {
  const PageAutosaveStatus({
    super.key,
    required this.status,
    required this.revision,
    this.spaceName,
  });

  final PageSaveStatus status;
  final int revision;
  final String? spaceName;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      PageSaveStatus.saved => 'Saved',
      PageSaveStatus.dirty => 'Unsaved',
      PageSaveStatus.saving => 'Saving…',
      PageSaveStatus.error => 'Not saved',
      PageSaveStatus.conflict => 'Changed elsewhere',
    };
    return Semantics(
      liveRegion: true,
      label: 'Page $label',
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: skyText(17, FontWeight.w600, Colors.white),
            ),
            if (spaceName != null)
              Text(
                'in $spaceName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: skyText(
                  13,
                  FontWeight.w400,
                  Colors.white.withValues(alpha: 0.85),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
