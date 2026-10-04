import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';
import 'package:friday_app/features/app_launcher/app_launcher_service.dart';
import 'package:friday_app/features/assistant/domain/intent_model.dart';
import 'package:friday_app/features/assistant/domain/intent_parser.dart';
import 'package:friday_app/features/assistant/presentation/assistant_controller.dart';
import 'package:friday_app/features/device_control/device_control_service.dart';
import 'package:friday_app/features/flashlight/flashlight_service.dart';
import 'package:friday_app/features/media_control/media_control_service.dart';
import 'package:friday_app/features/volume_control/volume_control_service.dart';
import 'package:friday_app/features/brightness_control/brightness_control_service.dart';
import 'package:friday_app/features/call/call_service.dart';
import 'package:friday_app/services/local_llm/local_llm_service.dart';
import 'package:friday_app/services/local_llm/model_downloader.dart';
import 'package:friday_app/services/local_llm/model_manager.dart';
import 'package:friday_app/services/tts/text_to_speech_service.dart';
import 'package:friday_app/services/voice/voice_command_service.dart';

class FakeLocalLLMService implements LocalLLMService {
  bool ready = true;
  String? nextResponse;
  String? nextChatReply;
  final List<String> inferenceCalls = [];

  @override
  bool get isReady => ready;

  @override
  String? get activeMode => 'command';

  @override
  bool get isChatModelLoaded => false;

  @override
  Future<void> loadModel(String modelPath) async {
    ready = true;
  }

  @override
  Future<void> unload() async {}

  @override
  Future<void> loadCommandModel(String modelPath) async {
    ready = true;
  }

  @override
  Future<void> loadChatModel(String modelPath) async {
    ready = true;
  }

  @override
  Future<String> chat(
    String userMessage, {
    List<Map<String, String>> history = const [],
    void Function(String token)? onToken,
  }) async {
    return nextChatReply ?? 'Smart reply to: $userMessage';
  }

  @override
  Future<String> infer(String userCommand) async {
    if (!ready) throw const ModelNotAvailableException();
    inferenceCalls.add(userCommand);

    if (nextResponse != null) {
      return nextResponse!;
    }

    final lower = userCommand.toLowerCase();

    // Emulate realistic LLM structured output
    if (lower.contains('youtube')) {
      return '{"action": "open_app", "target": "youtube"}';
    } else if (lower.contains('chrome')) {
      return '{"action": "open_app", "target": "chrome"}';
    } else if (lower.contains('spotify')) {
      return '{"action": "open_app", "target": "spotify"}';
    } else if (lower.contains('whatsapp')) {
      return '{"action": "open_app", "target": "whatsapp"}';
    } else if (lower.contains('telegram')) {
      return '{"action": "open_app", "target": "telegram"}';
    } else if (lower.contains('flashlight') ||
        lower.contains('flash') ||
        lower.contains('torch')) {
      return '{"action": "toggle_flashlight", "target": ""}';
    } else if (lower.contains('bluetooth')) {
      // Check for on/off in the command
      if (lower.contains('turn on') || lower.contains('switch on') || lower.contains('enable')) {
        return '{"action": "toggle_bluetooth", "target": "on"}';
      } else if (lower.contains('turn off') || lower.contains('switch off') || lower.contains('disable')) {
        return '{"action": "toggle_bluetooth", "target": "off"}';
      }
      return '{"action": "toggle_bluetooth", "target": ""}';
    } else if (lower.contains('wifi') || lower.contains('wi-fi')) {
      // Check for on/off in the command
      if (lower.contains('turn on') || lower.contains('switch on') || lower.contains('enable')) {
        return '{"action": "toggle_wifi", "target": "on"}';
      } else if (lower.contains('turn off') || lower.contains('switch off') || lower.contains('disable')) {
        return '{"action": "toggle_wifi", "target": "off"}';
      }
      return '{"action": "toggle_wifi", "target": ""}';
    } else if (lower.contains('volum')) {
      final m = RegExp(
        r'set\s+(?:the\s+)?volume\s+to\s+(\d{1,3})\s*%?',
        caseSensitive: false,
      ).firstMatch(lower);
      if (m != null) {
        return '{"action": "set_volume", "value": ${m.group(1)}}';
      }
      if (lower.contains('mute')) return '{"action": "mute"}';
      if (lower.contains('down') ||
          lower.contains('lower') ||
          lower.contains('quieter')) {
        return '{"action": "volume_down"}';
      }
      return '{"action": "volume_up"}';
    } else if (lower.contains('brightness') || lower.contains('dim')) {
      final m = RegExp(
        r'set\s+(?:the\s+)?brightness\s+to\s+(\d{1,3})\s*%?',
        caseSensitive: false,
      ).firstMatch(lower);
      if (m != null) {
        return '{"action": "set_brightness", "value": ${m.group(1)}}';
      }
      if (lower.contains('down') ||
          lower.contains('lower') ||
          lower.contains('dim')) {
        return '{"action": "brightness_down"}';
      }
      return '{"action": "brightness_up"}';
    } else if (lower.contains('playlist') || lower.contains('arijit')) {
      // Requests outside Phase 6 scope are not converted into media actions.
      return '{"action": "unsupported", "target": ""}';
    } else if (lower.contains('stop')) {
      return '{"action": "media_stop"}';
    } else if (lower.contains('pause')) {
      return '{"action": "media_pause"}';
    } else if (lower.contains('skip') || lower.contains('next')) {
      return '{"action": "media_next"}';
    } else if (lower.contains('previous') || lower.contains('go back')) {
      return '{"action": "media_previous"}';
    } else if (lower.contains('resume') || lower.contains('continue')) {
      return '{"action": "media_resume"}';
    } else if (lower.contains('play') ||
        lower.contains('music') ||
        lower.contains('song') ||
        lower.contains('track')) {
      return '{"action": "media_play"}';
    } else {
      return '{"action": "unsupported", "target": ""}';
    }
  }

  @override
  Future<void> dispose() async {
    ready = false;
  }
}

class FakeAppLauncherService implements AppLauncherService {
  final List<String> launchedTargets = [];
  final List<String> resolvedTargets = [];
  final Set<String> installedApps = {'youtube', 'chrome', 'spotify', 'whatsapp'};

  static const Map<String, String> _labels = {
    'youtube': 'YouTube',
    'chrome': 'Chrome',
    'spotify': 'Spotify',
    'whatsapp': 'WhatsApp',
    'telegram': 'Telegram',
  };

  String _label(String target) {
    final label = _labels[target.toLowerCase()];
    if (label != null) return label;
    return target[0].toUpperCase() + target.substring(1);
  }

  @override
  Future<String> resolveApp(String target) async {
    resolvedTargets.add(target);
    if (!installedApps.contains(target.toLowerCase())) {
      throw AppNotInstalledException(target);
    }
    return _label(target);
  }

  @override
  Future<String> launchApp(String target) async {
    launchedTargets.add(target);
    if (!installedApps.contains(target.toLowerCase())) {
      throw AppNotInstalledException(target);
    }
    return _label(target);
  }
}

class FakeFlashlightService implements FlashlightService {
  bool torchOn = false;
  bool fails = false;
  int toggleCount = 0;

  @override
  Future<bool> toggleFlashlight() async {
    toggleCount++;
    if (fails) {
      throw const FlashlightException('Flashlight is broken.');
    }
    torchOn = !torchOn;
    return torchOn;
  }
}

class FakeDeviceControlService implements DeviceControlService {
  bool bluetoothOn = false;
  bool wifiOn = false;
  bool panelOpened = false;
  bool fails = false;
  bool permissionRequired = false;
  final List<SystemToggle> toggled = [];

  @override
  Future<SystemToggleResult> toggle(SystemToggle toggle,
      {ToggleDesired desired = ToggleDesired.toggle}) async {
    toggled.add(toggle);
    if (fails) {
      throw const DeviceControlException('Device control failed.');
    }
    if (permissionRequired) {
      final current = toggle == SystemToggle.bluetooth ? bluetoothOn : wifiOn;
      return SystemToggleResult(
        success: false,
        panelOpened: false,
        isOn: current,
        wasOn: current,
        permissionRequired: true,
      );
    }
    if (panelOpened) {
      final current = toggle == SystemToggle.bluetooth ? bluetoothOn : wifiOn;
      return SystemToggleResult(
        success: true,
        panelOpened: true,
        isOn: current,
        wasOn: current,
      );
    }

    bool next;
    final current =
        toggle == SystemToggle.bluetooth ? bluetoothOn : wifiOn;
    if (desired == ToggleDesired.on) {
      next = true;
    } else if (desired == ToggleDesired.off) {
      next = false;
    } else {
      next = !current;
    }
    if (toggle == SystemToggle.bluetooth) {
      bluetoothOn = next;
    } else {
      wifiOn = next;
    }
    return SystemToggleResult(
      success: true,
      panelOpened: false,
      isOn: next,
      wasOn: current,
    );
  }
}

class FakeMediaControlService implements MediaControlService {
  final List<MediaAction> performed = [];
  bool fails = false;

  @override
  Future<MediaControlResult> perform(MediaAction action) async {
    performed.add(action);
    if (fails) {
      return const MediaControlResult(
        success: false,
        errorMessage: 'No active media session.',
      );
    }
    return const MediaControlResult(success: true);
  }
}

class FakeVolumeControlService implements VolumeControlService {
  int level = 50;
  bool fails = false;
  final List<String> commands = [];

  VolumeControlResult _ok(int l) =>
      VolumeControlResult(success: !fails, level: l);

  @override
  Future<VolumeControlResult> setVolume(int level) async {
    commands.add('set');
    this.level = level;
    return _ok(level);
  }

  @override
  Future<VolumeControlResult> volumeUp() async {
    commands.add('up');
    if (!fails) level = (level + 5).clamp(0, 100);
    return _ok(level);
  }

  @override
  Future<VolumeControlResult> volumeDown() async {
    commands.add('down');
    if (!fails) level = (level - 5).clamp(0, 100);
    return _ok(level);
  }

  @override
  Future<VolumeControlResult> mute() async {
    commands.add('mute');
    if (!fails) level = 0;
    return _ok(level);
  }

  @override
  Future<VolumeControlResult> unmute() async {
    commands.add('unmute');
    if (!fails) level = 50;
    return _ok(level);
  }

  @override
  Future<VolumeControlResult> query() async {
    commands.add('query');
    return _ok(level);
  }
}

class FakeBrightnessControlService implements BrightnessControlService {
  int level = 80;
  bool fails = false;
  bool permissionRequired = false;
  final List<String> commands = [];

  BrightnessControlResult _ok(int l) => BrightnessControlResult(
        success: !fails,
        level: l,
        permissionRequired: false,
      );

  BrightnessControlResult _permission() => BrightnessControlResult(
        success: false,
        level: level,
        permissionRequired: true,
        errorMessage: 'Brightness control needs system write permission.',
      );

  @override
  Future<BrightnessControlResult> setBrightness(int level) async {
    commands.add('set');
    if (permissionRequired) return _permission();
    this.level = level;
    return _ok(level);
  }

  @override
  Future<BrightnessControlResult> brightnessUp() async {
    commands.add('up');
    if (permissionRequired) return _permission();
    if (!fails) level = (level + 5).clamp(0, 100);
    return _ok(level);
  }

  @override
  Future<BrightnessControlResult> brightnessDown() async {
    commands.add('down');
    if (permissionRequired) return _permission();
    if (!fails) level = (level - 5).clamp(0, 100);
    return _ok(level);
  }

  @override
  Future<BrightnessControlResult> query() async {
    commands.add('query');
    if (permissionRequired) return _permission();
    return _ok(level);
  }
}

class FakeCallService implements CallService {
  final List<String> calledContacts = [];
  bool fails = false;
  bool contactNotFound = false;

  @override
  Future<CallResult> makeCall({required String contactName}) async {
    calledContacts.add(contactName);
    if (contactNotFound) throw ContactNotFoundException(contactName);
    if (fails) throw const CallException("I couldn't place that call.");
    return CallResult(
      success: true,
      resolvedPhone: '1234567890',
      resolvedName: contactName,
    );
  }
}

class FakeModelManager extends ModelManager {
  final String? mockPath;
  String? mockChatPath;
  FakeModelManager({this.mockPath = '/data/user/0/com.operator.app/files/models/model.gguf'});

  @override
  Future<String?> findModelPath({List<String>? fileNames}) async => mockPath;

  @override
  Future<String?> findCommandModelPath() async => mockPath;

  @override
  Future<String?> findChatModelPath() async => mockChatPath;

  @override
  Future<String> getPrimaryModelPath() async => mockPath ?? '/models/smollm2.gguf';
}

class FakeModelDownloader extends ModelDownloader {
  bool fail = false;
  String? destination;
  double lastReportedProgress = 0;

  FakeModelDownloader() : super(url: 'https://example.invalid/model.gguf');

  @override
  Future<String> downloadTo({
    required String destinationPath,
    void Function(double progress)? onProgress,
    void Function()? onComplete,
  }) async {
    if (fail) throw const ModelDownloadException('Network is down.');
    destination = destinationPath;
    onProgress?.call(0.5);
    lastReportedProgress = 0.5;
    onProgress?.call(1.0);
    lastReportedProgress = 1.0;
    onComplete?.call();
    return destinationPath;
  }
}

class FakeVoiceCommandService implements VoiceCommandService {
  bool available = true;
  bool listening = false;
  String heardText = '';
  String? failureError;
  Duration? lastListenFor;
  final List<String> processedCalls = [];

  @override
  double soundLevel = 0;

  @override
  bool get isAvailable => available;

  @override
  bool get isListening => listening;

  @override
  String? get errorMessage => failureError;

  @override
  void Function(String partialText)? onPartialResult;

  @override
  void Function(String recognizedText)? onFinalResult;

  @override
  void Function()? onListeningEnded;

  @override
  Future<bool> initialize() async => available;

  @override
  Future<bool> startListening({Duration? listenFor}) async {
    if (!available) return false;
    _delivered = false;
    lastListenFor = listenFor;
    listening = true;
    return true;
  }

  @override
  Future<String?> stopListening() async {
    listening = false;
    if (_delivered) return null;
    _delivered = true;
    onListeningEnded?.call();
    if (heardText.trim().isEmpty) return null;
    onFinalResult?.call(heardText.trim());
    return heardText.trim();
  }

  @override
  Future<void> cancelListening() async {
    _delivered = true;
    listening = false;
  }

  @override
  Future<void> dispose() async {
    listening = false;
  }

  @override
  Future<void> setLocale(String? localeId) async {}

  bool _delivered = false;
}

class FakeTextToSpeechService implements TextToSpeechService {
  bool available = true;
  bool failSpeak = false;
  int speakCount = 0;
  int stopCount = 0;
  int initializeCount = 0;
  final List<String> spokenTexts = [];
  final List<double> speechRates = [];
  bool speaking = false;
  Completer<void>? speakCompleter;

  @override
  bool get isAvailable => available;

  @override
  void Function()? onCompletion;

  @override
  Future<bool> initialize() async {
    initializeCount++;
    return available;
  }

  @override
  Future<void> speak(String text) async {
    spokenTexts.add(text);
    speakCount++;
    if (failSpeak) throw Exception('TTS engine failed');
    speaking = true;
    final gate = speakCompleter;
    if (gate != null) {
      await gate.future;
    }
    speaking = false;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    speechRates.add(rate);
  }

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<bool> isLanguageAvailable(String locale) async => true;

  @override
  Future<void> dispose() async {
    speakCompleter?.complete();
    speaking = false;
  }
}

void main() {
  late FakeLocalLLMService llmService;
  late IntentParser intentParser;
  late FakeAppLauncherService appLauncher;
  late FakeFlashlightService flashlightService;
  late FakeDeviceControlService deviceControlService;
  late FakeMediaControlService mediaControlService;
  late FakeVolumeControlService volumeControlService;
  late FakeBrightnessControlService brightnessControlService;
  late FakeCallService callService;
  late FakeModelManager modelManager;
  late FakeVoiceCommandService voiceService;
  late FakeTextToSpeechService tts;
  late AssistantController controller;

  setUp(() async {
    llmService = FakeLocalLLMService();
    intentParser = IntentParser();
    appLauncher = FakeAppLauncherService();
    flashlightService = FakeFlashlightService();
    deviceControlService = FakeDeviceControlService();
    mediaControlService = FakeMediaControlService();
    volumeControlService = FakeVolumeControlService();
    brightnessControlService = FakeBrightnessControlService();
    callService = FakeCallService();
    modelManager = FakeModelManager();
    voiceService = FakeVoiceCommandService();
    tts = FakeTextToSpeechService();

    controller = AssistantController(
      llmService: llmService,
      intentParser: intentParser,
      appLauncher: appLauncher,
      modelManager: modelManager,
      flashlightService: flashlightService,
      deviceControlService: deviceControlService,
      mediaControlService: mediaControlService,
      volumeControlService: volumeControlService,
      brightnessControlService: brightnessControlService,
      callService: callService,
      voiceCommandService: voiceService,
      ttsService: tts,
    );

    await controller.initializeModel();
  });

  group('AssistantController - App Opening Commands', () {
    test('Open YouTube launches YouTube', () async {
      await controller.processCommand('Open YouTube');

      expect(controller.statusMessage, 'Opening YouTube.');
      expect(appLauncher.launchedTargets, contains('youtube'));
    });

    test('Launch YouTube launches YouTube', () async {
      await controller.processCommand('Launch YouTube');

      expect(controller.statusMessage, 'Opening YouTube.');
      expect(appLauncher.launchedTargets, contains('youtube'));
    });

    test('Start YouTube launches YouTube', () async {
      await controller.processCommand('Start YouTube');

      expect(controller.statusMessage, 'Opening YouTube.');
      expect(appLauncher.launchedTargets, contains('youtube'));
    });

    test('Please open YouTube launches YouTube', () async {
      await controller.processCommand('Please open YouTube');

      expect(controller.statusMessage, 'Opening YouTube.');
      expect(appLauncher.launchedTargets, contains('youtube'));
    });

    test('Can you open Chrome? launches Chrome', () async {
      await controller.processCommand('Can you open Chrome?');

      expect(controller.statusMessage, 'Opening Chrome.');
      expect(appLauncher.launchedTargets, contains('chrome'));
    });

    test('Launch Spotify launches Spotify', () async {
      await controller.processCommand('Launch Spotify');

      expect(controller.statusMessage, 'Opening Spotify.');
      expect(appLauncher.launchedTargets, contains('spotify'));
    });

    test('Open WhatsApp launches WhatsApp', () async {
      await controller.processCommand('Open WhatsApp');

      expect(controller.statusMessage, 'Opening WhatsApp.');
      expect(appLauncher.launchedTargets, contains('whatsapp'));
    });
  });

group('AssistantController - Unsupported Commands', () {
    final unsupportedCommands = [
      'Send a message',
      'What\'s the weather?',
      'Search Google',
      'Play my workout playlist',
      'Play Arijit Singh',
    ];

    for (final command in unsupportedCommands) {
      test('Command "$command" is rejected and never reaches app launcher', () async {
        await controller.processCommand(command);

        // Without the smart model downloaded, open questions fall back to
        // the download prompt (still never launching anything).
        expect(
          controller.statusMessage,
          'Smart model not downloaded. Tap "Download Smart Model" (~1GB) for ChatGPT-like answers.',
        );
        expect(appLauncher.launchedTargets, isEmpty);
        expect(mediaControlService.performed, isEmpty);
      });
    }
  });

  group('AssistantController - Phone Call Commands', () {
    test('Call John places a call via heuristic without LLM', () async {
      await controller.processCommand('Call John');

      expect(controller.statusMessage, 'Calling John.');
      expect(callService.calledContacts, contains('John'));
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('Call mom places a call', () async {
      await controller.processCommand('Call mom');

      expect(controller.statusMessage, 'Calling Mom.');
      expect(callService.calledContacts, contains('mom'));
    });

    test('LLM call intent places a call', () async {
      llmService.nextResponse = '{"action": "call", "target": "mom"}';

      await controller.processCommand('Call mom');

      expect(controller.statusMessage, 'Calling Mom.');
      expect(callService.calledContacts, contains('mom'));
    });

    test('Unknown contact reports not found', () async {
      callService.contactNotFound = true;

      await controller.processCommand('Call John');

      expect(controller.statusMessage, 'Contact John not found.');
    });
  });

  group('AssistantController - Uninstalled Apps & Edge Cases', () {
    test('Uninstalled app displays not installed error', () async {
      await controller.processCommand('Open Telegram');

      expect(controller.statusMessage, 'Telegram isn\'t installed.');
    });

    test('Empty command displays prompt message without invoking LLM or launcher', () async {
      await controller.processCommand('   ');

      expect(controller.statusMessage, 'Please tell me which app to open.');
      expect(llmService.inferenceCalls, isEmpty);
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('Malformed AI response displays error without crashing or launching', () async {
      llmService.nextResponse = 'Non-JSON garbage output from model';

      await controller.processCommand('Open YouTube');

      expect(controller.statusMessage, 'I couldn\'t understand that command.');
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('Model unavailable displays clear error', () async {
      llmService.ready = false;
      controller = AssistantController(
        llmService: llmService,
        intentParser: intentParser,
        appLauncher: appLauncher,
        modelManager: FakeModelManager(mockPath: null),
      );
      await controller.initializeModel();

      await controller.processCommand('Open YouTube');

      expect(controller.statusMessage, 'The local AI model isn\'t available.');
      expect(appLauncher.launchedTargets, isEmpty);
    });
  });

  group('AssistantController - Voice Commands', () {
    test('Ineffective voice init marks speech unavailable', () async {
      voiceService.available = false;
      await controller.initializeSpeech();

      expect(controller.isSpeechAvailable, isFalse);
      expect(controller.statusMessage, 'Voice input is not available on this device.');
    });

    test('Initializing speech marks it available', () async {
      await controller.initializeSpeech();

      expect(controller.isSpeechAvailable, isTrue);
    });

    test('Toggling listening updates listening state', () async {
      await controller.initializeSpeech();

      await controller.toggleListening();
      expect(controller.isListening, isTrue);
      expect(controller.statusMessage, startsWith('Listening'));

      await controller.toggleListening();
      expect(controller.isListening, isFalse);
    });

    test('Spoken "Open YouTube" launches YouTube', () async {
      await controller.initializeSpeech();
      voiceService.heardText = 'Open YouTube';

      await controller.toggleListening();
      await controller.toggleListening();
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(controller.statusMessage, 'Opening YouTube.');
      expect(appLauncher.launchedTargets, contains('youtube'));
      expect(controller.lastUserCommand, 'Open YouTube');
    });

test('Spoken unsupported command is rejected without launching', () async {
      await controller.initializeSpeech();
      voiceService.heardText = 'Send a message';

      await controller.toggleListening();
      await controller.toggleListening();
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 100));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(
        controller.statusMessage,
        'Smart model not downloaded. Tap "Download Smart Model" (~1GB) for ChatGPT-like answers.',
      );
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('Silence during listening does not launch or crash', () async {
      await controller.initializeSpeech();
      voiceService.heardText = '';

      await controller.toggleListening();
      await controller.toggleListening();
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(appLauncher.launchedTargets, isEmpty);
      expect(controller.isListening, isFalse);
    });

    test('Toggle is ignored while a command is being processed', () async {
      await controller.initializeSpeech();

      controller.processCommand('Open YouTube');
      await controller.toggleListening();

      expect(controller.isListening, isFalse);
    });
  });

  group('AssistantController - Visual State (Orb)', () {
    test('soundLevel starts at zero when not listening', () {
      expect(controller.soundLevel.value, 0);
    });

    test('isResponding is true right after a reply', () async {
      await controller.processCommand('Open YouTube');

      expect(controller.isResponding, isTrue);
    });

    test('isResponding clears after the responding window', () async {
      final short = AssistantController(
        llmService: llmService,
        intentParser: intentParser,
        appLauncher: appLauncher,
        modelManager: FakeModelManager(),
        respondingDuration: const Duration(milliseconds: 20),
      );
      await short.initializeModel();

      await short.processCommand('Open YouTube');
      expect(short.isResponding, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(short.isResponding, isFalse);
    });

    test('processing takes priority over responding', () async {
      llmService.nextResponse = '{"action": "open_app", "target": "youtube"}';

      final future = controller.processCommand('Open YouTube');
      expect(controller.isProcessing, isTrue);
      await future;

      expect(controller.isProcessing, isFalse);
      expect(controller.isResponding, isTrue);
    });

    test('voice input feeds the soundLevel feed only while listening', () async {
      await controller.initializeSpeech();

      await controller.toggleListening();
      expect(controller.isListening, isTrue);

      voiceService.soundLevel = 0.8;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(controller.soundLevel.value, closeTo(0.8, 0.2));

      await controller.toggleListening();
      expect(controller.soundLevel.value, 0);
    });
  });

  group('AssistantController - Model Download', () {
    late FakeModelDownloader downloader;

    AssistantController buildDownloadController() => AssistantController(
          llmService: llmService,
          intentParser: intentParser,
          appLauncher: appLauncher,
          modelManager: FakeModelManager(),
          modelDownloader: downloader,
        );

    setUp(() {
      downloader = FakeModelDownloader();
    });

    test('downloadModel writes to the primary path and loads the model', () async {
      final c = buildDownloadController();
      await c.downloadModel();

      expect(downloader.destination, isNotEmpty);
      expect(c.modelDownloadProgress, 1.0);
      expect(c.isDownloadingModel, isFalse);
      expect(c.modelStatus, ModelStatus.ready);
      expect(c.statusMessage, 'Ready');
    });

    test('downloadModel reports intermediate progress', () async {
      final c = buildDownloadController();
      await c.downloadModel();

      expect(downloader.lastReportedProgress, 1.0);
      expect(c.statusMessage, 'Ready');
    });

    test('download failure surfaces a clear error', () async {
      downloader.fail = true;
      final c = buildDownloadController();

      await c.downloadModel();

      expect(c.isDownloadingModel, isFalse);
      expect(c.statusMessage, 'Network is down.');
      expect(c.modelStatus, isNot(ModelStatus.ready));
    });

    test('downloadModel is ignored while already downloading', () async {
      final c = buildDownloadController();
      final first = c.downloadModel();
      final second = c.downloadModel();
      await Future.wait([first, second]);

      expect(c.isDownloadingModel, isFalse);
      expect(downloader.destination, isNotEmpty);
    });
  });

  group('AssistantController - Flashlight Commands', () {
    test('Turn on the flashlight toggles torch on', () async {
      await controller.processCommand('Turn on the flashlight');

      expect(flashlightService.torchOn, isTrue);
      expect(controller.statusMessage, 'Flashlight is ON.');
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('Turn off the flashlight toggles torch off', () async {
      await controller.processCommand('Turn on the flashlight');
      await controller.processCommand('Turn off the flashlight');

      expect(flashlightService.torchOn, isFalse);
      expect(controller.statusMessage, 'Flashlight is OFF.');
    });

    test('Repeated toggles alternate the torch state', () async {
      await controller.processCommand('Turn on the flashlight');
      expect(flashlightService.torchOn, isTrue);
      expect(controller.statusMessage, 'Flashlight is ON.');

      await controller.processCommand('Turn off the flashlight');
      expect(flashlightService.torchOn, isFalse);
      expect(controller.statusMessage, 'Flashlight is OFF.');

      await controller.processCommand('Turn on the flashlight');
      expect(flashlightService.torchOn, isTrue);
      expect(controller.statusMessage, 'Flashlight is ON.');
    });

    test('Spoken "turn on flashlight" toggles the torch on', () async {
      await controller.initializeSpeech();
      voiceService.heardText = 'turn on the flashlight';

      await controller.toggleListening();
      await controller.toggleListening();
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(flashlightService.torchOn, isTrue);
      expect(controller.statusMessage, 'Flashlight is ON.');
    });

    test('Flashlight hardware failure surfaces the native error', () async {
      flashlightService.fails = true;

      await controller.processCommand('Turn on the flashlight');

      expect(flashlightService.toggleCount, 1);
      expect(controller.statusMessage, 'Flashlight is broken.');
      expect(appLauncher.launchedTargets, isEmpty);
    });
  });

  group('AssistantController - Device Control Commands', () {
    test('Turn on Bluetooth toggles bluetooth on', () async {
      await controller.processCommand('Turn on Bluetooth');

      expect(deviceControlService.bluetoothOn, isTrue);
      expect(controller.statusMessage, 'Bluetooth is ON.');
      expect(deviceControlService.toggled, contains(SystemToggle.bluetooth));
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('Turn off Bluetooth toggles bluetooth off', () async {
      await controller.processCommand('Turn on Bluetooth');
      await controller.processCommand('Turn off Bluetooth');

      expect(deviceControlService.bluetoothOn, isFalse);
      expect(controller.statusMessage, 'Bluetooth is OFF.');
    });

    test('Turn on Wi-Fi toggles wifi on', () async {
      await controller.processCommand('Turn on Wi-Fi');

      expect(deviceControlService.wifiOn, isTrue);
      expect(controller.statusMessage, 'Wi-Fi is ON.');
      expect(deviceControlService.toggled, contains(SystemToggle.wifi));
    });

    test('Turn off Wi-Fi toggles wifi off', () async {
      await controller.processCommand('Turn on Wi-Fi');
      await controller.processCommand('Turn off Wi-Fi');

      expect(deviceControlService.wifiOn, isFalse);
      expect(controller.statusMessage, 'Wi-Fi is OFF.');
    });

    test('On restricted Android, opening the settings panel is reported', () async {
      deviceControlService.panelOpened = true;

      await controller.processCommand('Turn on Bluetooth');

      expect(deviceControlService.bluetoothOn, isFalse);
      expect(controller.statusMessage, 'Opening Bluetooth settings. Tap to turn on.');
    });

    test('Spoken "turn on wifi" reaches device control', () async {
      await controller.initializeSpeech();
      voiceService.heardText = 'turn on wifi';

      await controller.toggleListening();
      await controller.toggleListening();
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 100));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(deviceControlService.wifiOn, isTrue);
      expect(controller.statusMessage, 'Wi-Fi is ON.');
    });

    test('Device control failure surfaces the native error', () async {
      deviceControlService.fails = true;

      await controller.processCommand('Turn on Wi-Fi');

      expect(deviceControlService.toggled, contains(SystemToggle.wifi));
      expect(controller.statusMessage, 'Device control failed.');
    });

    test('Turn on Bluetooth when already on reports already ON', () async {
      deviceControlService.bluetoothOn = true;

      await controller.processCommand('Turn on Bluetooth');

      expect(deviceControlService.bluetoothOn, isTrue);
      expect(controller.statusMessage, 'Bluetooth is already ON.');
    });

    test('Turn off Bluetooth when already off reports already OFF', () async {
      deviceControlService.bluetoothOn = false;

      await controller.processCommand('Turn off Bluetooth');

      expect(deviceControlService.bluetoothOn, isFalse);
      expect(controller.statusMessage, 'Bluetooth is already OFF.');
    });

    test('Turn on Wi-Fi when already on reports already ON', () async {
      deviceControlService.wifiOn = true;

      await controller.processCommand('Turn on Wi-Fi');

      expect(deviceControlService.wifiOn, isTrue);
      expect(controller.statusMessage, 'Wi-Fi is already ON.');
    });

    test('Turn off Wi-Fi when already off reports already OFF', () async {
      deviceControlService.wifiOn = false;

      await controller.processCommand('Turn off Wi-Fi');

      expect(deviceControlService.wifiOn, isFalse);
      expect(controller.statusMessage, 'Wi-Fi is already OFF.');
    });

    test('Bluetooth permission required surfaces permission message', () async {
      deviceControlService.permissionRequired = true;

      await controller.processCommand('Turn on Bluetooth');

      expect(controller.statusMessage, 'Need permission to turn Bluetooth on. Allow in settings.');
    });
  });

  group('AssistantController - Media Control Commands', () {
    test('Play music dispatches media play and confirms', () async {
      await controller.processCommand('Play music');

      expect(mediaControlService.performed, [MediaAction.play]);
      expect(controller.statusMessage, 'Playing.');
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('bare "Play" dispatches media play', () async {
      await controller.processCommand('Play');

      expect(mediaControlService.performed, [MediaAction.play]);
      expect(controller.statusMessage, 'Playing.');
    });

    test('"Start playing" dispatches media play', () async {
      await controller.processCommand('Start playing');

      expect(mediaControlService.performed, [MediaAction.play]);
      expect(controller.statusMessage, 'Playing.');
    });

    test('Pause dispatches media pause and confirms', () async {
      await controller.processCommand('Pause');

      expect(mediaControlService.performed, [MediaAction.pause]);
      expect(controller.statusMessage, 'Paused.');
    });

    test('"Pause the music" dispatches media pause', () async {
      await controller.processCommand('Pause the music');

      expect(mediaControlService.performed, [MediaAction.pause]);
      expect(controller.statusMessage, 'Paused.');
    });

    test('Resume dispatches media resume and confirms', () async {
      await controller.processCommand('Resume');

      expect(mediaControlService.performed, [MediaAction.resume]);
      expect(controller.statusMessage, 'Resuming.');
    });

    test('"Continue playing" dispatches media resume', () async {
      await controller.processCommand('Continue playing');

      expect(mediaControlService.performed, [MediaAction.resume]);
      expect(controller.statusMessage, 'Resuming.');
    });

    test('"Next song" dispatches media next and confirms', () async {
      await controller.processCommand('Next song');

      expect(mediaControlService.performed, [MediaAction.next]);
      expect(controller.statusMessage, 'Skipping.');
    });

    test('"Skip this song" dispatches media next', () async {
      await controller.processCommand('Skip this song');

      expect(mediaControlService.performed, [MediaAction.next]);
      expect(controller.statusMessage, 'Skipping.');
    });

    test('"Next track" dispatches media next', () async {
      await controller.processCommand('Next track');

      expect(mediaControlService.performed, [MediaAction.next]);
      expect(controller.statusMessage, 'Skipping.');
    });

    test('"Previous song" dispatches media previous and confirms', () async {
      await controller.processCommand('Previous song');

      expect(mediaControlService.performed, [MediaAction.previous]);
      expect(controller.statusMessage, 'Going back.');
    });

    test('"Go back one song" dispatches media previous', () async {
      await controller.processCommand('Go back one song');

      expect(mediaControlService.performed, [MediaAction.previous]);
      expect(controller.statusMessage, 'Going back.');
    });

    test('"Stop music" dispatches media stop and confirms', () async {
      await controller.processCommand('Stop music');

      expect(mediaControlService.performed, [MediaAction.stop]);
      expect(controller.statusMessage, 'Stopped.');
    });

    test('"Stop playing" dispatches media stop', () async {
      await controller.processCommand('Stop playing');

      expect(mediaControlService.performed, [MediaAction.stop]);
      expect(controller.statusMessage, 'Stopped.');
    });

    test('Media execution failure reports a controlled failure', () async {
      mediaControlService.fails = true;

      await controller.processCommand('Play music');

      expect(mediaControlService.performed, [MediaAction.play]);
      expect(controller.statusMessage, 'I couldn\'t control the media.');
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('LLM output of an invented media action is rejected', () async {
      llmService.nextResponse = '{"action": "media_rewind"}';

      await controller.processCommand('Play music');

      expect(controller.statusMessage, 'I can only open apps and control media, volume, brightness, alarms and reminders right now.');
      expect(mediaControlService.performed, isEmpty);
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('LLM output of an arbitrary shell action is rejected', () async {
      llmService.nextResponse = '{"action": "execute_shell", "target": "rm"}';

      await controller.processCommand('Play music');

      expect(controller.statusMessage, 'I can only open apps and control media, volume, brightness, alarms and reminders right now.');
      expect(mediaControlService.performed, isEmpty);
    });

    test('Spoken "Pause the music" controls media', () async {
      await controller.initializeSpeech();
      voiceService.heardText = 'Pause the music';

      await controller.toggleListening();
      await controller.toggleListening();
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(mediaControlService.performed, [MediaAction.pause]);
      expect(controller.statusMessage, 'Paused.');
    });

    test('Media commands never reach the app launcher', () async {
      await controller.processCommand('Play');
      await controller.processCommand('Next song');

      expect(appLauncher.launchedTargets, isEmpty);
      expect(mediaControlService.performed, [MediaAction.play, MediaAction.next]);
    });
  });

  group('AssistantController - Volume Control Commands', () {
    test('Volume up adjusts volume relatively and confirms', () async {
      await controller.processCommand('Volume up');

      expect(volumeControlService.commands, ['query', 'set']);
      expect(controller.statusMessage, 'Volume is now 55 percent.');
      expect(tts.spokenTexts, ['Done.']);
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('Volume down adjusts volume relatively and confirms', () async {
      await controller.processCommand('Volume down');

      expect(volumeControlService.commands, ['query', 'set']);
      expect(controller.statusMessage, 'Volume is now 45 percent.');
      expect(tts.spokenTexts, ['Done.']);
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('Set volume to 50% sets an absolute level', () async {
      await controller.processCommand('Set volume to 50%');

      expect(volumeControlService.commands, ['set']);
      expect(volumeControlService.level, 50);
      expect(controller.statusMessage, 'Volume set to 50 percent.');
      expect(tts.spokenTexts, ['Done.']);
    });

    test('Mute sets volume to zero', () async {
      await controller.processCommand('Mute');

      expect(volumeControlService.commands, ['mute']);
      expect(volumeControlService.level, 0);
      expect(controller.statusMessage, 'Muted.');
      expect(mediaControlService.performed, isEmpty);
    });

    test('Spoken "volume up" adjusts volume', () async {
      await controller.initializeSpeech();
      voiceService.heardText = 'turn the volume up';

      await controller.toggleListening();
      await controller.toggleListening();
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(volumeControlService.commands, ['query', 'set']);
      expect(controller.statusMessage, 'Volume is now 55 percent.');
    });

    test('Volume control failure surfaces the native error', () async {
      volumeControlService.fails = true;

      await controller.processCommand('Volume up');

      expect(volumeControlService.commands, ['query', 'up']);
      expect(controller.statusMessage, 'I couldn\'t adjust the volume.');
      expect(tts.spokenTexts, ['I couldn\'t adjust the volume.']);
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('Configurable volume step is applied', () async {
      controller.setVolumeStep(10);
      expect(controller.volumeStep, 10);

      await controller.processCommand('Volume up');

      expect(volumeControlService.commands, ['query', 'set']);
      expect(volumeControlService.level, 60);
      expect(controller.statusMessage, 'Volume is now 60 percent.');
    });

    test('Volume step clamps to 1-30', () async {
      controller.setVolumeStep(100);
      expect(controller.volumeStep, 30);
      controller.setVolumeStep(0);
      expect(controller.volumeStep, 1);
      controller.setVolumeStep(-5);
      expect(controller.volumeStep, 1);
    });
  });

  group('AssistantController - Brightness Control Commands', () {
    test('Brightness down dims the screen relatively', () async {
      await controller.processCommand('Brightness down');

      expect(brightnessControlService.commands, ['query', 'set']);
      expect(brightnessControlService.level, 75);
      expect(controller.statusMessage, 'Brightness is now 75 percent.');
      expect(tts.spokenTexts, ['Done.']);
      expect(appLauncher.launchedTargets, isEmpty);
    });

    test('Brightness up brightens the screen relatively', () async {
      brightnessControlService.level = 20;
      await controller.processCommand('Brightness up');

      expect(brightnessControlService.commands, ['query', 'set']);
      expect(brightnessControlService.level, 25);
      expect(controller.statusMessage, 'Brightness is now 25 percent.');
      expect(tts.spokenTexts, ['Done.']);
    });

    test('Set brightness to 80% sets an absolute level', () async {
      await controller.processCommand('Set brightness to 80%');

      expect(brightnessControlService.commands, ['set']);
      expect(brightnessControlService.level, 80);
      expect(controller.statusMessage, 'Brightness set to 80 percent.');
      expect(tts.spokenTexts, ['Done.']);
    });

    test('Dim the screen maps to a relative decrease', () async {
      await controller.processCommand('Dim the screen');

      expect(brightnessControlService.commands, ['query', 'set']);
      expect(controller.statusMessage, 'Brightness is now 75 percent.');
    });

    test('Configurable brightness step is applied', () async {
      controller.setBrightnessStep(10);
      expect(controller.brightnessStep, 10);
      brightnessControlService.level = 20;

      await controller.processCommand('Brightness up');

      expect(brightnessControlService.commands, ['query', 'set']);
      expect(brightnessControlService.level, 30);
      expect(controller.statusMessage, 'Brightness is now 30 percent.');
    });

    test('Brightness step clamps to 1-30', () async {
      controller.setBrightnessStep(100);
      expect(controller.brightnessStep, 30);
      controller.setBrightnessStep(0);
      expect(controller.brightnessStep, 1);
    });

    test('Missing write permission explains and does not claim success', () async {
      brightnessControlService.permissionRequired = true;

      await controller.processCommand('Brightness up');

      expect(controller.statusMessage, contains('system setting'));
      expect(controller.statusMessage, contains('Brightness'));
      expect(tts.spokenTexts, [controller.statusMessage]);
      expect(brightnessControlService.level, 80);
    });

    test('Spoken "brightness down" dims the screen', () async {
      await controller.initializeSpeech();
      voiceService.heardText = 'turn the brightness down';

      await controller.toggleListening();
      await controller.toggleListening();
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(brightnessControlService.commands, ['query', 'set']);
      expect(controller.statusMessage, 'Brightness is now 75 percent.');
    });

    test('Brightness commands never reach the app launcher', () async {
      await controller.processCommand('Brightness up');
      await controller.processCommand('Dim the screen');

      expect(appLauncher.launchedTargets, isEmpty);
      expect(mediaControlService.performed, isEmpty);
    });
  });

  group('AssistantController - TTS Responses', () {
    test('Open YouTube speaks Done and shows Opening detail', () async {
      await controller.processCommand('Open YouTube');

      expect(controller.statusMessage, 'Opening YouTube.');
      expect(appLauncher.launchedTargets, contains('youtube'));
      expect(tts.speakCount, 1);
      expect(tts.spokenTexts, ['Done.']);
    });

    test('Media control speaks exactly one short confirmation', () async {
      await controller.processCommand('Play music');
      expect(tts.spokenTexts, ['Playing.']);

      await controller.processCommand('Pause');
      expect(tts.spokenTexts, ['Playing.', 'Paused.']);

      await controller.processCommand('Next song');
      expect(tts.spokenTexts, ['Playing.', 'Paused.', 'Skipping.']);
    });

    test('Media failure speaks the controlled failure response', () async {
      mediaControlService.fails = true;

      await controller.processCommand('Play music');

      expect(controller.statusMessage, 'I couldn\'t control the media.');
      expect(tts.spokenTexts, ['I couldn\'t control the media.']);
    });

    test('Launch Chrome says Done and shows Opening detail', () async {
      await controller.processCommand('Launch Chrome');

      expect(controller.statusMessage, 'Opening Chrome.');
      expect(appLauncher.launchedTargets, contains('chrome'));
      expect(tts.spokenTexts, ['Done.']);
    });

    test('Start Spotify says Done and shows Opening detail', () async {
      await controller.processCommand('Start Spotify');

      expect(controller.statusMessage, 'Opening Spotify.');
      expect(appLauncher.launchedTargets, contains('spotify'));
      expect(tts.spokenTexts, ['Done.']);
    });

    test('Missing app speaks "not installed" and does not launch', () async {
      appLauncher.installedApps.remove('spotify');

      await controller.processCommand('Open Spotify');

      expect(controller.statusMessage, 'Spotify isn\'t installed.');
      expect(appLauncher.launchedTargets, isEmpty);
      expect(tts.spokenTexts, ['Spotify isn\'t installed.']);
    });

    test('Unsupported command speaks and does not launch', () async {
      await controller.processCommand('Send a message');

      expect(
        controller.statusMessage,
        'Smart model not downloaded. Tap "Download Smart Model" (~1GB) for ChatGPT-like answers.',
      );
      expect(appLauncher.launchedTargets, isEmpty);
      expect(
        tts.spokenTexts,
        ['Smart model not downloaded. Tap "Download Smart Model" (~1GB) for ChatGPT-like answers.'],
      );
    });

    test('Malformed AI output speaks "could not understand" and does not launch', () async {
      llmService.nextResponse = 'Non-JSON garbage output from model';

      await controller.processCommand('Open YouTube');

      expect(controller.statusMessage, 'I couldn\'t understand that command.');
      expect(appLauncher.launchedTargets, isEmpty);
      expect(tts.spokenTexts, ['I couldn\'t understand that command.']);
    });

    test('Open question with garbage small-model output routes to smart chat', () async {
      llmService.nextResponse = 'Non-JSON garbage output from model';

      await controller.processCommand('explain gravity');

      expect(
        controller.statusMessage,
        'Smart model not downloaded. Tap "Download Smart Model" (~1GB) for ChatGPT-like answers.',
      );
      expect(appLauncher.launchedTargets, isEmpty);
      expect(
        tts.spokenTexts,
        ['Smart model not downloaded. Tap "Download Smart Model" (~1GB) for ChatGPT-like answers.'],
      );
    });

    test('Open question with chat model available uses smart chat reply', () async {
      llmService.nextResponse = 'Non-JSON garbage output from model';
      llmService.nextChatReply = 'Gravity is a force that pulls objects together.';
      modelManager.mockChatPath = '/models/smollm2-1.7b.gguf';

      await controller.processCommand('explain gravity');

      expect(controller.statusMessage, 'Gravity is a force that pulls objects together.');
      expect(appLauncher.launchedTargets, isEmpty);
      expect(tts.spokenTexts, ['Gravity is a force that pulls objects together.']);
    });

    test('Empty input speaks a prompt and does nothing else', () async {
      await controller.processCommand('   ');

      expect(controller.statusMessage, 'Please tell me which app to open.');
      expect(llmService.inferenceCalls, isEmpty);
      expect(appLauncher.launchedTargets, isEmpty);
      expect(tts.spokenTexts, ['Please tell me which app to open.']);
    });

    test('Unavailable model speaks the model message', () async {
      llmService.ready = false;
      controller = AssistantController(
        llmService: llmService,
        intentParser: intentParser,
        appLauncher: appLauncher,
        modelManager: FakeModelManager(mockPath: null),
        ttsService: tts,
      );
      await controller.initializeModel();

      await controller.processCommand('Open YouTube');

      expect(controller.statusMessage, 'The local AI model isn\'t available.');
      expect(appLauncher.launchedTargets, isEmpty);
      expect(tts.spokenTexts, ['The local AI model isn\'t available.']);
    });

    test('Exactly one spoken response per command even with state changes', () async {
      await controller.processCommand('Open YouTube');
      expect(tts.speakCount, 1);

      // A second command produces its own single response.
      await controller.processCommand('Open Chrome');
      expect(tts.speakCount, 2);
      expect(tts.spokenTexts, ['Done.', 'Done.']);
    });

    test('TTS failure never breaks app launching', () async {
      tts.failSpeak = true;

      await controller.processCommand('Open YouTube');

      expect(controller.statusMessage, 'Opening YouTube.');
      expect(appLauncher.launchedTargets, contains('youtube'));
      expect(tts.speakCount, 1);
    });

    test('TTS disabled skips speech but still launches', () async {
      controller.setTtsEnabled(false);

      await controller.processCommand('Open YouTube');

      expect(appLauncher.launchedTargets, contains('youtube'));
      expect(tts.speakCount, 0);
      expect(tts.spokenTexts, isEmpty);
    });

    test('Microphone is stopped before FRIDAY speaks', () async {
      await controller.initializeSpeech();
      await controller.toggleListening();
      expect(controller.isListening, isTrue);

      await controller.processCommand('Open YouTube');

      expect(voiceService.isListening, isFalse);
      expect(controller.isListening, isFalse);
      expect(tts.speakCount, 1);
    });

    test('The app launches in parallel with TTS without waiting for speech', () async {
      final gate = Completer<void>();
      tts.speakCompleter = gate;

      final future = controller.processCommand('Open YouTube');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(tts.speaking, isTrue);
      expect(tts.spokenTexts, ['Done.']);
      // Fast-open: launch happens while speech is still in flight.
      expect(appLauncher.launchedTargets, contains('youtube'));

      gate.complete();
      await future;

      expect(appLauncher.launchedTargets, contains('youtube'));
      expect(tts.speaking, isFalse);
    });

    test('isSpeaking reflects an in-flight utterance', () async {
      final gate = Completer<void>();
      tts.speakCompleter = gate;

      final future = controller.processCommand('Open YouTube');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.isSpeaking, isTrue);
      expect(controller.phase, AssistantPhase.speaking);

      gate.complete();
      await future;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.isSpeaking, isFalse);
    });

    test('Speaking waits for completion without an arbitrary long delay', () async {
      tts.speakCompleter = Completer<void>();

      final stopwatch = Stopwatch()..start();
      final future = controller.processCommand('Open YouTube');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final elapsedBeforeSpeakDone = stopwatch.elapsed;
      tts.speakCompleter!.complete();
      await future;

      // The command cannot complete until the (gated) utterance completes.
      expect(elapsedBeforeSpeakDone, lessThan(const Duration(seconds: 1)));
      expect(appLauncher.launchedTargets, contains('youtube'));
    });
  });

}
