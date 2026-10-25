import 'package:flutter/material.dart';

/// The manga redesign's page: white paper, ink, one orange that means
/// "happening now or needs you". Tokens from
/// docs/app-design-2026-10-24/DIRECTION.md.
@immutable
class MangaInk {
  const MangaInk._({
    required this.ground,
    required this.raised,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.rule,
    required this.tone,
    required this.accent,
    required this.accentText,
    required this.border,
  });

  static const light = MangaInk._(
    ground: Color(0xFFFFFFFF),
    raised: Color(0xFFF2F2F4),
    ink: Color(0xFF0E0E10),
    ink2: Color(0xFF4A4A50),
    ink3: Color(0xFF6C6C73),
    rule: Color(0xFFDCDCE0),
    tone: Color(0xFFE4E4E8),
    accent: Color(0xFFFF5A26),
    accentText: Color(0xFFC23A0B),
    border: 2.5,
  );

  static const dark = MangaInk._(
    ground: Color(0xFF0B0B0D),
    raised: Color(0xFF18181B),
    ink: Color(0xFFF4F3EF),
    ink2: Color(0xFFB4B3AE),
    ink3: Color(0xFF8E8D88),
    rule: Color(0xFF2C2C30),
    tone: Color(0xFF26262B),
    accent: Color(0xFFFF6A36),
    accentText: Color(0xFFFF8A5E),
    border: 2,
  );

  static MangaInk of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  final Color ground;
  final Color raised;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color rule;

  /// Screentone: the grey of speed lines.
  final Color tone;
  final Color accent;

  /// Orange as text, measured against [ground].
  final Color accentText;

  /// Panel border width.
  final double border;

  /// Ink on orange, in both modes.
  Color get onAccent => const Color(0xFF0E0E10);
}

/// One family, Bricolage Grotesque: display moments at 75% width, text at
/// 100%. Seven steps; the inline run UI keeps its own scale inside a turn.
abstract final class MangaType {
  static const _family = 'BricolageGrotesque';

  static TextStyle _style(
    double size,
    double weight, {
    double width = 100,
    double height = 1.3,
    double tracking = 0,
    Color? color,
  }) => TextStyle(
    fontFamily: _family,
    fontSize: size,
    height: height,
    letterSpacing: tracking * size,
    fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
    fontVariations: [
      FontVariation('wght', weight),
      FontVariation('wdth', width),
      FontVariation('opsz', size.clamp(12, 96)),
    ],
    color: color,
  );

  static TextStyle display(Color c) =>
      _style(44, 800, width: 75, height: .95, tracking: -.03, color: c);
  static TextStyle hero(Color c) =>
      _style(28, 800, width: 75, height: 1, tracking: -.02, color: c);
  static TextStyle panel(Color c) =>
      _style(19, 800, width: 75, height: 1.05, tracking: -.01, color: c);
  static TextStyle body(Color c) => _style(17, 400, height: 1.4, color: c);
  static TextStyle title(Color c) => _style(17, 600, height: 1.25, color: c);
  static TextStyle line(Color c) => _style(14, 500, height: 1.3, color: c);
  static TextStyle speech(Color c) => _style(14, 600, height: 1.26, color: c);
  static TextStyle meta(Color c) => _style(13, 500, height: 1.3, color: c);
  static TextStyle label(Color c) => _style(12, 600, height: 1, color: c);
  static TextStyle stamp(Color c) =>
      _style(12, 800, width: 75, height: 1, tracking: .05, color: c);

  /// The bot's name on Pick: the one place the second face appears.
  static TextStyle fighter(Color c) => TextStyle(
    fontFamily: 'ArchivoBlackItalicExpanded',
    fontWeight: FontWeight.w900,
    fontStyle: FontStyle.italic,
    fontSize: 78,
    height: .86,
    letterSpacing: -.035 * 78,
    color: c,
  );
}

/// Motion values, after Emil Kowalski's rules: strong custom ease-out for
/// anything entering or responding, ease-in-out only for things moving on
/// screen, exits faster than entries, nothing over 300 ms except the one
/// signature moment.
abstract final class MangaMotion {
  /// Entering, responding, pressing.
  static const easeOut = Cubic(0.23, 1, 0.32, 1);

  /// Moving or morphing on screen.
  static const easeInOut = Cubic(0.77, 0, 0.175, 1);

  /// Sheets and full-screen grows (the iOS drawer curve).
  static const drawer = Cubic(0.32, 0.72, 0, 1);

  static const press = Duration(milliseconds: 120);
  static const release = Duration(milliseconds: 160);
  static const swap = Duration(milliseconds: 180);
  static const enter = Duration(milliseconds: 260);
  static const exit = Duration(milliseconds: 180);

  /// Pick growing out of a roster tile: the signature, allowed to be long.
  static const grow = Duration(milliseconds: 380);
  static const shrink = Duration(milliseconds: 240);
}

/// A bot's ground on Pick, taken from its art. Grounds mean "who", so they
/// are not accents.
@immutable
class MangaField {
  const MangaField(this.field, this.deep, this.ink, this.paper);

  final Color field;

  /// The slash across the field, and the tray behind the task box.
  final Color deep;

  /// Text on [field].
  final Color ink;

  /// The task box.
  final Color paper;

  bool get lightField => ink.computeLuminance() < .2;

  static const _byBot = <String, MangaField>{
    // Chief stands on white paper (the owner's call, 2026-10-24): his flame
    // is the only orange on his screen.
    'default': MangaField(
      Color(0xFFFFFFFF),
      Color(0xFFEDEBE8),
      Color(0xFF0E0E10),
      Color(0xFFFFFFFF),
    ),
    'chief': MangaField(
      Color(0xFFFFFFFF),
      Color(0xFFEDEBE8),
      Color(0xFF0E0E10),
      Color(0xFFFFFFFF),
    ),
    'kai': MangaField(
      Color(0xFF2F6FE4),
      Color(0xFF1D4BA8),
      Color(0xFFFFFFFF),
      Color(0xFFF2F6FF),
    ),
    'ops': MangaField(
      Color(0xFFE9E7E2),
      Color(0xFFBDB9B0),
      Color(0xFF0E0E10),
      Color(0xFFFFFFFF),
    ),
    'hermuse': MangaField(
      Color(0xFFC21E33),
      Color(0xFF8A1222),
      Color(0xFFFFFFFF),
      Color(0xFFFFF1F2),
    ),
    'architect': MangaField(
      Color(0xFFF2A3B6),
      Color(0xFFD9798F),
      Color(0xFF1A0C10),
      Color(0xFFFFF5F7),
    ),
    'scout': MangaField(
      Color(0xFF5B2FA6),
      Color(0xFF3E1D7A),
      Color(0xFFFFFFFF),
      Color(0xFFF5F1FF),
    ),
  };

  /// The tray under the tiles and task box: the field's darkest note.
  Color get tray => Color.lerp(deep, const Color(0xFF0B0B0D), .78)!;

  static MangaField forBot(String name, {String? avatarColor}) {
    final known = _byBot[name.toLowerCase()];
    if (known != null) return known;
    // A bot added later: its own avatar colour, else ink on bone.
    final parsed = _parse(avatarColor);
    if (parsed == null) return _byBot['ops']!;
    final hsl = HSLColor.fromColor(parsed);
    final light = parsed.computeLuminance() > .45;
    return MangaField(
      parsed,
      hsl.withLightness((hsl.lightness - .16).clamp(0, 1)).toColor(),
      light ? const Color(0xFF0E0E10) : const Color(0xFFFFFFFF),
      const Color(0xFFFFFFFF),
    );
  }

  static Color? _parse(String? hex) {
    if (hex == null) return null;
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return null;
    final value = int.tryParse(clean, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }
}
