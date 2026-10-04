import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/features/app_launcher/app_launcher_service.dart';
import 'package:friday_app/features/assistant/domain/intent_model.dart';
import 'package:friday_app/features/assistant/domain/intent_parser.dart';
import 'package:friday_app/features/assistant/presentation/assistant_controller.dart';
import 'package:friday_app/features/call/call_service.dart';
import 'package:friday_app/features/eyes/eyes_service.dart';
import 'package:friday_app/features/eyes/screen_context_service.dart';
import 'package:friday_app/services/local_llm/local_llm_service.dart';
import 'package:friday_app/services/local_llm/model_manager.dart';
import 'package:friday_app/services/tts/text_to_speech_service.dart';

class FakeEyesService extends EyesService {
  String mockSummary = '''
EYES pkg=com.android.chrome
-[TextView] "Breaking Tech News" [view] @[0.5,0.1]
-[TextView] "Call support at +1 628-998-5940 or visit https://example.com" [view] @[0.5,0.3]
-[Button] "Share article" [tap] @[0.8,0.9]
''';

  @override
  Future<String> getSummary({int maxNodes = 40}) async => mockSummary;
}

class FakeCallService implements CallService {
  final List<String> calledContacts = [];

  @override
  Future<CallResult> makeCall({required String contactName}) async {
    calledContacts.add(contactName);
    return CallResult(
      success: true,
      resolvedName: contactName,
      resolvedPhone: contactName,
    );
  }
}

class FakeTtsService implements TextToSpeechService {
  final List<String> spoken = [];

  @override
  bool get isAvailable => true;

  @override
  void Function()? onCompletion;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
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

class FakeAppLauncherService implements AppLauncherService {
  @override
  Future<String> resolveApp(String target) async => target;

  @override
  Future<String> launchApp(String target) async => target;
}

class FakeLLMService implements LocalLLMService {
  @override
  bool get isReady => false;

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
  Future<String> chat(String prompt, {List<Map<String, String>> history = const [], void Function(String)? onToken}) async => '';

  @override
  Future<String> infer(String prompt) async => '{"action": "unsupported"}';

  @override
  Future<void> dispose() async {}
}

void main() {
  group('ScreenContextService', () {
    late ScreenContextService service;

    setUp(() {
      service = ScreenContextService();
    });

    test('parses raw accessibility summary into structured ScreenContext', () {
      const raw = '''
EYES pkg=com.android.chrome
-[TextView] "Breaking Tech News" [view] @[0.5,0.1]
-[TextView] "For inquiries contact support@operator.ai or call 9876543210" [view] @[0.5,0.3]
-[Button] "Visit https://google.com" [tap] @[0.8,0.9]
''';
      final ctx = service.parseRawSummary(raw);

      expect(ctx.packageName, 'com.android.chrome');
      expect(ctx.appName, 'Chrome');
      expect(ctx.nodes.length, 3);
      expect(ctx.visibleTexts, contains('Breaking Tech News'));
      expect(ctx.phoneNumbers, contains('9876543210'));
      expect(ctx.emails, contains('support@operator.ai'));
      expect(ctx.urls, contains('https://google.com'));
    });

    test('handles EYES_EMPTY and EYES_ERROR summaries', () {
      final emptyCtx = service.parseRawSummary('EYES_EMPTY: no active window');
      expect(emptyCtx.isEmpty, isTrue);

      final errorCtx = service.parseRawSummary('EYES_ERROR: accessibility not connected');
      expect(errorCtx.isEmpty, isTrue);
    });

    test('generates offline summary for active screen', () {
      const raw = '''
EYES pkg=com.whatsapp
-[TextView] "John Doe" [view] @[0.5,0.1]
-[TextView] "Hey are you coming?" [view] @[0.5,0.3]
''';
      final ctx = service.parseRawSummary(raw);
      final summary = service.generateOfflineSummary(ctx);

      expect(summary, contains('WhatsApp'));
      expect(summary, contains('John Doe'));
      expect(summary, contains('Hey are you coming?'));
    });
  });

  group('IntentParser - ScreenContextIntent', () {
    final parser = IntentParser();

    test('parses screen_context JSON action', () {
      final intent = parser.parse('{"action": "screen_context", "query": "what is on my screen", "mode": "summarize"}');
      expect(intent, isA<ScreenContextIntent>());
      final s = intent as ScreenContextIntent;
      expect(s.query, 'what is on my screen');
      expect(s.action, 'summarize');
    });
  });

  group('AssistantController - On-Screen Context Awareness', () {
    late AssistantController controller;
    late FakeEyesService fakeEyes;
    late FakeCallService fakeCall;
    late FakeTtsService fakeTts;

    setUp(() {
      fakeEyes = FakeEyesService();
      fakeCall = FakeCallService();
      fakeTts = FakeTtsService();

      final screenService = ScreenContextService(eyes: fakeEyes);

      controller = AssistantController(
        llmService: FakeLLMService(),
        intentParser: IntentParser(),
        appLauncher: FakeAppLauncherService(),
        modelManager: ModelManager(),
        callService: fakeCall,
        ttsService: fakeTts,
        eyesService: fakeEyes,
        screenContextService: screenService,
      );
    });

    test('what is on my screen summarizes active screen content', () async {
      await controller.processCommand("What's on my screen");

      expect(controller.statusMessage, contains('In Chrome'));
      expect(controller.statusMessage, contains('Breaking Tech News'));
      expect(fakeTts.spoken.isNotEmpty, isTrue);
    });

    test('summarize this page produces offline summary', () async {
      await controller.processCommand('Summarize this page');

      expect(controller.statusMessage, contains('In Chrome'));
      expect(fakeTts.spoken.isNotEmpty, isTrue);
    });

    test('call number on screen extracts phone number and dials it', () async {
      await controller.processCommand('Call the number on my screen');

      expect(fakeCall.calledContacts.isNotEmpty, isTrue);
      expect(fakeCall.calledContacts.first, '+1 628-998-5940');
    });

    test('handles empty screen when accessibility tree is unavailable', () async {
      fakeEyes.mockSummary = 'EYES_ERROR: Accessibility disabled';

      await controller.processCommand("What's on my screen");

      expect(controller.statusMessage, contains('Accessibility'));
    });
  });
}
