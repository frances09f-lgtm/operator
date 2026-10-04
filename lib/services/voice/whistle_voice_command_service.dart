import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:cactus/cactus.dart';
import 'package:friday_app/services/voice/voice_command_service.dart';

/// [VoiceCommandService] implementation powered by the Whistle / Cactus
/// local on-device Automatic Speech Recognition engine.
///
/// Features:
/// - 100% offline, privacy-first local speech-to-text.
/// - 16 kHz mono audio recording via [AudioRecorder].
/// - Live amplitude / soundLevel tracking for voice-reactive UI orbs.
/// - Adaptive silence detection (VAD heuristic) to auto-stop when speech ends.
/// - Model download management and graceful fallback if model is not yet on-device.
class WhistleVoiceCommandService implements VoiceCommandService {
  static const Duration _minListenDuration = Duration(milliseconds: 400);
  static const Duration _defaultListenDuration = Duration(seconds: 10);
  static const double _silenceThresholdDb = -42.0;

  AudioRecorder? _audioRecorder;
  AudioRecorder get _recorder => _audioRecorder ??= AudioRecorder();

  CactusSTT? _cactusStt;
  CactusSTT get _stt => _cactusStt ??= CactusSTT();

  final String _modelName;

  bool _isAvailable = false;
  bool _isListening = false;
  bool _isModelDownloaded = false;
  bool _isDownloadingModel = false;
  double _modelDownloadProgress = 0.0;
  double _soundLevel = 0.0;
  String? _errorMessage;
  String? _currentRecordingPath;
  DateTime? _sessionStartTime;
  bool _speechDetected = false;

  Timer? _amplitudeTimer;
  Timer? _silenceTimer;
  Timer? _maxDurationTimer;

  @override
  void Function(String partialText)? onPartialResult;

  @override
  void Function(String recognizedText)? onFinalResult;

  @override
  void Function()? onListeningEnded;

  WhistleVoiceCommandService({
    AudioRecorder? audioRecorder,
    CactusSTT? cactusStt,
    String modelName = 'whisper-tiny',
  })  : _audioRecorder = audioRecorder,
        _cactusStt = cactusStt,
        _modelName = modelName;

  @override
  bool get isAvailable => _isAvailable;

  @override
  bool get isListening => _isListening;

  @override
  double get soundLevel => _soundLevel;

  @override
  String? get errorMessage => _errorMessage;

  bool get isModelDownloaded => _isModelDownloaded;
  bool get isDownloadingModel => _isDownloadingModel;
  double get modelDownloadProgress => _modelDownloadProgress;

  /// Checks whether the model file/folder exists locally.
  Future<bool> checkModelDownloaded() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final modelFolder = Directory('${appDocDir.path}/models/$_modelName');
      if (await modelFolder.exists()) {
        final vocabFile = File('${modelFolder.path}/vocab.json');
        final files = await modelFolder.list().toList();
        _isModelDownloaded = (await vocabFile.exists()) || files.length >= 10;
        return _isModelDownloaded;
      }
    } catch (_) {}
    _isModelDownloaded = false;
    return false;
  }

  /// Downloads the voice model with progress reporting.
  Future<bool> downloadModel({
    void Function(double progress, String status)? onProgress,
  }) async {
    if (_isDownloadingModel) return false;
    _isDownloadingModel = true;
    _modelDownloadProgress = 0.0;
    _errorMessage = null;

    try {
      debugPrint('[WhistleVoice] Starting download for model $_modelName...');
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        final modelFolder = Directory('${appDocDir.path}/models/$_modelName');
        final vocabFile = File('${modelFolder.path}/vocab.json');
        if (await modelFolder.exists() && !(await vocabFile.exists())) {
          await modelFolder.delete(recursive: true);
        }
      } catch (_) {}

      await _stt.downloadModel(
        model: _modelName,
        downloadProcessCallback: (progress, status, isError) {
          final p = progress ?? 0.0;
          _modelDownloadProgress = p;
          onProgress?.call(p, status);
        },
      );

      _isModelDownloaded = true;
      _isDownloadingModel = false;
      await initialize();
      return true;
    } catch (e) {
      debugPrint('[WhistleVoice] Download failed: $e');
      _errorMessage = 'Failed to download voice model: $e';
      _isDownloadingModel = false;
      return false;
    }
  }

  @override
  Future<bool> initialize() async {
    _errorMessage = null;

    // Cactus native library bindings are supported on Android, iOS, and macOS.
    // On other platforms (e.g. Windows desktop), report unavailable gracefully.
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      _errorMessage = 'Whistle local STT engine is only supported on mobile/Android devices.';
      _isAvailable = false;
      return false;
    }

    try {
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        _errorMessage = 'Microphone permission was not granted.';
        _isAvailable = false;
        return false;
      }

      // Check if the voice model exists locally before attempting initialization
      final modelExists = await checkModelDownloaded();
      if (!modelExists) {
        _errorMessage = 'Whistle voice model is not downloaded yet. Please download it in Settings.';
        _isAvailable = false;
        return false;
      }

      // Initialize the Cactus speech-to-text engine with existing local model
      await _stt.initializeModel(
        params: CactusInitParams(model: _modelName),
      );

      _isAvailable = true;
      return true;
    } catch (e) {
      debugPrint('[WhistleVoice] Initialization error: $e');
      _errorMessage = 'Failed to initialize Whistle local speech engine: $e';
      _isAvailable = false;
      return false;
    }
  }

  @override
  Future<bool> startListening({Duration? listenFor}) async {
    if (!_isAvailable) {
      final initOk = await initialize();
      if (!initOk) return false;
    }

    if (_isListening) {
      await stopListening();
    }

    _errorMessage = null;
    _soundLevel = 0.0;
    _speechDetected = false;
    _sessionStartTime = DateTime.now();

    try {
      final tempDir = await getTemporaryDirectory();
      _currentRecordingPath =
          '${tempDir.path}/whistle_${DateTime.now().millisecondsSinceEpoch}.wav';

      const config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      );

      await _recorder.start(config, path: _currentRecordingPath!);
      _isListening = true;

      // Start periodic amplitude monitoring
      _startAmplitudeMonitoring();

      // Set max session duration timer
      final maxDuration = listenFor ?? _defaultListenDuration;
      _maxDurationTimer?.cancel();
      _maxDurationTimer = Timer(maxDuration, () {
        if (_isListening) {
          stopListening();
        }
      });

      return true;
    } catch (e) {
      debugPrint('[WhistleVoice] startListening error: $e');
      _errorMessage = 'Failed to start microphone recording: $e';
      _isListening = false;
      return false;
    }
  }

  void _startAmplitudeMonitoring() {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
      if (!_isListening) return;

      try {
        final amp = await _recorder.getAmplitude();
        final currentDb = amp.current;

        // Convert dBFS (-60 to 0) to a normalized 0.0 .. 1.0 range
        final normalized = ((currentDb + 60.0) / 60.0).clamp(0.0, 1.0);
        _soundLevel = normalized;

        if (currentDb > _silenceThresholdDb) {
          // Voice activity detected
          _speechDetected = true;
          _silenceTimer?.cancel();
          _silenceTimer = null;
        } else if (_speechDetected) {
          // Silence after user was already talking -> arm silence timer
          _silenceTimer ??= Timer(const Duration(milliseconds: 1400), () {
            if (_isListening) {
              stopListening();
            }
          });
        }
      } catch (_) {}
    });
  }

  @override
  Future<String?> stopListening() async {
    if (!_isListening) return null;

    _cleanupTimers();
    _isListening = false;
    _soundLevel = 0.0;

    String? recordedPath;
    try {
      recordedPath = await _recorder.stop();
    } catch (e) {
      debugPrint('[WhistleVoice] Error stopping recorder: $e');
    }

    final targetPath = recordedPath ?? _currentRecordingPath;
    _currentRecordingPath = null;

    if (targetPath == null || !File(targetPath).existsSync()) {
      onListeningEnded?.call();
      return null;
    }

    // Check minimum duration to prevent false triggers on accidental taps
    final startTime = _sessionStartTime;
    if (startTime != null) {
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed < _minListenDuration) {
        _safeDeleteFile(targetPath);
        onListeningEnded?.call();
        return null;
      }
    }

    try {
      debugPrint('[WhistleVoice] Transcribing audio with local engine: $targetPath');
      final result = await _stt.transcribe(
        audioFilePath: targetPath,
      );

      _safeDeleteFile(targetPath);

      if (result.success && result.text.trim().isNotEmpty) {
        final recognized = result.text.trim();
        debugPrint('[WhistleVoice] Recognized: "$recognized"');
        onFinalResult?.call(recognized);
        onListeningEnded?.call();
        return recognized;
      } else {
        debugPrint('[WhistleVoice] Transcription yielded empty or failed result.');
        onListeningEnded?.call();
        return null;
      }
    } catch (e) {
      debugPrint('[WhistleVoice] Transcription error: $e');
      _errorMessage = 'Local speech transcription failed: $e';
      _safeDeleteFile(targetPath);
      onListeningEnded?.call();
      return null;
    }
  }

  @override
  Future<void> cancelListening() async {
    _cleanupTimers();
    _isListening = false;
    _soundLevel = 0.0;

    try {
      final path = await _recorder.stop();
      if (path != null) _safeDeleteFile(path);
      if (_currentRecordingPath != null) _safeDeleteFile(_currentRecordingPath!);
    } catch (_) {}

    _currentRecordingPath = null;
    onListeningEnded?.call();
  }

  @override
  Future<void> dispose() async {
    await cancelListening();
    try {
      _cactusStt?.unload();
    } catch (_) {}
    try {
      await _audioRecorder?.dispose();
    } catch (_) {}
  }

  @override
  Future<void> setLocale(String? localeId) async {
    // Whistle / Cactus handles language configuration or auto-detects multilingual speech.
  }

  void _cleanupTimers() {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
  }

  void _safeDeleteFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
