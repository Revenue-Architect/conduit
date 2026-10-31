import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Today's ground: Toronto's sky at this hour (docs/app-design-2026-10-30,
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
/// from an hour before sunset until 11 pm (the evening); with no sun times, Toronto's late-October hours stand in. In dark
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
/// Toronto skyline, and lit windows at dusk and night.
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

/// Toronto, flat: the same silhouette as the mockups' skyline (CN Tower at
/// x 264). Coordinates in a 412 × 280 box, origin top-left.
final Path _skyline = () {
  const ops = [
    'M0 280V232h22v-18h16v-26h20v34h14v-46h24v58h10v-22h18v-40h8v-14h12v14h8v52h16v-30h22v-58h6v-30h10v30h6v58h12v-36h20v52h10V174h14v-24h4l2-150h2l2 150h4v24h12v76h10v-44h22v-26h16v40h10v-58h20v48h14v-20h14v34h16v-18H412V280z',
  ];
  return _parse(ops.first);
}();

const _windows = <Rect>[
  Rect.fromLTWH(40, 240, 2, 3),
  Rect.fromLTWH(88, 210, 2, 3),
  Rect.fromLTWH(92, 230, 2, 3),
  Rect.fromLTWH(146, 190, 2, 3),
  Rect.fromLTWH(150, 212, 2, 3),
  Rect.fromLTWH(214, 190, 2, 3),
  Rect.fromLTWH(232, 220, 2, 3),
  Rect.fromLTWH(290, 240, 2, 3),
  Rect.fromLTWH(320, 202, 2, 3),
  Rect.fromLTWH(356, 226, 2, 3),
  Rect.fromLTWH(263, 160, 2, 2),
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
