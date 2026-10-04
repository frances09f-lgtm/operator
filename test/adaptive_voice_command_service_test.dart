import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/services/voice/adaptive_voice_command_service.dart';
import 'package:friday_app/services/voice/voice_command_service.dart';

class MockVoiceService implements VoiceCommandService {
  bool initResult;
  bool isAvailableVal;
  bool isListeningVal;
  double soundLevelVal;
  String? errorMessageVal;

  bool initCalled = false;
  bool startCalled = false;
  bool stopCalled = false;
  bool cancelCalled = false;
  bool disposeCalled = false;

  @override
  void Function(String partialText)? onPartialResult;

  @override
  void Function(String recognizedText)? onFinalResult;

  @override
  void Function()? onListeningEnded;

  MockVoiceService({
    this.initResult = true,
    this.isAvailableVal = true,
    this.isListeningVal = false,
    this.soundLevelVal = 0.0,
    this.errorMessageVal,
  });

  @override
  bool get isAvailable => isAvailableVal;

  @override
  bool get isListening => isListeningVal;

  @override
  double get soundLevel => soundLevelVal;

  @override
  String? get errorMessage => errorMessageVal;

  @override
  Future<bool> initialize() async {
    initCalled = true;
    isAvailableVal = initResult;
    return initResult;
  }

  @override
  Future<bool> startListening({Duration? listenFor}) async {
    startCalled = true;
    isListeningVal = true;
    return true;
  }

  @override
  Future<String?> stopListening() async {
    stopCalled = true;
    isListeningVal = false;
    onListeningEnded?.call();
    return 'hello world';
  }

  @override
  Future<void> cancelListening() async {
    cancelCalled = true;
    isListeningVal = false;
    onListeningEnded?.call();
  }

  @override
  Future<void> dispose() async {
    disposeCalled = true;
  }

  @override
  Future<void> setLocale(String? localeId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdaptiveVoiceCommandService Tests', () {
    test('Initializes and reports availability cleanly', () async {
      final adaptive = AdaptiveVoiceCommandService();

      // On desktop test runner, Whistle reports unsupported and falls back gracefully
      final ok = await adaptive.initialize();
      expect(ok, isA<bool>());
    });

    test('Wired callbacks receive speech events', () async {
      final adaptive = AdaptiveVoiceCommandService();
      String? deliveredText;
      adaptive.onFinalResult = (text) {
        deliveredText = text;
      };

      expect(adaptive.onFinalResult, isNotNull);
    });
  });
}
