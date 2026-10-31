import 'package:flutter/material.dart';

import 'hermez_card_route.dart';
import 'hermez_morph_origin.dart';

/// Pushes the content-sized card a button turns into: the button's own
/// surface grows into the card and folds back into it on close. The caller
/// hides the real button while this is up and shows it again when the
/// returned future completes, once the card is home.
Future<T?> pushHermezPanel<T>(
  BuildContext context, {
  required HermezMorphOrigin origin,
  required WidgetBuilder builder,
  ThemeData? theme,
  Color? surfaceColor,
  String? semanticLabel,
}) async {
  // One card (docs/app-design-2026-10-30/POPUPS-PLAN.md): the pressed
  // control grows into the content-sized card and folds back into it.
  return pushHermezCard<T>(
    context,
    origin: origin,
    originColor: origin.color ?? surfaceColor,
    // Callers show their button again and dispose fields once it's home.
    waitForClose: true,
    semanticLabel: semanticLabel,
    builder: (cardContext) => theme == null
        ? builder(cardContext)
        : Theme(data: theme, child: builder(cardContext)),
  );
}
