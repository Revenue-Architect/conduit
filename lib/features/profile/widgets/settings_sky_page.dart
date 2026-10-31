import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart'
    show AdaptiveSwitch;
import 'package:flutter/material.dart'
    as flutter_material
    show Theme, ThemeData;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/services/haptic_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../hermes/sky/hermez_sky_band.dart';
import '../../hermes/widgets/hermez_chat_palette.dart';

// The settings screens (docs/app-design-2026-10-30, s01 to s03): a sky band
// that folds into a pinned header, a rounded sheet, and flat rows under
// plain headings. Rows sit on the sheet; nothing is a card.

TextStyle _geist(double size, FontWeight weight, Color color) => TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
  fontFeatures: const [FontFeature.tabularFigures()],
);

HermezChatPalette _palette(BuildContext context) =>
    HermezChatPalette.forBrightness(Theme.of(context).brightness);

/// How far the sheet's rounded top rises over the sky.
const double _sheetRadius = 28;

/// A settings page: the sky band with a back arrow and a large title that
/// settles into the top bar as the page scrolls, over a sheet of [children].
class SettingsSkyPage extends StatelessWidget {
  const SettingsSkyPage({
    super.key,
    required this.title,
    required this.children,
    this.lede,
  });

  final String title;

  /// The one line under the title, inside the sheet.
  final String? lede;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    // The sky reads Flutter's own Theme, which this app's Material app does
    // not set; hand it the brightness the page is drawn in.
    return flutter_material.Theme(
      data: flutter_material.ThemeData(
        brightness: Theme.of(context).brightness,
      ),
      child: Material(
        color: palette.canvas,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
          ),
          child: CustomScrollView(
            primary: true,
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _SkyHeader(title: title, top: top),
              ),
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (lede != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                            child: Text(
                              lede!,
                              style: _geist(15, FontWeight.w400, palette.muted),
                            ),
                          ),
                        ...children,
                        SizedBox(height: 40 + bottom),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkyHeader extends SliverPersistentHeaderDelegate {
  _SkyHeader({required this.title, required this.top});

  final String title;
  final double top;

  // The sheet's top edge sits 112 dp under the status bar while the title is
  // large and 72 dp once it has folded; the rounded part comes on top.
  @override
  double get maxExtent => top + 112 + _sheetRadius;

  @override
  double get minExtent => top + 72 + _sheetRadius;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final palette = _palette(context);
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: _sheetRadius,
          child: const HermezSkyBand(),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _sheetRadius,
          child: HermezSkyGround(),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _sheetRadius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(_sheetRadius),
              ),
            ),
          ),
        ),
        Positioned(
          left: 4,
          top: top + 16,
          child: IconButton(
            key: const ValueKey<String>('utility-route-back-button'),
            tooltip:
                Localizations.of<MaterialLocalizations>(
                  context,
                  MaterialLocalizations,
                )?.backButtonTooltip ??
                'Back',
            color: Colors.white,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        Positioned(
          left: Tween<double>(begin: 20, end: 58).transform(t),
          right: 20,
          top: Tween<double>(begin: top + 64, end: top + 31).transform(t),
          child: Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  _geist(
                    Tween<double>(begin: 30, end: 17).transform(t),
                    FontWeight.w600,
                    Colors.white,
                  ).copyWith(
                    letterSpacing: Tween<double>(
                      begin: -1.2,
                      end: -0.3,
                    ).transform(t),
                  ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(_SkyHeader old) => old.title != title || old.top != top;
}

/// A group: a heading, its rows, and a quiet note under them.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    this.title,
    this.count,
    this.sub,
    required this.children,
    this.note,
    this.first = false,
  });

  final String? title;

  /// A small count beside the heading ("3 selected").
  final String? count;

  /// A line under the heading.
  final String? sub;
  final List<Widget> children;
  final String? note;

  /// The group right under the lede sits closer to it.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 4 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, sub == null ? 6 : 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title!,
                        style: _geist(
                          15,
                          FontWeight.w600,
                          palette.ink,
                        ).copyWith(letterSpacing: -0.3),
                      ),
                    ),
                  ),
                  if (count != null)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        child: Text(
                          count!,
                          style: _geist(12, FontWeight.w600, palette.muted),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
              child: Text(
                sub!,
                style: _geist(13, FontWeight.w400, palette.muted),
              ),
            ),
          ...children,
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Text(
                note!,
                style: _geist(13, FontWeight.w400, palette.faint),
              ),
            ),
        ],
      ),
    );
  }
}

/// A round 40 dp glyph on the sheet, the leading mark of a [SettingsRow].
class SettingsGlyph extends StatelessWidget {
  const SettingsGlyph({super.key, required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => SettingsGlyphShell(
    child: Icon(icon, size: 20, color: color ?? _palette(context).muted),
  );
}

/// The round frame of a glyph, for marks that are not an icon.
class SettingsGlyphShell extends StatelessWidget {
  const SettingsGlyphShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: palette.raised,
        shape: BoxShape.circle,
        border: Border.all(color: palette.border),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// One flat row: an optional glyph, a title and a line under it, a value, and
/// a chevron (or an arrow out, or a chevron down) when it opens something.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.sub,
    this.leading,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
    this.chevron = Icons.chevron_right_rounded,
    this.semanticLabel,
    this.subMaxLines = 3,
    this.minHeight = 56,
    this.preserveTrailingSemantics = false,
  });

  final String title;
  final String? sub;
  final Widget? leading;

  /// What the row is set to, in small type before the chevron.
  final String? value;

  /// Replaces the chevron (a switch, a button).
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;

  /// The mark at the end of a row that opens something; null for none.
  final IconData? chevron;
  final String? semanticLabel;
  final int subMaxLines;
  final double minHeight;

  /// Keeps an interactive trailing control (a button) as its own node.
  final bool preserveTrailingSemantics;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final interactive = enabled && onTap != null;
    final titleColor = destructive ? palette.failed : palette.ink;
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: _geist(
                      15,
                      FontWeight.w500,
                      titleColor,
                    ).copyWith(letterSpacing: -0.2),
                  ),
                  if (sub != null && sub!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        sub!,
                        maxLines: subMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: _geist(13, FontWeight.w400, palette.muted),
                      ),
                    ),
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _geist(13, FontWeight.w500, palette.muted),
                  ),
                ),
              ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ] else if (chevron != null && onTap != null) ...[
              const SizedBox(width: 8),
              Icon(chevron, size: 18, color: palette.faint),
            ],
          ],
        ),
      ),
    );
    return Semantics(
      button: interactive,
      enabled: enabled,
      label: semanticLabel ?? [title, ?sub].join('. '),
      excludeSemantics: !preserveTrailingSemantics,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        // Its own Material, so a row works on any page, not only this sheet.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: interactive
                ? () {
                    ConduitHaptics.trigger(HapticType.selection);
                    onTap!();
                  }
                : null,
            child: row,
          ),
        ),
      ),
    );
  }
}

/// A row that is a switch: the whole row flips it.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    this.sub,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final String title;
  final String? sub;
  final bool value;

  /// Null greys the row out.
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final change = onChanged;
    return SettingsRow(
      title: title,
      sub: sub,
      enabled: change != null,
      semanticLabel: semanticLabel,
      minHeight: sub == null ? 52 : 64,
      onTap: change == null ? null : () => change(!value),
      trailing: context.usesCupertinoChrome
          ? AdaptiveSwitch(value: value, onChanged: change)
          : Switch(
              value: value,
              onChanged: change == null
                  ? null
                  : (next) {
                      ConduitHaptics.selectionClick();
                      change(next);
                    },
              // Ink when on, a quiet outline when off (the mock's switch).
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? palette.raised
                    : palette.faint,
              ),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? palette.ink
                    : palette.surface,
              ),
              trackOutlineColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.transparent
                    : palette.faint,
              ),
            ),
    );
  }
}

/// A fact about this phone: a title and, on the right, what it is now.
class SettingsStatRow extends StatelessWidget {
  const SettingsStatRow({
    super.key,
    required this.title,
    required this.value,
    this.sub,
  });

  final String title;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) => SettingsRow(
    title: title,
    sub: sub,
    value: value,
    minHeight: 52,
    semanticLabel: '$title: $value',
  );
}

/// The small soft pill that fixes something (Battery settings).
class SettingsPill extends StatelessWidget {
  const SettingsPill({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Material(
      color: palette.surface,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap == null
            ? null
            : () {
                ConduitHaptics.trigger(HapticType.selection);
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Text(label, style: _geist(13, FontWeight.w600, palette.ink)),
        ),
      ),
    );
  }
}

/// A choice you can switch on and off in place: the quick-action chips.
class SettingsChip extends StatelessWidget {
  const SettingsChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? palette.ink : Colors.transparent,
        shape: StadiumBorder(
          side: selected ? BorderSide.none : BorderSide(color: palette.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap == null
              ? null
              : () {
                  ConduitHaptics.trigger(HapticType.selection);
                  onTap!();
                },
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check_rounded, size: 16, color: palette.raised),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: _geist(
                    13,
                    selected ? FontWeight.w600 : FontWeight.w500,
                    selected ? palette.raised : palette.muted,
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

/// A text-only action on the sheet ("Clear all").
class SettingsLink extends StatelessWidget {
  const SettingsLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            height: 44,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: _geist(13, FontWeight.w600, _palette(context).ink),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A row that unfolds its [children] in place under itself, the way a
/// menu would grow a card, instead of opening another page.
class SettingsDisclosure extends StatefulWidget {
  const SettingsDisclosure({
    super.key,
    required this.title,
    this.sub,
    this.leading,
    required this.children,
  });

  final String title;
  final String? sub;
  final Widget? leading;
  final List<Widget> children;

  @override
  State<SettingsDisclosure> createState() => _SettingsDisclosureState();
}

class _SettingsDisclosureState extends State<SettingsDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final duration = context.motionDuration(AnimationDuration.microInteraction);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          leading: widget.leading,
          title: widget.title,
          sub: widget.sub,
          trailing: AnimatedRotation(
            turns: _open ? 0.5 : 0,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: Icon(
              Icons.expand_more_rounded,
              size: 20,
              color: _palette(context).faint,
            ),
          ),
          onTap: () => setState(() => _open = !_open),
        ),
        AnimatedSize(
          duration: duration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
