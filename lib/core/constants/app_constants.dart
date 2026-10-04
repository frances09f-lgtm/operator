class AppConstants {
  static const String appLauncherChannel = 'friday/app_launcher';
  static const String flashlightChannel = 'friday/flashlight';
  static const String deviceControlChannel = 'friday/device_control';
  static const String mediaControlChannel = 'friday/media_control';
  static const String volumeControlChannel = 'friday/volume_control';
  static const String brightnessControlChannel = 'friday/brightness_control';
  static const String whatsAppChannel = 'friday/whatsapp';
  static const String phoneCallChannel = 'friday/phone_call';
  static const String automationChannel = 'friday/automation';
  static const String galleryChannel = 'friday/gallery';
  static const String youTubeChannel = 'friday/youtube';
  static const String assistChannel = 'friday/assist';
  static const String alarmChannel = 'friday/alarm';
  static const String smsChannel = 'friday/sms';
  static const String foPhoneNumber = '+16289985940';
  static const String foDisplayName = 'FO';
  static const String defaultModelFileName = 'SmolLM2-135M-Instruct-Q4_K_M.gguf';

  /// Large "smart" chat model used ONLY for open questions (ChatGPT-like).
  /// Kept unloaded until needed so fast device commands never slow down.
  /// Recommended: Qwen3 / Qwen2.5-1.5B-Instruct-Q4_K_M (~1GB, high quality/MB).
  static const String chatModelFileName =
      'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf';

  /// Context window for the chat model. Larger than command model to fit
  /// conversation history + longer answers.
  static const int chatInferenceContextSize = 2048;

  /// Number of CPU threads used by the local inference engine.
  /// Most modern phones expose 8 performance threads.
  static const int inferenceThreads = 8;

  /// Context window size used by the local inference engine.
  /// 768 keeps prefill fast (small KV cache, less RAM) while fitting the
  /// compact prompt (~350 tokens) + user command + 256 maxTokens output.
  /// 2048 was 4x slower and caused OOM slowness on low-RAM phones.
  static const int inferenceContextSize = 768;

  /// Direct-download URL for the default model (SmolLM2-135M Q4_K_M, ~100 MB).
  /// Used by the in-app "Download model" option when no .gguf is installed.
  static const String modelDownloadUrl =
      'https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/'
      'SmolLM2-135M-Instruct-Q4_K_M.gguf';

  /// Direct-download URL for the smart chat model (~1GB).
  static const String chatModelDownloadUrl =
      'https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/'
      'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf';

  /// Free-form chat system prompt (NOT JSON). Used only with the big model.
  static const String chatSystemPrompt =
      'You are FRIDAY, a helpful on-device assistant. '
      'Answer concisely in the user\'s language, max 150 words. '
      'No JSON, no markdown code fences unless code is asked.';

  /// System prompt strictly instructing the LLM to output only JSON.
  /// Keep short: smaller prompt = faster prefill and avoids
  /// "Failed to decode prompt" when context is tight. One example per
  /// action is enough; heuristics cover phrasing variants.
  /// Multi-step sequences are returned as a JSON array, in order.
  static const String systemPrompt =
      'You are FRIDAY, an Android command classifier.\n'
      'Respond ONLY with a single JSON object (or JSON array for multiple steps):\n'
      '- open app -> {"action": "open_app", "target": "<app>"}\n'
      '- flashlight/torch/flash -> {"action": "toggle_flashlight"}\n'
      '- bluetooth -> {"action": "toggle_bluetooth", "target": "on|off|toggle"}\n'
      '- wifi -> {"action": "toggle_wifi", "target": "on|off|toggle"}\n'
      '- media -> {"action": "media_play"} | media_pause | media_resume | media_next | media_previous | media_stop\n'
      '- volume -> {"action": "volume_up"} | volume_down | mute | unmute | {"action": "set_volume", "value": 50}\n'
      '- brightness -> {"action": "brightness_up"} | brightness_down | {"action": "set_brightness", "value": 70}\n'
      '- whatsapp -> {"action": "send_whatsapp", "target": "<name>", "message": "<text>"}\n'
      '- call/dial -> {"action": "make_call", "target": "<name_or_number>"}\n'
      '- read chat -> {"action": "read_chat", "target": "<contact>"}\n'
      '- email -> {"action": "read_email", "target": "unread"}\n'
      '- alarm -> {"action": "set_alarm", "time": "<time>"}\n'
      '- reminder -> {"action": "set_reminder", "time": "<time>", "message": "<text>"}\n'
      '- list alarms -> {"action": "list_alarms"}\n'
      '- cancel alarm -> {"action": "cancel_alarm", "target": "<label/time>"}\n'
      '- gallery video -> {"action": "play_gallery_video", "index": 2}\n'
      '- youtube search -> {"action": "youtube_search_play", "query": "<text>", "index": 1}\n'
      '- ai ask -> {"action": "ai_ask", "target": "<deepseek|chatgpt|gemini>", "query": "<question>"}\n'
      '- custom -> {"action": "custom", "target": "<phrase>"}\n'
      '- chat -> {"action": "chat", "message": "<short friendly reply>"}\n'
      '- unsupported -> {"action": "unsupported"}\n\n'
      'Examples:\n'
      'User: open youtube -> {"action": "open_app", "target": "youtube"}\n'
      'User: turn on flashlight -> {"action": "toggle_flashlight"}\n'
      'User: turn on bluetooth -> {"action": "toggle_bluetooth", "target": "on"}\n'
      'User: turn off wifi -> {"action": "toggle_wifi", "target": "off"}\n'
      'User: volume up -> {"action": "volume_up"}\n'
      'User: mute -> {"action": "mute"}\n'
      'User: pause music -> {"action": "media_pause"}\n'
      'User: stop -> {"action": "media_stop"}\n'
      'User: call mom -> {"action": "make_call", "target": "mom"}\n'
      'User: send whatsapp to mom saying hi -> {"action": "send_whatsapp", "target": "mom", "message": "hi"}\n'
      'User: set an alarm for 7 am -> {"action": "set_alarm", "time": "7am"}\n'
      'User: open gallery and play second video -> {"action": "play_gallery_video", "index": 2}\n'
      'User: hello -> {"action": "chat", "message": "Hello! I am FRIDAY."}\n\n'
      'Rules: Output ONLY raw JSON on one line. No markdown, no explanations. Never use open_app for flashlight/wifi/bluetooth/volume/brightness/media.';
}
