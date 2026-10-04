import 'dart:convert';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';
import 'package:friday_app/features/alarm/alarm_time_parser.dart' as alarm_t;
import 'package:friday_app/features/assistant/domain/intent_model.dart';

class IntentParser {
  /// Parses the raw output from the local LLM into a validated [AssistantIntent].
  ///
  /// If the output contains a multi-step sequence (JSON array or wrapper with
  /// `actions`/`sequence`/`steps`), a [SequenceIntent] with ordered steps is
  /// returned. Single-task outputs return the single intent as before.
  ///
  /// Throws [InvalidIntentException] if the LLM output is malformed or unparseable.
  /// Throws [UnsupportedActionException] if the action is not a known
  /// 'open_app', 'toggle_flashlight', 'toggle_bluetooth', 'toggle_wifi', or
  /// 'media_*' action.
  AssistantIntent parse(String rawLlmOutput) {
    final sequence = tryParseSequence(rawLlmOutput);
    if (sequence != null) return sequence;

    final cleaned = _extractJson(rawLlmOutput);
    if (cleaned == null || cleaned.isEmpty) {
      throw const InvalidIntentException();
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (_) {
      throw const InvalidIntentException();
    }

    if (decoded is! Map<String, dynamic>) {
      throw const InvalidIntentException();
    }

    // Strict schema check: only allow 'action', 'target' and 'message' keys
    // plus common aliases small model may emit. Keep tight but allow
    // whatsapp aliases. Controller has heuristic fallback for extra fields
    // like "reason".
    final allowedKeys = {
      'action',
      'target',
      'message',
      'text',
      'content',
      'msg',
      'reply',
      'response',
      'contact',
      'contactName',
      'name',
      'value',
      'level',
      'percent',
      'reason',
      'explanation',
      'query',
      'search',
      'search_query',
      'q',
      'index',
      'position',
      'n',
      'number',
      'ordinal',
      'count',
      'time',
      'at',
      'when',
      'timestamp',
      'millis',
      'epoch',
      'hour',
      'minute',
      'label',
      'title',
      'alarm_label',
      'reminder',
      'datetime',
      'date',
      'ampm',
      'meridiem',
      'amount',
      'pct',
      'app',
      'assistant',
      'recipient',
      'to',
      'phone',
      'phoneNumber',
      'body',
      'mode',
      'action_type',
      'type'
    };
    final extraKeys = decoded.keys.where((k) => !allowedKeys.contains(k));
    if (extraKeys.isNotEmpty) {
      // If extra keys are only benign explanation fields, ignore.
      // If truly unknown, still reject — heuristic will rescue whatsapp.
      final benign = {'reason', 'explanation'};
      final nonBenign = extraKeys.where((k) => !benign.contains(k));
      if (nonBenign.isNotEmpty) {
        // For whatsapp actions we are lenient: allow aliases
        final actionVal = decoded['action'];
        final normalizedForCheck = actionVal is String
            ? actionVal
                .trim()
                .toLowerCase()
                .replaceAll(RegExp(r'[\s\-]+'), '_')
                .replaceAll(RegExp(r'_+'), '_')
            : '';
        final isWhatsApp = actionVal is String &&
            normalizedForCheck.contains('whatsapp');
        // Volume/brightness actions may carry the target value numerically.
        final isLevelControl =
            _isVolumeAction(normalizedForCheck) || _isBrightnessAction(normalizedForCheck);
        if (!isWhatsApp && !isLevelControl) {
          throw const InvalidIntentException();
        }
        if (isWhatsApp) {
          // For whatsapp, allow any of the alias keys, reject truly unknown keys
          final whatsAppAllowed = {
            'action',
            'target',
            'message',
            'text',
            'content',
            'msg',
            'contact',
            'contactName',
            'name',
            'reason',
            'explanation'
          };
          final whatsAppExtra = decoded.keys.where((k) => !whatsAppAllowed.contains(k));
          if (whatsAppExtra.isNotEmpty) {
            throw const InvalidIntentException();
          }
        } else {
          // For volume/brightness actions only the level fields plus benign
          // explanation keys are accepted.
          const levelAllowed = {
            'action',
            'target',
            'value',
            'amount',
            'percent',
            'pct',
            'reason',
            'explanation'
          };
          final levelExtra = decoded.keys.where((k) => !levelAllowed.contains(k));
          if (levelExtra.isNotEmpty) {
            throw const InvalidIntentException();
          }
        }
      }
    }

    if (!decoded.containsKey('action')) {
      throw const InvalidIntentException();
    }

    final action = decoded['action'];
    final target = decoded['target'];

    if (action is! String) {
      throw const InvalidIntentException();
    }

    // Normalize: trim, lower-case, collapse spaces/dashes to underscores.
    // This handles LLM variants like "media-stop", "media stop",
    // "Turn_Off_Flashlight", "stop_music", etc.
    final normalizedAction = action
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    if (normalizedAction == 'unsupported') {
      return const UnsupportedIntent();
    }

    // Alias resolution before strict wire-name check.
    // Handles small-model drift for stop/flash off etc.
    final aliasedMedia = _resolveMediaAlias(normalizedAction);
    if (aliasedMedia != null) {
      return MediaIntent(aliasedMedia);
    }

    final mediaAction = MediaAction.fromWireName(normalizedAction);
    if (mediaAction != null) {
      return MediaIntent(mediaAction);
    }

    if (_isFlashlightAction(normalizedAction)) {
      return const ToggleFlashlightIntent();
    }

    if (_isGalleryPlayAction(normalizedAction, decoded)) {
      return PlayGalleryVideoIntent(index: _parseOrdinalIndex(decoded));
    }

    if (_isYouTubeSearchPlayAction(normalizedAction)) {
      final query = _parseYouTubeQuery(decoded);
      if (query == null || query.isEmpty) {
        throw const InvalidIntentException();
      }
      return YouTubeSearchPlayIntent(
          query: query, index: _parseOrdinalIndex(decoded));
    }

    if (_isBluetoothAction(normalizedAction)) {
      final desired = _parseToggleDesired(normalizedAction, decoded);
      return ToggleDeviceIntent(device: 'bluetooth', desired: desired);
    }

    if (_isWifiAction(normalizedAction)) {
      final desired = _parseToggleDesired(normalizedAction, decoded);
      return ToggleDeviceIntent(device: 'wifi', desired: desired);
    }

    if (normalizedAction == 'screen_context' ||
        normalizedAction == 'describe_screen' ||
        normalizedAction == 'summarize_screen' ||
        normalizedAction == 'read_screen') {
      final q = _firstStringField(decoded, ['query', 'text', 'message', 'target']) ?? 'summarize';
      final mode = _firstStringField(decoded, ['mode', 'action_type', 'type']) ?? 'summarize';
      return ScreenContextIntent(query: q, action: mode);
    }

    if (_isWhatsAppAction(normalizedAction)) {
      // target = contact name (aliases: contact, contactName, name), message = text (aliases: text, content, msg)
      final rawTarget = _firstStringField(decoded, ['target', 'contact', 'contactName', 'name']);
      final rawMessage = _firstStringField(decoded, ['message', 'text', 'content', 'msg']);
      if (rawTarget == null || rawTarget.trim().isEmpty) {
        throw const InvalidIntentException();
      }
      if (rawMessage == null || rawMessage.trim().isEmpty) {
        throw const InvalidIntentException();
      }
      final contactName = rawTarget.trim();
      final message = rawMessage.trim();
      if (contactName.length > 100 || message.length > 1000) {
        throw const InvalidIntentException();
      }
      return SendWhatsAppIntent(contactName: contactName, message: message);
    }

    if (_isSmsAction(normalizedAction)) {
      final rawTarget = _firstStringField(decoded, [
            'target',
            'contact',
            'contactName',
            'name',
            'recipient',
            'to',
          ]) ??
          'FO';
      final rawMessage = _firstStringField(decoded, [
        'message',
        'text',
        'content',
        'msg',
        'query',
        'body',
      ]);
      if (rawMessage == null || rawMessage.trim().isEmpty) {
        throw const InvalidIntentException();
      }
      final recipient = rawTarget.trim();
      final message = rawMessage.trim();
      if (recipient.length > 100 || message.length > 1000) {
        throw const InvalidIntentException();
      }
      final isFo = recipient.toUpperCase() == 'FO' ||
          recipient.toLowerCase() == 'wajo' ||
          recipient.toLowerCase() == 'wajo fo';
      final phone = isFo ? AppConstants.foPhoneNumber : null;
      return SendSmsIntent(
        recipient: isFo ? AppConstants.foDisplayName : recipient,
        message: message,
        phoneNumber: phone,
      );
    }

    if (_isCallAction(normalizedAction)) {
      final rawTarget = _firstStringField(decoded, ['target', 'contact', 'contactName', 'name']);
      if (rawTarget == null || rawTarget.trim().isEmpty) {
        throw const InvalidIntentException();
      }
      final contactName = rawTarget.trim();
      if (contactName.length > 100) {
        throw const InvalidIntentException();
      }
      return CallIntent(contactName: contactName);
    }

    if (_isReadChatAction(normalizedAction)) {
      final rawTarget = _firstStringField(decoded, ['target', 'contact', 'contactName', 'name', 'phrase']);
      // read_chat may have no target -> default to whatsapp, or optional contact
      if (rawTarget == null || rawTarget.trim().isEmpty) {
        return const ReadChatIntent(contactName: 'whatsapp', count: 5);
      }
      final contact = rawTarget.trim();
      if (contact.length > 100) throw const InvalidIntentException();
      return ReadChatIntent(contactName: contact, count: 5);
    }

    if (_isCustomAction(normalizedAction)) {
      final rawTarget = _firstStringField(decoded, ['target', 'phrase', 'text', 'content']);
      if (rawTarget == null || rawTarget.trim().isEmpty) {
        throw const InvalidIntentException();
      }
      final phrase = rawTarget.trim();
      if (phrase.length > 200) throw const InvalidIntentException();
      return CustomIntent(phrase: phrase);
    }

    if (_isChatAction(normalizedAction)) {
      final rawMessage = _firstStringField(
          decoded, ['message', 'text', 'content', 'msg', 'target', 'reply', 'response']);
      final message = (rawMessage ?? '').trim();
      if (message.isEmpty) {
        // Model emitted chat with no text — use a safe default rather than
        // failing, so greetings never become "couldn't understand".
        return const ChatIntent(message: "Hello! I'm FRIDAY. How can I help?");
      }
      final safe = message.length > 300 ? '${message.substring(0, 297).trim()}...' : message;
      return ChatIntent(message: safe);
    }

    if (_isVolumeAction(normalizedAction)) {
      return _buildVolumeIntent(normalizedAction, decoded);
    }

    if (_isReadEmailAction(normalizedAction, decoded)) {
      return _buildReadEmailIntent(decoded);
    }

    if (_isBrightnessAction(normalizedAction)) {
      return _buildBrightnessIntent(normalizedAction, decoded);
    }

    if (_isListAlarmsAction(normalizedAction)) {
      return const ListAlarmsIntent();
    }

    if (_isCancelAlarmAction(normalizedAction)) {
      final rawQuery = _firstStringField(
          decoded, ['target', 'query', 'text', 'content', 'message', 'label']);
      return CancelAlarmIntent(query: (rawQuery ?? '').trim());
    }

    if (_isAlarmAction(normalizedAction)) {
      final alarm = _buildAlarmIntent(decoded);
      if (alarm != null) return alarm;
      throw const InvalidIntentException();
    }

    if (_isReminderAction(normalizedAction)) {
      final reminder = _buildReminderIntent(decoded);
      if (reminder != null) return reminder;
      throw const InvalidIntentException();
    }

    if (_isAiAskAction(normalizedAction)) {
      final target = _normalizeAiTarget(
          _firstStringField(decoded, ['target', 'app', 'assistant', 'name']));
      final query = _parseAiAskQuery(decoded);
      if (target == null || query == null || query.isEmpty) {
        throw const InvalidIntentException();
      }
      return AiAskIntent(target: target, query: query);
    }

    if (normalizedAction != 'open_app') {
      throw const UnsupportedActionException();
    }

    if (target is! String || target.trim().isEmpty) {
      throw const UnsupportedActionException();
    }

    return OpenAppIntent(target: target.trim());
  }

  /// Tries to parse [rawLlmOutput] as an ordered multi-step sequence.
  ///
  /// Accepts:
  /// - JSON array: `[{"action":"open_app",...}, {"action":"set_volume",...}]`
  /// - Wrapper: `{"actions":[...]}` / `{"sequence":[...]}` / `{"steps":[...]}`
  /// - Concatenated objects: `{"action":...} {"action":...}`
  ///
  /// Returns a [SequenceIntent] when 2..10 valid steps are found, a single
  /// intent unwrapped when exactly 1 is found (as [SequenceIntent] with one
  /// step? No — returns null so [parse] falls back to single path to preserve
  /// exact error semantics), or null when the output is not a sequence.
  ///
  /// Throws [UnsupportedActionException]/[InvalidIntentException] when the
  /// sequence structure is present but a step is invalid — so callers can
  /// report honestly instead of silently dropping steps.
  AssistantIntent? tryParseSequence(String rawLlmOutput) {
    final raw = rawLlmOutput.trim();
    if (raw.isEmpty) return null;

    // Strip markdown fences for detection.
    var text = raw;
    if (text.startsWith('```')) {
      final firstBrace = text.indexOf('{');
      final firstBracket = text.indexOf('[');
      int start = -1;
      if (firstBrace != -1 && firstBracket != -1) {
        start = firstBrace < firstBracket ? firstBrace : firstBracket;
      } else {
        start = firstBrace != -1 ? firstBrace : firstBracket;
      }
      if (start != -1) text = text.substring(start);
    }

    // 1. JSON array form: [...] with at least 2 objects.
    final arrayJson = _extractJsonArray(text);
    if (arrayJson != null) {
      try {
        final decoded = jsonDecode(arrayJson);
        if (decoded is List && decoded.length >= 2) {
          final steps = _parseStepList(decoded);
          if (steps != null && steps.length >= 2) {
            return SequenceIntent(steps: steps);
          }
        }
      } catch (_) {
        // Not a valid array — fall through to other forms.
      }
    }

    // 2. Wrapper form: {"actions": [...]}, {"sequence": [...]}, {"steps": [...]}.
    try {
      final firstObj = _extractJson(text);
      if (firstObj != null) {
        final decoded = jsonDecode(firstObj);
        if (decoded is Map<String, dynamic>) {
          for (final key in const ['actions', 'sequence', 'steps']) {
            final inner = decoded[key];
            if (inner is List && inner.length >= 2) {
              final steps = _parseStepList(inner);
              if (steps != null && steps.length >= 2) {
                return SequenceIntent(steps: steps);
              }
            }
          }
        }
      }
    } catch (_) {}

    // 3. Concatenated objects: {"action":...} {"action":...} (or comma-separated
    //    without array brackets — small-model drift).
    final allObjects = _extractAllJsonObjects(text);
    if (allObjects.length >= 2) {
      // Guard: if the whole text is a single wrapper object containing the
      // others as nested values, allObjects would include the outer + inners.
      // Only treat as sequence when the objects are top-level siblings, i.e.
      // the text starts with '{' and decoding the first object does not
      // consume the whole trimmed text.
      final first = _extractJson(text);
      if (first != null) {
        final rest = text.substring(text.indexOf(first) + first.length).trim();
        // Strip leading commas/whitespace between sibling objects.
        final restStripped =
            rest.replaceAll(RegExp(r'^[\s,]+'), '').trim();
        if (restStripped.startsWith('{')) {
          try {
            final steps = <AssistantIntent>[];
            for (final obj in allObjects) {
              // Skip the outer wrapper if it contains actions/sequence/steps
              // (already handled above) to avoid double-counting.
              try {
                final d = jsonDecode(obj);
                if (d is Map<String, dynamic> &&
                    (d.containsKey('actions') ||
                        d.containsKey('sequence') ||
                        d.containsKey('steps'))) {
                  continue;
                }
              } catch (_) {}
              steps.add(parse(obj));
            }
            if (steps.length >= 2) {
              return SequenceIntent(
                  steps: steps.take(10).toList());
            }
          } catch (_) {
            // A step failed validation — propagate as sequence error by
            // attempting strict parse of each (throws proper exception).
            rethrow;
          }
        }
      }
    }

    return null;
  }

  /// Parses a raw decoded JSON list into validated intents (max 10 steps).
  ///
  /// Returns null when the list is not a valid non-empty step list.
  /// Throws the step's validation error when a step map is invalid.
  List<AssistantIntent>? _parseStepList(List<dynamic> list) {
    if (list.isEmpty || list.length > 10) return null;
    final steps = <AssistantIntent>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) return null;
      // Reuse strict single-item validation via round-trip JSON.
      steps.add(parse(jsonEncode(item)));
    }
    return steps;
  }

  /// Extracts the first balanced JSON array `[...]` from [text], or null.
  static String? _extractJsonArray(String text) {
    final start = text.indexOf('[');
    if (start == -1) return null;
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = start; i < text.length; i++) {
      final ch = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\' && inString) {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1).trim();
        }
        if (depth < 0) return null;
      }
    }
    return null;
  }

  /// Extracts ALL top-level balanced JSON objects from [text] in order.
  static List<String> _extractAllJsonObjects(String text) {
    final results = <String>[];
    int i = 0;
    while (i < text.length) {
      final start = text.indexOf('{', i);
      if (start == -1) break;
      final balanced = _extractBalancedJson(text.substring(start));
      if (balanced == null) break;
      results.add(balanced);
      i = start + balanced.length;
      if (results.length >= 10) break;
    }
    return results;
  }

  /// True when [text] already contains a complete outermost JSON object.
  ///
  /// Used by the inference layer to stop generation as soon as a valid
  /// intent has been produced, instead of sampling until end-of-sequence.
  /// Sequence-aware: when the model started a JSON array (`[`), waits for
  /// the closing `]` so multi-task arrays are not truncated after the first
  /// object.
  static bool hasCompleteJson(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final bracketIndex = trimmed.indexOf('[');
    final braceIndex = trimmed.indexOf('{');
    if (bracketIndex != -1 &&
        (braceIndex == -1 || bracketIndex < braceIndex)) {
      return _extractJsonArray(trimmed) != null;
    }
    return _extractJson(text) != null;
  }

  /// Extracts the first balanced JSON object from a potentially noisy LLM response.
  ///
  /// Uses brace-counting with string-awareness so trailing explanations
  /// like `} explanation }` don't cause the wrong substring to be taken
  /// (previous implementation used lastIndexOf('}') which was fragile).
  static String? _extractJson(String text) {
    var raw = text.trim();

    // Handle markdown code blocks: find first '{' and extract balanced JSON from there.
    if (raw.startsWith('```')) {
      final start = raw.indexOf('{');
      if (start != -1) {
        final balanced = _extractBalancedJson(raw.substring(start));
        if (balanced != null) return balanced;
      }
      return null;
    }

    final start = raw.indexOf('{');
    if (start == -1) return null;
    final balanced = _extractBalancedJson(raw.substring(start));
    if (balanced != null) return balanced;

    // Fallback to old behavior if balanced extraction fails.
    final endIndex = raw.lastIndexOf('}');
    if (endIndex > start) {
      return raw.substring(start, endIndex + 1).trim();
    }
    return null;
  }

  static String? _extractBalancedJson(String textStartingWithBrace) {
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = 0; i < textStartingWithBrace.length; i++) {
      final ch = textStartingWithBrace[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\' && inString) {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          return textStartingWithBrace.substring(0, i + 1).trim();
        }
        if (depth < 0) return null;
      }
    }
    return null;
  }

  MediaAction? _resolveMediaAlias(String normalized) {
    // Minimal alias sets for small-model drift — only add variants that
    // fix reported flaky commands (stop/flash) and don't conflict with
    // existing tests that expect rejection (e.g. play_music is rejected).
    const stopAliases = {
      'stop',
      'stop_music',
      'stop_playing',
      'stop_song',
      'stop_playback',
      'stop_audio',
      'media_stop_music',
      'media_stop_playing',
      'media_stop_song',
      'music_stop',
      'audio_stop',
    };
    // For play/pause etc we only alias bare forms, not compound forms
    // that tests expect to be rejected (play_music is intentionally
    // unsupported to keep app-open vs media distinction).
    const playAliases = {
      'play',
      'media_play_music',
    };
    const pauseAliases = {
      'pause',
      'pause_music',
      'pause_song',
      'pause_playing',
      'pause_audio',
      'media_pause_music',
    };
    const resumeAliases = {
      'resume',
      'resume_music',
      'resume_playing',
      'resume_song',
      'continue',
      'continue_playing',
      'continue_music',
      'unpause',
      'media_resume_music',
    };
    const nextAliases = {
      'next',
      'next_song',
      'next_track',
      'skip',
      'skip_song',
      'skip_track',
      'media_next_song',
      'media_skip',
      'skip_music',
    };
    const previousAliases = {
      'previous',
      'prev',
      'previous_song',
      'previous_track',
      'go_back',
      'back',
      'media_previous_song',
      'prev_song',
    };

    if (stopAliases.contains(normalized)) return MediaAction.stop;
    if (playAliases.contains(normalized)) return MediaAction.play;
    if (pauseAliases.contains(normalized)) return MediaAction.pause;
    if (resumeAliases.contains(normalized)) return MediaAction.resume;
    if (nextAliases.contains(normalized)) return MediaAction.next;
    if (previousAliases.contains(normalized)) return MediaAction.previous;

    // Broad substring fallback for LLM variants like "stop_music_extra"
    // Only for stop, which is the most reported flaky command.
    if (normalized.contains('stop')) return MediaAction.stop;

    return null;
  }

  bool _isGalleryPlayAction(
      String normalized, Map<String, dynamic> decoded) {
    const exact = {
      'play_gallery_video',
      'gallery_play_video',
      'play_gallery',
      'gallery_play',
      'open_gallery_play',
      'open_gallery_video',
      'play_video_gallery',
      'gallery_video_play',
      'play_gallery_videos',
      'gallery_video',
      'play_video',
      'play_nth_video',
      'play_second_video',
    };
    if (exact.contains(normalized)) return true;
    // "open gallery" alone stays open_app — require a play/video signal.
    // Check both the action name and the decoded payload text so drift like
    // {"action": "open_app", ...} never lands here (that path returns early
    // only for exact 'open_app'; this helper is only called for other names).
    final hasGallery = normalized.contains('galler') ||
        normalized.contains('google_photo') ||
        (normalized.contains('photo') && normalized.contains('play'));
    if (hasGallery &&
        (normalized.contains('play') || normalized.contains('video'))) {
      return true;
    }
    return false;
  }

  bool _isYouTubeSearchPlayAction(String normalized) {
    const exact = {
      'youtube_search_play',
      'search_youtube_play',
      'youtube_search',
      'search_youtube',
      'play_youtube_search',
      'open_youtube_search',
      'youtube_play',
      'play_youtube',
      'youtube_search_video',
      'youtube_play_video',
    };
    if (exact.contains(normalized)) return true;
    final mentionsYouTube = normalized.contains('youtube') ||
        normalized.contains('you_tube') ||
        normalized.contains('youtub');
    if (mentionsYouTube &&
        (normalized.contains('search') || normalized.contains('play'))) {
      return true;
    }
    return false;
  }

  bool _isAiAskAction(String normalized) {
    const exact = {
      'ai_ask',
      'ask_ai',
      'deepseek_ask',
      'ask_deepseek',
      'deepseek_search',
      'search_deepseek',
      'chatgpt_ask',
      'ask_chatgpt',
      'chatgpt_search',
      'search_chatgpt',
      'gemini_ask',
      'ask_gemini',
      'gemini_search',
      'search_gemini',
    };
    if (exact.contains(normalized)) return true;
    final mentionsAi = normalized.contains('deepseek') ||
        normalized.contains('deep_seek') ||
        normalized.contains('deepsik') ||
        normalized.contains('deep_sick') ||
        normalized.contains('chatgpt') ||
        normalized.contains('chat_gpt') ||
        normalized.contains('lipstik') ||
        normalized.contains('lipstick') ||
        normalized.contains('gemini') ||
        normalized.contains('jemini') ||
        normalized.contains('ai_ask') ||
        normalized.contains('ask_ai');
    if (mentionsAi &&
        (normalized.contains('ask') || normalized.contains('search'))) {
      return true;
    }
    return false;
  }

  /// Normalizes an AI app target to 'deepseek' | 'chatgpt' | 'gemini'.
  /// Returns null when the target is not one of the supported AI apps.
  static String? normalizeAiTarget(String? raw) {
    if (raw == null) return null;
    final t = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');
    if (t.isEmpty) return null;
    // Fuzzy-tolerant: STT often yields "deepsik", "deep sick".
    // User-confirmed: "lipstik/lipstick" is their DeepSeek pronunciation.
    if (t.contains('deepseek') ||
        t.contains('deepsik') ||
        t.contains('deepsick') ||
        t.contains('lipstik') ||
        t.contains('lipstick') ||
        t.contains('lipseek') ||
        t.contains('lipsik') ||
        t.contains('deepseekchat') ||
        t == 'deepseekchat' ||
        t == 'ds' ||
        RegExp(r'deep.*s[eiy]k').hasMatch(t)) {
      // Guard: "deep" alone is not DeepSeek — require a seek/sik tail
      // (lipstik already contains a sik/stik tail, so it passes).
      if (t.contains('seek') ||
          t.contains('sik') ||
          t.contains('sick') ||
          t.contains('stik') ||
          t.contains('stick') ||
          t.contains('syk') ||
          t == 'ds') {
        return 'deepseek';
      }
    }
    if (t.contains('chatgpt') ||
        t.contains('chatgptapp') ||
        t == 'gpt' ||
        t.contains('openaichat')) {
      return 'chatgpt';
    }
    if (t.contains('gemini') ||
        t.contains('jemini') ||
        t.contains('gemani') ||
        t.contains('bard')) {
      return 'gemini';
    }
    return null;
  }

  String? _normalizeAiTarget(String? raw) => normalizeAiTarget(raw);

  /// Extracts the question to ask the AI app from common JSON fields.
  ///
  /// Strips leading verbs like "ask deepseek" so
  /// "ask deepseek who is pm of india" becomes "who is pm of india".
  String? _parseAiAskQuery(Map<String, dynamic> decoded) {
    final raw = _firstStringField(
        decoded, ['query', 'search', 'search_query', 'q', 'message', 'text', 'content', 'target']);
    if (raw == null) return null;
    var q = raw.trim();
    if (q.isEmpty) return null;
    q = q.replaceAll(
        RegExp(
            r'^(ask\s+(deepseek|deep\s*seek|deepsik|deep\s*sick|chatgpt|chat\s*gpt|lipstik|lipstick|gpt|gemini|jemini|ai)\s+(on\s+|about\s+|for\s+)?)',
            caseSensitive: false),
        '').trim();
    q = q.replaceAll(
        RegExp(
            r'^(search\s+(on\s+|in\s+|with\s+)?(deepseek|deep\s*seek|deepsik|deep\s*sick|chatgpt|chat\s*gpt|lipstik|lipstick|gpt|gemini|jemini)\s+(for\s+)?)',
            caseSensitive: false),
        '').trim();
    q = q.replaceAll(
        RegExp(r'^(on\s+)?(deepseek|deepsik|chatgpt|chat\s*gpt|lipstik|lipstick|gemini|jemini)\s+(search\s+)?(for\s+)?',
            caseSensitive: false),
        '').trim();
    if (q.isEmpty || q.length > 500) return null;
    return q;
  }

  /// Parses a 1-based video/result position from common JSON fields.
  ///
  /// Accepts numbers ("2", 2, "2nd"), ordinals ("second", "first") and
  /// falls back to scanning free-text fields for the same patterns.
  /// Defaults to 1 (most recent / first result) and clamps to 1..50.
  int _parseOrdinalIndex(Map<String, dynamic> decoded) {
    // 1. Explicit numeric fields win.
    for (final key in const [
      'index',
      'position',
      'n',
      'number',
      'ordinal',
      'value',
      'level'
    ]) {
      final v = decoded[key];
      if (v is num) {
        return v.round().clamp(1, 50);
      }
      if (v is String) {
        final parsed = parseOrdinal(v);
        if (parsed != null) return parsed;
      }
    }
    // 2. Scan free-text fields for "second video", "video 3", etc.
    final text = _firstStringField(
        decoded, ['target', 'query', 'search', 'search_query', 'text', 'content', 'message']);
    if (text != null) {
      final parsed = parseOrdinal(text);
      if (parsed != null) return parsed;
    }
    return 1;
  }

  /// Extracts the YouTube search query from common JSON fields.
  ///
  /// Strips leading verbs like "search youtube for" so
  /// "search youtube for hindi music" becomes "hindi music".
  String? _parseYouTubeQuery(Map<String, dynamic> decoded) {
    final raw = _firstStringField(
        decoded, ['query', 'search', 'search_query', 'q', 'target', 'text', 'content', 'message']);
    if (raw == null) return null;
    var q = raw.trim();
    if (q.isEmpty) return null;
    // Strip "youtube search ..." / "search ... for ..." prefixes the small
    // model sometimes echoes back.
    q = q.replaceAll(
        RegExp(r'^(search\s+(on\s+)?(youtube|you\s*tube)\s+(for\s+)?)',
            caseSensitive: false),
        '').trim();
    q = q.replaceAll(
        RegExp(r'^(on\s+)?(youtube|you\s*tube)\s+search\s+(for\s+)?',
            caseSensitive: false),
        '').trim();
    q = q.replaceAll(
        RegExp(r'\s+and\s+play\s+(the\s+)?\w+(\s+video)?\s*$',
            caseSensitive: false),
        '').trim();
    if (q.isEmpty || q.length > 200) return null;
    return q;
  }

  /// Parses "first/second/2nd/3 ..." into a 1-based index, or null.
  static int? parseOrdinal(String text) {
    final lower = text.toLowerCase();
    const words = {
      'first': 1,
      'second': 2,
      'third': 3,
      'fourth': 4,
      'fifth': 5,
      'sixth': 6,
      'seventh': 7,
      'eighth': 8,
      'ninth': 9,
      'tenth': 10,
      'eleventh': 11,
      'twelfth': 12,
    };
    for (final entry in words.entries) {
      if (RegExp(r'\b' + entry.key + r'\b').hasMatch(lower)) {
        return entry.value;
      }
    }
    final digitMatch =
        RegExp(r'\b(\d{1,2})\s*(st|nd|rd|th)?\b').firstMatch(lower);
    if (digitMatch != null) {
      final n = int.tryParse(digitMatch.group(1)!);
      if (n != null && n >= 1 && n <= 50) return n;
    }
    return null;
  }

  bool _isFlashlightAction(String normalized) {
    const exact = {
      'toggle_flashlight',
      'toggle_flash',
      'toggle_torch',
      'flashlight',
      'torch',
      'flash',
      'turn_on_flashlight',
      'turn_off_flashlight',
      'turn_on_flash',
      'turn_off_flash',
      'flash_on',
      'flash_off',
      'torch_on',
      'torch_off',
      'enable_flashlight',
      'disable_flashlight',
      'flashlight_on',
      'flashlight_off',
      'switch_on_flashlight',
      'switch_off_flashlight',
      'switch_on_flash',
      'switch_off_flash',
      'flash_toggle',
      'torch_toggle',
    };
    if (exact.contains(normalized)) return true;
    // Any action mentioning flash/torch is a flashlight intent.
    // This handles drift like "flashlight_toggle", "toggle_flash_light" etc.
    if (normalized.contains('flash') || normalized.contains('torch')) {
      return true;
    }
    return false;
  }

  bool _isBluetoothAction(String normalized) {
    const exact = {
      'toggle_bluetooth',
      'bluetooth',
      'turn_on_bluetooth',
      'turn_off_bluetooth',
      'enable_bluetooth',
      'disable_bluetooth',
      'bluetooth_on',
      'bluetooth_off',
    };
    if (exact.contains(normalized)) return true;
    if (normalized.contains('bluetooth')) return true;
    return false;
  }

  bool _isWifiAction(String normalized) {
    const exact = {
      'toggle_wifi',
      'wifi',
      'wi_fi',
      'turn_on_wifi',
      'turn_off_wifi',
      'enable_wifi',
      'disable_wifi',
      'wifi_on',
      'wifi_off',
    };
    if (exact.contains(normalized)) return true;
    if (normalized.contains('wifi') || normalized.contains('wi_fi')) return true;
    return false;
  }

  ToggleDesired _parseToggleDesired(String normalized, Map<String, dynamic> decoded) {
    // Check the normalized action name first
    if (normalized.contains('turn_on') ||
        normalized.contains('enable_') ||
        normalized.contains('_on') ||
        normalized == 'on') {
      return ToggleDesired.on;
    }
    if (normalized.contains('turn_off') ||
        normalized.contains('disable_') ||
        normalized.contains('_off') ||
        normalized == 'off') {
      return ToggleDesired.off;
    }

    // Check decoded target/value fields for explicit state
    final target = decoded['target'];
    if (target is String) {
      final t = target.toLowerCase().trim();
      if (t == 'on' || t == 'true' || t == 'enable' || t == '1') return ToggleDesired.on;
      if (t == 'off' || t == 'false' || t == 'disable' || t == '0') return ToggleDesired.off;
    }

    final value = decoded['value'];
    if (value is String) {
      final v = value.toLowerCase().trim();
      if (v == 'on' || v == 'true' || v == 'enable' || v == '1') return ToggleDesired.on;
      if (v == 'off' || v == 'false' || v == 'disable' || v == '0') return ToggleDesired.off;
    }

    // Default to toggle
    return ToggleDesired.toggle;
  }

  bool _isWhatsAppAction(String normalized) {
    if (normalized.contains('whatsapp') || normalized.contains('whats_app')) {
      return true;
    }
    const exact = {
      'send_whatsapp',
      'whatsapp',
      'send_whatsapp_message',
      'whatsapp_message',
      'send_whats_app',
      'whats_app',
    };
    return exact.contains(normalized);
  }

  bool _isSmsAction(String normalized) {
    if (normalized.contains('whatsapp')) return false;
    const exact = {
      'send_sms',
      'sms',
      'send_message',
      'send_text',
      'text',
      'message',
      'ask_fo',
      'fo_message',
      'send_sms_message',
    };
    return exact.contains(normalized) ||
        normalized.startsWith('sms_') ||
        normalized.endsWith('_sms');
  }

  bool _isCallAction(String normalized) {
    const exact = {
      'call',
      'make_call',
      'call_phone',
      'call_contact',
      'phone_call',
      'place_call',
      'dial',
      'dial_number',
      'dial_contact',
      'phone_dial',
    };
    if (exact.contains(normalized)) return true;
    // Small-model drift: "calling_mom", "call_mom", "phone_call_mom", etc.
    // Exclude "recall" to avoid hijacking unrelated words.
    if (normalized.contains('recall')) return false;
    if (normalized == 'calling') return true;
    if (normalized.startsWith('call_') ||
        normalized.endsWith('_call') ||
        normalized.contains('_call_')) {
      return true;
    }
    if (normalized.startsWith('dial_') ||
        normalized.endsWith('_dial') ||
        normalized.contains('_dial_')) {
      return true;
    }
    if (normalized.contains('phone_call') || normalized.contains('place_call')) {
      return true;
    }
    return false;
  }

  bool _isReadChatAction(String normalized) {
    const exact = {
      'read_chat',
      'read_whatsapp',
      'check_whatsapp',
      'check_messages',
      'read_messages',
      'read_whatsapp_messages',
      'whatsapp_messages',
      'check_whatsapp_messages',
    };
    if (exact.contains(normalized)) return true;
    if (normalized.contains('read_chat') || normalized.contains('check_whatsapp') || normalized.contains('whatsapp_messages')) return true;
    // broader: check message(s) without send
    if (normalized.contains('check') && normalized.contains('message')) return true;
    if (normalized.contains('read') && normalized.contains('message')) return true;
    return false;
  }

  bool _isCustomAction(String normalized) {
    const exact = {
      'custom',
      'custom_command',
      'run_custom',
      'execute_custom',
      'teachable',
    };
    if (exact.contains(normalized)) return true;
    if (normalized.startsWith('custom_')) return true;
    return false;
  }

  bool _isReadEmailAction(
      String normalized, Map<String, dynamic> decoded) {
    const exact = {
      'read_email',
      'read_emails',
      'read_mail',
      'read_mails',
      'read_gmail',
      'read_inbox',
      'check_email',
      'check_emails',
      'check_mail',
      'check_mails',
      'check_gmail',
      'check_inbox',
      'get_emails',
      'show_emails',
      'show_inbox',
      'list_emails',
    };
    if (exact.contains(normalized)) return true;
    // Drift: "read_my_mails", "check_unread_mails", "gmail_unread", etc.
    // Require mail/email/gmail/inbox signal to avoid hijacking whatsapp
    // read_chat ("read messages" without mail stays read_chat).
    final hasMail = normalized.contains('mail') ||
        normalized.contains('email') ||
        normalized.contains('gmail') ||
        normalized.contains('inbox');
    if (!hasMail) return false;
    if (normalized.contains('read') ||
        normalized.contains('check') ||
        normalized.contains('show') ||
        normalized.contains('list') ||
        normalized.contains('get') ||
        normalized.contains('unread')) {
      return true;
    }
    return false;
  }

  ReadEmailIntent _buildReadEmailIntent(Map<String, dynamic> decoded) {
    // Reuse ordinal/count fields: "read 3 mails" -> count 3.
    for (final key in const [
      'index',
      'position',
      'n',
      'number',
      'ordinal',
      'count',
      'value',
      'level'
    ]) {
      final v = decoded[key];
      if (v is num) return ReadEmailIntent(count: v.round().clamp(1, 10));
      if (v is String) {
        final parsed = parseOrdinal(v);
        if (parsed != null) return ReadEmailIntent(count: parsed.clamp(1, 10));
      }
    }
    final text = _firstStringField(
        decoded, ['target', 'query', 'text', 'content', 'message']);
    if (text != null) {
      final parsed = parseOrdinal(text);
      if (parsed != null) return ReadEmailIntent(count: parsed.clamp(1, 10));
    }
    return const ReadEmailIntent(count: 5);
  }

  bool _isChatAction(String normalized) {
    const exact = {
      'chat',
      'small_talk',
      'smalltalk',
      'greeting',
      'greet',
      'conversation',
      'converse',
      'chitchat',
      'chit_chat',
    };
    if (exact.contains(normalized)) return true;
    if (normalized.startsWith('chat_')) return true;
    if (normalized.contains('small_talk') || normalized.contains('smalltalk')) {
      return true;
    }
    if (normalized.contains('greeting')) return true;
    return false;
  }

  bool _isVolumeAction(String normalized) {
    const exact = {
      'set_volume',
      'volume',
      'volume_level',
      'adjust_volume',
      'change_volume',
      'set_media_volume',
      'media_volume',
      'media_volume_up',
      'media_volume_down',
      'mute',
      'muted',
      'mute_volume',
      'unmute',
      'unmute_volume',
      'restore_volume',
      'volume_up',
      'volume_down',
      'increase_volume',
      'decrease_volume',
      'raise_volume',
      'lower_volume',
      'turn_up_volume',
      'turn_down_volume',
      'louder',
      'quieter',
      'max_volume',
      'full_volume',
      'min_volume',
      'max_media_volume',
      'volume_full',
      'volume_max',
      // Hindi volume keywords
      'awaaj_badhao',
      'awaaj_ghatao',
      'awaaj_band_karo',
      'awaaj_kholo',
      'awaaj_kya_hai',
      // Marathi volume keywords
      'chale_badhao',
      'ghatao',
      'band_karo',
      'kholo',
    };
    if (exact.contains(normalized)) return true;
    if (normalized.contains('volume')) return true;
    if (normalized.contains('mute') || normalized.contains('unmute')) return true;
    if (normalized == 'louder' || normalized == 'quieter') return true;
    // Hindi/Marathi keywords
    if (normalized.contains('awaaj') || normalized.contains('chale')) return true;
    return false;
  }

  bool _isBrightnessAction(String normalized) {
    const exact = {
      'set_brightness',
      'brightness',
      'brightness_level',
      'adjust_brightness',
      'change_brightness',
      'screen_brightness',
      'brightness_up',
      'brightness_down',
      'increase_brightness',
      'decrease_brightness',
      'raise_brightness',
      'lower_brightness',
      'brighten',
      'brighter',
      'dim',
      'dimmer',
      'dim_screen',
      'max_brightness',
      'full_brightness',
      'min_brightness',
      'brightness_max',
      'brightness_full',
      'screen_brightness_up',
      'screen_brightness_down',
      // Hindi/Marathi brightness keywords
      'chiya_badhao',
      'kashi_karo',
      'chiya',
      'kashi',
    };
    if (exact.contains(normalized)) return true;
    if (normalized.contains('brightness')) return true;
    if (normalized == 'brighten' || normalized == 'brighter') return true;
    if (normalized == 'dim' || normalized == 'dimmer') return true;
    // Hindi/Marathi
    if (normalized.contains('chiya') || normalized.contains('kashi')) return true;
    return false;
  }

  bool _isAlarmAction(String normalized) {
    const exact = {
      'set_alarm',
      'create_alarm',
      'add_alarm',
      'new_alarm',
      'alarm',
      'alarms',
      'wake_me_up',
      'wake_up',
      'wake_up_alarm',
    };
    if (exact.contains(normalized)) return true;
    if (normalized.contains('set_alarm') || normalized.contains('wake_me_up')) {
      return true;
    }
    if (normalized == 'alarm' || normalized.startsWith('alarm_')) return true;
    return false;
  }

  bool _isReminderAction(String normalized) {
    const exact = {
      'set_reminder',
      'create_reminder',
      'add_reminder',
      'new_reminder',
      'reminder',
      'remind',
      'remind_me',
      'set_remainder',
    };
    if (exact.contains(normalized)) return true;
    if (normalized.contains('remind')) return true;
    return false;
  }

  bool _isListAlarmsAction(String normalized) {
    const exact = {
      'list_alarms',
      'list_alarms_reminders',
      'show_alarms',
      'show_reminders',
      'get_alarms',
      'my_alarms',
      'check_alarms',
      'list_reminders',
    };
    if (exact.contains(normalized)) return true;
    if ((normalized.contains('list') ||
            normalized.contains('show') ||
            normalized.contains('what') ||
            normalized.contains('check')) &&
        (normalized.contains('alarm') || normalized.contains('remind'))) {
      return true;
    }
    return false;
  }

  bool _isCancelAlarmAction(String normalized) {
    const exact = {
      'cancel_alarm',
      'delete_alarm',
      'remove_alarm',
      'clear_alarm',
      'cancel_reminder',
      'delete_reminder',
      'remove_reminder',
      'dismiss_alarm',
      'stop_alarm',
      'cancel_all_alarms',
    };
    if (exact.contains(normalized)) return true;
    if ((normalized.contains('cancel') ||
            normalized.contains('delete') ||
            normalized.contains('remove') ||
            normalized.contains('clear') ||
            normalized.contains('dismiss') ||
            normalized.contains('stop')) &&
        (normalized.contains('alarm') || normalized.contains('remind'))) {
      return true;
    }
    return false;
  }

  /// Builds a [SetAlarmIntent] from LLM JSON. Accepts epoch millis
  /// (`timestamp`/`millis`) or a free time string (`time`/`target`/etc.)
  /// resolved with the offline clock parser. Returns null when no valid
  /// future time can be resolved.
  SetAlarmIntent? _buildAlarmIntent(Map<String, dynamic> decoded) {
    final epoch = _epochField(decoded);
    if (epoch != null) {
      final when = DateTime.fromMillisecondsSinceEpoch(epoch);
      if (!when.isAfter(DateTime.now().subtract(const Duration(seconds: 5)))) {
        return null;
      }
      final label = (_firstStringField(
                  decoded, ['label', 'title', 'alarm_label', 'message', 'text']) ??
              '')
          .trim();
      return SetAlarmIntent(time: when, label: label);
    }
    final timeText = _firstStringField(
        decoded, ['time', 'at', 'when', 'target', 'text', 'content', 'message']);
    if (timeText == null || timeText.trim().isEmpty) return null;
    final parsed = alarm_t.parseAlarmTime(timeText);
    if (parsed == null) return null;
    final label = (_firstStringField(
                decoded, ['label', 'title', 'alarm_label']) ??
            '')
        .trim();
    return SetAlarmIntent(time: parsed.when, label: label);
  }

  /// Builds a [SetReminderIntent] from LLM JSON. Returns null when the time
  /// or message is missing.
  SetReminderIntent? _buildReminderIntent(Map<String, dynamic> decoded) {
    final epoch = _epochField(decoded);
    final message = (_firstStringField(
                decoded, ['message', 'text', 'content', 'msg', 'target', 'reminder', 'label', 'title']) ??
            '')
        .trim();
    if (epoch != null) {
      if (message.isEmpty) return null;
      final when = DateTime.fromMillisecondsSinceEpoch(epoch);
      if (!when.isAfter(DateTime.now().subtract(const Duration(seconds: 5)))) {
        return null;
      }
      return SetReminderIntent(time: when, message: message);
    }
    final timeText = _firstStringField(
        decoded, ['time', 'at', 'when', 'target', 'text', 'content']);
    DateTime? when;
    if (timeText != null && timeText.trim().isNotEmpty) {
      when = alarm_t.parseAlarmTime(timeText)?.when;
    }
    // Fallback: the message field itself may contain the full phrase
    // ("drink water in 10 minutes") — parse time out of it.
    when ??= alarm_t.parseAlarmTime(message)?.when;
    if (when == null) return null;
    if (message.isEmpty) return null;
    // If message == time text, there is no real body.
    if (timeText != null && message.toLowerCase() == timeText.toLowerCase()) {
      return null;
    }
    return SetReminderIntent(time: when, message: message);
  }

  /// Reads epoch millis from common JSON fields.
  int? _epochField(Map<String, dynamic> decoded) {
    for (final key in const ['timestamp', 'millis', 'epoch']) {
      final v = decoded[key];
      if (v is num) {
        final ms = v.round();
        if (ms > 100000000000 && ms < 4102444800000) return ms;
        if (ms > 1000000000 && ms < 4102444800) return ms * 1000;
      }
      if (v is String) {
        final n = int.tryParse(v.trim());
        if (n == null) continue;
        if (n > 100000000000 && n < 4102444800000) return n;
        if (n > 1000000000 && n < 4102444800) return n * 1000;
      }
    }
    return null;
  }

  /// Builds a [VolumeIntent] from a normalized volume action plus decoded JSON.
  ///
  /// Priority: explicit numeric level > keyword hints in text/target >
  /// mute/unmute > up/down direction > current-level query.
  VolumeIntent _buildVolumeIntent(
      String normalized, Map<String, dynamic> decoded) {
    final level = _levelField(decoded);
    if (level != null) {
      return VolumeIntent(level: level);
    }

    final hint = _firstStringField(decoded, ['target', 'text', 'content', 'message']);
    if (hint != null) {
      final h = hint.toLowerCase();
      if (h.contains('max') || h.contains('full') || h.contains('highest')) {
        return const VolumeIntent(level: 100);
      }
      if (h.contains('min') || h.contains('lowest') || h.contains('zero')) {
        return const VolumeIntent(level: 0);
      }
    }

    if (_isUnmuteAction(normalized)) {
      return const VolumeIntent(unmute: true);
    }
    if (_isMuteAction(normalized)) {
      return const VolumeIntent(mute: true);
    }

    const upWords = ['up', 'increase', 'raise', 'louder', 'higher', 'more'];
    const downWords = [
      'down',
      'decrease',
      'lower',
      'quieter',
      'reduce',
      'softer',
      'less'
    ];
    if (upWords.any(normalized.contains)) {
      return const VolumeIntent(delta: 1);
    }
    if (downWords.any(normalized.contains)) {
      return const VolumeIntent(delta: -1);
    }
    // Hindi/Marathi direction keywords
    const hindiMarathiUpWords = ['badhao', 'badhao', 'badha', 'badh'];
    const hindiMarathiDownWords = ['ghatao', 'ghata', 'ghat'];
    if (hindiMarathiUpWords.any(normalized.contains)) {
      return const VolumeIntent(delta: 1);
    }
    if (hindiMarathiDownWords.any(normalized.contains)) {
      return const VolumeIntent(delta: -1);
    }
    if (normalized.contains('max') || normalized.contains('full')) {
      return const VolumeIntent(level: 100);
    }
    if (normalized.contains('min')) {
      return const VolumeIntent(level: 0);
    }
    if (normalized == 'awaaj_kya_hai' || normalized == 'chale_kya_hai') {
      return const VolumeIntent();
    }

    // No specific signal: report the current level (query).
    return const VolumeIntent();
  }

  /// Builds a [BrightnessIntent] from a normalized brightness action plus JSON.
  BrightnessIntent _buildBrightnessIntent(
      String normalized, Map<String, dynamic> decoded) {
    final level = _levelField(decoded);
    if (level != null) {
      return BrightnessIntent(level: level);
    }

    final hint = _firstStringField(decoded, ['target', 'text', 'content', 'message']);
    if (hint != null) {
      final h = hint.toLowerCase();
      if (h.contains('max') || h.contains('full') || h.contains('brightest')) {
        return const BrightnessIntent(level: 100);
      }
      if (h.contains('min') || h.contains('lowest') || h.contains('darkest')) {
        return const BrightnessIntent(level: 0);
      }
    }

    const upWords = ['up', 'increase', 'raise', 'brighten', 'brighter', 'higher', 'more'];
    const downWords = [
      'down',
      'decrease',
      'lower',
      'dim',
      'dimmer',
      'reduce',
      'darker',
      'softer',
      'less'
    ];
    if (upWords.any(normalized.contains)) {
      return const BrightnessIntent(delta: 1);
    }
    if (downWords.any(normalized.contains)) {
      return const BrightnessIntent(delta: -1);
    }
    // Hindi/Marathi direction keywords
    const hindiMarathiUpWords = ['chiya', 'badhao'];
    const hindiMarathiDownWords = ['kashi', 'ghatao'];
    if (hindiMarathiUpWords.any(normalized.contains)) {
      return const BrightnessIntent(delta: 1);
    }
    if (hindiMarathiDownWords.any(normalized.contains)) {
      return const BrightnessIntent(delta: -1);
    }
    if (normalized.contains('max') || normalized.contains('full')) {
      return const BrightnessIntent(level: 100);
    }
    if (normalized.contains('min')) {
      return const BrightnessIntent(level: 0);
    }

    // No specific signal: report the current brightness (query).
    return const BrightnessIntent();
  }

  bool _isMuteAction(String normalized) {
    if (normalized == 'mute' || normalized == 'muted' || normalized == 'mute_volume') {
      return true;
    }
    if (normalized.contains('silent') || normalized.contains('silence')) {
      return true;
    }
    if (normalized.contains('band_karo') || normalized.contains('band')) {
      return true;
    }
    return normalized.startsWith('mute_') || normalized == 'volume_off';
  }

  bool _isUnmuteAction(String normalized) {
    if (normalized == 'unmute' ||
        normalized == 'unmute_volume' ||
        normalized == 'restore_volume') {
      return true;
    }
    if (normalized.contains('kholo') || normalized.contains('unmute')) {
      return true;
    }
    return normalized.contains('unmute') || normalized.contains('restore_volume');
  }

  /// Reads an absolute 0-100 level from common JSON fields ('level', 'value',
  /// 'percent'), tolerating strings, trailing '%' and out-of-range values.
  /// Also accepts a numeric 'target' (small-model drift sometimes emits
  /// {"action": "set_volume", "target": "50%"} instead of "value": 50).
  int? _levelField(Map<String, dynamic> decoded) {
    for (final key in const ['level', 'value', 'percent']) {
      final v = decoded[key];
      if (v == null) continue;
      if (v is num) {
        return v.round().clamp(0, 100);
      }
      if (v is String) {
        final parsed = _parseLevelString(v);
        if (parsed != null) return parsed;
      }
    }
    // Numeric target fallback: only when the string actually contains a
    // number (so "max"/"min" keyword handling below is preserved).
    final target = decoded['target'];
    if (target is String) {
      final parsed = _parseLevelString(target);
      // Require a digit so "max"/"full"/"min" don't get consumed here.
      if (parsed != null && RegExp(r'\d').hasMatch(target)) return parsed;
    }
    // Last resort: scan free-text aliases for an embedded number.
    final hint = _firstStringField(decoded, ['text', 'content', 'message']);
    if (hint != null) {
      final m = RegExp(r'(\d{1,3})\s*%?(?:\s*percent)?\b', caseSensitive: false)
          .firstMatch(hint);
      if (m != null) {
        final d = double.tryParse(m.group(1)!);
        if (d != null) return d.round().clamp(0, 100);
      }
    }
    return null;
  }

  /// Parses "50", "50%", "50 percent" into 0-100, or null.
  int? _parseLevelString(String raw) {
    final s =
        raw.trim().replaceAll('%', '').replaceAll('percent', '').trim();
    // Accept embedded numbers like "volume 50" just in case.
    final m = RegExp(r'(\d{1,3})').firstMatch(s);
    if (m == null) return null;
    final d = double.tryParse(m.group(1)!);
    if (d != null) return d.round().clamp(0, 100);
    return null;
  }

  String? _firstStringField(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    return null;
  }
}
