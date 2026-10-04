import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:friday_app/services/tts/language_settings.dart';
import 'package:friday_app/services/voice/voice_command_service.dart';

/// [VoiceCommandService] implementation backed by the `speech_to_text`
/// plugin (Android's built-in SpeechRecognizer).
class SpeechToTextVoiceCommandService implements VoiceCommandService {
  static const Duration _minListenDuration = Duration(milliseconds: 300);

  final SpeechToText _speech;
  final Duration _listenFor;
  final Duration _finalTimeout;
  String? _localeId;

  String _recognizedText = '';
  bool _extraResultDelivered = false;
  String? _errorMessage;
  double _soundLevel = 0;
  Timer? _silenceTimer;
  Timer? _minListenTimer;
  Timer? _maxDurationTimer;
  DateTime? _sessionStartTime;

  SpeechToTextVoiceCommandService({
    SpeechToText? speech,
    Duration listenFor = const Duration(seconds: 8),
    Duration finalTimeout = const Duration(seconds: 8),
    AppLanguage? language,
  })  : _speech = speech ?? SpeechToText(),
        _listenFor = listenFor,
        _finalTimeout = finalTimeout,
        _localeId = language?.locale;

  @override
  bool get isAvailable => _speech.isAvailable;

  @override
  bool get isListening => _speech.isListening;

  @override
  double get soundLevel => _soundLevel;

  @override
  String? get errorMessage => _errorMessage;

  @override
  void Function(String partialText)? onPartialResult;

  @override
  void Function(String recognizedText)? onFinalResult;

  @override
  void Function()? onListeningEnded;

  @override
  Future<bool> initialize() async {
    _errorMessage = null;
    try {
      final available = await _speech.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
        finalTimeout: _finalTimeout,
        debugLogging: false,
      );
      return available;
    } catch (e) {
      _errorMessage = 'Speech recognition could not be initialized.';
      return false;
    }
  }

  @override
  Future<bool> startListening({Duration? listenFor}) async {
    if (!isAvailable) return false;

    _stopSilenceTimer();
    _recognizedText = '';
    _extraResultDelivered = false;
    _errorMessage = null;
    _soundLevel = 0;
    _sessionStartTime = DateTime.now();

    final isLongSession =
        listenFor != null && listenFor > const Duration(seconds: 30);

    try {
      final effectiveDuration = listenFor ?? _listenFor;
      _maxDurationTimer = Timer(effectiveDuration, () {
        if (isListening) {
          stopListening();
        }
      });

      await _speech.listen(
        onResult: _handleResult,
        onSoundLevelChange: _handleSoundLevel,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          // ListenMode.deviceDefault captures full natural voice commands
          // without cutting off mid-sentence.
          listenMode:
              isLongSession ? ListenMode.dictation : ListenMode.deviceDefault,
          pauseFor: isLongSession
              ? const Duration(seconds: 10)
              : const Duration(seconds: 3),
          listenFor: effectiveDuration,
          localeId: _localeId,
        ),
      );
      return true;
    } catch (e) {
      _errorMessage = 'Could not start the microphone.';
      return false;
    }
  }

  @override
  Future<String?> stopListening() async {
    _stopSilenceTimer();
    _soundLevel = 0;
    try {
      await _speech.stop();
    } catch (_) {}

    if (_extraResultDelivered) {
      return _recognizedText.trim().isEmpty ? null : _recognizedText.trim();
    }

    _deliverIfHeard();
    return _recognizedText.trim().isEmpty ? null : _recognizedText.trim();
  }

  @override
  Future<void> cancelListening() async {
    _stopSilenceTimer();
    _extraResultDelivered = true;
    _soundLevel = 0;
    try {
      await _speech.cancel();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    _stopSilenceTimer();
    _extraResultDelivered = true;
    _soundLevel = 0;
    try {
      await _speech.cancel();
    } catch (_) {}
  }

  @override
  Future<void> setLocale(String? localeId) async {
    _localeId = localeId;
  }

  static const Set<String> _incompletePrefixes = {
    'open',
    'launch',
    'start',
    'turn',
    'turn on',
    'turn off',
    'switch on',
    'switch off',
    'set',
    'set volume',
    'set brightness',
    'volume',
    'brightness',
    'call',
    'play',
    'send',
    'send message',
    'send sms',
    'message',
    'text',
    'search',
    'ask',
    'kholo',
    'chalu karo',
    'band karo',
    'badhao',
    'ghatao',
  };

  bool _isIncompletePrefix(String text) {
    final lower = text.trim().toLowerCase();
    return _incompletePrefixes.contains(lower);
  }

  void _handleResult(SpeechRecognitionResult result) {
    _recognizedText = result.recognizedWords;
    if (_recognizedText.trim().isNotEmpty) {
      onPartialResult?.call(_recognizedText.trim());
    }

    if (result.finalResult && !_isIncompletePrefix(_recognizedText)) {
      _stopSilenceTimer();
      _deliverIfHeard();
    } else if (_recognizedText.trim().isNotEmpty) {
      // Natural silence detection: gives extra time if user just said a command prefix like "open"
      _resetSilenceTimer();
    }
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    final isIncomplete = _isIncompletePrefix(_recognizedText);
    final timeout = isIncomplete
        ? const Duration(milliseconds: 1800)
        : const Duration(milliseconds: 1200);

    _silenceTimer = Timer(timeout, () {
      if (!_extraResultDelivered && _recognizedText.trim().isNotEmpty) {
        _finalizeWithMinDuration();
      }
    });
  }

  void _finalizeWithMinDuration() {
    final startTime = _sessionStartTime;
    if (startTime != null) {
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed < _minListenDuration) {
        final remaining = _minListenDuration - elapsed;
        _minListenTimer?.cancel();
        _minListenTimer = Timer(remaining, () {
          _deliverIfHeard();
        });
        return;
      }
    }
    _deliverIfHeard();
  }

  void _stopSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _minListenTimer?.cancel();
    _minListenTimer = null;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
  }

  void _deliverIfHeard() {
    if (_extraResultDelivered) return;
    _extraResultDelivered = true;

    // Turn off platform microphone recording immediately when command is heard
    try {
      _speech.stop();
    } catch (_) {}

    final text = _recognizedText.trim();
    if (text.isNotEmpty) {
      onFinalResult?.call(text);
    }
  }

  void _handleStatus(String status) {
    final ended = status == 'done' ||
        status == 'notListening' ||
        status == 'stopped' ||
        status == 'doneNoResult';

    if (ended) {
      _stopSilenceTimer();
      _soundLevel = 0;
      if (!_extraResultDelivered && _recognizedText.trim().isNotEmpty) {
        _deliverIfHeard();
      }
      onListeningEnded?.call();
    }
  }

  void _handleSoundLevel(double level) {
    _soundLevel = level.clamp(0.0, 1.0);
  }

  void _handleError(SpeechRecognitionError error) {
    _stopSilenceTimer();
    switch (error.errorMsg) {
      case 'error_no_match':
        _errorMessage = 'I didn\'t catch that. Try again.';
      case 'error_not_available':
        _errorMessage = 'Speech recognition is not available on this device.';
      case 'error_permission':
        _errorMessage = 'Microphone permission is required for voice commands.';
      case 'error_speech_timeout':
      case 'error_no_speech':
        _errorMessage = 'No speech was detected.';
      default:
        _errorMessage = 'Speech recognition error: ${error.errorMsg}';
    }
  }
}



