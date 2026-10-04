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
/// is unavailable, unsupported, or if the model is still being downloaded.
///
/// Ensures the microphone input NEVER fails or becomes disabled for the user.
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
  WhistleVoiceCommandService get whistleService => _whistleService;
  SpeechToTextVoiceCommandService get systemService => _systemService;

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
  bool get isAvailable {
    if (_activeEngine == VoiceEngineType.whistle) {
      if (_whistleService.isAvailable) return true;
      // If Whistle is selected but local model is not downloaded or ready yet,
      // allow fallback to system speech so the microphone button remains functional!
      return _systemService.isAvailable;
    }
    return _systemService.isAvailable;
  }

  @override
  bool get isListening => _whistleService.isListening || _systemService.isListening;

  @override
  double get soundLevel => _whistleService.isListening
      ? _whistleService.soundLevel
      : _systemService.soundLevel;

  @override
  String? get errorMessage {
    if (_activeEngine == VoiceEngineType.whistle && !_whistleService.isAvailable) {
      return _whistleService.errorMessage ?? _systemService.errorMessage;
    }
    return _currentService.errorMessage;
  }

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
    // Always initialize the system fallback service in background
    await _systemService.initialize();

    if (_preferWhistle) {
      debugPrint('[AdaptiveVoice] Checking Whistle local STT engine...');
      final whistleOk = await _whistleService.initialize();
      if (whistleOk) {
        _activeEngine = VoiceEngineType.whistle;
        debugPrint('[AdaptiveVoice] Whistle local STT engine initialized successfully.');
        return true;
      }
      debugPrint('[AdaptiveVoice] Whistle model not ready yet. Ready with system STT fallback.');
      _activeEngine = VoiceEngineType.whistle; // keep preference, fallback dynamically
      return _systemService.isAvailable;
    }

    final systemOk = await _systemService.initialize();
    if (systemOk) {
      _activeEngine = VoiceEngineType.systemSpeech;
      debugPrint('[AdaptiveVoice] System SpeechRecognizer initialized.');
      return true;
    }

    return false;
  }

  /// Switch the active voice engine.
  Future<bool> setEngine(VoiceEngineType engine) async {
    if (isListening) {
      await stopListening();
    }

    _activeEngine = engine;
    if (engine == VoiceEngineType.whistle) {
      _preferWhistle = true;
      final whistleOk = await _whistleService.initialize();
      if (!whistleOk) {
        await _systemService.initialize();
      }
      return isAvailable;
    } else {
      _preferWhistle = false;
      return await _systemService.initialize();
    }
  }

  @override
  Future<bool> startListening({Duration? listenFor}) async {
    if (_activeEngine == VoiceEngineType.whistle) {
      if (_whistleService.isAvailable) {
        return await _whistleService.startListening(listenFor: listenFor);
      }
      debugPrint('[AdaptiveVoice] Whistle not ready (model pending download). Using system speech fallback.');
      return await _systemService.startListening(listenFor: listenFor);
    }
    return await _systemService.startListening(listenFor: listenFor);
  }

  @override
  Future<String?> stopListening() {
    if (_whistleService.isListening) {
      return _whistleService.stopListening();
    }
    return _systemService.stopListening();
  }

  @override
  Future<void> cancelListening() async {
    if (_whistleService.isListening) {
      await _whistleService.cancelListening();
    }
    if (_systemService.isListening) {
      await _systemService.cancelListening();
    }
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
