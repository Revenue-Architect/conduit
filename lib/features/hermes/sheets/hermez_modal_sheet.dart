import 'package:flutter/material.dart';

import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_surfaces.dart';
import '../widgets/hermez_visual_theme.dart';

/// Shared detail sheet. Existing callers keep [showHermezSheet].
typedef HermezDetailSheet = HermezModalSheet;

/// A single visual shell for Hermes-owned details. Dismissing it never implies
/// a backend action; callers must resolve requests explicitly.
Future<T?> showHermezSheet<T>(
  BuildContext context, {
  required String title,
  String? eyebrow,
  required Widget body,
  Widget? footer,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => HermezModalSheet(
    title: title,
    eyebrow: eyebrow,
    body: body,
    footer: footer,
  ),
);

class HermezModalSheet extends StatelessWidget {
  const HermezModalSheet({
    super.key,
    required this.title,
    this.eyebrow,
    required this.body,
    this.footer,
  });

  final String title;
  final String? eyebrow;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext sheetContext) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(sheetContext).brightness,
    );
    return Theme(
      data: hermezVisualTheme(Theme.of(sheetContext)),
      child: FractionallySizedBox(
        heightFactor: 0.91,
        child: Material(
          color: palette.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: palette.ink.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (eyebrow != null)
                            Text(
                              eyebrow!.toUpperCase(),
                              style: HermezType.technical(palette.accent),
                            ),
                          Text(
                            title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: HermezType.display(palette).copyWith(
                              fontSize: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        size: const Size(28, 36),
                        painter: _SheetSlashPainter(palette.accent),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: body,
                ),
              ),
              if (footer != null)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: footer,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetSlashPainter extends CustomPainter {
  const _SheetSlashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.85),
      Offset(size.width * 0.85, size.height * 0.1),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SheetSlashPainter oldDelegate) => color != oldDelegate.color;
}
