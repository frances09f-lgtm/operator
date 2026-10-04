import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/features/assistant/domain/dialogue_state.dart';
import 'package:friday_app/features/assistant/domain/intent_model.dart';

void main() {
  group('EntityMemory', () {
    test('updates lastContact and lastApp on SendWhatsAppIntent', () {
      final memory = EntityMemory();
      memory.updateWithIntent(
        const SendWhatsAppIntent(contactName: 'Alice', message: 'Hello'),
      );
      expect(memory.lastContact, 'Alice');
      expect(memory.lastApp, 'WhatsApp');
    });

    test('updates lastContact and lastPhoneNumber on SendSmsIntent', () {
      final memory = EntityMemory();
      memory.updateWithIntent(
        const SendSmsIntent(
          recipient: 'Bob',
          message: 'See you',
          phoneNumber: '+1234567890',
        ),
      );
      expect(memory.lastContact, 'Bob');
      expect(memory.lastPhoneNumber, '+1234567890');
    });

    test('updates lastContact on CallIntent', () {
      final memory = EntityMemory();
      memory.updateWithIntent(const CallIntent(contactName: 'Charlie'));
      expect(memory.lastContact, 'Charlie');
    });

    test('updates lastQuery and lastApp on YouTubeSearchPlayIntent', () {
      final memory = EntityMemory();
      memory.updateWithIntent(
        const YouTubeSearchPlayIntent(query: 'Imagine Dragons', index: 1),
      );
      expect(memory.lastQuery, 'Imagine Dragons');
      expect(memory.lastApp, 'YouTube');
    });

    test('clear resets all entity memory', () {
      final memory = EntityMemory();
      memory.updateWithIntent(
        const SendWhatsAppIntent(contactName: 'Alice', message: 'Hello'),
      );
      memory.clear();
      expect(memory.lastContact, isNull);
      expect(memory.lastApp, isNull);
    });
  });

  group('ContextReferenceResolver', () {
    const resolver = ContextReferenceResolver();

    test('resolves "call him" when contact is stored', () {
      final memory = EntityMemory()..lastContact = 'Alex';
      final resolved = resolver.resolve('call him', memory);
      expect(resolved, 'call Alex');
    });

    test('resolves "send her a message" when contact is stored', () {
      final memory = EntityMemory()..lastContact = 'Sarah';
      final resolved = resolver.resolve('send her a message', memory);
      expect(resolved, 'send Sarah a message');
    });

    test('resolves "text them" when contact is stored', () {
      final memory = EntityMemory()..lastContact = 'John';
      final resolved = resolver.resolve('text them', memory);
      expect(resolved, 'text John');
    });

    test('resolves "play it on youtube" when query is stored', () {
      final memory = EntityMemory()..lastQuery = 'Queen Bohemian Rhapsody';
      final resolved = resolver.resolve('play it on youtube', memory);
      expect(resolved, 'play Queen Bohemian Rhapsody on youtube');
    });

    test('leaves input untouched when memory is empty', () {
      final memory = EntityMemory();
      expect(resolver.resolve('call him', memory), 'call him');
      expect(resolver.resolve('play it', memory), 'play it');
    });
  });

  group('DialogueStateTracker', () {
    late DialogueStateTracker tracker;

    setUp(() {
      tracker = DialogueStateTracker();
    });

    test('records conversation history up to max turns', () {
      for (int i = 0; i < 25; i++) {
        tracker.recordTurn(role: 'user', utterance: 'Turn $i');
      }
      expect(tracker.history.length, 20);
      expect(tracker.history.first.utterance, 'Turn 5');
      expect(tracker.history.last.utterance, 'Turn 24');
    });

    test('identifies missing message in WhatsApp intent and asks clarification', () {
      const intent = SendWhatsAppIntent(contactName: 'Mom', message: '');
      final clarification = tracker.inspectIntentForClarification(intent);

      expect(clarification, isNotNull);
      expect(clarification!.missingSlot, SlotType.message);
      expect(clarification.promptQuestion, 'What message would you like to send to Mom?');
      expect(tracker.isAwaitingClarification, isTrue);
    });

    test('identifies missing contact in Call intent and asks clarification', () {
      const intent = CallIntent(contactName: '');
      final clarification = tracker.inspectIntentForClarification(intent);

      expect(clarification, isNotNull);
      expect(clarification!.missingSlot, SlotType.contact);
      expect(clarification.promptQuestion, 'Who would you like to call?');
      expect(tracker.isAwaitingClarification, isTrue);
    });

    test('resolves pending WhatsApp message clarification with user reply', () {
      const intent = SendWhatsAppIntent(contactName: 'Mom', message: '');
      tracker.inspectIntentForClarification(intent);

      final resolvedIntent = tracker.tryResolveClarification("I'm on my way home");
      expect(resolvedIntent, isA<SendWhatsAppIntent>());
      final wa = resolvedIntent as SendWhatsAppIntent;
      expect(wa.contactName, 'Mom');
      expect(wa.message, "I'm on my way home");
      expect(tracker.isAwaitingClarification, isFalse);
    });

    test('handles cancellation phrase during clarification', () {
      const intent = SendWhatsAppIntent(contactName: 'Mom', message: '');
      tracker.inspectIntentForClarification(intent);

      final resolvedIntent = tracker.tryResolveClarification('cancel');
      expect(resolvedIntent, isA<ChatIntent>());
      expect((resolvedIntent as ChatIntent).message, 'Cancelled.');
      expect(tracker.isAwaitingClarification, isFalse);
    });

    test('returns null when intent is complete', () {
      const intent = SendWhatsAppIntent(contactName: 'Mom', message: 'Hello');
      final clarification = tracker.inspectIntentForClarification(intent);
      expect(clarification, isNull);
      expect(tracker.isAwaitingClarification, isFalse);
    });
  });
}
