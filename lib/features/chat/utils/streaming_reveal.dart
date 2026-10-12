import 'dart:math' as math;

/// A time-based prefix, bounded to 200ms regardless of burst size/frame rate.
/// Short nearby word boundaries are preferred; UTF-16 pairs stay intact.
int streamingRevealEnd({
  required String text,
  required int shown,
  required int startedAtLength,
  required Duration elapsed,
}) {
  const budget = Duration(milliseconds: 200);
  if (elapsed >= budget) return text.length;
  final progress = elapsed.inMicroseconds / budget.inMicroseconds;
  var end = math.min(
    text.length,
    math.max(
      shown + 3,
      startedAtLength + ((text.length - startedAtLength) * progress).ceil(),
    ),
  );
  if (end < text.length) {
    final space = text.indexOf(' ', end);
    if (space != -1 && space - end < 12) end = space;
    final unit = text.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end++;
  }
  return end;
}
