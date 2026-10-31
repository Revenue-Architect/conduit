import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Today's ground: Montreal's sky at this hour (docs/app-design-2026-10-30,
/// "The sky"). A system, not decoration: the gradient follows the real time
/// and weather, and dark mode always shows the evening or night version.
enum HermezSkyPhase { dawn, day, dusk, night }

enum HermezSkyWeather { clear, overcast, rain, snow }

@immutable
class HermezSkyState {
  const HermezSkyState({
    required this.phase,
    this.weather = HermezSkyWeather.clear,
  });

  final HermezSkyPhase phase;
  final HermezSkyWeather weather;

  bool get lit => phase == HermezSkyPhase.dusk || phase == HermezSkyPhase.night;

  @override
  bool operator ==(Object other) =>
      other is HermezSkyState &&
      other.phase == phase &&
      other.weather == weather;

  @override
  int get hashCode => Object.hash(phase, weather);
}

/// The phase at [now]. Dawn is an hour either side of sunrise; dusk runs
/// from an hour before sunset until 11 pm (the evening); with no sun times, late-October hours stand in. In dark
/// mode the sky is never daytime: dusk or night, whichever is nearer.
HermezSkyPhase hermezSkyPhaseAt(
  DateTime now, {
  DateTime? sunrise,
  DateTime? sunset,
  required bool dark,
}) {
  final day = DateTime(now.year, now.month, now.day);
  final rise = sunrise ?? day.add(const Duration(hours: 7, minutes: 50));
  final set = sunset ?? day.add(const Duration(hours: 18, minutes: 10));
  const hour = Duration(hours: 1);
  final HermezSkyPhase phase;
  if (now.isAfter(rise.subtract(hour)) && now.isBefore(rise.add(hour))) {
    phase = HermezSkyPhase.dawn;
  } else if (now.isAfter(set.subtract(hour)) &&
      now.isBefore(day.add(const Duration(hours: 23)))) {
    // The evening is the owner's dusk sky (variant A2) until 11 pm.
    phase = HermezSkyPhase.dusk;
  } else if (now.isAfter(rise) && now.isBefore(set)) {
    phase = HermezSkyPhase.day;
  } else {
    phase = HermezSkyPhase.night;
  }
  if (!dark) return phase;
  if (phase == HermezSkyPhase.night || phase == HermezSkyPhase.dusk) {
    return phase;
  }
  // Daylight in dark mode: dusk, the nearer of the two dark skies by day.
  return HermezSkyPhase.dusk;
}

/// The page colour under the sky and the skyline's flat silhouette colour.
Color hermezSkyGround(HermezSkyPhase phase) => switch (phase) {
  HermezSkyPhase.dawn || HermezSkyPhase.day => const Color(0xFF0F1E33),
  HermezSkyPhase.dusk => const Color(0xFF0A1220),
  HermezSkyPhase.night => const Color(0xFF070B14),
};

List<Color> _gradient(HermezSkyState state) {
  final base = switch (state.phase) {
    HermezSkyPhase.dawn => const [
      Color(0xFF0D2141),
      Color(0xFF2C4F80),
      Color(0xFF7E9DC2),
      Color(0xFFD9D3BE),
      Color(0xFFEFDDB2),
    ],
    HermezSkyPhase.day => const [
      Color(0xFF2E6DB4),
      Color(0xFF4F88C6),
      Color(0xFF6FA3D6),
      Color(0xFFA9CBE8),
      Color(0xFFCFE3F2),
    ],
    HermezSkyPhase.dusk => const [
      Color(0xFF081224),
      Color(0xFF14284A),
      Color(0xFF3B5A82),
      Color(0xFF7C7A80),
      Color(0xFFB89474),
    ],
    HermezSkyPhase.night => const [
      Color(0xFF05080F),
      Color(0xFF080F1A),
      Color(0xFF0B1424),
      Color(0xFF101C30),
      Color(0xFF15253D),
    ],
  };
  if (state.weather == HermezSkyWeather.clear) return base;
  // Overcast, rain and snow flatten the gradient toward grey.
  const grey = Color(0xFF8C96A3);
  final amount = state.lit ? 0.18 : 0.42;
  return [for (final c in base) Color.lerp(c, grey, amount)!];
}

/// Paints the sky: gradient, stars on a clear night, rain or snow, the
/// Montreal skyline, and lit windows at dusk and night.
class HermezSkyPainter extends CustomPainter {
  const HermezSkyPainter(this.state, {this.skylineHeight = 172});

  final HermezSkyState state;

  /// The skyline's drawn height at the bottom of the canvas.
  final double skylineHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          _gradient(state),
          const [0, 0.34, 0.64, 0.88, 1],
        ),
    );
    if (state.phase == HermezSkyPhase.night &&
        state.weather == HermezSkyWeather.clear) {
      final star = Paint()..color = const Color(0xFFFFFFFF);
      for (final (x, y, r) in _stars) {
        canvas.drawCircle(
          Offset(x * size.width, y * (size.height - skylineHeight)),
          r,
          star,
        );
      }
    }
    if (state.weather == HermezSkyWeather.rain) {
      final streak = Paint()
        ..color = const Color(0x12FFFFFF)
        ..strokeWidth = 1;
      for (var x = -size.height; x < size.width; x += 23) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x + size.height * 0.25, size.height),
          streak,
        );
      }
    } else if (state.weather == HermezSkyWeather.snow) {
      final flake = Paint()..color = const Color(0x66FFFFFF);
      for (final (x, y, _) in _stars) {
        canvas.drawCircle(Offset(x * size.width, y * size.height), 1.4, flake);
      }
    }
    // The skyline: 412 × 280 design units, stretched to the width.
    canvas.save();
    canvas.translate(0, size.height - skylineHeight);
    canvas.scale(size.width / 412, skylineHeight / 280);
    canvas.drawPath(_skyline, Paint()..color = hermezSkyGround(state.phase));
    if (state.lit) {
      final window = Paint()..color = const Color(0xB3F3E6C8);
      for (final r in _windows) {
        canvas.drawRect(r, window);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(HermezSkyPainter old) =>
      old.state != state || old.skylineHeight != skylineHeight;
}

/// Montreal, flat: Mount Royal and its cross, downtown (Place Ville Marie,
/// 1000 de La Gauchetière's copper peak, 1250 René-Lévesque's stepped
/// crown) and the Olympic Stadium's leaning tower. Coordinates in a
/// 412 × 280 box, origin top-left.
final Path _skyline = _parse(
  'M0 280V236l10-6l12-10l14-14l12-12h6h2v-20h-5v-4h5v-10h4v10h5v4h-5v20h8'
  'l14 10l14 12l12 10h4v-50h16v20h6v-68h30v68h4v-82l8-22l8 22v40h6v-44h4v-8'
  'h12v8h4v50h8v-20h18v40h10v-24h14v52h12v14h6l10-8h30l10 8l-24-70h14l22 70'
  'h10v-14h16v10h14v-8h12v18H412V280z',
);

/// Lit at dusk and night: windows, and the cross on Mount Royal.
const _windows = <Rect>[
  Rect.fromLTWH(56, 160, 4, 34),
  Rect.fromLTWH(51, 170, 14, 4),
  Rect.fromLTWH(118, 196, 2, 3),
  Rect.fromLTWH(140, 150, 2, 3),
  Rect.fromLTWH(152, 172, 2, 3),
  Rect.fromLTWH(172, 138, 2, 3),
  Rect.fromLTWH(198, 128, 2, 3),
  Rect.fromLTWH(202, 150, 2, 3),
  Rect.fromLTWH(226, 166, 2, 3),
  Rect.fromLTWH(250, 172, 2, 3),
  Rect.fromLTWH(356, 206, 2, 3),
  Rect.fromLTWH(384, 212, 2, 3),
];

const _stars = <(double, double, double)>[
  (0.10, 0.66, 1.1),
  (0.32, 0.71, 0.9),
  (0.52, 0.66, 1.2),
  (0.72, 0.73, 0.8),
  (0.85, 0.67, 1.0),
  (0.95, 0.59, 0.9),
  (0.20, 0.78, 0.7),
  (0.94, 0.45, 0.8),
];

/// A small parser for the skyline's own path (M, H, V, h, v, l and z only).
Path _parse(String d) {
  final path = Path();
  final tokens = RegExp(r'[MHVhvlz]|-?\d+(?:\.\d+)?')
      .allMatches(d)
      .map((m) => m[0]!)
      .toList();
  var x = 0.0, y = 0.0;
  var i = 0;
  String cmd = 'M';
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    final t = tokens[i];
    if (RegExp(r'^[MHVhvlz]$').hasMatch(t)) {
      cmd = t;
      i++;
      if (cmd == 'z') {
        path.close();
        continue;
      }
    }
    switch (cmd) {
      case 'M':
        x = next();
        y = next();
        path.moveTo(x, y);
      case 'H':
        x = next();
        path.lineTo(x, y);
      case 'V':
        y = next();
        path.lineTo(x, y);
      case 'h':
        x += next();
        path.lineTo(x, y);
      case 'v':
        y += next();
        path.lineTo(x, y);
      case 'l':
        x += next();
        y += next();
        path.lineTo(x, y);
    }
  }
  return path;
}
