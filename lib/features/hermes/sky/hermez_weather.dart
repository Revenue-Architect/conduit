import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'hermez_sky.dart';

/// Toronto's weather and sun for the sky, from Open-Meteo (no key). Fixed
/// coordinates: the phone's location is never read or sent.
class HermezWeather {
  const HermezWeather({
    required this.temperatureC,
    required this.code,
    required this.sunrise,
    required this.sunset,
    required this.fetchedAt,
  });

  final double temperatureC;

  /// WMO weather code.
  final int code;
  final DateTime sunrise;
  final DateTime sunset;
  final DateTime fetchedAt;

  HermezSkyWeather get sky => switch (code) {
    0 || 1 => HermezSkyWeather.clear,
    >= 51 && <= 67 || >= 80 && <= 82 || >= 95 => HermezSkyWeather.rain,
    >= 71 && <= 77 || 85 || 86 => HermezSkyWeather.snow,
    _ => HermezSkyWeather.overcast,
  };

  /// "clear", "light rain": the words on Today's top line.
  String get words => switch (code) {
    0 => 'clear',
    1 => 'mostly clear',
    2 => 'partly cloudy',
    3 => 'overcast',
    45 || 48 => 'fog',
    51 || 53 || 55 || 56 || 57 => 'drizzle',
    61 || 80 => 'light rain',
    63 || 81 => 'rain',
    65 || 82 => 'heavy rain',
    66 || 67 => 'freezing rain',
    71 || 85 => 'light snow',
    73 || 75 || 77 || 86 => 'snow',
    >= 95 => 'thunderstorms',
    _ => 'cloudy',
  };

  Map<String, Object> toJson() => {
    't': temperatureC,
    'c': code,
    'r': sunrise.toIso8601String(),
    's': sunset.toIso8601String(),
    'f': fetchedAt.toIso8601String(),
  };

  static HermezWeather? fromJson(Map<String, Object?> json) {
    try {
      return HermezWeather(
        temperatureC: (json['t'] as num).toDouble(),
        code: (json['c'] as num).toInt(),
        sunrise: DateTime.parse(json['r'] as String),
        sunset: DateTime.parse(json['s'] as String),
        fetchedAt: DateTime.parse(json['f'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

const _cacheKey = 'hermez.sky.weather.v1';
const _ttl = Duration(hours: 1);
final _endpoint = Uri.parse(
  'https://api.open-meteo.com/v1/forecast?latitude=43.65&longitude=-79.38'
  '&current=temperature_2m,weather_code&daily=sunrise,sunset'
  '&timezone=America%2FToronto&forecast_days=1',
);

/// The latest Toronto weather: the cached reading while it is under an hour
/// old, else a fresh one. Null offline with nothing cached; the sky then
/// follows the clock alone and Today hides the weather words.
final hermezWeatherProvider = FutureProvider<HermezWeather?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final cachedRaw = prefs.getString(_cacheKey);
  final cached = cachedRaw == null
      ? null
      : HermezWeather.fromJson(jsonDecode(cachedRaw) as Map<String, Object?>);
  final now = DateTime.now();
  if (cached != null && now.difference(cached.fetchedAt) < _ttl) return cached;
  try {
    final response = await http
        .get(_endpoint)
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return cached;
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final current = body['current'] as Map<String, Object?>;
    final daily = body['daily'] as Map<String, Object?>;
    final fresh = HermezWeather(
      temperatureC: (current['temperature_2m'] as num).toDouble(),
      code: (current['weather_code'] as num).toInt(),
      sunrise: DateTime.parse((daily['sunrise'] as List).first as String),
      sunset: DateTime.parse((daily['sunset'] as List).first as String),
      fetchedAt: now,
    );
    await prefs.setString(_cacheKey, jsonEncode(fresh.toJson()));
    return fresh;
  } catch (_) {
    return cached;
  }
});
