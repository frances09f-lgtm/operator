import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';
import 'package:friday_app/features/app_launcher/app_launcher_service.dart';
import 'package:friday_app/features/assistant/domain/dialogue_state.dart';
import 'package:friday_app/features/assistant/domain/intent_model.dart';
import 'package:friday_app/features/assistant/domain/intent_parser.dart';
import 'package:friday_app/features/assistant/domain/response_generator.dart';
import 'package:friday_app/features/assistant/domain/sequence_splitter.dart';
import 'package:friday_app/features/device_control/device_control_service.dart';
import 'package:friday_app/features/flashlight/flashlight_service.dart';
import 'package:friday_app/features/media_control/media_control_service.dart';
import 'package:friday_app/features/volume_control/volume_control_service.dart';
import 'package:friday_app/features/brightness_control/brightness_control_service.dart';
import 'package:friday_app/features/alarm/alarm_service.dart';
import 'package:friday_app/features/alarm/alarm_time_parser.dart'
    as alarm_parser;
import 'package:friday_app/features/eyes/eyes_service.dart';
import 'package:friday_app/features/eyes/screen_context_service.dart';
import 'package:friday_app/features/gallery/gallery_service.dart';
import 'package:friday_app/features/youtube/youtube_service.dart';
import 'package:friday_app/features/ai_ask/ai_ask_service.dart';
import 'package:friday_app/features/ai_ask/ai_name_normalizer.dart';
import 'package:friday_app/features/automation/models/custom_command.dart';
import 'package:friday_app/features/automation/services/tap_sequence_storage.dart';
import 'package:friday_app/features/whatsapp/whatsapp_service.dart';
import 'package:friday_app/features/sms/sms_service.dart';
import 'package:friday_app/features/call/call_service.dart';
import 'package:friday_app/features/gmail/gmail_service.dart';
import 'package:friday_app/features/automation/services/automation_service.dart' as auto_svc;
import 'package:friday_app/services/local_llm/local_llm_service.dart';
import 'package:friday_app/services/local_llm/model_downloader.dart';
import 'package:friday_app/services/local_llm/model_manager.dart';
import 'package:friday_app/services/tts/flutter_text_to_speech_service.dart';
import 'package:friday_app/services/tts/language_settings.dart';
import 'package:friday_app/services/tts/text_to_speech_service.dart';
import 'package:friday_app/services/tts/tts_settings.dart';
import 'package:friday_app/services/voice/adaptive_voice_command_service.dart';
import 'package:friday_app/services/voice/speech_to_text_voice_command_service.dart';
import 'package:friday_app/services/voice/voice_command_service.dart';
import 'package:friday_app/services/assist/assist_service.dart';

enum ModelStatus {
  notChecked,
  missing,
  loading,
  ready,
  error,
}

/// High-level state the assistant is in, for UI consumption.
enum AssistantPhase {
  idle,
  listening,
  processing,
  speaking,
  opening,
  error,
}

/// Outcome of one silent step inside an ordered [_executeSequence] run.
class _StepResult {
  final bool success;
  final String message;
  const _StepResult(this.success, this.message);
}

class AssistantController extends ChangeNotifier {
  final LocalLLMService _llmService;
  final IntentParser _intentParser;
  final AppLauncherService _appLauncher;
  final FlashlightService _flashlightService;
  final DeviceControlService _deviceControl;
  final MediaControlService _mediaControl;
  final VolumeControlService _volumeControl;
  final BrightnessControlService _brightnessControl;
  final GalleryService _galleryService;
  final YouTubeService _youTubeService;
  final AiAskService _aiAskService;
  final AlarmService _alarmService;
  final WhatsAppService _whatsAppService;
  final SmsService _smsService;
  final CallService _callService;
  final GmailService _gmailService;
  final auto_svc.AutomationService _automationService;
  final TapSequenceStorage _tapStorage;
  final ModelManager _modelManager;
  final VoiceCommandService _voiceService;
  final ModelDownloader _modelDownloader;
  final AssistService _assistService;
  final TextToSpeechService _tts;
  final ResponseGenerator _responseGenerator;
  final DialogueStateTracker _dialogueTracker;
  final EyesService _eyesService;
  final ScreenContextService _screenContextService;

  ModelStatus _modelStatus = ModelStatus.notChecked;
  String _statusMessage = 'Initializing...';
  String? _loadedModelPath;
  bool _isProcessing = false;
  bool _isListening = false;
  bool _isSpeechAvailable = false;
  bool _isResponding = false;
  bool _isSpeaking = false;
  bool _isOpening = false;
  bool _isDownloadingModel = false;
  double _modelDownloadProgress = 0;
  // ---- Smart chat (big model, on-demand only) ----
  bool _isDownloadingChatModel = false;
  double _chatDownloadProgress = 0;
  bool _isChatLoading = false;
  bool _isChatAvailable = false;
  String? _chatModelPath;
  final List<Map<String, String>> _chatHistory = [];
  String? _streamingReply;
  bool _smartChatCancelRequested = false;
  String? _lastUserCommand;
  String? _liveSpeechText;
  String? _lastRawModelOutput;
  String? _lastProcessingError;

  /// True once a spoken response has been produced for the current command,
  /// guaranteeing exactly one spoken response per user command.
  bool _didSpeakForCommand = false;

  /// Null until the TTS engine has been probed once.
  bool? _ttsAvailable;

  TtsSettings _ttsSettings = const TtsSettings();
  bool _disposed = false;

  /// Currently detected language based on user input.
  AppLanguage _currentLanguage = AppLanguage.english;

  /// True while the UI should render the bottom-bar assist overlay instead
  /// of the full app (long-press power). Kept warm in the same engine so
  /// assist stays fast — no second engine, no model reload.
  bool _assistMode = false;
  bool get isAssistMode => _assistMode;
  bool _isWaitingForAssistIntent = false;

  // Automation / teachable commands
  List<CustomCommand> _customCommands = [];
  String? _lastAutomationResult;
  bool _isExecutingAutomation = false;

  final Duration _respondingDuration;
  final Duration _ttsWaitTimeout;
  final ValueNotifier<double> _soundLevelNotifier = ValueNotifier<double>(0);
  Timer? _levelPoller;
  Timer? _respondingTimer;

  AssistantController({
    required LocalLLMService llmService,
    required IntentParser intentParser,
    required AppLauncherService appLauncher,
    required ModelManager modelManager,
    FlashlightService? flashlightService,
    DeviceControlService? deviceControlService,
    MediaControlService? mediaControlService,
    VolumeControlService? volumeControlService,
    BrightnessControlService? brightnessControlService,
    GalleryService? galleryService,
    YouTubeService? youTubeService,
    AiAskService? aiAskService,
    AlarmService? alarmService,
    WhatsAppService? whatsAppService,
    SmsService? smsService,
    CallService? callService,
    GmailService? gmailService,
    auto_svc.AutomationService? automationService,
    TapSequenceStorage? tapStorage,
    VoiceCommandService? voiceCommandService,
    ModelDownloader? modelDownloader,
    AssistService? assistService,
    TextToSpeechService? ttsService,
    ResponseGenerator? responseGenerator,
    DialogueStateTracker? dialogueStateTracker,
    EyesService? eyesService,
    ScreenContextService? screenContextService,
    Duration respondingDuration = const Duration(milliseconds: 2200),
    Duration ttsWaitTimeout = const Duration(seconds: 10),
  })  : _llmService = llmService,
        _intentParser = intentParser,
        _appLauncher = appLauncher,
        _flashlightService =
            flashlightService ?? MethodChannelFlashlightService(),
        _deviceControl =
            deviceControlService ?? MethodChannelDeviceControlService(),
        _mediaControl =
            mediaControlService ?? MethodChannelMediaControlService(),
        _volumeControl =
            volumeControlService ?? MethodChannelVolumeControlService(),
        _brightnessControl =
            brightnessControlService ?? MethodChannelBrightnessControlService(),
        _galleryService =
            galleryService ?? MethodChannelGalleryService(),
        _youTubeService =
            youTubeService ?? MethodChannelYouTubeService(),
        _aiAskService = aiAskService ?? MethodChannelAiAskService(),
        _alarmService = alarmService ?? MethodChannelAlarmService(),
        _whatsAppService =
            whatsAppService ?? MethodChannelWhatsAppService(),
        _smsService = smsService ?? MethodChannelSmsService(),
        _callService = callService ?? MethodChannelCallService(),
        _gmailService = gmailService ?? GoogleGmailService(),
        _automationService =
            automationService ?? auto_svc.MethodChannelAutomationService(),
        _tapStorage = tapStorage ?? TapSequenceStorage(),
        _modelManager = modelManager,
        _voiceService = voiceCommandService ?? SpeechToTextVoiceCommandService(),
        _modelDownloader =
            modelDownloader ?? ModelDownloader(url: AppConstants.modelDownloadUrl),
        _assistService = assistService ?? AssistService(),
        _tts = ttsService ?? FlutterTextToSpeechService(),
        _responseGenerator = responseGenerator ?? ResponseGenerator(),
        _dialogueTracker = dialogueStateTracker ?? DialogueStateTracker(),
        _eyesService = eyesService ?? EyesService(),
        _screenContextService = screenContextService ??
            ScreenContextService(eyes: eyesService ?? EyesService()),
        _respondingDuration = respondingDuration,
        _ttsWaitTimeout = ttsWaitTimeout;

  DialogueStateTracker get dialogueTracker => _dialogueTracker;
  bool get isAwaitingClarification => _dialogueTracker.isAwaitingClarification;
  ScreenContextService get screenContextService => _screenContextService;

  ModelStatus get modelStatus => _modelStatus;
  String get statusMessage => _statusMessage;
  String? get loadedModelPath => _loadedModelPath;
  bool get isProcessing => _isProcessing;
  bool get isListening => _isListening;
  bool get isSpeechAvailable => _isSpeechAvailable;

  /// True if using the 100% on-device Whistle local STT engine.
  bool get isWhistleEngineActive =>
      _voiceService is AdaptiveVoiceCommandService &&
      _voiceService.activeEngine == VoiceEngineType.whistle;

  /// True if the Whistle voice model is downloaded on device.
  bool get isVoiceModelDownloaded {
    final voice = _voiceService;
    if (voice is AdaptiveVoiceCommandService) {
      return voice.whistleService.isModelDownloaded;
    }
    return true;
  }

  /// True while the Whistle voice model is being downloaded.
  bool get isDownloadingVoiceModel {
    final voice = _voiceService;
    if (voice is AdaptiveVoiceCommandService) {
      return voice.whistleService.isDownloadingModel;
    }
    return false;
  }

  /// Download progress for the Whistle voice model (0.0..1.0).
  double get voiceModelDownloadProgress {
    final voice = _voiceService;
    if (voice is AdaptiveVoiceCommandService) {
      return voice.whistleService.modelDownloadProgress;
    }
    return 0.0;
  }

  /// Initiates download of the Whistle local voice model.
  Future<void> downloadVoiceModel() async {
    final voice = _voiceService;
    if (voice is AdaptiveVoiceCommandService) {
      notifyListeners();
      await voice.whistleService.downloadModel(
        onProgress: (progress, status) {
          notifyListeners();
        },
      );
      _isSpeechAvailable = voice.isAvailable;
      notifyListeners();
    }
  }

  /// Checks if the Whistle model is available on-disk.
  Future<void> checkVoiceModelStatus() async {
    final voice = _voiceService;
    if (voice is AdaptiveVoiceCommandService) {
      await voice.whistleService.checkModelDownloaded();
      notifyListeners();
    }
  }

  /// Sets the active speech engine (Whistle on-device STT vs system SpeechRecognizer).
  Future<void> setVoiceEngine(VoiceEngineType engine) async {
    final voice = _voiceService;
    if (voice is AdaptiveVoiceCommandService) {
      await voice.setEngine(engine);
      _isSpeechAvailable = voice.isAvailable;
      notifyListeners();
    }
  }

  /// Switches between Whistle on-device STT and system SpeechRecognizer.
  Future<void> toggleVoiceEngine() async {
    final voice = _voiceService;
    if (voice is AdaptiveVoiceCommandService) {
      final target = voice.activeEngine == VoiceEngineType.whistle
          ? VoiceEngineType.systemSpeech
          : VoiceEngineType.whistle;
      await voice.setEngine(target);
      _isSpeechAvailable = voice.isAvailable;
      notifyListeners();
    }
  }

  /// True during a short window after a reply has been produced, signaling
  /// the assistant is "speaking" so the UI can animate accordingly.
  bool get isResponding => _isResponding;

  /// True while the TTS engine is actually producing audio.
  bool get isSpeaking => _isSpeaking;

  /// True while a validated app is being opened after its response.
  bool get isOpening => _isOpening;

  /// True while the AI model is being downloaded in the background.
  bool get isDownloadingModel => _isDownloadingModel;

  /// Download progress for the AI model, 0.0..1.0.
  double get modelDownloadProgress => _modelDownloadProgress;

  // ---- Smart chat getters (big model stays unloaded until needed) ----
  bool get isDownloadingChatModel => _isDownloadingChatModel;
  double get chatDownloadProgress => _chatDownloadProgress;
  bool get isChatLoading => _isChatLoading;
  bool get isChatAvailable => _isChatAvailable;
  String? get streamingReply => _streamingReply;
  List<Map<String, String>> get chatHistory =>
      List.unmodifiable(_chatHistory);

  String? get lastUserCommand => _lastUserCommand;

  /// Live transcript of what the user is saying during the ongoing speech recognition session.
  String? get liveSpeechText => _liveSpeechText;

  /// Live mic level (0.0–1.0) while listening. Feed this to voice-reactive
  /// visuals; it updates at a high rate without spamming [ChangeNotifier].
  ValueNotifier<double> get soundLevel => _soundLevelNotifier;

  /// Raw output produced by the local model for the last command.
  String? get lastRawModelOutput => _lastRawModelOutput;

  /// Human-readable failure detail from the last command, if any.
  String? get lastProcessingError => _lastProcessingError;

  // ---- TTS settings ----

  bool get isTtsEnabled => _ttsSettings.enabled;

  double get ttsSpeechRate => _ttsSettings.speechRate;

  String? get ttsLanguage => _ttsSettings.language;

  /// Last Gmail failure detail (HTTP status / Google reason codes). Shown in
  /// the Gmail card so a failed connect is never a mystery.
  String? _gmailLastError;

  String? get gmailLastError => _gmailLastError;

  // ---- Volume / brightness step settings (in-memory, percent 1-30) ----
  //
  // Applied when the user says "increase/decrease volume/brightness" without
  // an explicit level. Configurable from Settings; defaults to 5%.

  int _volumeStep = 5;
  int _brightnessStep = 5;

  int get volumeStep => _volumeStep;
  int get brightnessStep => _brightnessStep;

  void setVolumeStep(int value) {
    _volumeStep = value.clamp(1, 30);
    notifyListeners();
  }

  void setBrightnessStep(int value) {
    _brightnessStep = value.clamp(1, 30);
    notifyListeners();
  }

  // Automation getters
  List<CustomCommand> get customCommands => List.unmodifiable(_customCommands);
  String? get lastAutomationResult => _lastAutomationResult;
  bool get isExecutingAutomation => _isExecutingAutomation;

  // Gmail getters (read-only Phase 1, background — no Gmail app opened)
  bool _isGmailConnected = false;
  bool _isConnectingGmail = false;
  List<EmailMessage> _lastEmails = const [];
  bool get isGmailConnected => _isGmailConnected;
  bool get isConnectingGmail => _isConnectingGmail;
  List<EmailMessage> get lastEmails => List.unmodifiable(_lastEmails);

  /// Current [AssistantPhase] derived from the controller's internal state.
  AssistantPhase get phase {
    if (_isOpening) return AssistantPhase.opening;
    if (_isSpeaking) return AssistantPhase.speaking;
    if (_isProcessing) return AssistantPhase.processing;
    if (_isListening) return AssistantPhase.listening;
    if (_modelStatus == ModelStatus.missing ||
        _modelStatus == ModelStatus.error) {
      return AssistantPhase.error;
    }
    return AssistantPhase.idle;
  }

  void setTtsEnabled(bool value) {
    _ttsSettings = _ttsSettings.copyWith(enabled: value);
    notifyListeners();
  }

  void setTtsSpeechRate(double value) {
    _ttsSettings =
        _ttsSettings.copyWith(speechRate: value.clamp(0.1, 1.0));
    notifyListeners();
  }

  /// Stops any utterance the TTS engine is currently producing.
  Future<void> stopSpeaking() => _stopSpeaking();

  /// Initializes the local model by checking storage paths and loading it once.
  /// Prefers the small fast command model so device actions stay instant.
  Future<void> initializeModel() async {
    _modelStatus = ModelStatus.loading;
    _statusMessage = 'Looking for local AI model...';
    notifyListeners();

    try {
      final modelPath = await _modelManager.findCommandModelPath() ??
          await _modelManager.findModelPath();
      if (modelPath == null) {
        _modelStatus = ModelStatus.missing;
        _statusMessage = 'The local AI model isn\'t available.';
        notifyListeners();
        return;
      }

      _statusMessage = 'Loading local AI model...';
      notifyListeners();

      await _llmService.loadCommandModel(modelPath);
      _loadedModelPath = modelPath;
      _modelStatus = ModelStatus.ready;
      _statusMessage = 'Ready';
      notifyListeners();
      // Probe smart-model availability without loading it (stays unloaded).
      unawaited(checkSmartModelAvailable());
    } catch (e) {
      _modelStatus = ModelStatus.error;
      _statusMessage = 'The local AI model isn\'t available.';
      notifyListeners();
    }
  }

  /// Downloads the default model into app storage and loads it.
  ///
  /// Coarse progress is exposed through [modelDownloadProgress]. This lets
  /// the app be set up without manually copying a .gguf to the device.
  Future<void> downloadModel() async {
    if (_isDownloadingModel || _isProcessing) return;

    _isDownloadingModel = true;
    _modelDownloadProgress = 0;
    _statusMessage = 'Downloading AI model...';
    notifyListeners();

    try {
      final destination = await _modelManager.getPrimaryModelPath();
      await _modelDownloader.downloadTo(
        destinationPath: destination,
        onProgress: (progress) {
          // Throttle UI updates to whole-percent steps.
          if ((progress * 100).round() != (_modelDownloadProgress * 100).round()) {
            _modelDownloadProgress = progress;
            _statusMessage =
                'Downloading AI model... ${(progress * 100).round()}%';
            notifyListeners();
          }
        },
      );

      _modelDownloadProgress = 1;
      _statusMessage = 'Download complete. Loading model...';
      notifyListeners();

      await initializeModel();
    } on AppException catch (e) {
      _statusMessage = e.message;
    } catch (_) {
      _statusMessage = 'Download failed. Check your connection and try again.';
    } finally {
      _isDownloadingModel = false;
      notifyListeners();
    }
  }

  /// Checks whether the big smart-chat model file exists (without loading it).
  Future<bool> checkSmartModelAvailable() async {
    try {
      _chatModelPath = await _modelManager.findChatModelPath();
      _isChatAvailable = _chatModelPath != null;
      notifyListeners();
      return _isChatAvailable;
    } catch (_) {
      _isChatAvailable = false;
      return false;
    }
  }

  /// Downloads the big smart-chat model (~1GB). Does NOT load it — it stays
  /// on disk until a question actually needs it.
  Future<void> downloadChatModel() async {
    if (_isDownloadingChatModel || _isChatLoading) return;
    _isDownloadingChatModel = true;
    _chatDownloadProgress = 0;
    _statusMessage = 'Downloading smart model... 0%';
    notifyListeners();
    try {
      final destination = await _modelManager.getPrimaryChatModelPath();
      final downloader =
          ModelDownloader(url: AppConstants.chatModelDownloadUrl);
      await downloader.downloadTo(
        destinationPath: destination,
        onProgress: (p) {
          if ((p * 100).round() != (_chatDownloadProgress * 100).round()) {
            _chatDownloadProgress = p;
            _statusMessage =
                'Downloading smart model... ${(p * 100).round()}%';
            notifyListeners();
          }
        },
      );
      _chatDownloadProgress = 1;
      _chatModelPath = destination;
      _isChatAvailable = true;
      _statusMessage = 'Smart model ready. Ask me anything.';
      notifyListeners();
    } on AppException catch (e) {
      _statusMessage = e.message;
      notifyListeners();
    } catch (_) {
      _statusMessage = 'Smart model download failed. Check connection.';
      notifyListeners();
    } finally {
      _isDownloadingChatModel = false;
      notifyListeners();
    }
  }

  /// Cancels a pending smart-chat load/answer. Commands remain usable.
  void cancelSmartChat() {
    _smartChatCancelRequested = true;
    try {
      _llmService.unload();
    } catch (_) {}
  }

  void clearChatHistory() {
    _chatHistory.clear();
    _streamingReply = null;
    notifyListeners();
  }

  /// Routes an open question to the big smart chat model (Qwen), then swaps
  /// back to the small fast model so the NEXT command stays instant.
  Future<void> _handleSmartChat(String question) async {
    final q = question.trim();
    if (q.isEmpty) return;

    _chatModelPath ??= await _modelManager.findChatModelPath();
    if (_chatModelPath == null) {
      _statusMessage =
          'Smart model not downloaded. Tap "Download Smart Model" (~1GB) for ChatGPT-like answers.';
      notifyListeners();
      await _speakResponse(_statusMessage);
      return;
    }
    _smartChatCancelRequested = false;
    _isChatLoading = true;
    _streamingReply = '';
    _statusMessage = 'Switching to smart mode...';
    notifyListeners();
    final commandPath = _loadedModelPath;
    try {
      await _llmService.loadChatModel(_chatModelPath!);
      if (_smartChatCancelRequested) return;
      _isChatLoading = false;
      _statusMessage = 'Thinking (smart mode)...';
      notifyListeners();
      final reply = await _llmService.chat(
        q,
        history: _chatHistory,
        onToken: (t) {
          _streamingReply = (_streamingReply ?? '') + t;
          notifyListeners();
        },
      );
      if (_smartChatCancelRequested) return;
      _chatHistory.add({'role': 'user', 'text': q});
      _chatHistory.add({'role': 'assistant', 'text': reply});
      if (_chatHistory.length > 20) {
        _chatHistory.removeRange(0, _chatHistory.length - 20);
      }
      _dialogueTracker.recordTurn(role: 'user', utterance: q);
      _dialogueTracker.recordTurn(role: 'assistant', utterance: reply);
      _streamingReply = null;
      final clean = _responseGenerator.chat(reply);
      _statusMessage = clean;
      notifyListeners();
      await _speakResponse(clean);
    } on AppException catch (e) {
      _lastProcessingError = e.message;
      if (e is InvalidIntentException) {
        _statusMessage = 'Smart chat had trouble replying. Please try again.';
      } else {
        _statusMessage = _messageForException(e);
      }
      notifyListeners();
      await _speakResponse(_statusMessage);
    } catch (e) {
      _lastProcessingError = '$e';
      _statusMessage = 'Smart chat failed. Please try again.';
      notifyListeners();
      await _speakResponse(_statusMessage);
    } finally {
      _isChatLoading = false;
      _streamingReply = null;
      notifyListeners();
      try {
        final backTo =
            commandPath ?? await _modelManager.findCommandModelPath();
        if (backTo != null && !_smartChatCancelRequested) {
          unawaited(_llmService.loadCommandModel(backTo).then((_) {
            _loadedModelPath = backTo;
            if (!_disposed) notifyListeners();
          }));
        }
      } catch (_) {}
    }
  }

  /// Initializes speech recognition and configures the voice result handler.
  /// Safe to call during app startup; it becomes a no-op fallback on
  /// platforms without a working speech recognizer.
  Future<void> initializeSpeech() async {
    _voiceService.onPartialResult = _handlePartialVoiceResult;
    _voiceService.onFinalResult = _handleVoiceResult;
    _voiceService.onListeningEnded = _handleVoiceSessionEnded;

    final available = await _voiceService.initialize();
    if (!available) {
      _isSpeechAvailable = false;
      _statusMessage = 'Voice input is not available on this device.';
      notifyListeners();
      return;
    }

    _isSpeechAvailable = true;
    await checkVoiceModelStatus();
    if (_modelStatus == ModelStatus.ready) {
      _statusMessage = 'Ready';
    }
    notifyListeners();
  }

  /// Changes the assistant language and updates TTS and speech recognition.
  Future<void> setLanguage(AppLanguage language) async {
    _currentLanguage = language;
    await _voiceService.setLocale(language.locale);
    if (_ttsSettings.enabled) {
      await _tts.setLanguage(language.locale);
    }
    notifyListeners();
  }

  /// Initializes the local TTS engine without speaking anything. Safe to call
  /// during app startup.
  Future<void> initializeTts() async {
    _tts.onCompletion = _handleTtsCompletion;
    _ttsAvailable = await _tts.initialize();
  }

  /// Loads teachable custom commands from storage.
  Future<void> initializeAutomation() async {
    try {
      _customCommands = await _tapStorage.loadAll();
      notifyListeners();
    } catch (_) {}
  }

  /// Wires ACTION_ASSIST (long-press power) auto-listen.
  ///
  /// Call once during app startup. If the app was cold-started via assist,
  /// consumes the native flag, switches to overlay mode and starts listening
  /// once speech/model are ready. Also handles warm-start assist while the
  /// app is already alive (same warm engine — no reload, stays fast).
  Future<void> initializeAssist() async {
    try {
      _assistService.setAssistHandlers(
        onAssist: _enterAssistMode,
        onLauncherOpen: exitAssistMode,
      );
      final launched = await _assistService.consumeAssistLaunch();
      if (launched) {
        _enterAssistMode();
      }
    } catch (_) {}
  }

  /// Enters assist mode explicitly (e.g. cold start via ACTION_ASSIST).
  void enterAssistMode() => _enterAssistMode();

  void _enterAssistMode() {
    if (_assistMode && (_isListening || _isProcessing || _isWaitingForAssistIntent)) return;
    _assistMode = true;
    notifyListeners();
    // Don't await: speech/model init may still be in flight.
    unawaited(_onAssistIntent());
  }

  /// Leaves overlay mode (overlay close calls this, then backgrounds the
  /// task so the engine stays warm for the next long-press).
  void exitAssistMode() {
    _assistMode = false;
    _liveSpeechText = null;
    _isWaitingForAssistIntent = false;
    try {
      unawaited(_assistService.clearAssistLaunch());
    } catch (_) {}
    if (_isListening) {
      unawaited(_voiceService.cancelListening());
      _isListening = false;
      _stopLevelPoller();
    }
    if (_isSpeaking) {
      _isSpeaking = false;
      unawaited(_tts.stop());
    }
    notifyListeners();
  }

  /// Starts listening for an assist invocation, waiting briefly for speech
  /// and model init to finish (cold overlay start). Safe to call multiple
  /// times; no-ops while busy.
  Future<void> _onAssistIntent() async {
    if (_isWaitingForAssistIntent) return;
    _isWaitingForAssistIntent = true;
    try {
      if (_isSpeechAvailable && !_isListening && !_isProcessing && _assistMode) {
        await toggleListening();
        return;
      }
      for (var i = 0; i < 40; i++) {
        if (_disposed || !_assistMode) return;
        if (_isListening || _isProcessing) return;
        if (_isSpeechAvailable) {
          if (!_isListening && !_isProcessing && _assistMode) {
            await toggleListening();
          }
          return;
        }
        await Future.delayed(const Duration(milliseconds: 40));
      }
    } finally {
      _isWaitingForAssistIntent = false;
    }
  }

  Future<void> refreshCustomCommands() async {
    _customCommands = await _tapStorage.loadAll();
    notifyListeners();
  }

  Future<void> saveCustomCommand(CustomCommand command) async {
    await _tapStorage.save(command);
    await refreshCustomCommands();
  }

  Future<void> deleteCustomCommand(String id) async {
    await _tapStorage.delete(id);
    await refreshCustomCommands();
  }

  Future<CustomCommandMatch?> findCustomCommandMatch(String input) async {
    // Use in-memory cache if available, else storage
    if (_customCommands.isNotEmpty) {
      for (final cmd in _customCommands) {
        final params = cmd.match(input);
        if (params != null) {
          return CustomCommandMatch(command: cmd, params: params, score: 100);
        }
      }
    }
    return _tapStorage.findBestMatch(input);
  }

  Future<bool> isAutomationAvailable() async {
    try {
      return await _automationService.isAccessibilityEnabled();
    } catch (_) {
      return false;
    }
  }

  Future<void> requestAutomationPermissions() async {
    try {
      await _automationService.requestAccessibilitySettings();
    } catch (_) {}
  }

  /// Receives real-time partial speech recognition results as the user speaks.
  void _handlePartialVoiceResult(String partialText) {
    final text = partialText.trim();
    if (text.isNotEmpty && _liveSpeechText != text) {
      _liveSpeechText = text;
      notifyListeners();
    }
  }

  /// Resets listening state when the platform closes a session on its own.
  void _handleVoiceSessionEnded() {
    _isListening = _voiceService.isListening;
    _stopLevelPoller();
    if (!_isListening && !_isProcessing) {
      final error = _voiceService.errorMessage;
      if (error != null) {
        _statusMessage = error;
      }
    }
    notifyListeners();
  }

  /// Toggles voice listening. When stopped with recognized speech, the
  /// captured command is processed automatically.
  Future<void> toggleListening() async {
    if (_isProcessing) return;

    if (_isListening) {
      await _voiceService.stopListening();
      _isListening = _voiceService.isListening;
      _stopLevelPoller();
      notifyListeners();
      return;
    }

    if (!_isSpeechAvailable) {
      _statusMessage = 'Voice input is not available on this device.';
      notifyListeners();
      return;
    }

    await _startCommandListening();
  }

  /// Starts a command-listening session and reports whether it began.
  Future<bool> _startCommandListening() async {
    _liveSpeechText = null;
    final started = await _voiceService.startListening();
    if (!started) {
      _isListening = false;
      _statusMessage = _voiceService.errorMessage ?? 'Could not start the microphone.';
      notifyListeners();
      return false;
    }

    _isListening = true;
    _statusMessage = 'Listening... speak your command';
    _startLevelPoller();
    notifyListeners();
    return true;
  }

  void _startLevelPoller() {
    _stopLevelPoller();
    _levelPoller = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final level = _voiceService.soundLevel;
      if (_soundLevelNotifier.value != level) {
        _soundLevelNotifier.value = level;
      }
    });
  }

  void _stopLevelPoller() {
    _levelPoller?.cancel();
    _levelPoller = null;
    if (_soundLevelNotifier.value != 0) {
      _soundLevelNotifier.value = 0;
    }
  }

  /// Processes a finalized voice input through the same pipeline as typed input.
  Future<void> _handleVoiceResult(String recognizedText) async {
    // STT often mishears AI names ("deepsik", "lipstik") — fix before anything
    // else sees the text so heuristics + LLM both get canonical spelling.
    final text = normalizeAiTranscript(recognizedText.trim());
    _liveSpeechText = text;
    // The platform session is over once a final result arrives.
    _isListening = false;
    _stopLevelPoller();

    if (text.isEmpty) {
      final message = _responseGenerator.emptyInput();
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
      return;
    }

    _currentLanguage = detectLanguage(text);
    _statusMessage = 'You said "$text"';
    notifyListeners();

    await processCommand(text);
  }

  /// Processes a typed user command through the full pipeline:
  /// User Input -> Local LLM -> Structured Intent -> Validation -> Response -> TTS -> Action
  Future<void> processCommand(String rawInput) async {
    // Same STT fix for typed/pasted commands and for tests calling this
    // directly with misheard text.
    final trimmed = normalizeAiTranscript(rawInput.trim());
    _lastUserCommand = trimmed;
    _lastRawModelOutput = null;
    _lastProcessingError = null;
    _didSpeakForCommand = false;
    // Detect language from input for TTS language selection.
    _currentLanguage = detectLanguage(trimmed);

    // Stop any utterance still playing from a previous command. Only awaits
    // when something is actually speaking, so isProcessing below is set
    // synchronously (a processing command must be visible immediately).
    if (_isSpeaking) {
      _isSpeaking = false;
      await _tts.stop();
    }

    // 1. Validate empty command
    if (trimmed.isEmpty) {
      final message = _responseGenerator.emptyInput();
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
      return;
    }

    // Check if user is replying to an active clarification question
    if (_dialogueTracker.isAwaitingClarification) {
      final resolvedFromClarification =
          _dialogueTracker.tryResolveClarification(trimmed);
      if (resolvedFromClarification != null) {
        _isProcessing = true;
        _statusMessage = 'Thinking...';
        notifyListeners();
        try {
          await _dispatchIntent(resolvedFromClarification);
          _lastProcessingError = null;
        } catch (err) {
          if (err is AppException) {
            _lastProcessingError = err.message;
            final message = _messageForException(err);
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          } else {
            _lastProcessingError = '$err';
            final message = _responseGenerator.cannotUnderstand();
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          }
        } finally {
          _isProcessing = false;
          _isOpening = false;
          _startRespondingWindow();
          notifyListeners();
        }
        return;
      }
    }

    // Resolve pronouns and contextual references using short-term entity memory
    final effectiveInput = _dialogueTracker.resolveContext(trimmed);

    _isProcessing = true;
    _statusMessage = 'Thinking...';
    notifyListeners();

    // 2a. Custom teachable command fast-path: heuristic match before LLM to support user-created phrases offline
    // This await is after isProcessing=true so toggleListening is correctly blocked (test contract).
    try {
      final customMatch = await findCustomCommandMatch(effectiveInput);
      if (customMatch != null) {
        _statusMessage = 'Running ${customMatch.command.displayName}...';
        notifyListeners();
        try {
          await _handleCustomCommand(customMatch.command.phraseTemplate, customMatch.params, customMatch.command.id);
        } finally {
          _isProcessing = false;
          _isOpening = false;
          _startRespondingWindow();
          notifyListeners();
        }
        return;
      }
    } catch (_) {}
    // isProcessing already true, status remains Thinking... for LLM path

    // 2b. Offline conversational fast-path: greetings / small-talk answer
    // instantly without any LLM call, even when the model is missing.
    final chatKind = heuristicChatKind(effectiveInput);
    if (chatKind != null) {
      try {
        await _handleChat(_responseGenerator.chatForKind(chatKind));
      } finally {
        _isProcessing = false;
        _isOpening = false;
        _startRespondingWindow();
        notifyListeners();
      }
      return;
    }

    // 2b2. Alarm/reminder fast-path (offline, no LLM): "set an alarm for
    // 7am", "remind me in 10 minutes", "show my alarms", "cancel alarms".
    // Runs before the model check so alarms work instantly even when the
    // model is missing/loading — key for the "very fast" requirement.
    final alarmHeuristic = _parseAlarmHeuristic(effectiveInput);
    if (alarmHeuristic != null) {
      try {
        await _dispatchIntent(alarmHeuristic);
        _lastProcessingError = null;
      } catch (err) {
        if (err is AppException) {
          _lastProcessingError = err.message;
          final message = _messageForException(err);
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        } else {
          _lastProcessingError = '$err';
          final message = _responseGenerator.alarmFailed();
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        }
      } finally {
        _isProcessing = false;
        _isOpening = false;
        _startRespondingWindow();
        notifyListeners();
      }
      return;
    }
    // Alarm-like input with no usable time/message: guide the user
    // instantly (offline) instead of waiting on the LLM.
    final alarmHint = _alarmMissingInfoHint(effectiveInput);
    if (alarmHint != null) {
      try {
        _statusMessage = alarmHint;
        notifyListeners();
        await _speakResponse(alarmHint);
      } finally {
        _isProcessing = false;
        _isOpening = false;
        _startRespondingWindow();
        notifyListeners();
      }
      return;
    }

    // 2b3. Email fast-path (no LLM): "read my mails", "check inbox",
    // "show unread mails". Runs before model check so inbox works even when
    // model is missing — Gmail itself still needs internet.
    final emailHeuristic = _parseEmailHeuristic(effectiveInput);
    if (emailHeuristic != null) {
      try {
        await _dispatchIntent(emailHeuristic);
        _lastProcessingError = null;
      } catch (err) {
        if (err is AppException) {
          _lastProcessingError = err.message;
          final message = _messageForException(err);
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        } else {
          _lastProcessingError = '$err';
          final message = _responseGenerator.gmailFailed();
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        }
      } finally {
        _isProcessing = false;
        _isOpening = false;
        _startRespondingWindow();
        notifyListeners();
      }
      return;
    }

    // 2b4. Volume/brightness fast-path (offline, no LLM): "set volume to 15",
    // "volume up", "mute", "set brightness to 80". Runs before the model
    // check so absolute levels are exact even when the small model mishears
    // numbers. Narrow guard only (number or explicit up/down/mute) so open
    // questions like "what is the volume of a sphere?" still go to smart chat.
    // Compound inputs ("open whatsapp, set volume...") are left to the
    // sequence path below so ordering is preserved.
    if (splitIntoSteps(effectiveInput).length == 1) {
      final fastVolume = _explicitVolumeHeuristic(effectiveInput);
      final fastBrightness =
          fastVolume == null ? _explicitBrightnessHeuristic(effectiveInput) : null;
      final fastIntent = fastVolume ?? fastBrightness;
      if (fastIntent != null) {
        try {
          await _dispatchIntent(fastIntent);
          _lastProcessingError = null;
        } catch (err) {
          if (err is AppException) {
            _lastProcessingError = err.message;
            final message = _messageForException(err);
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          } else {
            _lastProcessingError = '$err';
            final message = fastIntent is BrightnessIntent
                ? _responseGenerator.brightnessControlFailed()
                : _responseGenerator.volumeControlFailed();
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          }
        } finally {
          _isProcessing = false;
          _isOpening = false;
          _startRespondingWindow();
          notifyListeners();
        }
        return;
      }
    }

    // 2b5. Flashlight/wifi/bluetooth fast-path (offline, no LLM):
    // "turn on flashlight", "turn on wifi", "turn off bluetooth".
    // Runs before the model check so these stay instant even when the
    // small model is slow or hallucinates (e.g. flashlight misclassified
    // as open_app "game assistant"). Compound inputs are left to the
    // sequence path below.
    if (splitIntoSteps(effectiveInput).length == 1) {
      final fastDevice = _explicitDeviceHeuristic(effectiveInput);
      if (fastDevice != null) {
        try {
          await _dispatchIntent(fastDevice);
          _lastProcessingError = null;
        } catch (err) {
          if (err is AppException) {
            _lastProcessingError = err.message;
            final message = _messageForException(err);
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          } else {
            _lastProcessingError = '$err';
            final message = _responseGenerator.cannotUnderstand();
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          }
        } finally {
          _isProcessing = false;
          _isOpening = false;
          _startRespondingWindow();
          notifyListeners();
        }
        return;
      }
    }

    // 2b6. SMS / FO AI command fast-path (offline, no LLM):
    // "ask FO to call mom", "tell FO to check order", "send sms to FO".
    // Runs before the model check so FO messaging is instant.
    if (splitIntoSteps(effectiveInput).length == 1) {
      final fastSms = _parseSmsHeuristic(effectiveInput);
      if (fastSms != null) {
        try {
          await _dispatchIntent(fastSms);
          _lastProcessingError = null;
        } catch (err) {
          if (err is AppException) {
            _lastProcessingError = err.message;
            final message = _messageForException(err);
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          } else {
            _lastProcessingError = '$err';
            final message = _responseGenerator.smsFailed();
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          }
        } finally {
          _isProcessing = false;
          _isOpening = false;
          _startRespondingWindow();
          notifyListeners();
        }
        return;
      }
    }

    // 2b7. Screen context fast-path: "what's on my screen", "summarize page", "call number on screen".
    if (splitIntoSteps(effectiveInput).length == 1) {
      final fastScreen = _parseScreenContextHeuristic(effectiveInput);
      if (fastScreen != null) {
        try {
          await _dispatchIntent(fastScreen);
          _lastProcessingError = null;
        } catch (err) {
          _lastProcessingError = '$err';
          final message = 'Could not analyze screen content.';
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        } finally {
          _isProcessing = false;
          _isOpening = false;
          _startRespondingWindow();
          notifyListeners();
        }
        return;
      }
    }

    // 2b8. WhatsApp / Call fast-path (offline): "send whatsapp to mom", "call rahul".
    if (splitIntoSteps(effectiveInput).length == 1) {
      final fastWhatsApp = _parseWhatsAppHeuristic(effectiveInput);
      final fastCall = fastWhatsApp == null && _looksLikeCallCommand(effectiveInput.toLowerCase())
          ? _parseCallHeuristic(effectiveInput)
          : null;
      final commsIntent = fastWhatsApp ?? fastCall;
      if (commsIntent != null) {
        try {
          await _dispatchIntent(commsIntent);
          _lastProcessingError = null;
        } catch (err) {
          if (err is AppException) {
            _lastProcessingError = err.message;
            final message = _messageForException(err);
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          } else {
            _lastProcessingError = '$err';
            final message = commsIntent is SendWhatsAppIntent
                ? _responseGenerator.whatsAppFailed()
                : _responseGenerator.callFailed();
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          }
        } finally {
          _isProcessing = false;
          _isOpening = false;
          _startRespondingWindow();
          notifyListeners();
        }
        return;
      }
    }

    // 2c. Validate model availability (chat/alarms/email/volume/device/comms/screen handled offline above).
    if (_modelStatus != ModelStatus.ready || !_llmService.isReady) {
      final message = _responseGenerator.modelUnavailable();
      _statusMessage = message;
      _isProcessing = false;
      _isOpening = false;
      notifyListeners();
      await _speakResponse(message);
      _startRespondingWindow();
      notifyListeners();
      return;
    }

    try {
      // 3a. Compound fast-path: "open whatsapp, set volume to 40%, set
      // brightness to 30%" must run one-by-one in order. Splitting locally
      // first keeps this fast + offline (heuristics cover open/volume/
      // brightness without extra LLM calls). Falls through to single-task
      // LLM path when only one step is detected.
      final stepTexts = splitIntoSteps(effectiveInput);
      if (stepTexts.length >= 2) {
        await _handleCompoundCommand(stepTexts, effectiveInput);
        return;
      }

      // 3. Local LLM generates structured intent
      final rawResponse = await _llmService.infer(effectiveInput);
      _lastRawModelOutput = rawResponse;

      // 4. Intent Parser validates the schema and action
      final intent = _intentParser.parse(rawResponse);

      // Execute via _dispatchIntent so clarifications & dialogue turns are tracked uniformly.
      await _dispatchIntent(intent);
    } on InvalidIntentException catch (e) {
      // Heuristic fallback for "couldn't understand" which is common
      // for small-model drift on whatsapp / stop music / flash / open_app.
      // For open_app we only rescue when LLM output at least looked like JSON
      // (contains '{') — otherwise garbage like "Non-JSON garbage" must stay
      // as cannotUnderstand to preserve test contract.
      // Compound commands ("open whatsapp, set volume...") are rescued as an
      // ordered sequence first.
      final seqSteps = splitIntoSteps(trimmed);
      if (seqSteps.length >= 2) {
        final seq = _heuristicSequence(seqSteps);
        if (seq != null) {
          try {
            await _executeSequence(seq);
            _lastProcessingError = null;
            return;
          } catch (err) {
            if (err is AppException) {
              _lastProcessingError = err.message;
              final message = _messageForException(err);
              _statusMessage = message;
              notifyListeners();
              await _speakResponse(message);
            } else {
              _lastProcessingError = e.message;
              final message = _messageForException(e);
              _statusMessage = message;
              notifyListeners();
              await _speakResponse(message);
            }
            return;
          }
        }
      }
      var heuristic = _heuristicIntent(trimmed);
      if (heuristic is OpenAppIntent &&
          _lastRawModelOutput != null &&
          !_lastRawModelOutput!.contains('{')) {
        heuristic = null;
      }
      if (heuristic != null) {
        try {
          await _dispatchIntent(heuristic);
          // Clear the processing error since we recovered.
          _lastProcessingError = null;
        } catch (err) {
          // If heuristic dispatch itself throws (e.g. contact not found),
          // surface its real message instead of generic Invalid
          if (err is AppException) {
            _lastProcessingError = err.message;
            final message = _messageForException(err);
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          } else {
            _lastProcessingError = e.message;
            final message = _messageForException(e);
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          }
        }
      } else {
        // Conversational rescue: greeting mis-parsed as invalid JSON still
        // gets a friendly reply instead of "couldn't understand".
        final chatKind = heuristicChatKind(trimmed);
        if (chatKind != null) {
          await _handleChat(_responseGenerator.chatForKind(chatKind));
          _lastProcessingError = null;
        } else if (_looksLikeOpenQuestion(trimmed)) {
          // Small model emitted non-JSON garbage for an open question
          // ("explain gravity") — route to the big smart model instead
          // of a dead-end "couldn't understand".
          await _handleSmartChat(trimmed);
          _lastProcessingError = null;
        } else {
          _lastProcessingError = e.message;
          final message = _messageForException(e);
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        }
      }
    } on AppException catch (e) {
      // Heuristic rescue for UnsupportedActionException when user meant whatsapp
      // / open_app / gallery / youtube but LLM emitted "send_message" etc.
      // Only rescue safe action types to preserve security tests for invented
      // media actions like media_volume_up / execute_shell which must remain rejected.
      // Compound inputs are rescued as ordered sequences first.
      if (e is UnsupportedActionException) {
        final seqSteps = splitIntoSteps(trimmed);
        if (seqSteps.length >= 2) {
          final seq = _heuristicSequence(seqSteps);
          if (seq != null &&
              seq.every((s) =>
                  s is SendWhatsAppIntent ||
                  s is CallIntent ||
                  s is OpenAppIntent ||
                  s is PlayGalleryVideoIntent ||
                  s is YouTubeSearchPlayIntent ||
                  s is AiAskIntent ||
                  s is VolumeIntent ||
                  s is BrightnessIntent ||
                  s is ToggleFlashlightIntent ||
                  s is ToggleDeviceIntent ||
                  s is SetAlarmIntent ||
                  s is SetReminderIntent ||
                  s is ListAlarmsIntent ||
                  s is CancelAlarmIntent ||
                  s is ReadEmailIntent ||
                  s is MediaIntent)) {
            try {
              await _executeSequence(seq);
              _lastProcessingError = null;
              return;
            } catch (err) {
              if (err is AppException) {
                _lastProcessingError = err.message;
                final message = _messageForException(err);
                _statusMessage = message;
                notifyListeners();
                await _speakResponse(message);
                return;
              }
            }
          }
        }
        final heuristic = _heuristicIntent(trimmed);
        if (heuristic != null &&
            (heuristic is SendWhatsAppIntent ||
                heuristic is CallIntent ||
                heuristic is OpenAppIntent ||
                heuristic is PlayGalleryVideoIntent ||
                heuristic is YouTubeSearchPlayIntent ||
                heuristic is AiAskIntent ||
                heuristic is SetAlarmIntent ||
                heuristic is SetReminderIntent ||
                heuristic is ListAlarmsIntent ||
                heuristic is CancelAlarmIntent ||
                heuristic is ReadEmailIntent)) {
          try {
            await _dispatchIntent(heuristic);
            _lastProcessingError = null;
            return;
          } catch (err) {
            if (err is AppException) {
              _lastProcessingError = err.message;
              final message = _messageForException(err);
              _statusMessage = message;
              notifyListeners();
              await _speakResponse(message);
              return;
            }
          }
        }
      }
      // Conversational rescue for greetings that surfaced as
      // UnsupportedActionException.
      final chatKindAfterAction = heuristicChatKind(trimmed);
      if (chatKindAfterAction != null) {
        await _handleChat(
            _responseGenerator.chatForKind(chatKindAfterAction));
        _lastProcessingError = null;
        return;
      }
      if (_looksLikeOpenQuestion(trimmed)) {
        await _handleSmartChat(trimmed);
        _lastProcessingError = null;
        return;
      }
      _lastProcessingError = e.message;
      final message = _messageForException(e);
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
    } catch (e) {
      // Compound rescue first so "open whatsapp, set volume..." still runs
      // one-by-one even when the LLM path threw an unexpected error.
      final seqSteps = splitIntoSteps(trimmed);
      if (seqSteps.length >= 2) {
        final seq = _heuristicSequence(seqSteps);
        if (seq != null) {
          try {
            await _executeSequence(seq);
            _lastProcessingError = null;
            return;
          } catch (err) {
            if (err is AppException) {
              _lastProcessingError = err.message;
              final message = _messageForException(err);
              _statusMessage = message;
              notifyListeners();
              await _speakResponse(message);
            } else {
              _lastProcessingError = '$e';
              final message = _responseGenerator.cannotUnderstand();
              _statusMessage = message;
              notifyListeners();
              await _speakResponse(message);
            }
            return;
          }
        }
      }
      final heuristic = _heuristicIntent(trimmed);
      if (heuristic != null) {
        try {
          await _dispatchIntent(heuristic);
          _lastProcessingError = null;
        } catch (err) {
          if (err is AppException) {
            _lastProcessingError = err.message;
            final message = _messageForException(err);
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          } else {
            _lastProcessingError = '$e';
            final message = _responseGenerator.cannotUnderstand();
            _statusMessage = message;
            notifyListeners();
            await _speakResponse(message);
          }
        }
      } else {
        final chatKind = heuristicChatKind(trimmed);
        if (chatKind != null) {
          await _handleChat(_responseGenerator.chatForKind(chatKind));
          _lastProcessingError = null;
        } else if (_looksLikeOpenQuestion(trimmed)) {
          await _handleSmartChat(trimmed);
          _lastProcessingError = null;
        } else {
          _lastProcessingError = '$e';
          final message = _responseGenerator.cannotUnderstand();
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        }
      }
    } finally {
      _isProcessing = false;
      _isOpening = false;
      _startRespondingWindow();
      notifyListeners();
    }
  }



  /// True when [text] looks like an open-ended question that the big
  /// smart model should answer (vs. a device command).
  static bool _looksLikeOpenQuestion(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    if (t.split(RegExp(r'\s+')).length > 8) return true;
    if (t.length > 60) return true;
    return RegExp(r'\b(what|why|how|explain|write|code|story|essay|mean|who|when|where|which|tell me|define|describe)\b',
            caseSensitive: false)
        .hasMatch(t);
  }

  /// Parses desired toggle state from text (on/off/toggle).
  static ToggleDesired _parseToggleDesiredFromText(String lower) {
    // Check for explicit on/off keywords
    if (RegExp(r'\b(turn\s+on|switch\s+on|enable|activate)\b').hasMatch(lower)) {
      return ToggleDesired.on;
    }
    if (RegExp(r'\b(turn\s+off|switch\s+off|disable|deactivate)\b').hasMatch(lower)) {
      return ToggleDesired.off;
    }
    // Check for "on" or "off" as standalone words (but not part of other words)
    if (RegExp(r'\bon\b').hasMatch(lower)) {
      // Make sure it's not part of "on" in "turn on" etc (already handled above)
      return ToggleDesired.on;
    }
    if (RegExp(r'\boff\b').hasMatch(lower)) {
      return ToggleDesired.off;
    }
    return ToggleDesired.toggle;
  }

  /// Heuristic fallback for small-model drift.
  ///
  /// The 135M model misclassifies more often than 360M. This expanded
  /// fallback guarantees core phrases always succeed without relying
  /// on LLM sampling.
  AssistantIntent? _heuristicIntent(String rawInput) {
    final lower = rawInput.toLowerCase();

    // Alarms/reminders first: "stop alarm" must not become media-stop, and
    // "set an alarm" must not fall into app-open heuristics. Offline + fast.
    final alarmIntent = _parseAlarmHeuristic(rawInput);
    if (alarmIntent != null) return alarmIntent;

    // SMS / FO AI commands
    final smsIntent = _parseSmsHeuristic(rawInput);
    if (smsIntent != null) return smsIntent;

    // WhatsApp — check first to avoid "flash" substring confusion
    if (lower.contains('whatsapp') || lower.contains('whats app') || lower.contains('whatsApp')) {
      final whatsAppIntent = _parseWhatsAppHeuristic(rawInput);
      if (whatsAppIntent != null) return whatsAppIntent;
    }

    // Phone call — after alarm/whatsapp so "remind me to call mom in
    // 10 minutes" stays a reminder and whatsapp stays whatsapp.
    if (_looksLikeCallCommand(lower)) {
      final callIntent = _parseCallHeuristic(rawInput);
      if (callIntent != null) return callIntent;
    }

    // Email — after alarm/whatsapp/call so those keep priority, before
    // volume/app-open so "read my mails" never becomes open_app/media.
    final emailIntent = _parseEmailHeuristic(rawInput);
    if (emailIntent != null) return emailIntent;

    // Screen context awareness (read screen, summarize screen, what's on screen)
    final screenIntent = _parseScreenContextHeuristic(rawInput);
    if (screenIntent != null) return screenIntent;

     // Volume/mute — before flashlight so "mute" never hits app heuristics.
     // Includes Hindi (awaaj) and Marathi (chale) keywords.
     // NOTE: chiya/kashi are brightness keywords (owned by the brightness
     // branch below) — they must not trigger volume, otherwise "chiya
     // badhao" would report volume instead of brightening the screen.
      if (lower.contains('volum') ||
          lower.contains('mute') ||
          lower.contains('louder') ||
          lower.contains('quieter') ||
          lower.contains('silence') ||
          lower.contains('awaaj') ||
          lower.contains('chale') ||
          lower.contains('ghatao') ||
          lower.contains('band_karo') ||
          lower.contains('kholo')) {
       final volumeIntent = _heuristicVolumeIntent(rawInput, lower);
       if (volumeIntent != null) return volumeIntent;
     }

     // Brightness
     if (lower.contains('brightness') ||
         lower.contains('brighten') ||
         lower.contains('brighter') ||
         lower.contains('dimmer') ||
         lower.contains('dim the screen') ||
         lower.contains('screen bright') ||
         lower.contains('chiya') ||
         lower.contains('kashi')) {
       final brightnessIntent = _heuristicBrightnessIntent(rawInput, lower);
       if (brightnessIntent != null) return brightnessIntent;
     }

    // Gallery deep action — before flashlight/media so
    // "open gallery and play second video" never becomes open_app/media.
    // Requires gallery/photos + play/video to avoid hijacking "open gallery".
    final mentionsGallery = lower.contains('galler') ||
        lower.contains('google photos') ||
        (lower.contains('photos') &&
            (lower.contains('play') || lower.contains('video')));
    if (mentionsGallery &&
        (lower.contains('play') || lower.contains('video'))) {
      final galleryIntent = _parseGalleryPlayHeuristic(rawInput);
      if (galleryIntent != null) return galleryIntent;
    }

    // YouTube search+play — before app-open/media for the same reason.
    // Requires "youtube" + "search" so plain "open youtube" and
    // "Play Arijit Singh" keep their existing behavior.
    if ((lower.contains('youtube') || lower.contains('you tube')) &&
        lower.contains('search')) {
      final youTubeIntent = _parseYouTubeSearchPlayHeuristic(rawInput);
      if (youTubeIntent != null) return youTubeIntent;
    }

    // AI ask (DeepSeek / ChatGPT / Gemini) — before app-open so
    // "ask deepseek who is pm of india" never becomes open_app/chat.
    // Requires an AI app name + ask/search verb + a real query.
    // Uses fuzzy detection so STT mishearings ("deepsik", "lipstik")
    // still route here even if normalization missed a variant.
    if (lower.contains('deepseek') ||
        lower.contains('deep seek') ||
        lower.contains('chatgpt') ||
        lower.contains('chat gpt') ||
        lower.contains('gemini') ||
        detectAiTarget(rawInput) != null) {
      final aiIntent = _parseAiAskHeuristic(rawInput);
      if (aiIntent != null) return aiIntent;
    }

    // Flashlight/torch — highest priority, most flaky phrase
    if (lower.contains('flash') || lower.contains('torch') || lower.contains('light on') || lower.contains('light off')) {
      return const ToggleFlashlightIntent();
    }
    if (lower.contains('bluetooth')) {
      final desired = _parseToggleDesiredFromText(lower);
      return ToggleDeviceIntent(device: 'bluetooth', desired: desired);
    }
    if (lower.contains('wifi') ||
        lower.contains('wi-fi') ||
        lower.contains('wi fi') ||
        lower.contains('internet') ||
        lower.contains('network')) {
      final desired = _parseToggleDesiredFromText(lower);
      return ToggleDeviceIntent(device: 'wifi', desired: desired);
    }

    // App opening heuristic — rescue for small-model drift
    final appOpen = _parseAppOpenHeuristic(rawInput);
    if (appOpen != null) return appOpen;

    // Media controls: check most specific to most generic
    final stopRegex = RegExp(r'\bstop\b');
    if (stopRegex.hasMatch(lower)) {
      return const MediaIntent(MediaAction.stop);
    }
    if (lower.contains('pause')) {
      return const MediaIntent(MediaAction.pause);
    }
    if (lower.contains('resume') ||
        lower.contains('continue') ||
        lower.contains('unpause')) {
      return const MediaIntent(MediaAction.resume);
    }
    if (lower.contains('skip') || lower.contains('next')) {
      return const MediaIntent(MediaAction.next);
    }
    final prevRegex = RegExp(r'\b(previous|prev|go back)\b');
    if (prevRegex.hasMatch(lower)) {
      return const MediaIntent(MediaAction.previous);
    }
    // "play" generic music — avoid misclassifying "play youtube/spotify"
    if (lower.contains('play')) {
      if (lower.contains('music') ||
          lower.contains('song') ||
          lower.contains('track') ||
          lower.contains('audio')) {
        return const MediaIntent(MediaAction.play);
      }
      if (RegExp(r'^\s*play\s*$').hasMatch(lower)) {
        return const MediaIntent(MediaAction.play);
      }
    }

    return null;
  }

  /// Offline alarm/reminder heuristic (no LLM, microseconds).
  ///
  /// Handles:
  /// - "set an alarm for 7 am" / "set alarm in 10 minutes" / "wake me up at 6:30"
  /// - "remind me to drink water in 10 minutes" / "remind me at 9pm to call mom"
  /// - "show my alarms" / "list reminders"
  /// - "cancel my 7am alarm" / "cancel all alarms"
  ///
  /// Returns null when the text is not an alarm command, or when it looks
  /// like one but has no usable time (caller then guides with alarmNoTime).
  AssistantIntent? _parseAlarmHeuristic(String rawInput) {
    final input = rawInput.trim();
    if (input.isEmpty) return null;
    final lower = input.toLowerCase();

    final mentionsAlarm = lower.contains('alarm') ||
        lower.contains('wake me up') ||
        lower.contains('wake up');
    final mentionsReminder = lower.contains('remind') ||
        lower.contains('reminder') ||
        lower.contains('remainder');

    if (!mentionsAlarm && !mentionsReminder) return null;

    // Cancel: "cancel/delete/remove/clear/dismiss/stop ... alarm/reminder".
    if (RegExp(r'\b(cancel|cancelled|cancle|delete|remove|clear|dismiss|stop)\b',
            caseSensitive: false)
        .hasMatch(lower)) {
      var query = input.trim();
      query = query.replaceAll(
        RegExp(
          r'^\s*(please\s+|can you\s+|kindly\s+)?(cancel|cancelled|delete|remove|clear|dismiss|stop)\b',
          caseSensitive: false,
        ),
        '',
      ).trim();
      query = query.replaceAll(
        RegExp(r'\b(my|the|all|every)\b', caseSensitive: false),
        '',
      ).trim();
      query = query.replaceAll(
        RegExp(r'\b(alarms?|reminders?|remainder)\b', caseSensitive: false),
        '',
      ).trim();
      query = query.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (query.length > 100) query = query.substring(0, 100).trim();
      return CancelAlarmIntent(query: query);
    }

    // List: "show/list/what/check ... alarms/reminders" without set verbs.
    final isListVerb = RegExp(
            r'\b(show|list|display|view|what|which|check|see|get|tell|do i have)\b',
            caseSensitive: false)
        .hasMatch(lower);
    final isSetVerb = RegExp(
            r'\b(set|create|add|make|new|start|schedule|remind)\b',
            caseSensitive: false)
        .hasMatch(lower);
    if (isListVerb && !isSetVerb) {
      return const ListAlarmsIntent();
    }
    // "my alarms" / "my reminders" alone is a list query.
    if (RegExp(r'\bmy\s+(alarms?|reminders?)\b', caseSensitive: false)
            .hasMatch(lower) &&
        !isSetVerb) {
      return const ListAlarmsIntent();
    }

    // Set reminder: needs a message + a time.
    if (mentionsReminder) {
      final parsed = alarm_parser.parseAlarmTime(input);
      if (parsed == null) return null;
      final message = alarm_parser.parseReminderMessage(input);
      if (message.isEmpty) return null;
      return SetReminderIntent(time: parsed.when, message: message);
    }

    // Set alarm.
    if (mentionsAlarm) {
      final parsed = alarm_parser.parseAlarmTime(input);
      if (parsed == null) return null;
      final label = alarm_parser.parseAlarmLabel(input);
      return SetAlarmIntent(time: parsed.when, label: label);
    }

    return null;
  }

  /// Returns a guidance message when the input looks like an alarm/reminder
  /// command but is missing its time (or reminder message), so the user is
  /// guided instantly without waiting on the LLM.
  String? _alarmMissingInfoHint(String rawInput) {
    final lower = rawInput.trim().toLowerCase();
    if (lower.isEmpty) return null;
    final mentionsAlarm = lower.contains('alarm') ||
        lower.contains('wake me up') ||
        lower.contains('wake up');
    final mentionsReminder = lower.contains('remind') ||
        lower.contains('reminder') ||
        lower.contains('remainder');
    if (!mentionsAlarm && !mentionsReminder) return null;
    // Cancel/list without extra info are already handled (or valid with
    // empty query), so don't hint for them.
    if (RegExp(r'\b(cancel|delete|remove|clear|dismiss|stop|show|list|display|view|what|which|check)\b',
            caseSensitive: false)
        .hasMatch(lower)) {
      return null;
    }
    if (mentionsReminder) {
      final parsed = alarm_parser.parseAlarmTime(rawInput);
      if (parsed == null) return _responseGenerator.alarmNoTime();
      final message = alarm_parser.parseReminderMessage(rawInput);
      if (message.isEmpty) return _responseGenerator.reminderNoMessage();
      return null;
    }
    if (mentionsAlarm) {
      final parsed = alarm_parser.parseAlarmTime(rawInput);
      if (parsed == null) return _responseGenerator.alarmNoTime();
    }
    return null;
  }

  /// Parses WhatsApp heuristic from raw text — tolerant to "saying" vs direct.
  ///
  /// Handles:
  /// - "send whatsapp to mom saying i will be late"
  /// - "send whatsapp message to rahul saying hello"
  /// - "whatsapp john i am coming in 5 minutes" (no saying, no to)
  /// - "send whatsapp to mom hello how are you" (without saying)
  /// - "whatsapp to mom saying hi"
  /// - "message mom on whatsapp saying hi"
  /// - "text mom on whatsapp hello"
  AssistantIntent? _parseWhatsAppHeuristic(String rawInput) {
    final input = rawInput.trim();
    final lower = input.toLowerCase();

    if (!lower.contains('whatsapp') && !lower.contains('whats app')) {
      return null;
    }

    // Fast path: if "saying" exists, split on it — most reliable delimiter
    // "something saying message"  => contact = before saying, message = after
    final sayingIndex = lower.indexOf('saying');
    if (sayingIndex != -1) {
      final afterSaying = input.substring(sayingIndex + 'saying'.length).trim();
      if (afterSaying.isEmpty) return null;

      // Extract contact from beforeSaying part (after whatsapp)
      final whatsIndex = lower.indexOf('whatsapp');
      if (whatsIndex == -1) return null;
      var afterWhats = input.substring(whatsIndex + 'whatsapp'.length).trim();
      var afterLower = afterWhats.toLowerCase();
      if (afterLower.startsWith('message')) {
        afterWhats = afterWhats.substring('message'.length).trim();
        afterLower = afterWhats.toLowerCase();
      }
      if (afterLower.startsWith('to')) {
        afterWhats = afterWhats.substring(2).trim();
      }
      final contactPart = input.substring(whatsIndex + 'whatsapp'.length, sayingIndex).trim();
      var contact = contactPart;
      var cLower = contact.toLowerCase();
      if (cLower.startsWith('message')) {
        contact = contact.substring('message'.length).trim();
        cLower = contact.toLowerCase();
      }
      if (cLower.startsWith('to')) {
        contact = contact.substring(2).trim();
      }
      contact = contact.trim();
      if (contact.isEmpty) return null;
      if (contact.length > 30) {
        final parts = contact.split(RegExp(r'\s+'));
        if (parts.length > 2) contact = parts.take(2).join(' ');
      }
      if (contact.isEmpty || afterSaying.isEmpty) return null;
      if (contact.length <= 100 && afterSaying.length <= 1000) {
        return SendWhatsAppIntent(contactName: contact, message: afterSaying);
      }
    }

    // No "saying" — token-based fallback
    final whatsIndex = lower.indexOf('whatsapp');
    if (whatsIndex == -1) return null;
    var afterWhats = input.substring(whatsIndex + 'whatsapp'.length).trim();
    if (afterWhats.isEmpty) return null;

    var afterLower = afterWhats.toLowerCase();
    if (afterLower.startsWith('message')) {
      afterWhats = afterWhats.substring('message'.length).trim();
      afterLower = afterWhats.toLowerCase();
    }
    if (afterLower.startsWith('to')) {
      afterWhats = afterWhats.substring(2).trim();
    }
    if (afterWhats.isEmpty) return null;

    final tokens = afterWhats.split(RegExp(r'\s+'));
    if (tokens.isNotEmpty) {
      final contact = tokens.first.trim();
      var message = tokens.length > 1 ? tokens.skip(1).join(' ').trim() : '';
      if (message.toLowerCase().startsWith('saying ')) {
        message = message.substring(7).trim();
      }
      if (contact.isNotEmpty && contact.length <= 100 && message.length <= 1000) {
        return SendWhatsAppIntent(contactName: contact, message: message);
      }
    }

    // Regex fallback for any remaining edge cases
    final patterns = [
      RegExp(r'send\s+whats?app\s+(?:message\s+)?to\s+(.+?)\s+saying\s+(.+)', caseSensitive: false),
      RegExp(r'whats?app\s+(.+?)\s+saying\s+(.+)', caseSensitive: false),
      RegExp(r'send\s+whats?app\s+to\s+(.+?)\s+(.+)', caseSensitive: false),
      RegExp(r'whats?app\s+to\s+(.+?)\s+saying\s+(.+)', caseSensitive: false),
      RegExp(r'message\s+(.+?)\s+on\s+whats?app\s+saying\s+(.+)', caseSensitive: false),
      RegExp(r'text\s+(.+?)\s+on\s+whats?app\s+(.+)', caseSensitive: false),
    ];
    for (final regex in patterns) {
      final match = regex.firstMatch(input);
      if (match != null) {
        final contact2 = match.group(1)?.trim() ?? '';
        final message2 = match.group(2)?.trim() ?? '';
        if (contact2.isNotEmpty && message2.isNotEmpty && contact2.length <= 100 && message2.length <= 1000) {
          var cleanContact = contact2;
          if (cleanContact.toLowerCase().startsWith('to ')) {
            cleanContact = cleanContact.substring(3).trim();
          }
          if (cleanContact.isEmpty) continue;
          return SendWhatsAppIntent(contactName: cleanContact, message: message2);
        }
      }
    }

    return null;
  }

  /// Parses SMS / FO AI command heuristic from raw text.
  ///
  /// Handles:
  /// - "ask FO to call mom and ask how she is"
  /// - "ask FO call mom and ask how she is"
  /// - "tell FO to check my order"
  /// - "message FO call mom"
  /// - "send message to FO call mom"
  /// - "send sms to FO saying call mom"
  /// - "send sms to mom saying hello"
  /// - "text mom saying i will be late"
  AssistantIntent? _parseSmsHeuristic(String rawInput) {
    final input = rawInput.trim();
    if (input.isEmpty) return null;
    final lower = input.toLowerCase();

    // 1. FO AI Command Patterns
    final foPatterns = [
      RegExp(r'^(?:please\s+)?(?:can you\s+)?(?:ask|tell|say to)\s+fo\s+(?:to\s+|that\s+)?(.+)$', caseSensitive: false),
      RegExp(r'^(?:please\s+)?(?:can you\s+)?(?:send\s+(?:a\s+)?(?:sms|message)\s+to\s+fo\s+(?:saying\s+|that\s+|to\s+)?)(.+)$', caseSensitive: false),
      RegExp(r'^(?:please\s+)?(?:can you\s+)?(?:message|text|sms)\s+fo\s+(?:saying\s+|that\s+|to\s+)?(.+)$', caseSensitive: false),
      RegExp(r'^fo\s*[:,]\s*(.+)$', caseSensitive: false),
    ];

    for (final pattern in foPatterns) {
      final m = pattern.firstMatch(input);
      if (m != null) {
        final body = m.group(1)?.trim() ?? '';
        if (body.isNotEmpty) {
          return SendSmsIntent(
            recipient: AppConstants.foDisplayName,
            message: body,
            phoneNumber: AppConstants.foPhoneNumber,
          );
        }
      }
    }

    // 2. Explicit SMS / Text commands
    if (lower.contains('sms') || lower.contains('text message') || lower.startsWith('text ') || lower.startsWith('send message to ')) {
      final patterns = [
        RegExp(r'^(?:please\s+)?(?:can you\s+)?send\s+(?:an\s+)?sms\s+(?:message\s+)?to\s+(.+?)\s+saying\s+(.+)$', caseSensitive: false),
        RegExp(r'^(?:please\s+)?(?:can you\s+)?send\s+(?:a\s+)?message\s+to\s+(.+?)\s+saying\s+(.+)$', caseSensitive: false),
        RegExp(r'^(?:please\s+)?(?:can you\s+)?send\s+(?:an\s+)?sms\s+to\s+(.+?)\s+(.+)$', caseSensitive: false),
        RegExp(r'^(?:please\s+)?(?:can you\s+)?text\s+(.+?)\s+saying\s+(.+)$', caseSensitive: false),
        RegExp(r'^(?:please\s+)?(?:can you\s+)?sms\s+(.+?)\s+saying\s+(.+)$', caseSensitive: false),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(input);
        if (match != null) {
          final recipient = match.group(1)?.trim() ?? '';
          final body = match.group(2)?.trim() ?? '';
          if (recipient.isNotEmpty && body.isNotEmpty && recipient.length <= 100 && body.length <= 1000) {
            final isFo = recipient.toUpperCase() == 'FO' || recipient.toLowerCase().contains('wajo fo');
            return SendSmsIntent(
              recipient: isFo ? AppConstants.foDisplayName : recipient,
              message: body,
              phoneNumber: isFo ? AppConstants.foPhoneNumber : null,
            );
          }
        }
      }
    }

    return null;
  }

  /// True when [lower] (already lower-cased) looks like a phone-call command.
  ///
  /// Requires a call verb (call/dial/phone) and excludes reminder/alarm and
  /// whatsapp contexts so "remind me to call mom ..." stays a reminder.
  static bool _looksLikeCallCommand(String lower) {
    if (lower.contains('recall')) return false;
    if (lower.contains('remind') ||
        lower.contains('reminder') ||
        lower.contains('alarm') ||
        lower.contains('whatsapp') ||
        lower.contains('whats app') ||
        lower.contains('ask fo') ||
        lower.contains('tell fo') ||
        lower.contains('screen')) {
      return false;
    }
    return RegExp(r'\b(call|calling|dial|dialing|phone)\b').hasMatch(lower);
  }

  /// Heuristic for "call mom" / "dial 9876543210" / "phone dad".
  ///
  /// Handles:
  /// - "call mom", "please call mom", "call my mom"
  /// - "make a call to rahul", "dial mom", "phone dad"
  /// - "call 9876543210" (raw number, kept as-is)
  /// Returns null when no contact/number can be extracted.
  AssistantIntent? _parseCallHeuristic(String rawInput) {
    final input = rawInput.trim();
    if (input.isEmpty) return null;
    final lower = input.toLowerCase();

    // Find the call-verb anchor: call/calling/dial/phone/make a call.
    final verbMatch = RegExp(
      r'\b(make\s+(a\s+)?(phone\s+)?call|phone\s+call|call|calling|dial(?:ing)?|phone)\b',
      caseSensitive: false,
    ).firstMatch(input);
    if (verbMatch == null) return null;

    var after = input.substring(verbMatch.end).trim();
    // Strip leading fillers: "to", "my", "please" leftovers.
    after = after.replaceAll(
      RegExp(r'^(to|my|the)\b\s*', caseSensitive: false),
      '',
    ).trim();
    // "call mom on phone" / "call mom on speaker" -> keep "mom".
    after = after.replaceAll(
      RegExp(r'\s+on\s+(phone|speaker|mobile)\s*$', caseSensitive: false),
      '',
    ).trim();
    after = after.replaceAll(
      RegExp(r'\s+please\s*$', caseSensitive: false),
      '',
    ).trim();
    after = after.replaceAll(RegExp(r'\s+'), ' ').trim();

    final afterLower = after.toLowerCase();
    if (after.isEmpty ||
        afterLower == 'someone' ||
        afterLower == 'anyone' ||
        afterLower == 'somebody' ||
        afterLower == 'a person') {
      return const CallIntent(contactName: '');
    }

    if (after.length > 100) return null;
    // Guard: message-like tails mean this is not a bare call
    // ("call mom saying hi" is a whatsapp-style message, not a phone call).
    if (afterLower.contains('saying') ||
        RegExp(r'\b(say|tell|message|whatsapp)\b').hasMatch(afterLower)) {
      return null;
    }
    // Keep only the contact segment before any sequence connector
    // ("call mom and set volume..." is split upstream, but be safe here).
    final connectorCut = RegExp(
      r'\s+(and|then|,|;)\b.*$',
      caseSensitive: false,
    ).firstMatch(after);
    if (connectorCut != null) {
      after = after.substring(0, connectorCut.start).trim();
      if (after.isEmpty) return null;
    }
    // Contact is 1-4 words or a phone number; longer text is not a call.
    final isPhoneNumber = RegExp(r'^[+\d][\d\s\-()]{5,18}$').hasMatch(after);
    if (!isPhoneNumber) {
      if (after.length < 2) return null;
      if (after.split(RegExp(r'\s+')).length > 4) return null;
      // Reject question-like tails.
      if (RegExp(r'\b(what|why|how|when|where|which|who)\b', caseSensitive: false)
          .hasMatch(afterLower)) {
        return null;
      }
      // Lower must actually contain the contact (sanity against verb-only).
      if (!lower.contains(afterLower.split(RegExp(r'\s+')).first)) {
        return null;
      }
    }
    return CallIntent(contactName: after);
  }

  /// Heuristic for on-screen context awareness.
  /// Matches phrases like "what's on my screen", "summarize this page",
  /// "call number on screen", "read screen aloud".
  AssistantIntent? _parseScreenContextHeuristic(String rawInput) {
    final lower = rawInput.toLowerCase().trim();

    // Call number on screen
    if (RegExp(r'\b(call|dial|phone)\s+(the\s+)?(phone\s+)?number\s+(on|from)\s+(my\s+|the\s+)?screen\b', caseSensitive: false).hasMatch(lower) ||
        RegExp(r'\bcall\s+number\s+on\s+screen\b', caseSensitive: false).hasMatch(lower)) {
      return const ScreenContextIntent(query: 'call_number', action: 'extract_phone');
    }

    // Extract / copy link
    if (RegExp(r'\b(copy|extract|get)\s+(the\s+)?(link|url)\s+(on|from)\s+(my\s+|the\s+)?screen\b', caseSensitive: false).hasMatch(lower)) {
      return const ScreenContextIntent(query: 'extract_link', action: 'extract_url');
    }

    // Read screen aloud
    if (RegExp(r'\bread\s+(this\s+|the\s+|my\s+)?(screen|page|aloud)\b', caseSensitive: false).hasMatch(lower) ||
        RegExp(r'\bread\s+(out\s+loud|aloud)\b', caseSensitive: false).hasMatch(lower)) {
      return const ScreenContextIntent(query: 'read_aloud', action: 'read_aloud');
    }

    // Summarize screen / page
    if (RegExp(r'\b(summarize|summarise)\s+(this\s+|the\s+|my\s+)?(screen|page|article)\b', caseSensitive: false).hasMatch(lower) ||
        RegExp(r"\b(what\s+is|what's)\s+(this\s+|the\s+)?(page|article)\s+about\b", caseSensitive: false).hasMatch(lower)) {
      return const ScreenContextIntent(query: 'summarize', action: 'summarize');
    }

    // What's on my screen / describe screen
    if (RegExp(r"\b(what\s+is|what's)\s+(on\s+)?(my\s+|the\s+)?screen\b", caseSensitive: false).hasMatch(lower) ||
        RegExp(r'\bdescribe\s+(this\s+|the\s+|my\s+)?screen\b', caseSensitive: false).hasMatch(lower)) {
      return const ScreenContextIntent(query: 'what_on_screen', action: 'summarize');
    }

    return null;
  }

  /// Heuristic for opening apps — catches small-model failures for core phrase.
  /// Returns OpenAppIntent for "open youtube", "launch chrome", "start spotify".
  /// Does NOT handle "play X" to avoid conflicts with media (play music vs
  /// play spotify is disambiguated by LLM). Keep heuristic minimal to preserve
  /// security tests where "Play my workout playlist" must remain unsupported.
  AssistantIntent? _parseAppOpenHeuristic(String rawInput) {
    final lower = rawInput.toLowerCase().trim();

    // Skip if it's clearly a whatsapp message (already handled) or pure media
    if (lower.contains('whatsapp') && (lower.contains('saying') || lower.contains('message to'))) {
      return null;
    }
    // Gallery deep actions and YouTube search+play have dedicated parsers.
    if ((lower.contains('galler') || lower.contains('google photos')) &&
        (lower.contains('play') || lower.contains('video'))) {
      return null;
    }
    if ((lower.contains('youtube') || lower.contains('you tube')) &&
        lower.contains('search')) {
      return null;
    }
    if (RegExp(r'\b(play|pause|stop|resume|next|previous|skip)\b').hasMatch(lower) &&
        RegExp(r'\b(music|song|track|audio|playlist|album)\b').hasMatch(lower)) {
      return null;
    }

    // Only rescue explicit open/launch/start verbs. "play" is intentionally
    // excluded — LLM correctly handles play-spotify vs play-music distinction.
    final appPattern = RegExp(
      r'^\s*(?:please\s+)?(?:can you\s+)?(?:open|launch|start|go to)\s+(.+?)\s*$',
      caseSensitive: false,
    );
    final match = appPattern.firstMatch(rawInput.trim());
    if (match != null) {
      var target = match.group(1)?.trim() ?? '';
      if (target.isEmpty) return null;
      target = target.replaceAll(RegExp(r'\s+please\s*$', caseSensitive: false), '').trim();
      if (target.isEmpty) return null;
      if (target.length > 100 || target.length < 2) return null;
      return OpenAppIntent(target: target);
    }

    return null;
  }

  /// Heuristic for "open gallery and play second video".
  ///
  /// Requires gallery/photos + play/video (checked by caller). Extracts the
  /// ordinal via [IntentParser.parseOrdinal], defaulting to 1.
  AssistantIntent? _parseGalleryPlayHeuristic(String rawInput) {
    final index = IntentParser.parseOrdinal(rawInput) ?? 1;
    return PlayGalleryVideoIntent(index: index.clamp(1, 50));
  }

  /// Heuristic for "open youtube search hindi music and play first video".
  ///
  /// Requires youtube + search (checked by caller) so plain "open youtube"
  /// and bare "Play <song>" keep their existing behavior.
  AssistantIntent? _parseYouTubeSearchPlayHeuristic(String rawInput) {
    final input = rawInput.trim();
    final lower = input.toLowerCase();
    final ytIndex = lower.indexOf('youtube');
    final youTubeSpacedIndex = lower.indexOf('you tube');
    int anchorIndex;
    int anchorLen;
    if (ytIndex != -1 && (youTubeSpacedIndex == -1 || ytIndex < youTubeSpacedIndex)) {
      anchorIndex = ytIndex;
      anchorLen = 'youtube'.length;
    } else if (youTubeSpacedIndex != -1) {
      anchorIndex = youTubeSpacedIndex;
      anchorLen = 'you tube'.length;
    } else {
      return null;
    }

    String after = input.substring(anchorIndex + anchorLen).trim();
    // Strip a leading "search".
    after = after.replaceAll(
        RegExp(r'^(search)\b\s*', caseSensitive: false), '').trim();
    // Strip a leading "for" left over from "search for X".
    after = after.replaceAll(
        RegExp(r'^(for)\b\s*', caseSensitive: false), '').trim();

    int index = 1;
    String query = after;

    // Cut off a trailing play-tail: "and play first video",
    // "play 2nd video", "and play song 3", ...
    final tailPatterns = [
      RegExp(r'\s+and\s+play\b.*$', caseSensitive: false),
      RegExp(r'\s+play\b.*$', caseSensitive: false),
    ];
    for (final tail in tailPatterns) {
      final m = tail.firstMatch(query);
      if (m != null) {
        final tailText = m.group(0)!;
        final tailIndex = IntentParser.parseOrdinal(tailText);
        if (tailIndex != null) index = tailIndex;
        query = query.substring(0, m.start).trim();
        break;
      }
    }

    // Query-before-YouTube form: "search hindi music on youtube ...".
    if (query.isEmpty || query.length < 2) {
      var before = input.substring(0, anchorIndex).trim();
      before = before.replaceAll(
          RegExp(r'^(please\s+|can you\s+|open\s+|launch\s+|start\s+|search\s+)+',
              caseSensitive: false),
          '').trim();
      before = before.replaceAll(
          RegExp(r'\s+(on|in|at)\s*$', caseSensitive: false), '').trim();
      before = before.replaceAll(
          RegExp(r'\s+and\s+play\b.*$', caseSensitive: false), '').trim();
      if (before.length >= 2) {
        query = before;
        final beforeIndex = IntentParser.parseOrdinal(input);
        // Only take the ordinal from the play-tail; a bare number in the
        // query itself (e.g. "top 10") must not shift the result index.
        if (RegExp(r'\bplay\b', caseSensitive: false).hasMatch(input) &&
            beforeIndex != null &&
            query == before) {
          // Keep index from tail if we found one, else use it.
          if (index == 1) index = beforeIndex;
        }
      }
    }

    // Final cleanup of the query.
    query = query.replaceAll(
        RegExp(r'\s+(on\s+youtube|on\s+you\s+tube)\s*$', caseSensitive: false),
        '').trim();
    query = query.replaceAll(
        RegExp(r'^(for|search for|search)\b\s*', caseSensitive: false), '').trim();
    query = query.replaceAll(RegExp(r'\s+please\s*$', caseSensitive: false), '').trim();
    query = query.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (query.isEmpty || query.length < 2 || query.length > 200) {
      return null;
    }
    // Guard against the query being just "video"/"music" with no real term.
    if (RegExp(r'^(videos?|music|songs?)$', caseSensitive: false).hasMatch(query)) {
      return null;
    }
    return YouTubeSearchPlayIntent(query: query, index: index.clamp(1, 50));
  }

  /// Heuristic for "ask deepseek who is pm of india" /
  /// "search on chatgpt for flutter" / "ask gemini capital of france".
  ///
  /// Requires an AI app name (checked by caller). Returns null for bare
  /// "open deepseek" (no query) so plain opens keep open_app behavior.
  AssistantIntent? _parseAiAskHeuristic(String rawInput) {
    // Re-normalize defensively: callers normally pass already-normalized
    // text, but direct calls / tests may pass raw STT ("deepsik").
    final input = normalizeAiTranscript(rawInput.trim());
    if (input.isEmpty) return null;
    final lower = input.toLowerCase();

    String? target;
    int anchorIndex = -1;
    int anchorLen = 0;
    final candidates = <String, String>{
      'deepseek': 'deepseek',
      'deep seek': 'deepseek',
      'chatgpt': 'chatgpt',
      'chat gpt': 'chatgpt',
      'gemini': 'gemini',
    };
    for (final entry in candidates.entries) {
      final idx = lower.indexOf(entry.key);
      if (idx != -1 && (anchorIndex == -1 || idx < anchorIndex)) {
        anchorIndex = idx;
        anchorLen = entry.key.length;
        target = entry.value;
      }
    }
    // Lone "gpt" (without "chat") -> chatgpt.
    if (target == null) {
      final gptMatch =
          RegExp(r'\bgpt\b', caseSensitive: false).firstMatch(lower);
      if (gptMatch != null) {
        anchorIndex = gptMatch.start;
        anchorLen = 3;
        target = 'chatgpt';
      }
    }
    if (target == null || anchorIndex == -1) return null;

    String after = input.substring(anchorIndex + anchorLen).trim();
    after = after.replaceAll(
        RegExp(r'^(search|ask)\b\s*', caseSensitive: false), '').trim();
    after = after.replaceAll(
        RegExp(r'^(for|about|on|in)\b\s*', caseSensitive: false), '').trim();

    String query = after;
    if (query.length < 2) {
      // Query-before-app form: "who is pm of india on deepseek",
      // "search hindi music on deepseek".
      var before = input.substring(0, anchorIndex).trim();
      before = before.replaceAll(
          RegExp(
              r'^(please\s+|can you\s+|open\s+|launch\s+|start\s+|search\s+|ask\s+)+',
              caseSensitive: false),
          '').trim();
      before = before.replaceAll(
          RegExp(r'\s+(on|in|at|with|using)\s*$', caseSensitive: false), '').trim();
      before = before.replaceAll(
          RegExp(r'^(for|search for|search|ask)\b\s*', caseSensitive: false), '').trim();
      if (before.length >= 2) query = before;
    }

    query = query.replaceAll(
        RegExp(r'\s+(on\s+deepseek|on\s+deep\s+seek|on\s+chatgpt|on\s+chat\s+gpt|on\s+gemini)\s*$',
            caseSensitive: false),
        '').trim();
    query = query.replaceAll(
        RegExp(r'^(for|search for|search|ask)\b\s*', caseSensitive: false), '').trim();
    query = query.replaceAll(RegExp(r'\s+please\s*$', caseSensitive: false), '').trim();
    query = query.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (query.length < 2 || query.length > 500) return null;
    // Bare app open ("open deepseek") has no query — leave to open_app.
    if (RegExp(r'^(open|launch|start|app)$', caseSensitive: false)
        .hasMatch(query)) {
      return null;
    }
    return AiAskIntent(target: target, query: query);
  }

  /// Heuristic volume intent that tolerates small-model drift, e.g.
  /// "turn volume up", "set volume to 50%", "mute", "unmute".
  /// Narrow offline check for explicit single-step volume commands.
  ///
  /// Returns a [VolumeIntent] only when the text carries an unambiguous
  /// signal (absolute number, up/down, mute/unmute, max/min). Bare mentions
  /// like "what is the volume of a sphere?" return null so open questions
  /// still reach the smart-chat path instead of becoming a volume query.
  VolumeIntent? _explicitVolumeHeuristic(String rawInput) {
    final lower = rawInput.toLowerCase();
    final mentionsVolume = lower.contains('volum') ||
        lower.contains('mute') ||
        lower.contains('unmute') ||
        lower.contains('louder') ||
        lower.contains('quieter') ||
        lower.contains('silence') ||
        lower.contains('awaaj') ||
        lower.contains('chale') ||
        lower.contains('ghatao') ||
        lower.contains('band_karo') ||
        lower.contains('kholo') ||
        lower.contains('badhao') ||
        lower.contains('badha');
    if (!mentionsVolume) return null;
    // Explicit Hindi query ("awaaj kya hai") is a real volume query.
    final isHindiQuery = lower.contains('awaaj kya hai') ||
        lower.contains('chale kya hai') ||
        lower.contains('awaaj_kya_hai') ||
        lower.contains('chale_kya_hai');
    final parsed = _heuristicVolumeIntent(rawInput, lower);
    if (parsed == null) return null;
    if (parsed.level != null ||
        parsed.delta != 0 ||
        parsed.mute ||
        parsed.unmute) {
      return parsed;
    }
    // Bare query fallback: only fast-path explicit Hindi queries.
    if (isHindiQuery) return parsed;
    return null;
  }

  /// Narrow offline check for explicit single-step brightness commands.
  /// Same contract as [_explicitVolumeHeuristic]: absolute number or
  /// up/down only; bare mentions fall through to the LLM path.
  BrightnessIntent? _explicitBrightnessHeuristic(String rawInput) {
    final lower = rawInput.toLowerCase();
    final mentionsBrightness = lower.contains('brightness') ||
        lower.contains('brighten') ||
        lower.contains('brighter') ||
        lower.contains('dimmer') ||
        lower.contains('dim the screen') ||
        lower.contains('screen bright') ||
        lower.contains('chiya') ||
        lower.contains('kashi');
    if (!mentionsBrightness) return null;
    final parsed = _heuristicBrightnessIntent(rawInput, lower);
    if (parsed == null) return null;
    if (parsed.level != null || parsed.delta != 0) return parsed;
    return null;
  }

  /// Offline fast-path for flashlight / wifi / bluetooth ONLY.
  ///
  /// Returns a device [AssistantIntent] only for unambiguous single-step
  /// commands so "turn on flashlight" never pays LLM latency and can never
  /// be hallucinated into open_app "game assistant". Open questions
  /// ("what is bluetooth?") return null and keep the LLM/smart-chat path.
  ///
  /// Media and app-open intentionally stay on the LLM path: the Fake/real
  /// LLM + post-LLM fallback own the play-vs-open distinction ("Start
  /// playing" is media, "Play Arijit Singh" is unsupported) and the
  /// open_app target casing tests rely on LLM normalization.
  AssistantIntent? _explicitDeviceHeuristic(String rawInput) {
    final lower = rawInput.toLowerCase().trim();
    if (lower.isEmpty) return null;

    // Flashlight/torch — highest priority, most flaky phrase. Matches the
    // post-LLM fallback so behavior is identical, just instant + offline.
    // Guard: ignore when the text is clearly a question about flashlight.
    final isFlashQuestion = RegExp(
      r'\b(what|why|how|where|which|mean|price|buy)\b',
      caseSensitive: false,
    ).hasMatch(lower);
    if (!isFlashQuestion &&
        (lower.contains('flash') ||
            lower.contains('torch') ||
            lower.contains('light on') ||
            lower.contains('light off'))) {
      return const ToggleFlashlightIntent();
    }

    // Bluetooth / wifi — require the radio word + an action verb (or bare
    // "bluetooth"/"wifi" toggle) so "what is wifi?" stays a question.
    if (lower.contains('bluetooth')) {
      final hasVerb = RegExp(
        r'\b(turn|switch|toggle|enable|disable|on|off|open)\b',
        caseSensitive: false,
      ).hasMatch(lower);
      if (hasVerb || lower.trim() == 'bluetooth') {
        return ToggleDeviceIntent(
          device: 'bluetooth',
          desired: AssistantController._parseToggleDesiredFromText(lower),
        );
      }
      return null;
    }
    if (lower.contains('wifi') ||
        lower.contains('wi-fi') ||
        lower.contains('wi fi')) {
      final hasVerb = RegExp(
        r'\b(turn|switch|toggle|enable|disable|on|off|open|internet|network)\b',
        caseSensitive: false,
      ).hasMatch(lower);
      if (hasVerb || lower.trim() == 'wifi' || lower.trim() == 'wi-fi') {
        return ToggleDeviceIntent(
          device: 'wifi',
          desired: AssistantController._parseToggleDesiredFromText(lower),
        );
      }
      return null;
    }

    return null;
  }

  VolumeIntent? _heuristicVolumeIntent(String rawInput, String lower) {
    // Absolute level: "set volume to 50", "set the volume to 50%",
    // "volume to 50", "volume 50", "volume to 50 percent"
    // (the last forms cover elliptical sequence steps like
    // "set volume to 50% and brightness to 80%").
    final setMatch = RegExp(
      r'set\s+(?:the\s+)?volume\s+to\s+(\d{1,3})\s*%?(?:\s*percent)?',
      caseSensitive: false,
    ).firstMatch(rawInput);
    if (setMatch != null) {
      final level = int.tryParse(setMatch.group(1)!)?.clamp(0, 100);
      if (level != null) return VolumeIntent(level: level);
    }
    final bareMatch = RegExp(
      r'volume\s+(?:to\s+|at\s+|of\s+)?(\d{1,3})\s*%?(?:\s*percent)?',
      caseSensitive: false,
    ).firstMatch(rawInput);
    if (bareMatch != null) {
      final level = int.tryParse(bareMatch.group(1)!)?.clamp(0, 100);
      if (level != null) return VolumeIntent(level: level);
    }
    if (lower.contains('set volume') && lower.contains('max')) {
      return const VolumeIntent(level: 100);
    }
    if (lower.contains('set volume') && lower.contains('min')) {
      return const VolumeIntent(level: 0);
    }

     if (lower.contains('unmute')) return const VolumeIntent(unmute: true);
     if (lower.contains('mute') || lower.contains('silence') ||
         lower.contains('band_karo') || lower.contains('awaaj_band')) {
       return const VolumeIntent(mute: true);
     }
     if (lower.contains('zero volume') || lower.contains('awaaj_zero')) {
       return const VolumeIntent(level: 0);
     }
     if (lower.contains('full volume') ||
         lower.contains('max volume') ||
         lower.contains('maximum volume') ||
         lower.contains('awaaj_max')) {
       return const VolumeIntent(level: 100);
     }

     const upWords = ['volume up', 'turn up', 'increase', 'raise', 'louder', 'higher'];
     const downWords = ['volume down', 'turn down', 'decrease', 'lower', 'quieter', 'softer'];
     // Hindi/Marathi up/down keywords
     const hindiMarathiUpWords = ['awaaj_badhao', 'chale_badhao', 'awaaj badhao', 'chale badhao', 'badhao', 'badha'];
     const hindiMarathiDownWords = ['awaaj_ghatao', 'chale_ghatao', 'awaaj ghatao', 'chale ghatao', 'ghatao'];
     if (upWords.any(lower.contains) || hindiMarathiUpWords.any(lower.contains)) return const VolumeIntent(delta: 1);
     if (downWords.any(lower.contains) || hindiMarathiDownWords.any(lower.contains)) return const VolumeIntent(delta: -1);

     // Hindi: "awaaj 50 karo", "chale 50 karo" -> set volume to 50
     final hindiLevelMatch = RegExp(r'(?:awaaj|chale)\s+(\d{1,3})\s*karo', caseSensitive: false).firstMatch(rawInput);
     if (hindiLevelMatch != null) {
       final level = int.tryParse(hindiLevelMatch.group(1)!)?.clamp(0, 100);
       if (level != null) return VolumeIntent(level: level);
     }

     // Hindi: "awaaj kya hai" -> query volume
     if (lower.contains('awaaj_kya_hai') || lower.contains('chale_kya_hai') || lower.contains('awaaj kya hai') || lower.contains('chale kya hai')) {
       return const VolumeIntent();
     }

     return const VolumeIntent();
   }

  /// Heuristic brightness intent that tolerates small-model drift, e.g.
  /// "brightness up", "set brightness to 80%", "dim the screen".
  BrightnessIntent? _heuristicBrightnessIntent(String rawInput, String lower) {
    final setMatch = RegExp(
      r'set\s+(?:the\s+)?brightness\s+to\s+(\d{1,3})\s*%?(?:\s*percent)?',
      caseSensitive: false,
    ).firstMatch(rawInput);
    if (setMatch != null) {
      final level = int.tryParse(setMatch.group(1)!)?.clamp(0, 100);
      if (level != null) return BrightnessIntent(level: level);
    }
    // Elliptical sequence fragment: "brightness to 80%", "brightness 80",
    // "brightness to 80 percent" (from "... and brightness to 80%").
    final bareMatch = RegExp(
      r'brightness\s+(?:to\s+|at\s+|of\s+)?(\d{1,3})\s*%?(?:\s*percent)?',
      caseSensitive: false,
    ).firstMatch(rawInput);
    if (bareMatch != null) {
      final level = int.tryParse(bareMatch.group(1)!)?.clamp(0, 100);
      if (level != null) return BrightnessIntent(level: level);
    }
    if (lower.contains('max brightness') ||
        lower.contains('full brightness') ||
        lower.contains('maximum brightness') ||
        (lower.contains('brightness') && lower.contains('max'))) {
      return const BrightnessIntent(level: 100);
    }
    if (lower.contains('min brightness') ||
        lower.contains('minimum brightness') ||
        lower.contains('lowest brightness') ||
        lower.contains('zero brightness')) {
      return const BrightnessIntent(level: 0);
    }

     const upWords = ['brightness up', 'turn up', 'increase', 'raise', 'brighten', 'brighter', 'higher'];
     const downWords = ['brightness down', 'turn down', 'decrease', 'lower', 'dim', 'dimmer', 'darker', 'reduce'];
     // Hindi/Marathi brightness keywords
     const hindiMarathiUpWords = ['chiya', 'chiya_badhao', 'badhao'];
     const hindiMarathiDownWords = ['kashi', 'kashi_karo', 'ghatao'];
     if (upWords.any(lower.contains) || hindiMarathiUpWords.any(lower.contains)) return const BrightnessIntent(delta: 1);
     if (downWords.any(lower.contains) || hindiMarathiDownWords.any(lower.contains)) return const BrightnessIntent(delta: -1);

     return const BrightnessIntent();
   }

  /// Dispatches a heuristic intent using the same handlers as the normal path.
  Future<void> _dispatchIntent(AssistantIntent intent) async {
    final clarification = _dialogueTracker.inspectIntentForClarification(intent);
    if (clarification != null) {
      _statusMessage = clarification.promptQuestion;
      notifyListeners();
      await _speakResponse(clarification.promptQuestion);
      _dialogueTracker.recordTurn(
        role: 'assistant',
        utterance: clarification.promptQuestion,
        intent: intent,
      );
      if (_isSpeechAvailable && !_isListening) {
        unawaited(_startCommandListening());
      }
      return;
    }

    _dialogueTracker.recordTurn(
      role: 'user',
      utterance: _lastUserCommand ?? '',
      intent: intent,
    );

    switch (intent) {
      case UnsupportedIntent():
        final heuristic = _heuristicIntent(_lastUserCommand ?? '');
        if (heuristic != null && heuristic is! UnsupportedIntent) {
          await _dispatchIntent(heuristic);
          break;
        }
        final chatKindFallback = heuristicChatKind(_lastUserCommand ?? '');
        if (chatKindFallback != null) {
          await _handleChat(_responseGenerator.chatForKind(chatKindFallback));
          break;
        }
        final fallbackQ = _lastUserCommand?.trim() ?? '';
        if (fallbackQ.isNotEmpty) {
          await _handleSmartChat(fallbackQ);
        } else {
          final message = _responseGenerator.unsupportedCommand();
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        }
        break;
      case ChatIntent(:final message):
        final userCmd = _lastUserCommand ?? '';
        if (userCmd.split(RegExp(r'\s+')).length > 8 ||
            userCmd.length > 60 ||
            RegExp(r'\b(what|why|how|explain|write|code|story|essay|mean)\b',
                    caseSensitive: false)
                .hasMatch(userCmd)) {
          await _handleSmartChat(userCmd);
        } else {
          await _handleChat(message);
        }
        break;
      case OpenAppIntent(:final target):
        final userLower = (_lastUserCommand ?? '').toLowerCase();
        if (userLower.contains('flash') || userLower.contains('torch')) {
          await _dispatchIntent(const ToggleFlashlightIntent());
          break;
        }
        await _handleOpenApp(target);
        break;
      case ToggleFlashlightIntent():
        _statusMessage = 'Toggling flashlight...';
        notifyListeners();
        final torchOn = await _flashlightService.toggleFlashlight();
        final message = torchOn ? 'Flashlight is ON.' : 'Flashlight is OFF.';
        _statusMessage = message;
        notifyListeners();
        await _speakResponse(message);
        break;
      case ToggleDeviceIntent(:final device, :final desired):
        final toggle =
            device == 'wifi' ? SystemToggle.wifi : SystemToggle.bluetooth;
        final label = device == 'wifi' ? 'Wi-Fi' : 'Bluetooth';
        final desiredLabel = desired == ToggleDesired.on ? 'on' : desired == ToggleDesired.off ? 'off' : 'toggle';
        _statusMessage = 'Turning $label $desiredLabel...';
        notifyListeners();
        final result = await _deviceControl.toggle(toggle, desired: desired);
        final String message;
        if (result.errorMessage != null) {
          message = result.errorMessage!;
        } else if (result.panelOpened) {
          message = 'Opening $label settings. Tap to turn $desiredLabel.';
        } else if (result.permissionRequired) {
          message = 'Need permission to turn $label $desiredLabel. Allow in settings.';
        } else {
          // Check if the desired state matches PREVIOUS state for on/off
          // (wasOn = state before the operation)
          if (desired == ToggleDesired.on && result.wasOn) {
            message = '$label is already ON.';
          } else if (desired == ToggleDesired.off && !result.wasOn) {
            message = '$label is already OFF.';
          } else {
            message = result.isOn ? '$label is ON.' : '$label is OFF.';
          }
        }
        _statusMessage = message;
        notifyListeners();
        await _speakResponse(message);
        break;
      case MediaIntent(:final action):
        await _handleMediaControl(action);
        break;
      case VolumeIntent(:final level, :final delta, :final unmute, :final mute):
        await _handleVolumeControl(level, delta, unmute, mute);
        break;
      case BrightnessIntent(:final level, :final delta):
        await _handleBrightnessControl(level, delta);
        break;
      case SendWhatsAppIntent(:final contactName, :final message):
        await _handleSendWhatsApp(contactName, message);
        break;
      case SendSmsIntent(:final recipient, :final message, :final phoneNumber):
        await _handleSendSms(recipient, message, phoneNumber: phoneNumber);
        break;
      case CallIntent(:final contactName):
        await _handleMakeCall(contactName);
        break;
      case PlayGalleryVideoIntent(:final index):
        await _handlePlayGalleryVideo(index);
        break;
      case YouTubeSearchPlayIntent(:final query, :final index):
        await _handleYouTubeSearchPlay(query, index);
        break;
      case AiAskIntent(:final target, :final query):
        await _handleAiAsk(target, query);
        break;
      case CustomIntent(:final phrase, :final params, :final commandId):
        await _handleCustomCommand(phrase, params, commandId);
        break;
      case ReadChatIntent(:final contactName, :final count):
        await _handleReadChat(contactName, count);
        break;
      case SetAlarmIntent(:final time, :final label):
        await _handleSetAlarm(time, label);
        break;
      case SetReminderIntent(:final time, :final message):
        await _handleSetReminder(time, message);
        break;
      case ListAlarmsIntent():
        await _handleListAlarms();
        break;
      case CancelAlarmIntent(:final query):
        await _handleCancelAlarm(query);
        break;
      case ReadEmailIntent(:final count):
        await _handleReadEmail(count);
        break;
      case ScreenContextIntent():
        await _handleScreenContext(intent);
        break;
      case SequenceIntent(:final steps):
        await _executeSequence(steps);
        break;
    }

    if (_statusMessage.isNotEmpty) {
      _dialogueTracker.recordTurn(
        role: 'assistant',
        utterance: _statusMessage,
      );
    }
  }

  /// Resolves a compound utterance into ordered intents via heuristics.
  ///
  /// Returns null when any step cannot be understood heuristically (caller
  /// then falls back to LLM per-step inference).
  List<AssistantIntent>? _heuristicSequence(List<String> stepTexts) {
    if (stepTexts.length < 2) return null;
    final intents = <AssistantIntent>[];
    for (final step in stepTexts) {
      final intent = _heuristicIntent(step);
      if (intent == null) return null;
      // Never nest sequences. Chat + device mixes are not sequences —
      // handle them via the LLM path instead.
      if (intent is SequenceIntent) return null;
      if (intent is UnsupportedIntent) return null;
      if (intent is ChatIntent) return null;
      intents.add(intent);
    }
    return intents;
  }

  /// Offline small-talk detector. Returns a kind key for
  /// [ResponseGenerator.chatForKind], or null when the input is a device
  /// command or out-of-scope request (those keep the existing
  /// unsupported/cannotUnderstand behavior).
  ///
  /// Intentionally narrow so device phrases never match:
  /// - "Call John", "What's the weather?" stay unsupported (alarms and
  ///   reminders are device commands handled by the alarm fast-path).
  /// - "Play Arijit Singh" stays unsupported (media heuristic owns play).
  static String? heuristicChatKind(String rawInput) {
    final input = rawInput.trim().toLowerCase();
    if (input.isEmpty || input.length > 140) return null;

    // Device/task signals disqualify chat — these belong to command handlers.
    const deviceSignals = [
      'open',
      'launch',
      'start',
      'turn on',
      'turn off',
      'toggle',
      'flash',
      'torch',
      'bluetooth',
      'wifi',
      'wi-fi',
      'volume',
      'brightness',
      'mute',
      'unmute',
      'play',
      'pause',
      'resume',
      'stop',
      'next',
      'previous',
      'skip',
      'song',
      'music',
      'video',
      'youtube',
      'gallery',
      'whatsapp',
      'message',
      'send',
      'call',
      'alarm',
      'mail',
      'email',
      'gmail',
      'inbox',
      'unread',
      'weather',
      'search',
      'ask deepseek',
      'ask chatgpt',
      'ask gemini',
      'ask gpt',
      'deepseek',
      'chatgpt',
      'chat gpt',
      'gemini',
      'set ',
      'screen',
    ];
    if (deviceSignals.any(input.contains)) {
      // "dim the screen" is brightness; "thank you for opening..." edge —
      // still let device path win when a device verb is present, except a
      // leading thanks ("thanks, open youtube" is a compound, not chat).
      return null;
    }

    bool matches(RegExp re) => re.hasMatch(input);

    if (matches(RegExp(r'\bgood\s+morning\b'))) return 'morning';
    if (matches(RegExp(r'\bgood\s+afternoon\b'))) return 'afternoon';
    if (matches(RegExp(r'\bgood\s+evening\b'))) return 'evening';
    if (matches(RegExp(
        r'\b(who are you|what are you|your name|about yourself|introduce yourself)\b'))) {
      return 'who_are_you';
    }
    if (matches(RegExp(
        r'\b(what can you do|what do you do|help|capabilit|commands|how do i use)\b'))) {
      return 'help';
    }
    if (matches(RegExp(
        r'\b(how are you|how r u|how are u|hows it going|how do you do|how is it going)\b'))) {
      return 'how_are_you';
    }
    if (matches(RegExp(r'\b(thank you|thanks|thankyou|thx|shukriya|dhanyavad)\b'))) {
      return 'thanks';
    }
    if (matches(RegExp(
        r'^(bye|goodbye|good bye|see you|see ya|good ?night|take care|catch you later)\b')) ||
        matches(RegExp(r'\b(bye|goodbye)\b'))) {
      return 'bye';
    }
    if (matches(RegExp(
        r'^(hi|hii+|hello|helo|hey|yo|namaste|salaam|sat sri akal|vanakkam)\b[\s!.,]*$')) ||
        matches(RegExp(
            r'^(hi|hello|hey)\s+friday\b')) ||
        matches(RegExp(r'^friday\s+(hi|hello|hey)\b'))) {
      return 'greeting';
    }

    return null;
  }

  /// Speaks a conversational reply (offline heuristic or LLM `chat` intent).
  Future<void> _handleChat(String rawMessage) async {
    final message = _responseGenerator.chat(rawMessage);
    _statusMessage = message;
    notifyListeners();
    await _speakResponse(message);
  }

  /// Handles "task1, task2, task3" by running each step one-by-one in order.
  ///
  /// Strategy (offline-first):
  /// 1. Try pure heuristics for every step (covers open/volume/brightness/
  ///    flashlight/media without any LLM call).
  /// 2. Otherwise ask the LLM once for the full utterance (it may return a
  ///    JSON array) and execute that sequence.
  /// 3. Otherwise resolve each step individually (heuristic, then per-step
  ///    LLM infer+parse) and execute whatever resolved.
  Future<void> _handleCompoundCommand(
      List<String> stepTexts, String fullInput) async {
    // Cap steps to avoid runaway TTS / native calls.
    final steps = stepTexts.take(10).toList();

    // 1. Pure-heuristic fast path.
    final heuristicSteps = _heuristicSequence(steps);
    if (heuristicSteps != null) {
      await _executeSequence(heuristicSteps);
      return;
    }

    // 2. Single LLM call for the whole compound utterance.
    try {
      final rawResponse = await _llmService.infer(fullInput);
      _lastRawModelOutput = rawResponse;
      final parsed = _intentParser.parse(rawResponse);
      if (parsed is SequenceIntent && parsed.steps.length >= 2) {
        await _executeSequence(parsed.steps.take(10).toList());
        return;
      }
      // LLM returned a single intent but input had multiple steps — fall
      // through to per-step resolution rather than dropping tasks.
    } catch (_) {
      // Ignore and fall through to per-step resolution.
    }

    // 3. Per-step resolution: heuristic first, then one LLM infer per
    //    unresolved step.
    final resolved = <AssistantIntent>[];
    for (final step in steps) {
      final h = _heuristicIntent(step);
      if (h != null && h is! UnsupportedIntent && h is! SequenceIntent) {
        resolved.add(h);
        continue;
      }
      try {
        final raw = await _llmService.infer(step);
        // Keep last raw output as the most recent step for debugging.
        _lastRawModelOutput = raw;
        final parsed = _intentParser.parse(raw);
        if (parsed is SequenceIntent) {
          resolved.addAll(parsed.steps.take(10 - resolved.length));
        } else if (parsed is! UnsupportedIntent) {
          resolved.add(parsed);
        } else {
          // Unsupported step — abort with clear message.
          final message = _responseGenerator.unsupportedCommand();
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
          return;
        }
      } catch (e) {
        if (e is AppException) {
          _lastProcessingError = e.message;
          final message = _messageForException(e);
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        } else {
          _lastProcessingError = '$e';
          final message = _responseGenerator.cannotUnderstand();
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        }
        return;
      }
    }

    if (resolved.isEmpty) {
      final message = _responseGenerator.cannotUnderstand();
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
      return;
    }
    if (resolved.length == 1) {
      await _dispatchIntent(resolved.first);
      return;
    }
    await _executeSequence(resolved);
  }

  /// Executes [steps] strictly one-by-one in order, awaiting each before
  /// starting the next.
  ///
  /// Each step updates [_statusMessage] with "Step i/N ..." progress so the
  /// UI shows ordering. Only ONE spoken reply is produced at the end
  /// (full success -> "Done. All N tasks completed.", partial -> honest
  /// count), keeping the single-utterance-per-command TTS contract.
  Future<void> _executeSequence(List<AssistantIntent> steps) async {
    final capped = steps.take(10).toList();
    final total = capped.length;
    if (total == 0) {
      final message = _responseGenerator.cannotUnderstand();
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
      return;
    }
    if (total == 1) {
      await _dispatchIntent(capped.first);
      return;
    }

    final lines = <String>[];
    var succeeded = 0;

    for (var i = 0; i < capped.length; i++) {
      final step = capped[i];
      _statusMessage = 'Step ${i + 1}/$total...';
      notifyListeners();
      try {
        final result = await _executeStepSilently(step);
        if (result.success) {
          succeeded++;
          lines.add('${i + 1}. ${result.message}');
        } else {
          lines.add('${i + 1}. ${result.message}');
        }
        // Show incremental progress on screen.
        _statusMessage = lines.join('\n');
        notifyListeners();
      } catch (e) {
        final message =
            e is AppException ? _messageForException(e) : '$e';
        lines.add('${i + 1}. $message');
        _lastProcessingError =
            e is AppException ? e.message : '$e';
        _statusMessage = lines.join('\n');
        notifyListeners();
        // Continue with remaining steps one-by-one (do not abort the
        // whole routine on a single failure).
      }
    }

    final summary = _responseGenerator.sequenceSummary(lines);
    _statusMessage = summary;
    notifyListeners();

    if (succeeded == total) {
      await _speakResponse(_responseGenerator.sequenceDone(total));
    } else if (succeeded == 0) {
      // All failed: speak the detailed summary so the user hears why.
      await _speakResponse(summary);
    } else {
      await _speakResponse(
          '${_responseGenerator.sequencePartial(succeeded, total)} $summary');
    }
  }

  /// Runs a single intent without speaking, returning its outcome.
  ///
  /// Used by [_executeSequence] so N tasks produce exactly one final
  /// utterance instead of N overlapping TTS calls.
  Future<_StepResult> _executeStepSilently(AssistantIntent intent) async {
    switch (intent) {
      case UnsupportedIntent():
        throw const UnsupportedActionException();
      case ChatIntent(:final message):
        return _StepResult(true, _responseGenerator.chat(message));
      case SequenceIntent(:final steps):
        // Flatten (should not happen — sequences never nest).
        final lines = <String>[];
        var ok = true;
        for (final s in steps.take(10)) {
          final r = await _executeStepSilently(s);
          lines.add(r.message);
          if (!r.success) ok = false;
        }
        return _StepResult(ok, lines.join(' '));
      case OpenAppIntent(:final target):
        final appLabel = await _appLauncher.resolveApp(target);
        _isOpening = true;
        notifyListeners();
        try {
          await _appLauncher.launchApp(target);
        } finally {
          _isOpening = false;
        }
        return _StepResult(true, _responseGenerator.opening(appLabel));
      case ToggleFlashlightIntent():
        final torchOn = await _flashlightService.toggleFlashlight();
        return _StepResult(
            true, torchOn ? 'Flashlight is ON.' : 'Flashlight is OFF.');
      case ToggleDeviceIntent(:final device, :final desired):
        final toggle =
            device == 'wifi' ? SystemToggle.wifi : SystemToggle.bluetooth;
        final label = device == 'wifi' ? 'Wi-Fi' : 'Bluetooth';
        final desiredLabel = desired == ToggleDesired.on ? 'on' : desired == ToggleDesired.off ? 'off' : 'toggle';
        final result = await _deviceControl.toggle(toggle, desired: desired);
        if (result.errorMessage != null) {
          return _StepResult(false, result.errorMessage!);
        } else if (result.panelOpened) {
          return _StepResult(
              true, 'Opening $label settings. Tap to turn $desiredLabel.');
        } else if (result.permissionRequired) {
          return _StepResult(
              false, 'Need permission to turn $label $desiredLabel. Allow in settings.');
        } else {
          // Check if the desired state matches PREVIOUS state for on/off
          // (wasOn = state before the operation)
          if (desired == ToggleDesired.on && result.wasOn) {
            return _StepResult(true, '$label is already ON.');
          } else if (desired == ToggleDesired.off && !result.wasOn) {
            return _StepResult(true, '$label is already OFF.');
          } else {
            return _StepResult(
                true, result.isOn ? '$label is ON.' : '$label is OFF.');
          }
        }
      case MediaIntent(:final action):
        final result = await _mediaControl.perform(action);
        if (!result.success) {
          return _StepResult(
              false, _responseGenerator.mediaControlFailed());
        }
        final message = switch (action) {
          MediaAction.play => _responseGenerator.mediaPlaying(),
          MediaAction.pause => _responseGenerator.mediaPaused(),
          MediaAction.resume => _responseGenerator.mediaResuming(),
          MediaAction.next => _responseGenerator.mediaSkipping(),
          MediaAction.previous => _responseGenerator.mediaGoingBack(),
          MediaAction.stop => _responseGenerator.mediaStopped(),
        };
        return _StepResult(true, message);
      case VolumeIntent(:final level, :final delta, :final unmute, :final mute):
        final VolumeControlResult result;
        if (unmute) {
          result = await _volumeControl.unmute();
        } else if (mute) {
          result = await _volumeControl.mute();
        } else if (level != null) {
          result = await _volumeControl.setVolume(level);
        } else if (delta > 0) {
          result = await _applyVolumeStep(1);
        } else if (delta < 0) {
          result = await _applyVolumeStep(-1);
        } else {
          result = await _volumeControl.query();
        }
        if (!result.success) {
          return _StepResult(false,
              result.errorMessage ?? _responseGenerator.volumeControlFailed());
        }
        if (unmute) {
          return _StepResult(
              true, _responseGenerator.volumeUnmuted(result.level));
        } else if (mute) {
          return _StepResult(true, _responseGenerator.volumeMuted());
        } else if (level != null) {
          return _StepResult(
              true, _responseGenerator.volumeSet(result.level));
        } else if (delta > 0) {
          return _StepResult(
              true, _responseGenerator.volumeUpResult(result.level));
        } else if (delta < 0) {
          return _StepResult(
              true, _responseGenerator.volumeDownResult(result.level));
        }
        return _StepResult(
            true, _responseGenerator.volumeQuery(result.level));
      case BrightnessIntent(:final level, :final delta):
        final BrightnessControlResult result;
        if (level != null) {
          result = await _brightnessControl.setBrightness(level);
        } else if (delta > 0) {
          result = await _applyBrightnessStep(1);
        } else if (delta < 0) {
          result = await _applyBrightnessStep(-1);
        } else {
          result = await _brightnessControl.query();
        }
        if (!result.success) {
          if (result.permissionRequired) {
            return _StepResult(false,
                _responseGenerator.brightnessPermissionRequired());
          }
          return _StepResult(
              false,
              result.errorMessage ??
                  _responseGenerator.brightnessControlFailed());
        }
        if (level != null) {
          return _StepResult(
              true, _responseGenerator.brightnessSet(result.level));
        } else if (delta > 0) {
          return _StepResult(
              true, _responseGenerator.brightnessUpResult(result.level));
        } else if (delta < 0) {
          return _StepResult(
              true, _responseGenerator.brightnessDownResult(result.level));
        }
        return _StepResult(
            true, _responseGenerator.brightnessQuery(result.level));
      case SendWhatsAppIntent(:final contactName, :final message):
        final result = await _whatsAppService.sendWhatsApp(
          contactName: contactName,
          message: message,
        );
        final displayName = result.resolvedName ?? contactName;
        return _StepResult(
            true, _responseGenerator.openingWhatsApp(displayName));
      case SendSmsIntent(:final recipient, :final message, :final phoneNumber):
        final displayTarget = (recipient.toUpperCase() == 'FO' || recipient.toLowerCase().contains('wajo fo'))
            ? AppConstants.foDisplayName
            : recipient;
        await _smsService.sendSms(
          recipient: recipient,
          message: message,
          phoneNumber: phoneNumber,
        );
        return _StepResult(true, _responseGenerator.smsSent(displayTarget));
      case CallIntent(:final contactName):
        final callResult = await _callService.makeCall(contactName: contactName);
        final callDisplay = callResult.resolvedName ?? contactName;
        return _StepResult(true, _responseGenerator.calling(callDisplay));
      case PlayGalleryVideoIntent(:final index):
        final safeIndex = index.clamp(1, 50);
        _isOpening = true;
        notifyListeners();
        try {
          await _galleryService.playVideoAt(index: safeIndex);
        } finally {
          _isOpening = false;
        }
        return _StepResult(
            true, _responseGenerator.playingGalleryVideo(safeIndex));
      case YouTubeSearchPlayIntent(:final query, :final index):
        final safeIndex = index.clamp(1, 50);
        _isOpening = true;
        notifyListeners();
        try {
          final ytResult = await _youTubeService.searchAndPlay(
              query: query, index: safeIndex);
          final ytMessage = ytResult.autoPlayed
              ? _responseGenerator.playingYouTubeResult(query, safeIndex)
              : _responseGenerator.youTubeOpenedTapManually(
                  query, safeIndex);
          return _StepResult(true, ytMessage);
        } finally {
          _isOpening = false;
        }
      case AiAskIntent(:final target, :final query):
        _isOpening = true;
        notifyListeners();
        try {
          final aiResult =
              await _aiAskService.ask(target: target, query: query);
          final aiMessage = aiResult.autoSent
              ? _responseGenerator.aiAskSent(aiResult.appLabel)
              : _responseGenerator.aiAskOpenedTapSend(
                  aiResult.appLabel, query);
          return _StepResult(true, aiMessage);
        } finally {
          _isOpening = false;
        }
      case CustomIntent(:final phrase, :final params, :final commandId):
        CustomCommand? cmd;
        if (commandId != null) {
          try {
            cmd = _customCommands.firstWhere((c) => c.id == commandId);
          } catch (_) {}
          cmd ??= await _tapStorage.getById(commandId);
        }
        if (cmd == null) {
          final match = await findCustomCommandMatch(phrase);
          if (match == null) throw CustomCommandNotFoundException(phrase);
          cmd = match.command;
          if (params.isEmpty) {
            // params is final on the intent — use matched params.
            final result = await _automationService.executeCommand(
                cmd, match.params);
            _lastAutomationResult = result.collectedTexts.join('\n');
            if (result.collectedTexts.isNotEmpty) {
              return _StepResult(true,
                  '${cmd.displayName} completed. ${result.collectedTexts.first}');
            }
            return _StepResult(
                true, _responseGenerator.customCollected(cmd.displayName));
          }
        }
        _isExecutingAutomation = true;
        notifyListeners();
        try {
          final result =
              await _automationService.executeCommand(cmd, params);
          _isExecutingAutomation = false;
          _lastAutomationResult = result.collectedTexts.join('\n');
          if (result.collectedTexts.isNotEmpty) {
            return _StepResult(true,
                '${cmd.displayName} completed. ${result.collectedTexts.first}');
          }
          return _StepResult(
              true, _responseGenerator.customCollected(cmd.displayName));
        } catch (_) {
          _isExecutingAutomation = false;
          rethrow;
        }
      case ReadChatIntent(:final contactName):
        final match =
            await findCustomCommandMatch('check whatsapp messages');
        if (match != null) {
          final r = await _executeStepSilently(CustomIntent(
              phrase: match.command.phraseTemplate,
              params: {},
              commandId: match.command.id));
          return r;
        }
        try {
          await _appLauncher.launchApp('whatsapp');
        } catch (_) {}
        return _StepResult(
            true, _responseGenerator.readChatResult(contactName));
      case SetAlarmIntent(:final time, :final label):
        final item = await _alarmService.setAlarm(time, label: label);
        return _StepResult(
            true,
            _responseGenerator.alarmSet(
                alarm_parser.formatAlarmSpeech(item.time),
                label: item.label));
      case SetReminderIntent(:final time, :final message):
        final reminder = await _alarmService.setReminder(time, message);
        return _StepResult(
            true,
            _responseGenerator.reminderSet(reminder.label,
                alarm_parser.formatAlarmSpeech(reminder.time)));
      case ListAlarmsIntent():
        final items = await _alarmService.listAlarms();
        final lines = <String>[];
        final sorted = [...items]
          ..sort((a, b) => a.triggerAtMillis.compareTo(b.triggerAtMillis));
        for (var i = 0; i < sorted.length && i < 10; i++) {
          final it = sorted[i];
          final whenSpeech = alarm_parser.formatAlarmSpeech(it.time);
          final kind = it.kind == 'reminder' ? 'Reminder' : 'Alarm';
          final name =
              it.label.trim().isEmpty ? kind : '$kind: ${it.label}';
          lines.add('${i + 1}. $name $whenSpeech.');
        }
        return _StepResult(true, _responseGenerator.alarmsListed(lines));
      case CancelAlarmIntent(:final query):
        final cancelled = await _alarmService.cancelAlarm(query);
        if (cancelled == 0) {
          return _StepResult(
              false, _responseGenerator.alarmsCancelled(0));
        }
        return _StepResult(
            true, _responseGenerator.alarmsCancelled(cancelled));
      case ReadEmailIntent(:final count):
        final mails = await _gmailService.listUnread(count: count.clamp(1, 10));
        _lastEmails = mails;
        if (mails.isEmpty) {
          return const _StepResult(true, 'You have no unread mails.');
        }
        final lines = <String>[];
        for (var i = 0; i < mails.length; i++) {
          lines.add('${i + 1}. ${mails[i].from} — ${mails[i].subject}.');
        }
        return _StepResult(true, _responseGenerator.emailsListed(lines));
      case ScreenContextIntent():
        final screenCtx = await _screenContextService.captureContext(maxNodes: 60);
        final summary = _screenContextService.generateOfflineSummary(screenCtx);
        return _StepResult(true, summary);
    }
  }

  /// Validates, opens the requested app, and confirms with a short voice reply.
  ///
  /// Resolution happens first so FRIDAY can confirm the app exists (and
  /// learn its real label). The screen shows the detail ("Opening Spotify.")
  /// while voice says only "Done." Then speech and launch run concurrently
  /// so the app opens instantly while the confirmation plays. A TTS failure
  /// never blocks the launch.
  Future<void> _handleOpenApp(String target) async {
    // Defense-in-depth: if the USER said flash/torch but the model emitted
    // open_app (e.g. target "game assistant" / "flashlight"), honor the user
    // and toggle the torch instead of launching a wrong app.
    final userCmd = (_lastUserCommand ?? '').toLowerCase();
    if (userCmd.contains('flash') || userCmd.contains('torch')) {
      final torchOn = await _flashlightService.toggleFlashlight();
      final torchMsg = torchOn ? 'Flashlight is ON.' : 'Flashlight is OFF.';
      _statusMessage = torchMsg;
      notifyListeners();
      await _speakResponse(torchMsg);
      return;
    }
    // 5. Android native layer validates and resolves the app (no launch).
    final appLabel = await _appLauncher.resolveApp(target);

    final displayMessage = _responseGenerator.opening(appLabel);
    _statusMessage = displayMessage;
    notifyListeners();

    // 6. Speak and launch concurrently — never wait for audio before
    // opening the app. Voice says only "Done.", screen keeps the detail.
    final speakFuture = _speakResponse(_responseGenerator.done());

    // 7. Launch immediately while the response is playing.
    _isOpening = true;
    notifyListeners();
    try {
      await _appLauncher.launchApp(target);
    } finally {
      _isOpening = false;
    }

    // 8. Still await speech so one command produces exactly one completed
    // utterance before processCommand returns.
    await speakFuture;
  }

  /// Dispatches a media transport action through the Android native layer and
  /// confirms with a short spoken response.
  ///
  /// The native layer re-validates [action] before executing. A non-success
  /// result (or a thrown [MediaControlException]) is reported honestly rather
  /// than claiming the command was executed.
  Future<void> _handleMediaControl(MediaAction action) async {
    final result = await _mediaControl.perform(action);

    final String message;
    if (result.success) {
      message = switch (action) {
        MediaAction.play => _responseGenerator.mediaPlaying(),
        MediaAction.pause => _responseGenerator.mediaPaused(),
        MediaAction.resume => _responseGenerator.mediaResuming(),
        MediaAction.next => _responseGenerator.mediaSkipping(),
        MediaAction.previous => _responseGenerator.mediaGoingBack(),
        MediaAction.stop => _responseGenerator.mediaStopped(),
      };
    } else {
      message = _responseGenerator.mediaControlFailed();
    }

    _statusMessage = message;
    notifyListeners();
    await _speakResponse(message);
  }

  /// Applies the user-configured volume step in [direction] (+1 up, -1 down).
  ///
  /// Queries the current level first so "increase volume" moves by exactly
  /// [volumeStep] percent. Falls back to the legacy single native step when
  /// the query fails.
  Future<VolumeControlResult> _applyVolumeStep(int direction) async {
    final step = _volumeStep.clamp(1, 30);
    final sign = direction >= 0 ? 1 : -1;
    try {
      final current = await _volumeControl.query();
      if (current.success) {
        final target = (current.level + sign * step).clamp(0, 100);
        return await _volumeControl.setVolume(target);
      }
    } catch (_) {}
    return sign > 0
        ? await _volumeControl.volumeUp()
        : await _volumeControl.volumeDown();
  }

  /// Applies the user-configured brightness step in [direction] (+1/-1).
  Future<BrightnessControlResult> _applyBrightnessStep(int direction) async {
    final step = _brightnessStep.clamp(1, 30);
    final sign = direction >= 0 ? 1 : -1;
    try {
      final current = await _brightnessControl.query();
      if (current.success) {
        final target = (current.level + sign * step).clamp(0, 100);
        return await _brightnessControl.setBrightness(target);
      }
    } catch (_) {}
    return sign > 0
        ? await _brightnessControl.brightnessUp()
        : await _brightnessControl.brightnessDown();
  }

  /// Adjusts the media volume through the Android native layer and confirms
  /// with a short spoken response.
  Future<void> _handleVolumeControl(int? level, int delta, bool unmute, bool mute) async {
    final VolumeControlResult result;
    if (unmute) {
      result = await _volumeControl.unmute();
    } else if (mute) {
      result = await _volumeControl.mute();
    } else if (level != null) {
      result = await _volumeControl.setVolume(level);
    } else if (delta > 0) {
      result = await _applyVolumeStep(1);
    } else if (delta < 0) {
      result = await _applyVolumeStep(-1);
    } else {
      result = await _volumeControl.query();
    }

    final String message;
    if (result.success) {
      if (unmute) {
        message = _responseGenerator.volumeUnmuted(result.level);
      } else if (mute) {
        message = _responseGenerator.volumeMuted();
      } else if (level != null) {
        message = _responseGenerator.volumeSet(result.level);
      } else if (delta > 0) {
        message = _responseGenerator.volumeUpResult(result.level);
      } else if (delta < 0) {
        message = _responseGenerator.volumeDownResult(result.level);
      } else {
        message = _responseGenerator.volumeQuery(result.level);
      }
    } else {
      message = result.errorMessage ?? _responseGenerator.volumeControlFailed();
    }

    _statusMessage = message;
    notifyListeners();
    final bool isQuery = !unmute && !mute && level == null && delta == 0;
    await _speakResponse(
        result.success && !isQuery ? _responseGenerator.done() : message);
  }

  /// Adjusts the screen brightness through the Android native layer and
  /// confirms with a short spoken response.
  Future<void> _handleBrightnessControl(int? level, int delta) async {
    final BrightnessControlResult result;
    if (level != null) {
      result = await _brightnessControl.setBrightness(level);
    } else if (delta > 0) {
      result = await _applyBrightnessStep(1);
    } else if (delta < 0) {
      result = await _applyBrightnessStep(-1);
    } else {
      result = await _brightnessControl.query();
    }

    final String message;
    if (result.success) {
      if (level != null) {
        message = _responseGenerator.brightnessSet(result.level);
      } else if (delta > 0) {
        message = _responseGenerator.brightnessUpResult(result.level);
      } else if (delta < 0) {
        message = _responseGenerator.brightnessDownResult(result.level);
      } else {
        message = _responseGenerator.brightnessQuery(result.level);
      }
    } else if (result.permissionRequired) {
      message = _responseGenerator.brightnessPermissionRequired();
    } else {
      message = result.errorMessage ?? _responseGenerator.brightnessControlFailed();
    }

    _statusMessage = message;
    notifyListeners();
    final bool isQuery = level == null && delta == 0;
    await _speakResponse(
        result.success && !isQuery ? _responseGenerator.done() : message);
  }

  /// Resolves contact name -> phone via native layer, speaks confirmation,
  /// then opens WhatsApp chat with pre-filled message.
  ///
  /// TTS is spoken first so user hears confirmation even if WhatsApp
  /// fails to launch. The message is pre-filled but not auto-sent
  /// (Android security requires user to tap send).
  Future<void> _handleSendWhatsApp(String contactName, String message) async {
    _statusMessage = 'Opening WhatsApp...';
    notifyListeners();

    final result = await _whatsAppService.sendWhatsApp(
      contactName: contactName,
      message: message,
    );

    // Use resolved display name if available for natural speech
    final displayName = result.resolvedName ?? contactName;
    final speakMessage = _responseGenerator.openingWhatsApp(displayName);
    _statusMessage = speakMessage;
    notifyListeners();
    await _speakResponse(speakMessage);
  }

  /// Sends an SMS or messages an AI assistant like FO (+1 628-998-5940) or a contact.
  Future<void> _handleSendSms(
    String recipient,
    String message, {
    String? phoneNumber,
  }) async {
    final displayTarget = (recipient.toUpperCase() == 'FO' || recipient.toLowerCase().contains('wajo fo'))
        ? AppConstants.foDisplayName
        : recipient;
    _statusMessage = _responseGenerator.smsSending(displayTarget);
    notifyListeners();

    try {
      await _smsService.sendSms(
        recipient: recipient,
        message: message,
        phoneNumber: phoneNumber,
      );

      final speakMessage = _responseGenerator.smsSent(displayTarget);
      _statusMessage = speakMessage;
      notifyListeners();
      await _speakResponse(speakMessage);
    } catch (e) {
      final speakMessage = _responseGenerator.smsFailed();
      _statusMessage = speakMessage;
      notifyListeners();
      await _speakResponse(speakMessage);
      rethrow;
    }
  }

  /// Resolves contact name -> phone via native layer and places a direct
  /// phone call with ACTION_CALL.
  ///
  /// Speaks "Calling <name>." first so the user hears confirmation even if
  /// the dialer fails to open. A TTS failure never blocks the call.
  Future<void> _handleMakeCall(String contactName) async {
    _statusMessage = 'Calling...';
    notifyListeners();

    final result = await _callService.makeCall(contactName: contactName);

    final displayName = result.resolvedName ?? contactName;
    final speakMessage = _responseGenerator.calling(displayName);
    _statusMessage = speakMessage;
    notifyListeners();
    await _speakResponse(speakMessage);
  }

  /// Handles execution of a matched teachable custom command.
  Future<void> _handleCustomCommand(String phrase, Map<String, String> params, String? commandId) async {
    CustomCommand? cmd;
    if (commandId != null) {
      try {
        cmd = _customCommands.firstWhere((c) => c.id == commandId);
      } catch (_) {}
      cmd ??= await _tapStorage.getById(commandId);
    }
    if (cmd == null) {
      final match = await findCustomCommandMatch(phrase);
      if (match == null) throw CustomCommandNotFoundException(phrase);
      cmd = match.command;
      // Merge LLM-extracted phrase params with template match
      if (params.isEmpty) params = match.params;
    }

    _isExecutingAutomation = true;
    _statusMessage = _responseGenerator.customExecuting(cmd.displayName);
    notifyListeners();

    final result = await _automationService.executeCommand(cmd, params);
    _isExecutingAutomation = false;
    _lastAutomationResult = result.collectedTexts.join('\n');

    final String message;
    if (result.collectedTexts.isNotEmpty) {
      // Show collected texts in status; summarize if many
      message = '${cmd.displayName} completed. ${result.collectedTexts.first}';
      _statusMessage = result.collectedTexts.join('\n');
    } else {
      message = _responseGenerator.customCollected(cmd.displayName);
      _statusMessage = message;
    }
    notifyListeners();
    await _speakResponse(message);
  }

  /// Handles read chat intent via automation fallback or direct message.
  Future<void> _handleReadChat(String contactName, int count) async {
    // Try custom automation first if a command exists for reading whatsapp
    final match = await findCustomCommandMatch('check whatsapp messages');
    if (match != null) {
      await _handleCustomCommand(match.command.phraseTemplate, {}, match.command.id);
      return;
    }
    // Fallback: try to execute a generic read via automation steps constructed on fly
    // If no automation, open whatsapp via existing service if available
    final message = _responseGenerator.readChatResult(contactName);
    _statusMessage = message;
    notifyListeners();
    await _speakResponse(message);
    // Try to open whatsapp as best effort
    try {
      await _appLauncher.launchApp('whatsapp');
    } catch (_) {}
  }

  /// Opens the gallery and plays the Nth video (1-based, most-recent-first).
  ///
  /// Speaks first ("Playing second video...") so the user hears confirmation,
  /// then the native layer queries MediaStore and launches a VIEW intent.
  /// A TTS failure never blocks playback.
  Future<void> _handlePlayGalleryVideo(int index) async {
    final safeIndex = index.clamp(1, 50);
    final message = _responseGenerator.playingGalleryVideo(safeIndex);
    _statusMessage = message;
    notifyListeners();
    await _speakResponse(message);

    _isOpening = true;
    notifyListeners();
    try {
      await _galleryService.playVideoAt(index: safeIndex);
    } finally {
      _isOpening = false;
    }
  }

  /// Opens YouTube with [query] and plays the Nth result (1-based).
  ///
  /// The native layer opens the search results (reliable offline, no API key)
  /// and auto-plays the Nth result when the accessibility service is
  /// enabled (node-based click with retries); otherwise results are opened
  /// and the user taps manually — reported honestly instead of claiming
  /// playback.
  Future<void> _handleYouTubeSearchPlay(String query, int index) async {
    final safeIndex = index.clamp(1, 50);
    _statusMessage = _responseGenerator.searchingYouTube(query, safeIndex);
    notifyListeners();

    _isOpening = true;
    notifyListeners();
    try {
      final result = await _youTubeService.searchAndPlay(
          query: query, index: safeIndex);
      final message = result.autoPlayed
          ? _responseGenerator.playingYouTubeResult(query, safeIndex)
          : _responseGenerator.youTubeOpenedTapManually(query, safeIndex);
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
    } finally {
      _isOpening = false;
    }
  }

  /// Asks an installed AI app ([target] deepseek/chatgpt/gemini): opens the
  /// app, types [query], taps Send via accessibility.
  ///
  /// App-only, no browser fallback. When the app is missing, reports
  /// "X isn't installed." When accessibility is off or Send isn't found,
  /// opens the app and asks the user to tap Send manually — reported
  /// honestly instead of claiming auto-send.
  Future<void> _handleAiAsk(String target, String query) async {
    final label = MethodChannelAiAskService.displayLabel(target);
    _statusMessage = _responseGenerator.askingAi(label, query);
    notifyListeners();

    _isOpening = true;
    notifyListeners();
    try {
      final result = await _aiAskService.ask(target: target, query: query);
      final message = result.autoSent
          ? _responseGenerator.aiAskSent(result.appLabel)
          : _responseGenerator.aiAskOpenedTapSend(result.appLabel, query);
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
    } on AiAskNotInstalledException catch (e) {
      final message = _responseGenerator.aiNotInstalled(e.appName);
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
    } on AppNotInstalledException catch (e) {
      final message = _responseGenerator.aiNotInstalled(e.appName);
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
    } on AppException catch (e) {
      _lastProcessingError = e.message;
      final message = _messageForException(e);
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
    } finally {
      _isOpening = false;
    }
  }

  /// Schedules a one-shot alarm natively and confirms with TTS.
  Future<void> _handleSetAlarm(DateTime time, String label) async {
    _statusMessage = 'Setting alarm...';
    notifyListeners();
    final item = await _alarmService.setAlarm(time, label: label);
    final whenSpeech = alarm_parser.formatAlarmSpeech(item.time);
    final message =
        _responseGenerator.alarmSet(whenSpeech, label: item.label);
    _statusMessage = message;
    notifyListeners();
    await _speakResponse(message);
  }

  /// Schedules a reminder notification natively and confirms with TTS.
  Future<void> _handleSetReminder(DateTime time, String message) async {
    _statusMessage = 'Setting reminder...';
    notifyListeners();
    final item = await _alarmService.setReminder(time, message);
    final whenSpeech = alarm_parser.formatAlarmSpeech(item.time);
    final confirm =
        _responseGenerator.reminderSet(item.label, whenSpeech);
    _statusMessage = confirm;
    notifyListeners();
    await _speakResponse(confirm);
  }

  /// Lists scheduled alarms + reminders.
  Future<void> _handleListAlarms() async {
    final items = await _alarmService.listAlarms();
    final lines = <String>[];
    final sorted = [...items]
      ..sort((a, b) => a.triggerAtMillis.compareTo(b.triggerAtMillis));
    for (var i = 0; i < sorted.length && i < 10; i++) {
      final it = sorted[i];
      final whenSpeech = alarm_parser.formatAlarmSpeech(it.time);
      final kind = it.kind == 'reminder' ? 'Reminder' : 'Alarm';
      final name = it.label.trim().isEmpty ? kind : '$kind: ${it.label}';
      lines.add('${i + 1}. $name $whenSpeech.');
    }
    final message = _responseGenerator.alarmsListed(lines);
    _statusMessage = message;
    notifyListeners();
    await _speakResponse(message);
  }

  /// Cancels matching alarms/reminders (empty query cancels all).
  Future<void> _handleCancelAlarm(String query) async {
    final cancelled = await _alarmService.cancelAlarm(query);
    final message = _responseGenerator.alarmsCancelled(cancelled);
    _statusMessage = message;
    notifyListeners();
    await _speakResponse(message);
  }

  /// Refreshes cached Gmail link state (silent sign-in, no UI).
  Future<void> checkGmailStatus() async {
    try {
      _isGmailConnected = await _gmailService.isConnected();
    } catch (_) {
      _isGmailConnected = false;
    }
    notifyListeners();
  }

  /// Shows Google account picker, requests gmail.readonly scope.
  Future<void> connectGmail() async {
    if (_isConnectingGmail) return;
    _isConnectingGmail = true;
    _statusMessage = 'Connecting Gmail...';
    notifyListeners();
    try {
      await _gmailService.connect();
      _isGmailConnected = true;
      _gmailLastError = null;
      _statusMessage = 'Gmail connected. Say "read my unread mails".';
      notifyListeners();
    } on AppException catch (e) {
      _gmailLastError = e is GmailException ? (e.detail ?? e.message) : e.message;
      _lastProcessingError = _gmailLastError;
      _statusMessage = _messageForException(e);
      notifyListeners();
      await _speakResponse(_statusMessage);
    } catch (e) {
      _gmailLastError = '$e';
      _lastProcessingError = '$e';
      _statusMessage = _messageForException(mapGmailFailure(e));
      notifyListeners();
      await _speakResponse(_statusMessage);
    } finally {
      _isConnectingGmail = false;
      notifyListeners();
    }
  }

  /// Unlinks Gmail locally (revokes + clears flag, never deletes mail).
  Future<void> disconnectGmail() async {
    try {
      await _gmailService.disconnect();
    } catch (_) {}
    _isGmailConnected = false;
    _lastEmails = const [];
    _gmailLastError = null;
    _statusMessage = 'Gmail disconnected.';
    notifyListeners();
  }

  /// Reads unread Gmail in background (no Gmail app opened) and speaks a
  /// short template summary. Mail content never leaves the phone.
  Future<void> _handleReadEmail(int count) async {
    final safeCount = count.clamp(1, 10);
    _statusMessage = _responseGenerator.readingEmails();
    notifyListeners();
    try {
      final mails = await _gmailService.listUnread(count: safeCount);
      _lastEmails = mails;
      if (mails.isEmpty) {
        const message = 'You have no unread mails.';
        _statusMessage = message;
        notifyListeners();
        await _speakResponse(message);
        return;
      }
      final lines = <String>[];
      for (var i = 0; i < mails.length; i++) {
        final m = mails[i];
        final sub = m.subject.length > 80
            ? '${m.subject.substring(0, 77).trim()}...'
            : m.subject;
        lines.add('${i + 1}. ${m.from} — $sub.');
      }
      final message = _responseGenerator.emailsListed(lines);
      _statusMessage = message;
      _gmailLastError = null;
      notifyListeners();
      await _speakResponse(message);
    } on GmailNotConnectedException {
      _isGmailConnected = false;
      final message = _responseGenerator.gmailNotConnected();
      _statusMessage = message;
      _gmailLastError = message;
      notifyListeners();
      await _speakResponse(message);
    } on GmailNetworkException {
      final message = _responseGenerator.gmailNeedsInternet();
      _statusMessage = message;
      _gmailLastError = message;
      notifyListeners();
      await _speakResponse(message);
    } on AppException catch (e) {
      _gmailLastError = e is GmailException ? (e.detail ?? e.message) : e.message;
      _lastProcessingError = _gmailLastError;
      final message = _messageForException(e);
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
    } catch (e) {
      _gmailLastError = '$e';
      _lastProcessingError = '$e';
      final message = _messageForException(mapGmailFailure(e));
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
    }
  }

  /// Offline email heuristic (no LLM): "read my mails", "check inbox",
  /// "show unread mails", "read 3 mails". Returns null when not an email
  /// command. Excludes whatsapp contexts so whatsapp stays whatsapp.
  AssistantIntent? _parseEmailHeuristic(String rawInput) {
    final lower = rawInput.toLowerCase();
    if (lower.contains('whatsapp') || lower.contains('whats app')) return null;
    final hasMail = lower.contains('gmail') ||
        lower.contains('email') ||
        lower.contains('e-mail') ||
        lower.contains(' e mail') ||
        lower.contains('mail') ||
        lower.contains('inbox') ||
        lower.contains('unread');
    if (!hasMail) return null;
    final isReadVerb = RegExp(
            r'\b(read|check|show|list|get|see|tell|any|have|new|unread|inbox)\b')
        .hasMatch(lower);
    if (!isReadVerb) return null;
    // "email mom" (send intent, Phase 2) is not a read — leave for later.
    if (RegExp(r'\b(send|write|compose|draft|reply)\b').hasMatch(lower)) {
      return null;
    }
    final n = IntentParser.parseOrdinal(rawInput) ?? 5;
    return ReadEmailIntent(count: n.clamp(1, 10));
  }

  /// Handles on-screen context awareness: reading, summarizing, entity extraction, or screen QA.
  Future<void> _handleScreenContext(ScreenContextIntent intent) async {
    _statusMessage = 'Reading screen...';
    notifyListeners();

    try {
      final screenCtx = await _screenContextService.captureContext(maxNodes: 60);

      if (screenCtx.isEmpty) {
        const message = 'I cannot see what is on your screen right now. Please make sure Accessibility is enabled for Friday.';
        _statusMessage = message;
        notifyListeners();
        await _speakResponse(message);
        return;
      }

      if (intent.action == 'extract_phone') {
        if (screenCtx.phoneNumbers.isNotEmpty) {
          final phone = screenCtx.phoneNumbers.first;
          _statusMessage = 'Calling $phone from screen...';
          notifyListeners();
          await _handleMakeCall(phone);
        } else {
          const message = "I couldn't find any phone numbers on your current screen.";
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        }
        return;
      }

      if (intent.action == 'extract_url') {
        if (screenCtx.urls.isNotEmpty) {
          final url = screenCtx.urls.first;
          final message = 'Found link: $url';
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        } else {
          const message = "I couldn't find any links on your current screen.";
          _statusMessage = message;
          notifyListeners();
          await _speakResponse(message);
        }
        return;
      }

      if (intent.action == 'read_aloud') {
        final reading = screenCtx.visibleTexts.take(5).join('. ');
        final message = reading.isNotEmpty ? reading : 'The screen appears to have no readable text.';
        _statusMessage = message;
        notifyListeners();
        await _speakResponse(message);
        return;
      }

      // Default: summarize / QA
      if (_modelStatus == ModelStatus.ready && _llmService.isReady) {
        final prompt = _screenContextService.buildLlmScreenPrompt(
          context: screenCtx,
          userQuery: _lastUserCommand ?? intent.query,
        );
        try {
          final String answer;
          if (_llmService.isChatModelLoaded) {
            answer = await _llmService.chat(prompt);
          } else {
            answer = await _llmService.infer(prompt);
          }
          final clean = answer.trim();
          if (clean.isNotEmpty && !clean.startsWith('{') && !clean.contains('"action":')) {
            _statusMessage = clean;
            notifyListeners();
            await _speakResponse(clean);
            return;
          }
        } catch (_) {}
      }

      // Offline heuristic summary
      final summary = _screenContextService.generateOfflineSummary(screenCtx);
      _statusMessage = summary;
      notifyListeners();
      await _speakResponse(summary);
    } catch (e) {
      _lastProcessingError = '$e';
      const message = 'Failed to analyze screen content.';
      _statusMessage = message;
      notifyListeners();
      await _speakResponse(message);
    }
  }

  /// Maps the final system state text to the message that should be spoken.
  String _messageForException(AppException e) {
    return switch (e) {
      InvalidIntentException() => _responseGenerator.cannotUnderstand(),
      UnsupportedActionException() => _responseGenerator.unsupportedCommand(),
      ModelNotAvailableException() => _responseGenerator.modelUnavailable(),
      AppNotInstalledException(:final appName) =>
        _responseGenerator.appNotInstalled(appName),
      AiAskNotInstalledException(:final appName) =>
        _responseGenerator.aiNotInstalled(appName),
      AiAskException(:final message) =>
        message.isEmpty
            ? _responseGenerator.aiAskFailed('AI app')
            : message,
      MediaControlException() => _responseGenerator.mediaControlFailed(),
      VolumeControlException() => _responseGenerator.volumeControlFailed(),
      BrightnessControlException() =>
        _responseGenerator.brightnessControlFailed(),
      ContactNotFoundException(:final contactName) =>
        _responseGenerator.contactNotFound(contactName),
      WhatsAppNotInstalledException() =>
        _responseGenerator.whatsAppNotInstalled(),
      WhatsAppException() => _responseGenerator.whatsAppFailed(),
      CallException() => _responseGenerator.callFailed(),
      GalleryVideoNotFoundException(:final index) =>
        _responseGenerator.galleryVideoNotFound(index),
      GalleryException() => _responseGenerator.galleryAccessFailed(),
      YouTubeNotInstalledException() =>
        _responseGenerator.youTubeNotInstalled(),
      YouTubeException() => _responseGenerator.youTubeSearchFailed(),
      AlarmException() => _responseGenerator.alarmFailed(),
      GmailNotConnectedException() => _responseGenerator.gmailNotConnected(),
      GmailNetworkException() => _responseGenerator.gmailNeedsInternet(),
      GmailException(:final message) =>
        message.trim().isEmpty ? _responseGenerator.gmailFailed() : message,
      CustomCommandNotFoundException() => e.message,
      _ => e.message,
    };
  }

  /// Speaks [message] exactly once per command.
  ///
  /// - Guarantees a single spoken response per user command (UI rebuilds and
  ///   repeated callbacks can never trigger speech more than once).
  /// - Stops the microphone before speaking so FRIDAY never hears itself.
  /// - Failures are logged and swallowed: TTS is an enhancement, never a
  ///   dependency of the app-opening action.
  Future<void> _speakResponse(String message) async {
    if (_didSpeakForCommand) return;
    _didSpeakForCommand = true;

    if (message.isEmpty || !_ttsSettings.enabled) return;

    // Never let the microphone capture FRIDAY's own voice.
    if (_isListening) {
      try {
        await _voiceService.cancelListening();
      } catch (_) {}
      _isListening = false;
      _stopLevelPoller();
      notifyListeners();
    }

    try {
      if (_ttsAvailable == null) {
        _ttsAvailable = await _tts.initialize();
        if (_ttsAvailable != true) return;
      }

       await _tts.setSpeechRate(_ttsSettings.speechRate);

      // Set TTS language based on detected user language, falling back to explicit setting.
      final detectedLocale = _currentLanguage.ttsLocale;
      if (detectedLocale != null && detectedLocale.isNotEmpty) {
        final available = await _tts.isLanguageAvailable(detectedLocale);
        if (available == true) {
          await _tts.setLanguage(detectedLocale);
        } else if (_ttsSettings.language != null && _ttsSettings.language!.isNotEmpty) {
          await _tts.setLanguage(_ttsSettings.language!);
        }
      } else if (_ttsSettings.language != null && _ttsSettings.language!.isNotEmpty) {
        await _tts.setLanguage(_ttsSettings.language!);
      }

      _isSpeaking = true;
      notifyListeners();
      await _tts.speak(message).timeout(_ttsWaitTimeout);
    } catch (e) {
      debugPrint('Text-to-speech failed: $e');
    } finally {
      if (_isSpeaking) {
        _isSpeaking = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  /// Stops any utterance currently playing from a previous command.
  Future<void> _stopSpeaking() async {
    if (!_isSpeaking) return;
    try {
      await _tts.stop();
    } catch (_) {}
    _isSpeaking = false;
  }

  /// Invoked by the platform TTS engine when an utterance ends on its own.
  void _handleTtsCompletion() {
    if (_disposed) return;
    if (_isSpeaking) {
      _isSpeaking = false;
      notifyListeners();
    }
  }

  /// Flips the "speaking" flag on for [_respondingDuration] after a reply,
  /// giving the visual a chance to animate like it is talking.
  void _startRespondingWindow() {
    _respondingTimer?.cancel();
    _isResponding = true;
    _respondingTimer = Timer(_respondingDuration, () {
      _isResponding = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _levelPoller?.cancel();
    _respondingTimer?.cancel();
    try {
      _assistService.clearHandler();
    } catch (_) {}
    _soundLevelNotifier.dispose();
    _tts.dispose();
    super.dispose();
  }
}
