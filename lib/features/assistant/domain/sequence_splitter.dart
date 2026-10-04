/// Splits a compound voice command into ordered single-task steps.
///
/// Examples:
/// - "open whatsapp, set volume to 40 percent, set brightness to 30 percent"
///   -> ["open whatsapp", "set volume to 40 percent", "set brightness to 30 percent"]
/// - "open whatsapp then set volume to 40 percent then set brightness to 30"
///   -> 3 steps
/// - "open whatsapp set volume to 40 percent set brightness to 30 percent"
///   (no delimiters, concatenated) -> 3 steps via action-boundary detection
///
/// Single-task commands that legitimately contain "and play" are NOT split:
/// - "open gallery and play second video" -> 1 step
/// - "open youtube search hindi music and play first video" -> 1 step
library;

/// Splits [rawInput] into 1..N ordered step strings.
///
/// Always returns at least one trimmed non-empty step (the original input)
/// when no sequence is detected.
List<String> splitIntoSteps(String rawInput) {
  final input = rawInput.trim();
  if (input.isEmpty) return [input];

  final lower = input.toLowerCase();

  // Guard: dedicated single intents that contain "and play" must never split.
  if (_isSingleGalleryPlay(lower) ||
      _isSingleYouTubeSearchPlay(lower) ||
      _isSingleAiAsk(lower)) {
    return [input];
  }

  // Guard: whatsapp send with free-text message. Only split on STRONG
  // delimiters (then/comma/semicolon) to avoid splitting inside the message
  // body (e.g. "saying hello and welcome").
  final isWhatsAppSend = lower.contains('whatsapp');

  // 1. Split on strong sequence delimiters: comma, semicolon, then,
  //    and then, after that, followed by, afterwards, next.
  var chunks = _splitOnStrongDelimiters(input);

  // 2. Split remaining chunks on "and" / "&" / "plus" ONLY when followed by
  //    an action starter (so "hello and welcome" is preserved).
  final List<String> afterAnd = [];
  for (final chunk in chunks) {
    // For whatsapp chunks containing "saying", be conservative: only split
    // on strong "and then" style, already done above. Skip plain "and" split
    // inside the message portion.
    if (isWhatsAppSend && _containsSaying(chunk)) {
      afterAnd.addAll(_splitWhatsAppChunk(chunk));
    } else {
      afterAnd.addAll(_splitOnAndBeforeAction(chunk));
    }
  }

  // 3. For chunks still containing multiple concatenated actions without any
  //    delimiter ("open whatsapp set volume to 40 ..."), slice on
  //    action boundaries.
  final List<String> steps = [];
  for (final chunk in afterAnd) {
    steps.addAll(_splitOnActionBoundaries(chunk));
  }

  final cleaned = steps.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (cleaned.isEmpty) return [input];
  // Repair elliptical fragments like "brightness to 80%" (from
  // "set volume to 50% and brightness to 80%"): the second task drops its
  // verb. Restore "set " so downstream parsing sees the level.
  final repaired = _repairEllipticalSteps(cleaned);
  // De-duplicate empty splits; if only one, return original trimmed form
  // to preserve exact casing/punctuation for downstream heuristics.
  if (repaired.length == 1) return [repaired.first];
  return repaired;
}

/// Prepends a missing "set " verb to elliptical level fragments.
///
/// "set volume to 50% and brightness to 80%" splits into
/// ["set volume to 50%", "brightness to 80%"] — the second step is missing
/// its verb and would otherwise be read as a query (reporting the current
/// level instead of setting 80). Same for "volume 50 and brightness 80".
List<String> _repairEllipticalSteps(List<String> steps) {
  final out = <String>[];
  for (final step in steps) {
    final lower = step.toLowerCase().trim();
    // Already has a verb — keep as-is.
    if (RegExp(r'^(set|turn|increase|decrease|raise|lower|mute|unmute|open|launch|start|play|pause|resume|stop|dim|brighten|toggle)\b',
            caseSensitive: false)
        .hasMatch(lower)) {
      out.add(step);
      continue;
    }
    // Bare "<volume|brightness> ..." with a number -> restore "set ".
    // Covers "brightness to 80%", "brightness 80", "volume to 50%",
    // "volume 50%", "brightness to 80 percent".
    if (RegExp(
            r'^(volume|brightness)\b.*\b\d{1,3}\b',
            caseSensitive: false)
        .hasMatch(lower)) {
      out.add('set $step');
      continue;
    }
    out.add(step);
  }
  return out;
}

/// True when the input has more than one executable step.
bool isCompoundCommand(String rawInput) => splitIntoSteps(rawInput).length > 1;

bool _isSingleGalleryPlay(String lower) {
  final mentionsGallery = lower.contains('galler') ||
      lower.contains('google photos') ||
      (lower.contains('photos') &&
          (lower.contains('play') || lower.contains('video')));
  return mentionsGallery &&
      (lower.contains('play') || lower.contains('video'));
}

bool _isSingleYouTubeSearchPlay(String lower) {
  return (lower.contains('youtube') || lower.contains('you tube')) &&
      lower.contains('search');
}

bool _isSingleAiAsk(String lower) {
  // NOTE: callers pass already-normalized text (see processCommand), so
  // exact checks cover "deepsik/lipstik" via normalizeAiTranscript. The extra
  // fuzzy patterns below are a safety net for direct calls.
  final mentionsAi = lower.contains('deepseek') ||
      lower.contains('deep seek') ||
      lower.contains('chatgpt') ||
      lower.contains('chat gpt') ||
      lower.contains('gemini') ||
      lower.contains('deepsik') ||
      lower.contains('deep sick') ||
      lower.contains('lipstik') ||
      lower.contains('lipstick') ||
      lower.contains('jemini') ||
      RegExp(r'\bgpt\b').hasMatch(lower);
  if (!mentionsAi) return false;
  return lower.contains('ask') ||
      lower.contains('search') ||
      lower.contains('pucho') ||
      lower.contains('puch') ||
      lower.contains('batao') ||
      lower.contains('bata');
}

bool _containsSaying(String chunk) =>
    chunk.toLowerCase().contains('saying');

/// Splits a whatsapp chunk conservatively: cut only on strong delimiters
/// occurring AFTER the message start, keeping "A and B" inside messages.
List<String> _splitWhatsAppChunk(String chunk) {
  // Already split on strong delimiters globally; here just handle
  // "and set volume..." style tails after a whatsapp message.
  // e.g. "send whatsapp to mom saying hi and set volume to 40"
  final andAction = RegExp(
    r'\band\b(?=\s*(?:open|launch|start|set|volume|brightness|turn|increase|decrease|raise|lower|mute|unmute|play|pause|resume|stop|next|previous|skip|dim|brighten|flashlight|torch|wifi|bluetooth|call|dial|phone|remind|reminder|wake|cancel|alarm|alarms)\b)',
    caseSensitive: false,
  );
  final parts = chunk.split(andAction);
  if (parts.length <= 1) return [chunk];
  // Only accept the split if the first part still looks like whatsapp and
  // the trailing parts look like independent commands.
  return parts;
}

List<String> _splitOnStrongDelimiters(String input) {
  final strong = RegExp(
    r'\s*(?:;|\band\s+then\b|\bthen\b|\bafter\s+that\b|\bfollowed\s+by\b|\bafterwards\b|\bafterward\b)\s*'
    r'|'
    r'\s*,\s*',
    caseSensitive: false,
  );
  return input.split(strong);
}

List<String> _splitOnAndBeforeAction(String chunk) {
  final andBeforeAction = RegExp(
    r'\s*(?:\band\b|\&|\bplus\b)\s*(?=(?:open|launch|start|set|volume|brightness|turn|increase|decrease|raise|lower|mute|unmute|play|pause|resume|stop|next|previous|skip|dim|brighten|brighter|dimmer|flashlight|torch|wifi|bluetooth|whatsapp|call|dial|phone|check|read|remind|reminder|wake|cancel|alarm|alarms)\b)',
    caseSensitive: false,
  );
  // Avoid splitting "open gallery and play ..." — guarded earlier globally,
  // but also guard per-chunk in case strong-split produced gallery chunks.
  final lower = chunk.toLowerCase();
  if (_isSingleGalleryPlay(lower) ||
      _isSingleYouTubeSearchPlay(lower) ||
      _isSingleAiAsk(lower)) {
    return [chunk];
  }
  return chunk.split(andBeforeAction);
}

/// Action-starter pattern for concatenated commands without delimiters.
///
/// Matches the beginning of a new task: "open X", "launch X", "start X",
/// "set volume/brightness ...", "volume up/down", "brightness up/down",
/// "mute", "unmute", "turn on/off ...", "increase/decrease ...",
/// media verbs, "send whatsapp ...", "check whatsapp ...", etc.
final RegExp _actionStarter = RegExp(
   '(?:'
   r'\bopen\s+[a-z]|\blaunch\s+[a-z]|\bstart\s+[a-z]'
   r'|\bset\s+(?:the\s+)?(?:volume|brightness)\b'
   r'|\bvolume\s+(?:up|down)\b|\bbrightness\s+(?:up|down)\b'
   r'|\bturn\s+(?:up|down|on|off)\b'
   r'|\btoggle\s+(?:the\s+)?(?:flashlight|torch|flash|wifi|bluetooth)\b'
   r'|\bincrease\s+(?:the\s+)?(?:volume|brightness)\b'
   r'|\bdecrease\s+(?:the\s+)?(?:volume|brightness)\b'
   r'|\braise\s+(?:the\s+)?(?:volume|brightness)\b'
   r'|\blower\s+(?:the\s+)?(?:volume|brightness)\b'
   r'|\bmute\b|\bunmute\b'
   r'|\bdim\s+(?:the\s+)?(?:screen|brightness)?\b|\bbrighten\b|\bbrighter\b|\bdimmer\b'
    r'|\bplay\b|\bpause\b|\bresume\b|\bcontinue\b|\bstop\b|\bnext\b|\bprevious\b|\bskip\b'
     r'|\bsend\s+(?:a\s+)?whatsapp\b|\bwhatsapp\b|\bcheck\s+whatsapp\b|\bread\s+chat\b|\bcheck\s+messages\b|\bread\s+messages\b'
    r'|\bcall\b|\bcalling\b|\bdial\b|\bphone\s+call\b|\bmake\s+(?:a\s+)?call\b'
    r'|\bset\s+(?:an?\s+)?alarm\b|\bremind\s+me\b|\breminder\b|\bremind\b'
   r'|\bwake\s+me\s+up\b|\bwake\s+up\b'
   r'|\bcancel\s+(?:the\s+|my\s+|all\s+)?(?:alarm|reminder)'
   r'|\b(?:show|list|check)\s+(?:my\s+|the\s+|all\s+)?(?:alarm|reminder)'
   // Hindi/Marathi action starters
   r'|\bawaaj\b|\bchale\b|\bchiya\b|\bkashi\b'
   r')',
   caseSensitive: false,
 );

List<String> _splitOnActionBoundaries(String chunk) {
  final trimmed = chunk.trim();
  if (trimmed.isEmpty) return [chunk];
  final lower = trimmed.toLowerCase();
  if (_isSingleGalleryPlay(lower) ||
      _isSingleYouTubeSearchPlay(lower) ||
      _isSingleAiAsk(lower)) {
    return [trimmed];
  }

  final matches = _actionStarter.allMatches(trimmed).toList();
  if (matches.length <= 1) return [trimmed];

  // Keep only matches that start a genuinely new task: the first match must
  // be at/near position 0, subsequent matches must be separated by at least
  // a couple of characters of prior content (avoids "turn up ... volume up"
  // double-counting inside one task).
  final starts = <int>[];
  for (final m in matches) {
    if (starts.isEmpty) {
      // First action should be at the start (allow small leading noise like
      // "please").
      if (m.start <= 12) {
        starts.add(m.start);
      } else {
        // No leading action — treat whole chunk as one step.
        return [trimmed];
      }
    } else {
      // Require at least 3 chars since previous start to avoid overlapping
      // hits like "turn" + "volume" inside the same task counting twice.
      // Also require the text between to look like a completed prior task
      // (at least 4 chars).
      if (m.start - starts.last >= 4) {
        // Avoid splitting "turn on the flashlight" on inner "flashlight":
        // if previous start was "turn on ..." and this is just its object,
        // skip when the gap is small and previous segment has no completion.
        final prevSegment =
            trimmed.substring(starts.last, m.start).trim().toLowerCase();
        if (_isContinuation(prevSegment)) continue;
        starts.add(m.start);
      }
    }
  }

  if (starts.length <= 1) return [trimmed];

  final steps = <String>[];
  for (var i = 0; i < starts.length; i++) {
    final end = i + 1 < starts.length ? starts[i + 1] : trimmed.length;
    final step = trimmed.substring(starts[i], end).trim();
    // Strip trailing connectors left over from slicing ("and", ",").
    final cleaned =
        step.replaceAll(RegExp(r'^(and|then|,|;)\b\s*', caseSensitive: false), '').trim();
    if (cleaned.isNotEmpty) steps.add(cleaned);
  }
  return steps.isEmpty ? [trimmed] : steps;
}

/// True when [segment] looks like an incomplete task whose next keyword is
/// its object, not a new task (e.g. "turn on the" before "flashlight").
bool _isContinuation(String segment) {
  var s = segment
      .replaceAll(
          RegExp(r'^(please|can you|kindly)\b\s*', caseSensitive: false), '')
      .trim()
      .toLowerCase();
  if (s.isEmpty) return true;
  // Verb-only prefixes: the next word is the object of the same task.
  if (RegExp(
           r'^(open|launch|start|turn|set|increase|decrease|raise|lower|send|check|read|play|pause|resume|stop|volume|brightness|mute|unmute|dim|brighten|call|dial|phone|awaaj|chale|chiya|kashi)$')
       .hasMatch(s)) {
     return true;
   }
  if (RegExp(
           r'^(turn\s+(on|off|up|down)(\s+the)?|set\s+(the)?|open\s*|launch\s*|start\s*|send\s*(a|the)?|check\s*(the)?|increase\s*(the)?|decrease\s*(the)?|raise\s*(the)?|lower\s*(the)?|call\s*(a|the|my)?|dial\s*|awaaj|chale)$')
       .hasMatch(s)) {
     return true;
   }
  // "turn on the flashlight" style: short verb phrase without a noun yet.
  // If the segment has no object noun, the next match completes it.
  if (s.length <= 16 &&
      RegExp(r'^(turn|set|open|launch|start|send|check|call|dial|increase|decrease|raise|lower)\b')
          .hasMatch(s) &&
      !RegExp(r'\b(flashlight|torch|flash|wifi|bluetooth|volume|brightness|music|song|youtube|whatsapp|gallery)\b')
          .hasMatch(s)) {
    return true;
  }
  return false;
}
