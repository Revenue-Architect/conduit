import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../sky/hermez_sky_band.dart';
import '../widgets/hermez_chat_palette.dart';
import '../widgets/hermez_visual_theme.dart';

/// Geist at [size] with tabular figures, the redesign's text (DIRECTION.md).
TextStyle skyText(double size, FontWeight weight, Color color) => TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
  fontFeatures: const [FontFeature.tabularFigures()],
);

const double _toolbarHeight = 56;
const double _sheetRadius = 28;

/// A pushed screen of the redesign (docs/app-design-2026-10-30, s04 to s07):
/// Today's sky as a band with the back arrow, the title and the actions,
/// over a rounded sheet that holds the page. Pushed screens have no dock.
///
/// With [title] the title is large in the band (lists). With [toolbarTitle]
/// the band is one toolbar tall and that widget sits beside the back arrow
/// (the Page editor's "Saved, in Kaizen").
class SkySheetPage extends StatelessWidget {
  const SkySheetPage({
    super.key,
    required this.child,
    this.title,
    this.toolbarTitle,
    this.onBack,
    this.actions = const [],
    this.sheetColor,
  }) : assert(title != null || toolbarTitle != null);

  final Widget child;
  final String? title;
  final Widget? toolbarTitle;

  /// Defaults to popping the route.
  final VoidCallback? onBack;

  /// Drawn in white on the sky: give icons `tint`/`color` white.
  final List<Widget> actions;

  /// The sheet's colour; the page canvas by default.
  final Color? sheetColor;

  @override
  Widget build(BuildContext context) {
    final theme = hermezVisualTheme(Theme.of(context));
    final palette = HermezChatPalette.forBrightness(theme.brightness);
    final top = MediaQuery.paddingOf(context).top;
    final large = title != null;
    final bandHeight = top + _toolbarHeight + (large ? 52 : 14);
    // Only the band is white-on-sky; the sheet keeps the page's theme.
    final onSky = theme.copyWith(
      iconTheme: theme.iconTheme.copyWith(color: Colors.white),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: Colors.white),
      ),
    );
    return Theme(
      data: theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: palette.canvas,
          resizeToAvoidBottomInset: true,
          body: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                SizedBox(
                  height: bandHeight,
                  child: Stack(
                    children: [
                      const Positioned.fill(child: HermezSkyBand()),
                      Theme(
                        data: onSky,
                        child: Padding(
                          padding: EdgeInsets.only(top: top),
                          child: Column(
                            children: [
                              SizedBox(
                                height: _toolbarHeight,
                                child: Row(
                                  children: [
                                    const SizedBox(width: 4),
                                    IconButton(
                                      tooltip: MaterialLocalizations.of(context)
                                          .backButtonTooltip,
                                      onPressed:
                                          onBack ??
                                          () => Navigator.maybePop(context),
                                      icon: const Icon(
                                        Icons.arrow_back_rounded,
                                      ),
                                    ),
                                    if (toolbarTitle != null)
                                      Expanded(child: toolbarTitle!)
                                    else
                                      const Spacer(),
                                    ...actions,
                                    const SizedBox(width: 4),
                                  ],
                                ),
                              ),
                              if (large)
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        0,
                                        20,
                                        6,
                                      ),
                                      child: Text(
                                        title!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            skyText(
                                              30,
                                              FontWeight.w600,
                                              Colors.white,
                                            ).copyWith(
                                              letterSpacing: -1.2,
                                              height: 1.1,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      // Behind the sheet's rounded corners: the skyline's
                      // own ground, so the band runs on into the sheet.
                      const Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: _sheetRadius,
                        child: HermezSkyGround(),
                      ),
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(_sheetRadius),
                          ),
                          child: ColoredBox(
                            color: sheetColor ?? palette.canvas,
                            child: child,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
