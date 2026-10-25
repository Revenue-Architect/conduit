import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../../../core/utils/debug_logger.dart';

/// Frame timings for the character selector, in diagnostic builds only
/// (`--dart-define=CONDUIT_DIAG=true`): every burst of frames (a swipe, a
/// keyboard slide) is summarised to the log as build and raster times, so
/// smoothness is measured on the phone rather than guessed. Inert in normal
/// builds.
class MangaFrameProbe {
  MangaFrameProbe(this.label);

  static const bool _enabled = bool.fromEnvironment('CONDUIT_DIAG');

  final String label;
  final List<FrameTiming> _burst = [];
  Timer? _quiet;

  void start() {
    if (!_enabled) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_enabled) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _quiet?.cancel();
    _flush();
  }

  void _onTimings(List<FrameTiming> timings) {
    _burst.addAll(timings);
    // A burst ends after 400 ms without frames.
    _quiet?.cancel();
    _quiet = Timer(const Duration(milliseconds: 400), _flush);
  }

  void _flush() {
    if (_burst.length < 6) {
      _burst.clear();
      return;
    }
    double ms(Duration d) => d.inMicroseconds / 1000;
    final build = _burst.map((t) => ms(t.buildDuration)).toList()..sort();
    final raster = _burst.map((t) => ms(t.rasterDuration)).toList()..sort();
    double pct(List<double> v, double p) =>
        v[((v.length - 1) * p).round().clamp(0, v.length - 1)];
    // At 120 Hz a frame has 8.3 ms; one that takes longer in either thread
    // is late.
    final late = _burst
        .where((t) => ms(t.buildDuration) > 8.3 || ms(t.rasterDuration) > 8.3)
        .length;
    DebugLogger.log(
      'frames',
      scope: 'pick-probe/$label',
      data: {
        'n': _burst.length,
        'late': late,
        'build_p50': pct(build, .5).toStringAsFixed(1),
        'build_p90': pct(build, .9).toStringAsFixed(1),
        'build_max': build.last.toStringAsFixed(1),
        'raster_p50': pct(raster, .5).toStringAsFixed(1),
        'raster_p90': pct(raster, .9).toStringAsFixed(1),
        'raster_max': raster.last.toStringAsFixed(1),
      },
    );
    _burst.clear();
  }
}
