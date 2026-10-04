import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:friday_app/services/voice/speech_to_text_voice_command_service.dart';

class FakeSpeechToText implements SpeechToText {
  bool available = true;
  bool listenCalled = false;
  bool stopCalled = false;
  bool cancelCalled = false;
  SpeechListenOptions? lastListenOptions;
  void Function(String status)? statusListener;

  @override
  bool get isAvailable => available;

  @override
  bool get isListening => listenCalled && !stopCalled && !cancelCalled;

  @override
  Future<bool> initialize({
    dynamic onStatus,
    dynamic onError,
    Duration? finalTimeout,
    dynamic debugLogging,
    dynamic options,
  }) async {
    if (onStatus != null) {
      statusListener = (String status) => onStatus(status);
    }
    return available;
  }

  @override
  Future<void> listen({
    dynamic onResult,
    dynamic onSoundLevelChange,
    SpeechListenOptions? listenOptions,
    Duration? listenFor,
    Duration? pauseFor,
    dynamic partialResults,
    dynamic onDevice,
    String? localeId,
    ListenMode? listenMode,
    dynamic sampleRate,
    dynamic cancelOnError,
  }) async {
    listenCalled = true;
    stopCalled = false;
    cancelCalled = false;
    lastListenOptions = listenOptions;
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
    statusListener?.call('stopped');
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
    statusListener?.call('notListening');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeSpeechToText fakeSpeech;
  late SpeechToTextVoiceCommandService service;

  setUp(() async {
    fakeSpeech = FakeSpeechToText();
    service = SpeechToTextVoiceCommandService(speech: fakeSpeech);
    await service.initialize();
  });

  group('SpeechToTextVoiceCommandService', () {
    test('startListening uses deviceDefault mode and responsive pauseFor for short commands', () async {
      final started = await service.startListening();

      expect(started, isTrue);
      expect(fakeSpeech.listenCalled, isTrue);
      expect(fakeSpeech.lastListenOptions?.listenMode, ListenMode.deviceDefault);
      expect(
        fakeSpeech.lastListenOptions?.pauseFor,
        const Duration(seconds: 3),
      );
    });

    test('startListening uses dictation mode when long session requested', () async {
      final started = await service.startListening(
        listenFor: const Duration(minutes: 1),
      );

      expect(started, isTrue);
      expect(fakeSpeech.lastListenOptions?.listenMode, ListenMode.dictation);
      expect(
        fakeSpeech.lastListenOptions?.pauseFor,
        const Duration(seconds: 10),
      );
    });
  });
}


