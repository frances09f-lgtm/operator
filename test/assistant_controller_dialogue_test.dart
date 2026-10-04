import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';
import 'package:friday_app/features/app_launcher/app_launcher_service.dart';
import 'package:friday_app/features/assistant/domain/dialogue_state.dart';
import 'package:friday_app/features/assistant/domain/intent_parser.dart';
import 'package:friday_app/features/assistant/presentation/assistant_controller.dart';
import 'package:friday_app/features/call/call_service.dart';
import 'package:friday_app/features/whatsapp/whatsapp_service.dart';
import 'package:friday_app/services/local_llm/local_llm_service.dart';
import 'package:friday_app/services/local_llm/model_manager.dart';
import 'package:friday_app/services/tts/text_to_speech_service.dart';
import 'package:friday_app/services/voice/voice_command_service.dart';

class FakeLocalLLMService implements LocalLLMService {
  @override
  bool get isReady => true;

  @override
  String? get activeMode => 'command';

  @override
  bool get isChatModelLoaded => false;

  @override
  Future<void> loadModel(String modelPath) async {}

  @override
  Future<void> unload() async {}

  @override
  Future<void> loadCommandModel(String modelPath) async {}

  @override
  Future<void> loadChatModel(String modelPath) async {}

  @override
  Future<String> chat(
    String userMessage, {
    List<Map<String, String>> history = const [],
    void Function(String token)? onToken,
  }) async => 'Chat reply';

  @override
  Future<String> infer(String userCommand) async {
    return '{"action": "unsupported", "target": ""}';
  }

  @override
  Future<void> dispose() async {}
}

class FakeAppLauncherService implements AppLauncherService {
  @override
  Future<String> resolveApp(String target) async => target;

  @override
  Future<String> launchApp(String target) async => target;
}

class FakeWhatsAppService implements WhatsAppService {
  final List<Map<String, String>> sentMessages = [];

  @override
  Future<WhatsAppResult> sendWhatsApp({
    required String contactName,
    required String message,
  }) async {
    sentMessages.add({'contactName': contactName, 'message': message});
    return WhatsAppResult(
      success: true,
      resolvedName: contactName,
      resolvedPhone: '1234567890',
    );
  }
}

class FakeCallService implements CallService {
  final List<String> calledContacts = [];

  @override
  Future<CallResult> makeCall({required String contactName}) async {
    calledContacts.add(contactName);
    return CallResult(
      success: true,
      resolvedName: contactName,
      resolvedPhone: '1234567890',
    );
  }
}

class FakeVoiceCommandService implements VoiceCommandService {
  @override
  double soundLevel = 0.0;

  @override
  bool get isAvailable => true;

  @override
  bool get isListening => false;

  @override
  String? get errorMessage => null;

  @override
  void Function(String)? onFinalResult;

  @override
  void Function(String)? onPartialResult;

  @override
  void Function()? onListeningEnded;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<bool> startListening({Duration? listenFor}) async => true;

  @override
  Future<String?> stopListening() async => null;

  @override
  Future<void> cancelListening() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> setLocale(String? localeId) async {}
}

class FakeTextToSpeechService implements TextToSpeechService {
  final List<String> spokenTexts = [];

  @override
  bool get isAvailable => true;

  @override
  void Function()? onCompletion;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> speak(String text) async {
    spokenTexts.add(text);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<bool> isLanguageAvailable(String locale) async => true;

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('AssistantController - Dialogue State & Memory', () {
    late AssistantController controller;
    late FakeWhatsAppService fakeWhatsApp;
    late FakeCallService fakeCall;
    late FakeTextToSpeechService fakeTts;
    late FakeVoiceCommandService fakeVoice;
    late DialogueStateTracker tracker;

    setUp(() {
      fakeWhatsApp = FakeWhatsAppService();
      fakeCall = FakeCallService();
      fakeTts = FakeTextToSpeechService();
      fakeVoice = FakeVoiceCommandService();
      tracker = DialogueStateTracker();

      controller = AssistantController(
        llmService: FakeLocalLLMService(),
        intentParser: IntentParser(),
        appLauncher: FakeAppLauncherService(),
        modelManager: ModelManager(),
        whatsAppService: fakeWhatsApp,
        callService: fakeCall,
        voiceCommandService: fakeVoice,
        ttsService: fakeTts,
        dialogueStateTracker: tracker,
      );
    });

    test('clarifies missing message slot on WhatsApp and completes it on reply', () async {
      // Step 1: User says to send a whatsapp message to Mom without body
      await controller.processCommand('Send WhatsApp message to Mom');

      expect(tracker.isAwaitingClarification, isTrue);
      expect(controller.statusMessage, 'What message would you like to send to Mom?');
      expect(fakeWhatsApp.sentMessages.isEmpty, isTrue);

      // Step 2: User provides the message content
      await controller.processCommand('I will reach in 10 minutes');

      expect(tracker.isAwaitingClarification, isFalse);
      expect(fakeWhatsApp.sentMessages.length, 1);
      expect(fakeWhatsApp.sentMessages.first['contactName'], 'Mom');
      expect(fakeWhatsApp.sentMessages.first['message'], 'I will reach in 10 minutes');
    });

    test('resolves contact pronouns from entity memory across turns', () async {
      // Step 1: Call Alice
      await controller.processCommand('Call Alice');
      expect(fakeCall.calledContacts.contains('Alice'), isTrue);
      expect(tracker.memory.lastContact, 'Alice');

      // Step 2: User says "send her a message saying hello"
      await controller.processCommand('Send WhatsApp message to her saying hello');
      expect(fakeWhatsApp.sentMessages.length, 1);
      expect(fakeWhatsApp.sentMessages.first['contactName'], 'Alice');
      expect(fakeWhatsApp.sentMessages.first['message'], 'hello');
    });

    test('allows user to cancel an active clarification', () async {
      await controller.processCommand('Send WhatsApp message to Mom');
      expect(tracker.isAwaitingClarification, isTrue);

      await controller.processCommand('cancel');
      expect(tracker.isAwaitingClarification, isFalse);
      expect(controller.statusMessage, 'Cancelled.');
      expect(fakeWhatsApp.sentMessages.isEmpty, isTrue);
    });
  });
}
