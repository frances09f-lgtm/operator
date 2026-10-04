import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:friday_app/services/voice/speech_to_text_voice_command_service.dart';
import 'package:friday_app/services/voice/voice_command_service.dart';
import 'package:friday_app/services/voice/whistle_voice_command_service.dart';

enum VoiceEngineType {
  whistle,
  systemSpeech,
}

/// Adaptive [VoiceCommandService] that prefers the 100% on-device [WhistleVoiceCommandService],
/// but gracefully falls back to [SpeechToTextVoiceCommandService] if local inference
/// is unavailable or unsupported on the current platform/device.
class AdaptiveVoiceCommandService implements VoiceCommandService {
  final WhistleVoiceCommandService _whistleService;
  final SpeechToTextVoiceCommandService _systemService;

  VoiceEngineType _activeEngine = VoiceEngineType.whistle;
  bool _preferWhistle = true;

  void Function(String partialText)? _onPartialResult;
  void Function(String recognizedText)? _onFinalResult;
  void Function()? _onListeningEnded;

  AdaptiveVoiceCommandService({
    WhistleVoiceCommandService? whistleService,
    SpeechToTextVoiceCommandService? systemService,
    bool preferWhistle = true,
  })  : _whistleService = whistleService ?? WhistleVoiceCommandService(),
        _systemService = systemService ?? SpeechToTextVoiceCommandService(),
        _preferWhistle = preferWhistle {
    _wireCallbacks();
  }

  VoiceEngineType get activeEngine => _activeEngine;
  bool get preferWhistle => _preferWhistle;

  VoiceCommandService get _currentService =>
      _activeEngine == VoiceEngineType.whistle ? _whistleService : _systemService;

  void _wireCallbacks() {
    _whistleService.onPartialResult = (text) => _onPartialResult?.call(text);
    _whistleService.onFinalResult = (text) => _onFinalResult?.call(text);
    _whistleService.onListeningEnded = () => _onListeningEnded?.call();

    _systemService.onPartialResult = (text) => _onPartialResult?.call(text);
    _systemService.onFinalResult = (text) => _onFinalResult?.call(text);
    _systemService.onListeningEnded = () => _onListeningEnded?.call();
  }

  @override
  bool get isAvailable => _currentService.isAvailable;

  @override
  bool get isListening => _currentService.isListening;

  @override
  double get soundLevel => _currentService.soundLevel;

  @override
  String? get errorMessage => _currentService.errorMessage;

  @override
  void Function(String partialText)? get onPartialResult => _onPartialResult;

  @override
  set onPartialResult(void Function(String partialText)? callback) {
    _onPartialResult = callback;
  }

  @override
  void Function(String recognizedText)? get onFinalResult => _onFinalResult;

  @override
  set onFinalResult(void Function(String recognizedText)? callback) {
    _onFinalResult = callback;
  }

  @override
  void Function()? get onListeningEnded => _onListeningEnded;

  @override
  set onListeningEnded(void Function()? callback) {
    _onListeningEnded = callback;
  }

  @override
  Future<bool> initialize() async {
    if (_preferWhistle) {
      debugPrint('[AdaptiveVoice] Attempting initialization with Whistle local STT engine...');
      final whistleOk = await _whistleService.initialize();
      if (whistleOk) {
        _activeEngine = VoiceEngineType.whistle;
        debugPrint('[AdaptiveVoice] Whistle local STT engine initialized successfully.');
        return true;
      }
      debugPrint('[AdaptiveVoice] Whistle init failed/unsupported. Falling back to system STT.');
    }

    final systemOk = await _systemService.initialize();
    if (systemOk) {
      _activeEngine = VoiceEngineType.systemSpeech;
      debugPrint('[AdaptiveVoice] System SpeechRecognizer initialized successfully.');
      return true;
    }

    return false;
  }

  /// Manually switch the voice engine (e.g. from user Settings).
  Future<bool> setEngine(VoiceEngineType engine) async {
    if (_currentService.isListening) {
      await _currentService.stopListening();
    }

    _activeEngine = engine;
    if (engine == VoiceEngineType.whistle) {
      _preferWhistle = true;
      return await _whistleService.initialize();
    } else {
      _preferWhistle = false;
      return await _systemService.initialize();
    }
  }

  @override
  Future<bool> startListening({Duration? listenFor}) {
    return _currentService.startListening(listenFor: listenFor);
  }

  @override
  Future<String?> stopListening() {
    return _currentService.stopListening();
  }

  @override
  Future<void> cancelListening() {
    return _currentService.cancelListening();
  }

  @override
  Future<void> dispose() async {
    await _whistleService.dispose();
    await _systemService.dispose();
  }

  @override
  Future<void> setLocale(String? localeId) async {
    await _whistleService.setLocale(localeId);
    await _systemService.setLocale(localeId);
  }
}
