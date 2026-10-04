import 'package:flutter/material.dart';
import 'package:friday_app/features/app_launcher/app_launcher_service.dart';
import 'package:friday_app/features/assistant/domain/intent_parser.dart';
import 'package:friday_app/features/assistant/presentation/assistant_controller.dart';
import 'package:friday_app/features/assistant/presentation/assist_overlay_screen.dart';
import 'package:friday_app/features/assistant/presentation/assistant_screen.dart';
import 'package:friday_app/features/friday_skeleton/manual_test_screen.dart';
import 'package:friday_app/services/assist/assist_service.dart';
import 'package:friday_app/features/automation/services/automation_service.dart';
import 'package:friday_app/features/automation/services/tap_sequence_storage.dart';
import 'package:friday_app/features/device_control/device_control_service.dart';
import 'package:friday_app/features/flashlight/flashlight_service.dart';
import 'package:friday_app/features/alarm/alarm_service.dart';
import 'package:friday_app/features/gallery/gallery_service.dart';
import 'package:friday_app/features/youtube/youtube_service.dart';
import 'package:friday_app/features/media_control/media_control_service.dart';
import 'package:friday_app/features/volume_control/volume_control_service.dart';
import 'package:friday_app/features/brightness_control/brightness_control_service.dart';
import 'package:friday_app/services/local_llm/llama_local_llm_service.dart';
import 'package:friday_app/services/local_llm/model_manager.dart';
import 'package:friday_app/services/tts/flutter_text_to_speech_service.dart';
import 'package:friday_app/services/voice/adaptive_voice_command_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final llmService = LlamaLocalLLMService();
  final intentParser = IntentParser();
  final appLauncher = MethodChannelAppLauncherService();
  final flashlightService = MethodChannelFlashlightService();
  final deviceControl = MethodChannelDeviceControlService();
  final mediaControl = MethodChannelMediaControlService();
  final volumeControl = MethodChannelVolumeControlService();
  final brightnessControl = MethodChannelBrightnessControlService();
  final galleryService = MethodChannelGalleryService();
  final youTubeService = MethodChannelYouTubeService();
  final alarmService = MethodChannelAlarmService();
  final modelManager = ModelManager();
  final voiceService = AdaptiveVoiceCommandService();
  final ttsService = FlutterTextToSpeechService();
  final automationService = MethodChannelAutomationService();
  final tapStorage = TapSequenceStorage();
  final assistService = AssistService();

  final controller = AssistantController(
    llmService: llmService,
    intentParser: intentParser,
    appLauncher: appLauncher,
    modelManager: modelManager,
    flashlightService: flashlightService,
    deviceControlService: deviceControl,
    mediaControlService: mediaControl,
    volumeControlService: volumeControl,
    brightnessControlService: brightnessControl,
    galleryService: galleryService,
    youTubeService: youTubeService,
    alarmService: alarmService,
    automationService: automationService,
    tapStorage: tapStorage,
    voiceCommandService: voiceService,
    ttsService: ttsService,
    assistService: assistService,
  );

  // If cold-started via long-press power / assist gesture, enter assist mode
  // immediately so the full app is NEVER rendered on the first frame.
  final isAssist = await assistService.isAssistLaunch();
  if (isAssist) {
    controller.enterAssistMode();
  }

  runApp(FridayApp(controller: controller, isAssistLaunch: isAssist));
}

class FridayApp extends StatelessWidget {
  final AssistantController controller;
  final bool isAssistLaunch;

  const FridayApp({
    super.key,
    required this.controller,
    this.isAssistLaunch = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FRIDAY',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor:
            isAssistLaunch ? Colors.transparent : const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: _AssistantGate(
        controller: controller,
        isAssistOnly: isAssistLaunch,
      ),
      routes: {
        '/assist': (_) => AssistOverlayScreen(controller: controller),
        '/friday-test': (_) => const ManualTestScreen(),
      },
    );
  }
}

/// Shows the full app normally, and pushes the bottom-bar overlay when the
/// warm activity was invoked via long-press power (same engine — stays fast).
///
/// When [isAssistOnly] is true (invoked via AssistActivity), AssistantScreen
/// is never instantiated, keeping memory footprint small and startup instant.
class _AssistantGate extends StatefulWidget {
  final AssistantController controller;
  final bool isAssistOnly;

  const _AssistantGate({
    required this.controller,
    this.isAssistOnly = false,
  });

  @override
  State<_AssistantGate> createState() => _AssistantGateState();
}

class _AssistantGateState extends State<_AssistantGate> {
  late bool _overlayOpen;
  final AssistService _assistService = AssistService();

  @override
  void initState() {
    super.initState();
    _overlayOpen = widget.controller.isAssistMode;
    widget.controller.addListener(_syncOverlay);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncOverlay);
    super.dispose();
  }

  void _syncOverlay() {
    final want = widget.controller.isAssistMode;
    if (want == _overlayOpen) return;
    setState(() {
      _overlayOpen = want;
    });
    _assistService.setAssistWindow(want);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isAssistOnly) {
      if (!_overlayOpen) return const SizedBox.shrink();
      return AssistOverlayScreen(controller: widget.controller);
    }
    return Stack(
      children: [
        Offstage(
          offstage: _overlayOpen,
          child: AssistantScreen(controller: widget.controller),
        ),
        if (_overlayOpen)
          AssistOverlayScreen(controller: widget.controller),
      ],
    );
  }
}