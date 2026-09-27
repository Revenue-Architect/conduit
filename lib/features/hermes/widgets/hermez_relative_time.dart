/// Product time labels. Never returns a raw [DateTime] dump.
String hermezRelativeLabel(DateTime time, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final local = time.toLocal();
  final localNow = clock.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final dayDelta = day.difference(today).inDays;
  final elapsed = localNow.difference(local);

  if (dayDelta == 0) {
    if (!elapsed.isNegative && elapsed.inMinutes < 1) return 'Just now';
    if (!elapsed.isNegative && elapsed.inMinutes < 90) {
      if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
      return '${elapsed.inHours}h ago';
    }
    return 'Today, ${_clock(local)}';
  }
  if (dayDelta == -1) return 'Yesterday, ${_clock(local)}';
  if (dayDelta == 1) return 'Tomorrow, ${_clock(local)}';
  if (dayDelta < -1 && dayDelta > -7) {
    return '${-dayDelta}d ago';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}, ${_clock(local)}';
}

String hermezWhen(DateTime? time, {DateTime? now, String? prefix}) {
  if (time == null) return '';
  final label = hermezRelativeLabel(time, now: now);
  if (prefix == null || prefix.isEmpty) return label;
  return '$prefix $label';
}

String _clock(DateTime local) {
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}
