import 'package:flutter/material.dart';

import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';
import 'hermez_status_morph.dart';
import 'hermez_surfaces.dart';

const _onDark = Color(0xFFF6F5F2);
const _onDarkMuted = Color(0xFFA9ABB0);

/// A spaced technical caption with an optional leading icon and trailing
/// widget: `RUN HISTORY          View all >`.
class HermezSectionLabel extends StatelessWidget {
  const HermezSectionLabel(
    this.label, {
    super.key,
    this.icon,
    this.trailing,
    this.color,
  });

  final String label;
  final IconData? icon;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: palette.ink),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: HermezType.technical(color ?? palette.ink)
                .copyWith(letterSpacing: 2.2),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// A small fact tile: icon, spaced label, and a value. Used for status,
/// next run, duration, and similar real fields.
class HermezStatTile extends StatelessWidget {
  const HermezStatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.leading,
    this.onTap,
  });

  final String label;
  final Widget value;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return HermezSurface(
      kind: HermezSurfaceKind.utility,
      border: Border.all(color: palette.border.withValues(alpha: 0.75)),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      weight: HermezMotionWeight.light,
      onTap: onTap,
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            Icon(icon, size: 24, color: palette.ink),
          if (leading != null || icon != null) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HermezType.technical(palette.muted)
                      .copyWith(fontSize: 9.5, letterSpacing: 1.8),
                ),
                const SizedBox(height: 5),
                DefaultTextStyle.merge(
                  style: HermezType.body(palette)
                      .copyWith(fontWeight: FontWeight.w600, fontSize: 15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  child: value,
                ),
              ],
            ),
          ),
          if (onTap != null)
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: palette.canvas,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: palette.ink,
              ),
            ),
        ],
      ),
    );
  }
}

/// The large action from the mockups. Primary is the dark instrument panel
/// with a white icon disc; secondary is a bordered white panel. The label
/// changes in place while [busy]; the control never swaps for a spinner
/// elsewhere.
class HermezActionTile extends StatelessWidget {
  const HermezActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.onOpen,
    this.primary = false,
    this.busy = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final ValueChanged<HermezMorphOrigin?>? onOpen;
  final bool primary;
  final bool busy;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final enabled = !busy && (onTap != null || onOpen != null);
    final ink = primary ? _onDark : palette.ink;
    final muted = primary ? _onDarkMuted : palette.muted;
    return HermezSurface(
      kind: primary ? HermezSurfaceKind.technical : HermezSurfaceKind.utility,
      motif: primary ? HermezMotif.slash : HermezMotif.none,
      border: primary
          ? null
          : Border.all(color: palette.border.withValues(alpha: 0.75)),
      semanticLabel: title,
      weight: HermezMotionWeight.medium,
      onTap: enabled ? onTap : null,
      onOpen: enabled ? onOpen : null,
      padding: EdgeInsets.fromLTRB(primary ? 14 : 12, 12, 12, 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Container(
              width: primary ? 42 : 40,
              height: primary ? 42 : 40,
              decoration: BoxDecoration(
                color: primary ? _onDark : palette.canvas,
                shape: primary ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: primary ? null : BorderRadius.circular(12),
              ),
              child: busy
                  ? Padding(
                      padding: const EdgeInsets.all(11),
                      child: HermezStatusMorph(
                        state: HermezMorphState.working,
                        size: 18,
                        tint: primary ? const Color(0xFF17181C) : palette.ink,
                        ink: primary ? const Color(0xFF17181C) : palette.ink,
                      ),
                    )
                  : Icon(
                      icon,
                      size: 22,
                      color: primary ? const Color(0xFF17181C) : palette.ink,
                    ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled || busy
                          ? ink
                          : ink.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w800,
                      fontSize: primary ? 16 : 14.5,
                      height: 1.15,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 12, height: 1.2),
                    ),
                  ],
                ],
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: muted, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

/// Seven day bars for a schedule. Only drawn when the schedule's weekdays
/// are known; [days] uses 1 = Monday through 7 = Sunday.
class HermezWeekdayBars extends StatelessWidget {
  const HermezWeekdayBars({super.key, required this.days});

  final Set<int> days;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Semantics(
      label: 'Runs on ${days.length} days a week',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var day = 1; day <= 7; day++)
              Padding(
                padding: EdgeInsets.only(left: day == 1 ? 0 : 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 40,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: palette.canvas,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          if (days.contains(day))
                            Container(
                              height: 24,
                              decoration: BoxDecoration(
                                color: palette.accent,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _labels[day - 1],
                      style: HermezType.meta(palette)
                          .copyWith(fontSize: 10, color: palette.muted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Weekdays a five-field cron schedule runs on, 1 = Monday through
/// 7 = Sunday. Null when the schedule is not a plain weekly pattern (day of
/// month or month restricted, or unparseable), so no chart is invented.
Set<int>? hermezCronWeekdays(String schedule) {
  final fields = schedule.trim().split(RegExp(r'\s+'));
  if (fields.length != 5) return null;
  if (fields[2] != '*' || fields[3] != '*') return null;
  final field = fields[4].toLowerCase();
  const names = {
    'sun': 0,
    'mon': 1,
    'tue': 2,
    'wed': 3,
    'thu': 4,
    'fri': 5,
    'sat': 6,
  };
  int? parse(String value) {
    final named = names[value];
    if (named != null) return named;
    final number = int.tryParse(value);
    if (number == null || number < 0 || number > 7) return null;
    return number;
  }

  final result = <int>{};
  for (final part in field.split(',')) {
    final stepSplit = part.split('/');
    if (stepSplit.length > 2) return null;
    final step = stepSplit.length == 2 ? int.tryParse(stepSplit[1]) : 1;
    if (step == null || step < 1) return null;
    int start;
    int end;
    if (stepSplit[0] == '*') {
      start = 0;
      end = 6;
    } else if (stepSplit[0].contains('-')) {
      final range = stepSplit[0].split('-');
      if (range.length != 2) return null;
      final a = parse(range[0]);
      final b = parse(range[1]);
      if (a == null || b == null || b < a) return null;
      start = a;
      end = b;
    } else {
      final single = parse(stepSplit[0]);
      if (single == null) return null;
      start = single;
      end = stepSplit.length == 2 ? 6 : single;
    }
    for (var day = start; day <= end; day += step) {
      result.add(day % 7 == 0 ? 7 : day % 7);
    }
  }
  return result.isEmpty ? null : result;
}
