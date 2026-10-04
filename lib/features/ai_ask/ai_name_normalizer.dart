/// Offline STT transcript normalizer for AI app names.
///
/// Android's SpeechRecognizer frequently mishears proper nouns:
/// - "DeepSeek" -> "deepsik", "deep sick", "deep chic", "dip seek",
///   "lipstik/lipstick/lip seek" (d/l confusion in noise — maps to DeepSeek)
/// - "ChatGPT"  -> "chat gpt", "cat gpt", "chat jee pee tee", "chat gp"
/// - "Gemini"   -> "jemini", "gemani", "jamini"
///
/// This runs BEFORE heuristics + the local LLM so both layers see the
/// canonical `deepseek | chatgpt | gemini` spelling. Pure Dart, no I/O,
/// safe to call on every command.
library;

/// Canonical AI app targets.
const String kDeepSeek = 'deepseek';
const String kChatGpt = 'chatgpt';
const String kGemini = 'gemini';
const String kFo = 'fo';

/// Rewrites common STT mishearings of AI app names to their canonical form.
///
/// Only the app-name span is replaced; the rest of the query (casing,
/// punctuation) is preserved. Returns [input] unchanged when nothing matches.
String normalizeAiTranscript(String input) {
  if (input.isEmpty) return input;
  var out = input;
  final lower = input.toLowerCase();

  // ---- DeepSeek variants (rare words, safe to replace unconditionally) ----
  // Matches: deepsik, deepseek, deep seek, deep sick, deep chic/chick,
  // deep sheek, dipseek, dip seek, deepsek, deepseeek, deep seak,
  // deep shik/sikh, beep seek, leap seek, etc.
  out = out.replaceAllMapped(
    RegExp(
      r'\bdeep[\s\-_]*s[eiy]+k\b'
      r'|\bdeep[\s\-_]*seek\b'
      r'|\bdeep[\s\-_]*sick\b'
      r'|\bdeep[\s\-_]*chic[k]?\b'
      r'|\bdeep[\s\-_]*sheek\b'
      r'|\bdeep[\s\-_]*seak\b'
      r'|\bdeep[\s\-_]*sek\b'
      r'|\bdeep[\s\-_]*shik\b'
      r'|\bdeep[\s\-_]*sikh\b'
      r'|\bdeep[\s\-_]*six\b'
      r'|\bdips+eek\b'
      r'|\bdip[\s\-_]+seek\b'
      r'|\bdip[\s\-_]*sik\b'
      r'|\bbeep[\s\-_]*seek\b'
      r'|\bleap[\s\-_]*seek\b'
      r'|\bdeep[\s\-_]*si[kc]+\b',
      caseSensitive: false,
    ),
    (_) => kDeepSeek,
  );

  // ---- Gemini variants (rare words, safe unconditionally) ----
  out = out.replaceAllMapped(
    RegExp(
      r'\bjemini\b'
      r'|\bgemani\b'
      r'|\bjemani\b'
      r'|\bjamini\b'
      r'|\bjimini\b'
      r'|\bgemni\b'
      r'|\bgeminy\b'
      r'|\bgemini\b',
      caseSensitive: false,
    ),
    (_) => kGemini,
  );

  // ---- ChatGPT variants (unconditional, unambiguous) ----
  // Matches: chatgpt, chat gpt, chat-gpt, chat g p t, chat gp, cat gpt,
  // chart gpt, chad gpt, shat gpt (accent), chat gpd (STT typo).
  out = out.replaceAllMapped(
    RegExp(
      r'\bchat[\s\-_]*g[\s\.\-]*p[\s\.\-]*t+\b'
      r'|\bchat[\s\-_]*gp\b'
      r'|\bchat[\s\-_]*gpd\b'
      r'|\bcat[\s\-_]*gpt\b'
      r'|\bchart[\s\-_]*gpt\b'
      r'|\bchad[\s\-_]*gpt\b'
      r'|\bshat[\s\-_]*gpt\b',
      caseSensitive: false,
    ),
    (_) => kChatGpt,
  );

  // ---- FO (Wajo AI) variants (Unconditional / unambiguous phonetic forms) ----
  // Matches: "wajo fo", "wajoo fo", "wajo's fo", "eff oh", "eff-oh", "ef oh",
  // "f oh", "f-oh", "f.o.", "f.o", "f o", "f-o"
  out = out.replaceAllMapped(
    RegExp(
      r'\bwajo[\s\-_]*(?:fo|foe)?\b'
      r'|\bwajoo[\s\-_]*(?:fo|foe)?\b'
      r'|\b(?:eff|ef)[\s\-_]*(?:oh|o)\b'
      r'|\bf\.o\.'
      r'|\bf\.o\b'
      r'|\bf[\s\-_]+o\b',
      caseSensitive: false,
    ),
    (_) => 'FO',
  );

  // ---- "lipstick/lipstik/lip seek" -> DeepSeek (CONDITIONAL) ----
  // "lipstick" is a real word, so only rewrite when the utterance looks like
  // an AI-ask command (ask/search/open/question verb nearby). This avoids
  // breaking e.g. "buy red lipstick" while fixing "ask lipstik ...".
  // User-confirmed: lipstik sounds like their DeepSeek pronunciation.
  final looksLikeAiAsk = RegExp(
    r'\b(ask|search|open|launch|start|question|questions|pucho|puch|batao|bata|tell|gpt|deepseek|deepsik|gemini|chat|lipstik|lipstick|message|text|send|fo)\b',
    caseSensitive: false,
  ).hasMatch(lower);
  if (looksLikeAiAsk) {
    out = out.replaceAllMapped(
      RegExp(
        r'\blip[\s\-_]*sti[ck]+\b'
        r'|\blipstick\b'
        r'|\blipstic\b'
        r'|\blip[\s\-_]*seek\b'
        r'|\blip[\s\-_]*sik\b'
        r'|\bleep[\s\-_]*seek\b',
        caseSensitive: false,
      ),
      (_) => kDeepSeek,
    );
    // "chat jee pee tee" / "chat g p t" spoken letter-by-letter.
    out = out.replaceAllMapped(
      RegExp(
        r'\bchat(\s+(jee|ji|g|pee|pea|p|tee|ti|te))+\b',
        caseSensitive: false,
      ),
      (_) => kChatGpt,
    );
    // Conditional FO variants when in command context:
    // "ask foe to...", "tell foe that...", "message foe...", "send to faux..."
    out = out.replaceAllMapped(
      RegExp(
        r'\b(ask|tell|message|text|send(?:\s+to|\s+message\s+to)?|say\s+to)\s+(foe|foh|faux|4o|four\s+oh|pho|flow)\b',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)} FO',
    );
    out = out.replaceAllMapped(
      RegExp(
        r'\b(foe|foh|faux|4o)\s+(to|that|if|can|could|please|call|message|text|send|do)\b',
        caseSensitive: false,
      ),
      (m) => 'FO ${m.group(2)}',
    );
  }

  // ---- Lone "gpt" -> "chatgpt" (CONDITIONAL, same guard) ----
  // Avoids breaking unrelated "gpt" mentions outside ask context... in
  // practice bare "gpt" almost always means ChatGPT, but keep the guard.
  if (looksLikeAiAsk) {
    out = out.replaceAllMapped(
      RegExp(r'\bgpt\b', caseSensitive: false),
      (_) => kChatGpt,
    );
  }

  // ---- Token-level fuzzy fallback (edit distance <= 2) ----
  // Catches anything the regexes missed ("deapseek", "chatgpd", "gimini")
  // but ONLY on single tokens inside an AI-ask-looking utterance, so normal
  // speech is never rewritten.
  if (looksLikeAiAsk) {
    out = _fuzzyFixTokens(out);
  }

  return out;
}

/// Detects which canonical AI target (if any) an utterance refers to.
///
/// Fuzzy-tolerant: works on raw STT output WITHOUT prior normalization.
/// Returns 'deepseek' | 'chatgpt' | 'gemini' | 'fo' or null.
String? detectAiTarget(String input) {
  final lower = input.toLowerCase();
  if (lower.isEmpty) return null;

  // Fast exact path.
  if (lower.contains('deepseek') || lower.contains('deep seek')) {
    return kDeepSeek;
  }
  if (lower.contains('chatgpt') || lower.contains('chat gpt')) {
    return kChatGpt;
  }
  if (lower.contains('gemini')) return kGemini;
  if (lower.contains('fo') || lower.contains('wajo')) return kFo;

  // Fuzzy path: check phonetic regexes + token edit distance.
  final normalized = normalizeAiTranscript(input).toLowerCase();
  if (normalized.contains('deepseek')) return kDeepSeek;
  if (normalized.contains('chatgpt')) return kChatGpt;
  if (normalized.contains('gemini')) return kGemini;
  if (normalized.contains('fo') || normalized.contains('wajo')) return kFo;
  return null;
}

/// Replaces tokens within edit distance <= 2 of an AI name (ask-context only).
String _fuzzyFixTokens(String input) {
  // Split preserving delimiters so casing/punctuation survive.
  final tokenRe = RegExp(r"[A-Za-z']+");
  return input.replaceAllMapped(tokenRe, (m) {
    final word = m.group(0)!;
    final w = word.toLowerCase();
    if (w.length < 4) return word; // too short, avoid false hits.
    if (_editDistance(w, 'deepseek') <= 2) return _matchCase(word, kDeepSeek);
    if (_editDistance(w, 'chatgpt') <= 2) return _matchCase(word, kChatGpt);
    if (_editDistance(w, 'gemini') <= 2) return _matchCase(word, kGemini);
    return word;
  });
}

String _matchCase(String original, String canonical) {
  // Keep it simple: AI names are matched lowercase downstream, so always
  // emit lowercase canonical form.
  return canonical;
}

/// Classic Levenshtein distance, capped early at > 2 for speed.
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if ((a.length - b.length).abs() > 2) return 99;
  final m = a.length;
  final n = b.length;
  List<int> prev = List<int>.generate(n + 1, (j) => j);
  List<int> curr = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    curr[0] = i;
    var rowMin = curr[0];
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = [
        prev[j] + 1,
        curr[j - 1] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      if (curr[j] < rowMin) rowMin = curr[j];
    }
    if (rowMin > 2) return 99; // early exit.
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[n];
}
