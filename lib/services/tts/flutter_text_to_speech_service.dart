import 'package:flutter_tts/flutter_tts.dart';
import 'package:friday_app/services/tts/text_to_speech_service.dart';

/// [TextToSpeechService] backed by the `flutter_tts` plugin, which wraps
/// Android's built-in `android.speech.tts.TextToSpeech` engine â€” fully local,
/// no network access.
class FlutterTextToSpeechService implements TextToSpeechService {
  FlutterTts? _tts;
  bool _initialized = false;
  bool _available = false;
  double _speechRate = 0.5;
  String? _language;

  FlutterTextToSpeechService({FlutterTts? tts}) : _tts = tts;

  @override
  bool get isAvailable => _available;

  @override
  void Function()? onCompletion;

  /// Creates the platform engine lazily (a real engine can only be built after
  /// the Flutter binding is up; on headless test runs this returns null
  /// instead of asserting).
  FlutterTts? _ensureEngine() {
    if (_tts != null) return _tts;
    try {
      return _tts = FlutterTts();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;

    final engine = _ensureEngine();
    if (engine == null) return false;

    try {
      // Completing/cancelling/failing an utterance all resolve the same way
      // from the assistant's perspective: it is done speaking.
      engine.setCompletionHandler(() => onCompletion?.call());
      engine.setCancelHandler(() => onCompletion?.call());
      engine.setErrorHandler((_) => onCompletion?.call());

      await engine.setSpeechRate(_speechRate);
      if (_language != null && _language!.isNotEmpty) {
        final available = await engine.isLanguageAvailable(_language!);
        if (available == true) {
          await engine.setLanguage(_language!);
        }
      }
      _available = true;
    } catch (_) {
      _available = false;
    }

    return _available;
  }

  @override
  Future<void> speak(String text) async {
    final engine = _ensureEngine();
    if (engine == null) {
      onCompletion?.call();
      return;
    }
    try {
      // Ensure the speak future completes only when the utterance actually
      // finishes (supported on Android/iOS). Wrapped in a try/catch so the
      // caller is never stuck waiting.
      await engine.awaitSpeakCompletion(true);
      await engine.speak(text);
    } catch (_) {
      onCompletion?.call();
    }
  }

  @override
  Future<void> stop() async {
    final engine = _tts;
    if (engine == null) return;
    try {
      await engine.stop();
    } catch (_) {}
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate.clamp(0.0, 1.0);
    final engine = _ensureEngine();
    if (engine == null) return;
    try {
      await engine.setSpeechRate(_speechRate);
    } catch (_) {}
  }

  @override
  Future<void> setLanguage(String language) async {
    _language = language;
    final engine = _ensureEngine();
    if (engine == null) return;
    try {
      final available = await engine.isLanguageAvailable(language);
      if (available == true) {
        await engine.setLanguage(language);
      }
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    final engine = _tts;
    if (engine == null) return;
    try {
      await engine.stop();
    } catch (_) {}
  }

  @override
  Future<bool> isLanguageAvailable(String locale) async {
    final engine = _ensureEngine();
    if (engine == null) return false;
    try {
      return await engine.isLanguageAvailable(locale) == true;
    } catch (_) {
      return false;
    }
  }
}