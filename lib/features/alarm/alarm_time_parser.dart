/// Fast offline time parsing for alarms & reminders.
///
/// Pure-Dart, regex-only (no async, no model) so alarm/reminder commands
/// resolve in microseconds before any LLM call.
///
/// Supported (case-insensitive):
/// - Relative: "in 10 seconds/minutes/hours/days", "after 5 minutes",
///   "5 minutes later", "after 1 hour 30 minutes"
/// - Absolute: "at 7", "at 7am/pm", "at 7:30 pm", "19:30", "7 o'clock",
///   "tomorrow at 6:30 am", "today at 9pm", "7 in the morning/evening"
library;

/// Result of parsing an alarm/reminder time expression.
class ParsedTime {
  /// Absolute local time to fire.
  final DateTime when;

  /// True when the input was a relative duration ("in 10 minutes").
  final bool isRelative;

  const ParsedTime(this.when, {this.isRelative = false});
}

/// Parses a fire-time from free voice text.
///
/// Returns null when no recognizable time is present. Past absolute times
/// roll to tomorrow (so "set alarm for 7am" at 9am means tomorrow 7am).
/// Relative durations under 10 seconds are clamped to 10s so the native
/// AlarmManager never fires in the past.
ParsedTime? parseAlarmTime(String rawInput, {DateTime? now}) {
  final nowDt = now ?? DateTime.now();
  final input = rawInput.trim();
  if (input.isEmpty) return null;
  final lower = input.toLowerCase();

  // 1. Relative durations win (unambiguous + fastest).
  final relative = _parseRelative(lower, nowDt);
  if (relative != null) return relative;

  // 2. Absolute clock times.
  return _parseAbsolute(lower, nowDt);
}

/// Extracts an alarm label ("called gym", "named workout", "to wake up").
String parseAlarmLabel(String rawInput) {
  final text = rawInput.trim();
  // Prefer an explicit "called/named/..." tag at the end — a plain "for"
  // would otherwise swallow the time itself ("for 7am called gym").
  final tagged = RegExp(
    r'\b(?:called|named|label(?:led)?|titled?)\s+([a-z][a-z0-9\s]{0,48})$',
    caseSensitive: false,
  ).firstMatch(text);
  String? candidate = tagged?.group(1)?.trim();
  candidate ??= RegExp(
    r'\bfor\s+([a-z][a-z0-9\s]{0,48})$',
    caseSensitive: false,
  ).firstMatch(text)?.group(1)?.trim();
  if (candidate == null || candidate.isEmpty) return '';
  var label = candidate;
  // Don't steal the time itself ("for 7am" is not a label).
  if (RegExp(r'^\d', caseSensitive: false).hasMatch(label)) return '';
  if (RegExp(r'^(alarm|reminder|wake|me|up)\b', caseSensitive: false)
      .hasMatch(label)) {
    return '';
  }
  if (label.length > 50) label = label.substring(0, 50).trim();
  return label;
}

/// Extracts the reminder message body, stripping the verb + time expression.
String parseReminderMessage(String rawInput) {
  var text = rawInput.trim();
  // Strip leading verbs.
  text = text.replaceAll(
    RegExp(
      r'^\s*(please\s+|can you\s+|kindly\s+)?(set\s+(a\s+|an\s+)?(reminder|remainder|remind)|remind\s+me|reminder|remind)\b\s*(to\s+|me\s+to\s+|for\s+)?',
      caseSensitive: false,
    ),
    '',
  ).trim();
  if (text.isEmpty) return '';

  // Cut trailing/leading time expressions so "call mom in 10 minutes"
  // keeps "call mom".
  final timePatterns = [
    RegExp(
      r'\s*\b(in|after)\s+\d+\s*(seconds?|secs?|s|minutes?|mins?|hours?|hrs?|days?)\b(\s+\d+\s*(seconds?|secs?|s|minutes?|mins?|hours?|hrs?))?\s*(later|from now|hence)?\s*$',
      caseSensitive: false,
    ),
    RegExp(r'\s*\b\d+\s*(seconds?|minutes?|hours?|days?)\s+later\s*$',
        caseSensitive: false),
    RegExp(
      r'\s*\b(at|by|on|for)\s+\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.|o\s*clock)?\s*(today|tonight|tomorrow|morning|afternoon|evening|night)?\s*$',
      caseSensitive: false,
    ),
    RegExp(
      r'\s*\btomorrow(\s+morning|\s+afternoon|\s+evening)?(\s+at\s+\d{1,2}(:\d{2})?\s*(am|pm)?)?\s*$',
      caseSensitive: false,
    ),
    RegExp(
      r'\s*\btoday(\s+at\s+\d{1,2}(:\d{2})?\s*(am|pm)?)?\s*$',
      caseSensitive: false,
    ),
  ];
  for (final p in timePatterns) {
    text = text.replaceAll(p, '').trim();
  }
  // Strip a leading "at <time>" left over from "remind me at 9pm to X".
  text = text.replaceAll(
    RegExp(
      r'^\s*(at|on|by)\s+\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)?\s*(today|tonight|tomorrow)?\s*(to\s+)?',
      caseSensitive: false,
    ),
    '',
  ).trim();
  // Strip "that/i that" connectors.
  text = text.replaceAll(
    RegExp(r'^(that|to)\s+', caseSensitive: false),
    '',
  ).trim();
  if (text.length > 200) text = text.substring(0, 200).trim();
  return text;
}

// ---------------------------------------------------------------------------
// Relative: "in 5 minutes", "after 1 hour", "10 seconds later"
// ---------------------------------------------------------------------------

ParsedTime? _parseRelative(String lower, DateTime now) {
  // "in 5 minutes" / "after 1 hour 30 minutes" / "in 1 hour and 15 minutes"
  var m = RegExp(
    r'\b(?:in|after)\s+(\d{1,3})\s*(seconds?|secs?|s|minutes?|mins?|hours?|hrs?|days?)\b(?:\s*(?:and\s+)?(\d{1,3})\s*(seconds?|secs?|s|minutes?|mins?|hours?|hrs?))?',
    caseSensitive: false,
  ).firstMatch(lower);
  if (m != null) {
    var total = _unitToDuration(
      int.parse(m.group(1)!),
      m.group(2)!,
    );
    final n2 = m.group(3);
    final u2 = m.group(4);
    if (n2 != null && u2 != null) {
      total += _unitToDuration(int.parse(n2), u2);
    }
    if (total.inSeconds <= 0) return null;
    if (total.inSeconds < 10) total = const Duration(seconds: 10);
    return ParsedTime(now.add(total), isRelative: true);
  }

  // "for 10 minutes" ("set an alarm for 10 minutes" = in 10 minutes).
  m ??= RegExp(
    r'\bfor\s+(\d{1,3})\s*(seconds?|secs?|s|minutes?|mins?|hours?|hrs?|days?)\b',
    caseSensitive: false,
  ).firstMatch(lower);
  if (m != null) {
    var total = _unitToDuration(
      int.parse(m.group(1)!),
      m.group(2)!,
    );
    if (total.inSeconds <= 0) return null;
    if (total.inSeconds < 10) total = const Duration(seconds: 10);
    return ParsedTime(now.add(total), isRelative: true);
  }

  // "5 minutes later" / "10 seconds from now"
  m = RegExp(
    r'\b(\d{1,3})\s*(seconds?|secs?|s|minutes?|mins?|hours?|hrs?|days?)\s+(later|from now|hence|from here)\b',
    caseSensitive: false,
  ).firstMatch(lower);
  if (m != null) {
    var total = _unitToDuration(int.parse(m.group(1)!), m.group(2)!);
    if (total.inSeconds <= 0) return null;
    if (total.inSeconds < 10) total = const Duration(seconds: 10);
    return ParsedTime(now.add(total), isRelative: true);
  }
  return null;
}

Duration _unitToDuration(int n, String unit) {
  final u = unit.toLowerCase();
  if (u.startsWith('s')) return Duration(seconds: n);
  if (u.startsWith('min') || u == 'm') return Duration(minutes: n);
  if (u.startsWith('h')) return Duration(hours: n);
  if (u.startsWith('d')) return Duration(days: n);
  return Duration(minutes: n);
}

// ---------------------------------------------------------------------------
// Absolute: "7am", "7:30 pm", "19:30", "7 o'clock", "tomorrow at 6am"
// ---------------------------------------------------------------------------

ParsedTime? _parseAbsolute(String lower, DateTime now) {
  final isTomorrow = lower.contains('tomorrow') ||
      lower.contains('day after tomorrow') ||
      lower.contains('next day');
  final isToday = lower.contains('today') || lower.contains('tonight');

  // "at 7:30 pm" / "at 7 am" / "at 19:30" / "at 7"
  var m = RegExp(
    r'\b(?:at|by)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.?\s*m\.?|p\.?\s*m\.?)?\b',
    caseSensitive: false,
  ).firstMatch(lower);

  // Bare "7:30pm" / "7am" / "19:30" anywhere (covers "for 7am" too).
  m ??= RegExp(
    r'\b(\d{1,2}):(\d{2})\s*(am|pm|a\.?\s*m\.?|p\.?\s*m\.?)?\b',
    caseSensitive: false,
  ).firstMatch(lower);

  // Bare "7am" / "7 am" / "7pm" without "at" ("for 7am", "alarm 7pm").
  m ??= RegExp(
    r'\b(\d{1,2})\s*(am|pm|a\.?\s*m\.?|p\.?\s*m\.?)\b',
    caseSensitive: false,
  ).firstMatch(lower);

  // "7 o'clock" / "7 o clock".
  m ??= RegExp(
    r'\b(\d{1,2})\s*o\s*clock\s*(am|pm)?\b',
    caseSensitive: false,
  ).firstMatch(lower);

  // Bare hour after for/at ("for 7", "at 9") — next occurrence.
  m ??= RegExp(
    r'\b(?:for|at)\s+(\d{1,2})\b',
    caseSensitive: false,
  ).firstMatch(lower);

  if (m == null) {
    // "7 in the morning/evening" / "wake me up at 7".
    final m2 = RegExp(
      r'\b(\d{1,2})\s*(in the\s+)?(morning|afternoon|evening|night)\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (m2 != null) {
      final hour12 = int.parse(m2.group(1)!);
      if (hour12 < 1 || hour12 > 12) return null;
      final part = m2.group(3)!.toLowerCase();
      final isPm = part == 'afternoon' || part == 'evening';
      return _resolveClockTime(
        hour12,
        0,
        isPm ? 'pm' : 'am',
        now,
        isTomorrow: isTomorrow,
        isToday: isToday,
        hasMeridiem: true,
      );
    }
    // Bare "at 7" without minutes already covered; last try: "wake up 7".
    return null;
  }

  final hourRaw = int.parse(m.group(1)!);
  int minute = 0;
  String? meridiem;
  // Works for every arity: 3-group ("7:30 pm"), 2-group ("7am",
  // "7 o'clock", "for 7") and optional groups that did not participate.
  for (var gi = 2; gi <= m.groupCount; gi++) {
    final g = m.group(gi);
    if (g == null || g.isEmpty) continue;
    if (RegExp(r'^\d+$').hasMatch(g)) {
      minute = int.parse(g);
    } else {
      meridiem = g;
    }
  }
  if (minute < 0 || minute > 59) return null;
  return _resolveClockTime(
    hourRaw,
    minute,
    meridiem,
    now,
    isTomorrow: isTomorrow,
    isToday: isToday,
    hasMeridiem: meridiem != null && meridiem.trim().isNotEmpty,
  );
}

ParsedTime? _resolveClockTime(
  int hourRaw,
  int minute,
  String? meridiemRaw,
  DateTime now, {
  required bool isTomorrow,
  required bool isToday,
  required bool hasMeridiem,
}) {
  int hour;
  final mer = (meridiemRaw ?? '').toLowerCase().replaceAll(RegExp(r'[\s.]'), '');
  final isAm = mer.startsWith('a');
  final isPm = mer.startsWith('p');

  if (hasMeridiem) {
    if (hourRaw < 1 || hourRaw > 12) return null;
    hour = hourRaw % 12;
    if (isPm) hour += 12;
  } else {
    // 24h when hour > 12 or minute form; bare 1..12 without meridiem:
    // guess by closeness — pick the next occurrence (am or pm) whichever
    // is sooner in the future.
    if (hourRaw > 23) return null;
    if (hourRaw > 12 || minute > 0 && hourRaw <= 23) {
      hour = hourRaw;
      if (hour > 23) return null;
      final candidate =
          DateTime(now.year, now.month, now.day, hour, minute);
      if (!isTomorrow) {
        if (isToday) {
          if (!candidate.isAfter(now)) return null; // today but passed
          return ParsedTime(candidate);
        }
        if (candidate.isAfter(now)) return ParsedTime(candidate);
        return ParsedTime(candidate.add(const Duration(days: 1)));
      }
      return ParsedTime(
        DateTime(now.year, now.month, now.day, hour, minute)
            .add(const Duration(days: 1)),
      );
    }
    // Bare hour 1..12: next occurrence (covers "alarm at 7" fast).
    final am = DateTime(now.year, now.month, now.day, hourRaw % 24, minute);
    final pm =
        DateTime(now.year, now.month, now.day, (hourRaw % 12) + 12, minute);
    if (isTomorrow) return ParsedTime(am.add(const Duration(days: 1)));
    if (am.isAfter(now) && pm.isAfter(now)) {
      return ParsedTime(am.isBefore(pm) ? am : pm);
    }
    if (am.isAfter(now)) return ParsedTime(am);
    if (pm.isAfter(now)) return ParsedTime(pm);
    return ParsedTime(am.add(const Duration(days: 1)));
  }

  var candidate = DateTime(now.year, now.month, now.day, hour, minute);
  if (isTomorrow) {
    candidate = candidate.add(const Duration(days: 1));
    return ParsedTime(candidate);
  }
  if (!candidate.isAfter(now)) {
    // Roll to tomorrow — never schedule in the past.
    candidate = candidate.add(const Duration(days: 1));
  }
  return ParsedTime(candidate);
}

/// "7:30 AM", "7 AM tomorrow", "in 5 minutes" — short speech-friendly text.
String formatAlarmSpeech(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = when.difference(ref);
  if (diff.inSeconds < 90) return 'in a few seconds';
  if (diff.inMinutes < 90) {
    final mins = diff.inMinutes;
    return 'in $mins minute${mins == 1 ? '' : 's'}';
  }
  final hour12 = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final mm = when.minute.toString().padLeft(2, '0');
  final mer = when.hour < 12 ? 'AM' : 'PM';
  final time = mm == '00' ? '$hour12 $mer' : '$hour12:$mm $mer';
  final dayDiff = DateTime(when.year, when.month, when.day)
      .difference(DateTime(ref.year, ref.month, ref.day))
      .inDays;
  if (dayDiff <= 0) return 'today at $time';
  if (dayDiff == 1) return 'tomorrow at $time';
  return 'on ${when.day}/${when.month} at $time';
}
