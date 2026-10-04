import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/features/alarm/alarm_service.dart';
import 'package:friday_app/features/app_launcher/app_launcher_service.dart';
import 'package:friday_app/features/assistant/domain/intent_parser.dart';
import 'package:friday_app/features/assistant/presentation/assistant_controller.dart';
import 'package:friday_app/services/local_llm/local_llm_service.dart';
import 'package:friday_app/services/local_llm/model_manager.dart';
import 'package:friday_app/services/tts/text_to_speech_service.dart';

class _OfflineLLM implements LocalLLMService {
  int calls = 0;
  @override
  bool get isReady => false;

  @override
  String? get activeMode => null;

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
  }) async {
    throw StateError('LLM should not be called for alarms');
  }

  @override
  Future<String> infer(String userCommand) async {
    calls++;
    throw StateError('LLM should not be called for alarms');
  }

  @override
  Future<void> dispose() async {}
}

class _FakeAlarm implements AlarmService {
  int setAlarmCalls = 0;
  int setReminderCalls = 0;
  int listCalls = 0;
  int cancelCalls = 0;
  String lastLabel = '';
  String lastMessage = '';
  String lastQuery = '';
  final List<AlarmItem> items = [];

  @override
  Future<AlarmItem> setAlarm(DateTime time, {String label = ''}) async {
    setAlarmCalls++;
    lastLabel = label;
    final item = AlarmItem(
      id: 1,
      kind: 'alarm',
      triggerAtMillis: time.millisecondsSinceEpoch,
      label: label,
    );
    items.add(item);
    return item;
  }

  @override
  Future<AlarmItem> setReminder(DateTime time, String message) async {
    setReminderCalls++;
    lastMessage = message;
    final item = AlarmItem(
      id: 2,
      kind: 'reminder',
      triggerAtMillis: time.millisecondsSinceEpoch,
      label: message,
    );
    items.add(item);
    return item;
  }

  @override
  Future<List<AlarmItem>> listAlarms() async {
    listCalls++;
    return List.of(items);
  }

  @override
  Future<int> cancelAlarm(String query) async {
    cancelCalls++;
    lastQuery = query;
    final n = items.length;
    items.clear();
    return n;
  }
}

class _NoopLauncher implements AppLauncherService {
  @override
  Future<String> launchApp(String target) async => target;
  @override
  Future<String> resolveApp(String target) async => target;
}

class _NoopModelManager extends ModelManager {
  @override
  Future<String?> findModelPath({List<String>? fileNames}) async => null;
  @override
  Future<String?> findCommandModelPath() async => null;
  @override
  Future<String?> findChatModelPath() async => null;
  @override
  Future<String> getPrimaryModelPath() async => '/none';
}

class _NoopTTS implements TextToSpeechService {
  final List<String> spoken = [];
  @override
  bool get isAvailable => true;
  @override
  void Function()? onCompletion;
  @override
  Future<void> dispose() async {}
  @override
  Future<bool> initialize() async => true;
  @override
  Future<bool> isLanguageAvailable(String locale) async => true;
  @override
  Future<void> setLanguage(String language) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}
}

void main() {
  group('AssistantController - alarms fast path (offline, no LLM)', () {
    late _OfflineLLM llm;
    late _FakeAlarm alarm;
    late _NoopTTS tts;
    late AssistantController controller;

    setUp(() {
      llm = _OfflineLLM();
      alarm = _FakeAlarm();
      tts = _NoopTTS();
      controller = AssistantController(
        llmService: llm,
        intentParser: IntentParser(),
        appLauncher: _NoopLauncher(),
        modelManager: _NoopModelManager(),
        alarmService: alarm,
        ttsService: tts,
      );
    });

    test('set alarm in 10 minutes never touches the LLM', () async {
      await controller.processCommand('set an alarm in 10 minutes');

      expect(alarm.setAlarmCalls, 1);
      expect(llm.calls, 0);
      expect(controller.statusMessage.toLowerCase(), contains('alarm set'));
      expect(tts.spoken.single.toLowerCase(), contains('alarm set'));
    });

    test('reminder keeps its message', () async {
      await controller.processCommand('remind me to drink water in 10 minutes');

      expect(alarm.setReminderCalls, 1);
      expect(alarm.lastMessage, 'drink water');
      expect(llm.calls, 0);
      expect(controller.statusMessage.toLowerCase(), contains('drink water'));
    });

    test('alarm with no time guides instead of failing', () async {
      await controller.processCommand('set an alarm');

      expect(alarm.setAlarmCalls, 0);
      expect(llm.calls, 0);
      expect(controller.statusMessage.toLowerCase(), contains('what time'));
    });

    test('show my alarms lists without the LLM', () async {
      await controller.processCommand('set an alarm in 10 minutes');
      await controller.processCommand('show my alarms');

      expect(alarm.listCalls, 1);
      expect(llm.calls, 0);
      expect(controller.statusMessage.toLowerCase(), contains('alarm'));
    });

    test('cancel alarm works offline', () async {
      await controller.processCommand('set an alarm in 10 minutes');
      await controller.processCommand('cancel my alarm');

      expect(alarm.cancelCalls, 1);
      expect(controller.statusMessage.toLowerCase(), contains('cancelled'));
    });
  });
}
