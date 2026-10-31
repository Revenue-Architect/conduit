import 'package:flutter/material.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../widgets/hermez_chat_palette.dart';
import 'hermez_card_route.dart';
import 'hermez_card_stack.dart';

/// One choice in a [showHermezSelectCard].
class HermezSelectOption<T> {
  const HermezSelectOption(
    this.value,
    this.label, {
    this.subtitle,
    this.leading,
    this.trailing,
  });

  final T value;
  final String label;
  final String? subtitle;
  final Widget? leading;

  /// Replaces the check, such as a chevron for a choice that opens more.
  final Widget? trailing;
}

/// The select card (Morphlet's MorphSelect): the field or chip that was
/// pressed grows into its options and folds back into it once one is picked;
/// the caller then shows the new value on the field. Returns the picked
/// value, or null when the card is dismissed.
Future<T?> showHermezSelectCard<T>(
  BuildContext context, {
  required String title,
  required List<HermezSelectOption<T>> options,
  T? selected,
  String? description,
  BuildContext? from,
}) {
  final palette = HermezChatPalette.forBrightness(Theme.of(context).brightness);
  return pushHermezCard<T>(
    context,
    from: from,
    semanticLabel: title,
    builder: (cardContext) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      child: HermezCardStack(
        root: HermezCardView(
          title: title,
          builder: (_) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (description != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: Text(
                    description,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      height: 1.4,
                      color: palette.muted,
                    ),
                  ),
                ),
              for (final option in options)
                HermezSelectRow(
                  label: option.label,
                  subtitle: option.subtitle,
                  leading: option.leading,
                  trailing: option.trailing,
                  selected: option.value == selected,
                  onTap: () => Navigator.of(cardContext).pop(option.value),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// An option row of the select card; the selected one sits on a soft fill
/// and carries a check.
class HermezSelectRow extends StatelessWidget {
  const HermezSelectRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: selected ? palette.canvas : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 15,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: palette.ink,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 12,
                                  height: 1.35,
                                  color: palette.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (trailing != null)
                      trailing!
                    else if (selected)
                      Icon(Icons.check_rounded, size: 20, color: palette.ink),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
