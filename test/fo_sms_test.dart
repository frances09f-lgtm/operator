import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/features/ai_ask/ai_name_normalizer.dart';
import 'package:friday_app/features/assistant/domain/intent_model.dart';
import 'package:friday_app/features/assistant/domain/intent_parser.dart';
import 'package:friday_app/features/assistant/domain/response_generator.dart';
import 'package:friday_app/features/assistant/presentation/assistant_controller.dart';
import 'package:friday_app/features/sms/sms_service.dart';
import 'package:friday_app/features/app_launcher/app_launcher_service.dart';
import 'package:friday_app/services/local_llm/local_llm_service.dart';
import 'package:friday_app/services/local_llm/model_manager.dart';
import 'package:friday_app/services/tts/text_to_speech_service.dart';
import 'package:friday_app/services/voice/voice_command_service.dart';

class FakeSmsService implements SmsService {
  String? lastRecipient;
  String? lastMessage;
  String? lastPhoneNumber;
  bool shouldSucceed = true;

  @override
  Future<SmsResult> sendSms({
    required String recipient,
    required String message,
    String? phoneNumber,
  }) async {
    lastRecipient = recipient;
    lastMessage = message;
    lastPhoneNumber = phoneNumber;
    return SmsResult(
      success: shouldSucceed,
      status: shouldSucceed ? 'SENT_DIRECT' : 'ERROR',
      recipient: recipient,
      resolvedPhone: phoneNumber,
      isDirectSend: true,
      errorMessage: shouldSucceed ? null : 'Failed to send',
    );
  }
}

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
  Future<void> loadCommandModel(String path) async {}

  @override
  Future<void> loadChatModel(String path) async {}

  @override
  Future<void> unload() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<String> infer(String prompt) async =>
      '{"action": "send_sms", "target": "FO", "message": "test"}';

  @override
  Future<String> chat(String prompt,
          {List<Map<String, String>> history = const [],
          void Function(String token)? onToken}) async =>
      'chat reply';

  @override
  Future<String> generateRaw(
          {required String system,
          required String user,
          int maxTokens = 32}) async =>
      '';
}

class FakeAppLauncher implements AppLauncherService {
  @override
  Future<String> launchApp(String appName) async => appName;

  @override
  Future<String> resolveApp(String target) async => target;
}

class FakeModelManager extends ModelManager {
  @override
  Future<String?> findModelPath({List<String>? fileNames}) async => '/fake/command.gguf';

  @override
  Future<String?> findCommandModelPath() async => '/fake/command.gguf';

  @override
  Future<String?> findChatModelPath() async => '/fake/chat.gguf';

  @override
  Future<String> getPrimaryModelPath() async => '/fake/command.gguf';
}

class FakeTtsService implements TextToSpeechService {
  String? lastSpoken;

  @override
  bool get isAvailable => true;

  @override
  bool get isSpeaking => false;

  @override
  void Function()? onCompletion;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> speak(String text) async {
    lastSpoken = text;
    onCompletion?.call();
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> setLanguage(String languageCode) async {}

  @override
  Future<bool> isLanguageAvailable(String locale) async => true;

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> dispose() async {}
}

class FakeVoiceService implements VoiceCommandService {
  @override
  String? get errorMessage => null;

  @override
  Future<bool> initialize() async => true;

  @override
  bool get isAvailable => true;

  @override
  bool get isListening => false;

  @override
  void Function(String partialText)? onPartialResult;

  @override
  void Function(String recognizedText)? onFinalResult;

  @override
  void Function()? onListeningEnded;

  @override
  Future<void> setLocale(String? localeId) async {}

  @override
  double get soundLevel => 0;

  @override
  Future<bool> startListening({Duration? listenFor}) async => true;

  @override
  Future<String?> stopListening() async => null;

  @override
  Future<void> cancelListening() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('FO Name Normalizer Tests', () {
    test('normalizes direct FO AI spellings and mishearings', () {
      expect(
        normalizeAiTranscript('ask foe to call mom and ask how she is'),
        'ask FO to call mom and ask how she is',
      );
      expect(
        normalizeAiTranscript('ask eff oh to call mom and ask how she is'),
        'ask FO to call mom and ask how she is',
      );
      expect(
        normalizeAiTranscript('ask ef oh to call mom and ask how she is'),
        'ask FO to call mom and ask how she is',
      );
      expect(
        normalizeAiTranscript('ask f.o. to call mom and ask how she is'),
        'ask FO to call mom and ask how she is',
      );
      expect(
        normalizeAiTranscript('ask f o to call mom and ask how she is'),
        'ask FO to call mom and ask how she is',
      );
      expect(
        normalizeAiTranscript('ask wajo fo to call mom and ask how she is'),
        'ask FO to call mom and ask how she is',
      );
      expect(
        normalizeAiTranscript('tell foe to check the weather'),
        'tell FO to check the weather',
      );
      expect(
        normalizeAiTranscript('message foe call mom'),
        'message FO call mom',
      );
    });

    test('detectAiTarget detects FO from mishearings', () {
      expect(detectAiTarget('ask foe something'), 'fo');
      expect(detectAiTarget('ask eff oh something'), 'fo');
      expect(detectAiTarget('wajo fo help'), 'fo');
      expect(detectAiTarget('ask fo to do something'), 'fo');
    });
  });

  group('FO IntentParser Tests', () {
    final parser = IntentParser();

    test('parses JSON ask_fo or send_sms targeting FO', () {
      const jsonStr = '{"action": "send_sms", "target": "FO", "message": "call mom and ask how she is"}';
      final intent = parser.parse(jsonStr);
      expect(intent, isA<SendSmsIntent>());
      final smsIntent = intent as SendSmsIntent;
      expect(smsIntent.recipient, 'FO');
      expect(smsIntent.message, 'call mom and ask how she is');
      expect(smsIntent.phoneNumber, '+16289985940');
    });

    test('parses JSON with target wajo', () {
      const jsonStr = '{"action": "send_sms", "target": "wajo", "message": "hello"}';
      final intent = parser.parse(jsonStr);
      expect(intent, isA<SendSmsIntent>());
      final smsIntent = intent as SendSmsIntent;
      expect(smsIntent.recipient, 'FO');
      expect(smsIntent.phoneNumber, '+16289985940');
    });
  });

  group('AssistantController FO Command Flow', () {
    late FakeSmsService fakeSms;
    late FakeTtsService fakeTts;
    late AssistantController controller;

    setUp(() {
      fakeSms = FakeSmsService();
      fakeTts = FakeTtsService();
      controller = AssistantController(
        llmService: FakeLocalLLMService(),
        intentParser: IntentParser(),
        appLauncher: FakeAppLauncher(),
        modelManager: FakeModelManager(),
        smsService: fakeSms,
        ttsService: fakeTts,
        voiceCommandService: FakeVoiceService(),
        responseGenerator: const ResponseGenerator(),
      );
    });

    test('executes "ask FO to call mom and ask how she is" fast-path to FO phone number', () async {
      await controller.processCommand('ask FO to call mom and ask how she is');

      expect(fakeSms.lastRecipient, 'FO');
      expect(fakeSms.lastMessage, 'call mom and ask how she is');
      expect(fakeSms.lastPhoneNumber, AppConstants.foPhoneNumber);
      expect(controller.statusMessage, contains('Command sent to FO'));
    });

    test('executes "ask foe to call mom and ask how she is" via speech normalization', () async {
      await controller.processCommand('ask foe to call mom and ask how she is');

      expect(fakeSms.lastRecipient, 'FO');
      expect(fakeSms.lastMessage, 'call mom and ask how she is');
      expect(fakeSms.lastPhoneNumber, AppConstants.foPhoneNumber);
    });

    test('executes "tell eff oh to check order status" via speech normalization', () async {
      await controller.processCommand('tell eff oh to check order status');

      expect(fakeSms.lastRecipient, 'FO');
      expect(fakeSms.lastMessage, 'check order status');
      expect(fakeSms.lastPhoneNumber, AppConstants.foPhoneNumber);
    });

    test('executes "message fo call mom and ask how she is"', () async {
      await controller.processCommand('message fo call mom and ask how she is');

      expect(fakeSms.lastRecipient, 'FO');
      expect(fakeSms.lastMessage, 'call mom and ask how she is');
      expect(fakeSms.lastPhoneNumber, AppConstants.foPhoneNumber);
    });
  });
}
