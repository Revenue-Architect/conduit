import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hermez_sky.dart';
import 'hermez_weather.dart';

/// Montreal's sky right now, from the cached Open-Meteo reading; dark mode
/// always gets the evening or night version.
HermezSkyState watchHermezSky(BuildContext context, WidgetRef ref) {
  final weather = ref.watch(hermezWeatherProvider).value;
  return HermezSkyState(
    phase: hermezSkyPhaseAt(
      DateTime.now(),
      sunrise: weather?.sunrise,
      sunset: weather?.sunset,
      dark: Theme.of(context).brightness == Brightness.dark,
    ),
    weather: weather?.sky ?? HermezSkyWeather.clear,
  );
}

/// The sky behind a page header (mockup r4 02, 03, 05): Today's sky cut
/// short, with a low skyline along its bottom edge. Fills its parent.
class HermezSkyBand extends ConsumerWidget {
  const HermezSkyBand({super.key, this.skylineHeight = 30});

  final double skylineHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CustomPaint(
    painter: HermezSkyPainter(
      watchHermezSky(context, ref),
      skylineHeight: skylineHeight,
    ),
    child: const SizedBox.expand(),
  );
}

/// The flat colour under the skyline, for a strip that continues the band
/// (behind a sheet's rounded corners).
class HermezSkyGround extends ConsumerWidget {
  const HermezSkyGround({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ColoredBox(color: hermezSkyGround(watchHermezSky(context, ref).phase));
}
