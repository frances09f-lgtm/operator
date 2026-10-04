/// Abstraction over the platform text-to-speech layer so the assistant can
/// speak responses without depending on a specific plugin.
///
/// Implementations use the phone's local TTS engine only. No cloud service is
/// involved at any point.
abstract class TextToSpeechService {
  /// Whether the device has a usable local TTS engine.
  bool get isAvailable;

  /// Optional callback fired when an utterance finishes, is cancelled, or
  /// fails on the platform side.
  void Function()? onCompletion;

  /// Initializes the TTS engine (requesting default voice/language if
  /// needed). Returns true when speech is usable.
  Future<bool> initialize();

  /// Speaks [text] aloud. Completes once the utterance has finished (or has
  /// been interrupted/failed), never hangs indefinitely from the caller's
  /// perspective.
  Future<void> speak(String text);

  /// Stops any utterance currently being spoken.
  Future<void> stop();

  /// Sets the speech rate, expected in the 0.0–1.0 range.
  Future<void> setSpeechRate(double rate);

  /// Requests a specific language/locale (best effort). When the language is
  /// unavailable the implementation falls back to the device default.
  Future<void> setLanguage(String language);

  /// Checks if a specific language/locale is available on the device.
  Future<bool> isLanguageAvailable(String locale);

  /// Releases platform TTS resources.
  Future<void> dispose();
}