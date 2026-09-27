import 'package:flutter/material.dart';

import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_visual_theme.dart';

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
            side: BorderSide(color: palette.border),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: palette.border,
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
                              style: TextStyle(
                                color: palette.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.8,
                              ),
                            ),
                          Text(
                            title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                              height: 1.08,
                            ),
                          ),
                        ],
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
