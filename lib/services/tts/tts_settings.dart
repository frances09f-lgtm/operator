/// Minimal, in-memory settings for the assistant's voice responses.
class TtsSettings {
  /// Whether spoken responses are enabled at all.
  final bool enabled;

  /// Speech rate for the local TTS engine, clamped to 0.0–1.0
  /// (flutter_tts: 0.0 slowest .. 1.0 fastest).
  final double speechRate;

  /// Requested language/locale (e.g. 'en-US'). Null = the device's default
  /// language as provided by the phone's TTS engine.
  final String? language;

  const TtsSettings({
    this.enabled = true,
    this.speechRate = 0.5,
    this.language,
  });

  TtsSettings copyWith({
    bool? enabled,
    double? speechRate,
    String? language,
  }) {
    return TtsSettings(
      enabled: enabled ?? this.enabled,
      speechRate: speechRate ?? this.speechRate,
      language: language ?? this.language,
    );
  }
}