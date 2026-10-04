/// Abstraction over the platform speech-recognition layer so the assistant
/// can receive voice commands without depending on a specific plugin.
abstract class VoiceCommandService {
  /// Whether the device/app supports microphone speech recognition.
  bool get isAvailable;

  /// Whether the microphone is currently capturing speech.
  bool get isListening;

  /// Live microphone level between 0.0 and 1.0 while listening, else 0.0.
  ///
  /// Drives voice-reactive animations.
  double get soundLevel;

  /// Human-readable error from the platform if the last operation failed.
  String? get errorMessage;

  /// Invoked whenever intermediate/partial transcribed speech arrives while talking.
  void Function(String partialText)? onPartialResult;

  /// Invoked once when a final (processed) voice input arrives.
  ///
  /// The [recognizedText] is trimmed; it may be empty when silence was heard.
  void Function(String recognizedText)? onFinalResult;

  /// Invoked when the platform ends a listening session on its own (timeout,
  /// silence, or error), without an explicit [stopListening] call.
  void Function()? onListeningEnded;

  /// Initializes speech recognition (requesting microphone permission if
  /// needed). Returns true when voice input is usable.
  Future<bool> initialize();

  /// Starts listening and returns true when recognition has begun.
///
/// Optional [listenFor] caps the session length. Hands-free passes a very
  /// long window so the platform does not kill the session on a timer —
  /// sessions then end only on speech, silence-timeout, or error, and the
  /// controller re-arms instantly to keep the mic effectively always hot.
  Future<bool> startListening({Duration? listenFor});

  /// Stops listening. Delivers any gathered text through [onFinalResult]
  /// if it has not already been delivered. Returns the recognized text,
  /// or null if nothing was heard.
  Future<String?> stopListening();

  /// Cancels listening without delivering any result.
  Future<void> cancelListening();

  /// Releases platform recognition resources.
  Future<void> dispose();

  /// Sets the locale for speech recognition. Pass null to use the device default.
  Future<void> setLocale(String? localeId);
}
