import 'package:friday_app/features/assistant/domain/intent_model.dart';

/// Supported slot types for assistant intents.
enum SlotType {
  contact,
  message,
  time,
  query,
  app,
  phoneNumber,
}

/// A single turn in the conversation history.
class ConversationTurn {
  final String role; // 'user' or 'assistant'
  final String utterance;
  final AssistantIntent? intent;
  final DateTime timestamp;

  ConversationTurn({
    required this.role,
    required this.utterance,
    this.intent,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => '[$role at $timestamp]: $utterance';
}

/// Represents an unresolved slot requiring clarification from the user.
class PendingClarification {
  final Type intentType;
  final SlotType missingSlot;
  final Map<String, dynamic> capturedSlots;
  final String promptQuestion;
  final DateTime createdAt;

  PendingClarification({
    required this.intentType,
    required this.missingSlot,
    required this.capturedSlots,
    required this.promptQuestion,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Whether this clarification request has expired (default: 2 minutes).
  bool get isExpired => DateTime.now().difference(createdAt).inMinutes >= 2;

  @override
  String toString() =>
      'PendingClarification(type: $intentType, missing: $missingSlot, slots: $capturedSlots, prompt: "$promptQuestion")';
}

/// Short-term entity memory capturing recently mentioned people, apps, and queries.
class EntityMemory {
  String? lastContact;
  String? lastPhoneNumber;
  String? lastApp;
  String? lastQuery;
  String? lastSubject;
  DateTime? lastAlarmTime;
  AssistantIntent? lastIntent;

  /// Updates entity memory based on executed or parsed intents.
  void updateWithIntent(AssistantIntent intent) {
    lastIntent = intent;
    if (intent is SendWhatsAppIntent) {
      if (intent.contactName.trim().isNotEmpty) {
        lastContact = intent.contactName.trim();
        lastSubject = lastContact;
      }
      lastApp = 'WhatsApp';
    } else if (intent is SendSmsIntent) {
      if (intent.recipient.trim().isNotEmpty) {
        lastContact = intent.recipient.trim();
        lastSubject = lastContact;
      }
      if (intent.phoneNumber != null && intent.phoneNumber!.trim().isNotEmpty) {
        lastPhoneNumber = intent.phoneNumber!.trim();
      }
    } else if (intent is CallIntent) {
      if (intent.contactName.trim().isNotEmpty) {
        lastContact = intent.contactName.trim();
        lastSubject = lastContact;
      }
    } else if (intent is OpenAppIntent) {
      if (intent.target.trim().isNotEmpty) {
        lastApp = intent.target.trim();
      }
    } else if (intent is YouTubeSearchPlayIntent) {
      if (intent.query.trim().isNotEmpty) {
        lastQuery = intent.query.trim();
        lastSubject = lastQuery;
      }
      lastApp = 'YouTube';
    } else if (intent is SetAlarmIntent) {
      lastAlarmTime = intent.time;
    }
  }

  /// Extracts potential subject entities from user utterances (e.g. "Who is Elon Musk?").
  void extractEntitiesFromUtterance(String utterance) {
    final trimmed = utterance.trim();
    if (trimmed.isEmpty) return;

    // "who is/was X", "tell me about X", "what is/was X"
    final subjectMatch = RegExp(
      r'^(?:who\s+(?:is|was)|tell\s+me\s+about|what\s+(?:is|was)|information\s+(?:on|about))\s+([A-Za-z0-9\s\.\-]+?)(?:\?|\.|\s*$)',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (subjectMatch != null) {
      final candidate = subjectMatch.group(1)?.trim();
      if (candidate != null &&
          candidate.isNotEmpty &&
          candidate.length < 50 &&
          !RegExp(r'\b(the|a|an|it|this|that|he|she|they|him|her)\b', caseSensitive: false).hasMatch(candidate)) {
        lastSubject = candidate;
        lastContact ??= candidate;
      }
    }
  }

  /// Clears all stored entities.
  void clear() {
    lastContact = null;
    lastPhoneNumber = null;
    lastApp = null;
    lastQuery = null;
    lastSubject = null;
    lastAlarmTime = null;
    lastIntent = null;
  }
}

/// Resolves pronouns and contextual references in user utterances.
class ContextReferenceResolver {
  const ContextReferenceResolver();

  /// Resolves pronouns (him, her, them, he, she, it, that) and references (again, back)
  /// in [input] using the active [memory].
  String resolve(String input, EntityMemory memory) {
    var text = input.trim();
    if (text.isEmpty) return text;

    final targetContact = memory.lastContact ?? memory.lastSubject;

    // 1. Resolve contact pronouns and actions
    if (targetContact != null && targetContact.isNotEmpty) {
      // Repetition actions: "call back", "call again", "redial"
      text = text.replaceAllMapped(
        RegExp(r'\b(call|phone|ring|dial)\s+(?:back|again)\b', caseSensitive: false),
        (m) => '${m[1]} $targetContact',
      );
      if (RegExp(r'^\s*redial\s*$', caseSensitive: false).hasMatch(text)) {
        text = 'call $targetContact';
      }

      // Repetition actions: "text again", "message again", "whatsapp again"
      text = text.replaceAllMapped(
        RegExp(r'\b(text|message|msg|dm|whatsapp|sms)\s+again\b', caseSensitive: false),
        (m) => '${m[1]} $targetContact',
      );

      // Communication verbs: "call him/her/them", "phone him/her/them"
      text = text.replaceAllMapped(
        RegExp(r'\b(call|phone|ring|dial)\s+(him|her|them)\b', caseSensitive: false),
        (m) => '${m[1]} $targetContact',
      );

      // Messaging verbs: "text him/her/them", "message him/her/them", "whatsapp him/her/them", "sms him/her/them"
      text = text.replaceAllMapped(
        RegExp(r'\b(text|message|msg|dm|whatsapp|sms)\s+(him|her|them)\b', caseSensitive: false),
        (m) => '${m[1]} $targetContact',
      );

      // Speech/tell verbs: "tell him/her/them", "ask him/her/them", "say to him/her/them"
      text = text.replaceAllMapped(
        RegExp(r'\b(tell|ask|say to|say)\s+(him|her|them)\b', caseSensitive: false),
        (m) => '${m[1]} $targetContact',
      );

      // Send verbs: "send to him/her/them", "send him/her/them"
      text = text.replaceAllMapped(
        RegExp(r'\bsend\s+to\s+(him|her|them)\b', caseSensitive: false),
        (m) => 'send to $targetContact',
      );
      text = text.replaceAllMapped(
        RegExp(r'\bsend\s+(him|her|them)\b', caseSensitive: false),
        (m) => 'send $targetContact',
      );

      // Prepositional references: "to him", "to her", "to them"
      text = text.replaceAllMapped(
        RegExp(r'\bto\s+(him|her|them)\b', caseSensitive: false),
        (m) => 'to $targetContact',
      );

      // Questions: "how old is he/she", "who is he/she", "where is he/she"
      text = text.replaceAllMapped(
        RegExp(r'\b(is|was|about|for)\s+(he|she|him|her)\b', caseSensitive: false),
        (m) => '${m[1]} $targetContact',
      );
    }

    // 2. Resolve query/media references: "play it on youtube", "search that", "find that"
    if (memory.lastQuery != null && memory.lastQuery!.isNotEmpty) {
      final query = memory.lastQuery!;
      text = text.replaceAllMapped(
        RegExp(r'\b(search|play|find|look up)\s+(?:for\s+)?(that|it)\b', caseSensitive: false),
        (m) => '${m[1]} $query',
      );
    }

    // 3. Resolve app references: "open it again", "launch it", "switch to it"
    if (memory.lastApp != null && memory.lastApp!.isNotEmpty) {
      final app = memory.lastApp!;
      text = text.replaceAllMapped(
        RegExp(r'\b(open|launch|start|switch to)\s+(?:it|that|again)\b', caseSensitive: false),
        (m) => '${m[1]} $app',
      );
    }

    return text;
  }
}

/// Dialogue State Tracker managing conversation turns, entity memory,
/// and interactive clarification flows.
class DialogueStateTracker {
  final EntityMemory memory;
  final ContextReferenceResolver resolver;
  final List<ConversationTurn> _history = [];
  final int maxHistoryTurns;

  PendingClarification? _pendingClarification;

  DialogueStateTracker({
    EntityMemory? memory,
    ContextReferenceResolver? resolver,
    this.maxHistoryTurns = 20,
  })  : memory = memory ?? EntityMemory(),
        resolver = resolver ?? const ContextReferenceResolver();

  /// Currently active pending clarification, or null if none is pending.
  PendingClarification? get pendingClarification {
    if (_pendingClarification != null && _pendingClarification!.isExpired) {
      _pendingClarification = null;
    }
    return _pendingClarification;
  }

  /// Whether the assistant is currently waiting for user clarification.
  bool get isAwaitingClarification => pendingClarification != null;

  /// Read-only view of recent conversation history.
  List<ConversationTurn> get history => List.unmodifiable(_history);

  /// Records a conversation turn.
  void recordTurn({
    required String role,
    required String utterance,
    AssistantIntent? intent,
  }) {
    _history.add(ConversationTurn(
      role: role,
      utterance: utterance,
      intent: intent,
    ));
    if (_history.length > maxHistoryTurns) {
      _history.removeAt(0);
    }
    if (intent != null) {
      memory.updateWithIntent(intent);
    } else if (role == 'user') {
      memory.extractEntitiesFromUtterance(utterance);
    }
  }

  /// Pre-processes [rawInput] by resolving contextual references with [EntityMemory].
  String resolveContext(String rawInput) {
    return resolver.resolve(rawInput, memory);
  }

  /// Checks if [intent] is missing required slots and sets up a pending clarification.
  /// Returns the [PendingClarification] if one was created, or `null` if the intent is complete.
  PendingClarification? inspectIntentForClarification(AssistantIntent intent) {
    if (intent is SendWhatsAppIntent) {
      final contact = intent.contactName.trim();
      final msg = intent.message.trim();

      if (contact.isEmpty) {
        _pendingClarification = PendingClarification(
          intentType: SendWhatsAppIntent,
          missingSlot: SlotType.contact,
          capturedSlots: {'message': msg},
          promptQuestion: 'Who would you like to message on WhatsApp?',
        );
        return _pendingClarification;
      } else if (msg.isEmpty) {
        _pendingClarification = PendingClarification(
          intentType: SendWhatsAppIntent,
          missingSlot: SlotType.message,
          capturedSlots: {'contactName': contact},
          promptQuestion: 'What message would you like to send to $contact?',
        );
        return _pendingClarification;
      }
    } else if (intent is SendSmsIntent) {
      final recipient = intent.recipient.trim();
      final msg = intent.message.trim();

      if (recipient.isEmpty) {
        _pendingClarification = PendingClarification(
          intentType: SendSmsIntent,
          missingSlot: SlotType.contact,
          capturedSlots: {'message': msg, 'phoneNumber': intent.phoneNumber},
          promptQuestion: 'Who would you like to send an SMS to?',
        );
        return _pendingClarification;
      } else if (msg.isEmpty) {
        _pendingClarification = PendingClarification(
          intentType: SendSmsIntent,
          missingSlot: SlotType.message,
          capturedSlots: {'recipient': recipient, 'phoneNumber': intent.phoneNumber},
          promptQuestion: 'What message would you like to text to $recipient?',
        );
        return _pendingClarification;
      }
    } else if (intent is CallIntent) {
      final contact = intent.contactName.trim();
      if (contact.isEmpty) {
        _pendingClarification = PendingClarification(
          intentType: CallIntent,
          missingSlot: SlotType.contact,
          capturedSlots: {},
          promptQuestion: 'Who would you like to call?',
        );
        return _pendingClarification;
      }
    } else if (intent is OpenAppIntent) {
      final target = intent.target.trim();
      if (target.isEmpty) {
        _pendingClarification = PendingClarification(
          intentType: OpenAppIntent,
          missingSlot: SlotType.app,
          capturedSlots: {},
          promptQuestion: 'Which app would you like me to open?',
        );
        return _pendingClarification;
      }
    } else if (intent is YouTubeSearchPlayIntent) {
      final query = intent.query.trim();
      if (query.isEmpty) {
        _pendingClarification = PendingClarification(
          intentType: YouTubeSearchPlayIntent,
          missingSlot: SlotType.query,
          capturedSlots: {'index': intent.index},
          promptQuestion: 'What would you like to search for on YouTube?',
        );
        return _pendingClarification;
      }
    }

    return null;
  }

  /// Attempts to complete any active [PendingClarification] using the user's [reply].
  /// Returns the completed [AssistantIntent] if resolved, or `null` if no pending
  /// clarification exists or if it could not be resolved.
  AssistantIntent? tryResolveClarification(String reply) {
    final pending = pendingClarification;
    if (pending == null) return null;

    final trimmedReply = reply.trim();
    if (trimmedReply.isEmpty) return null;

    // Check for cancellation phrases ("cancel", "nevermind", "forget it", "stop")
    final lower = trimmedReply.toLowerCase();
    if (lower == 'cancel' || lower == 'nevermind' || lower == 'never mind' || lower == 'forget it' || lower == 'stop') {
      clearClarification();
      return const ChatIntent(message: 'Cancelled.');
    }

    _pendingClarification = null; // Consume the pending clarification

    if (pending.intentType == SendWhatsAppIntent) {
      if (pending.missingSlot == SlotType.message) {
        final contact = pending.capturedSlots['contactName'] as String? ?? '';
        return SendWhatsAppIntent(contactName: contact, message: trimmedReply);
      } else if (pending.missingSlot == SlotType.contact) {
        final message = pending.capturedSlots['message'] as String? ?? '';
        return SendWhatsAppIntent(contactName: trimmedReply, message: message);
      }
    } else if (pending.intentType == SendSmsIntent) {
      if (pending.missingSlot == SlotType.message) {
        final recipient = pending.capturedSlots['recipient'] as String? ?? '';
        final phone = pending.capturedSlots['phoneNumber'] as String?;
        return SendSmsIntent(recipient: recipient, message: trimmedReply, phoneNumber: phone);
      } else if (pending.missingSlot == SlotType.contact) {
        final message = pending.capturedSlots['message'] as String? ?? '';
        return SendSmsIntent(recipient: trimmedReply, message: message);
      }
    } else if (pending.intentType == CallIntent) {
      if (pending.missingSlot == SlotType.contact) {
        return CallIntent(contactName: trimmedReply);
      }
    } else if (pending.intentType == OpenAppIntent) {
      if (pending.missingSlot == SlotType.app) {
        return OpenAppIntent(target: trimmedReply);
      }
    } else if (pending.intentType == YouTubeSearchPlayIntent) {
      if (pending.missingSlot == SlotType.query) {
        final index = pending.capturedSlots['index'] as int? ?? 1;
        return YouTubeSearchPlayIntent(query: trimmedReply, index: index);
      }
    }

    return null;
  }

  /// Explicitly clears any active pending clarification.
  void clearClarification() {
    _pendingClarification = null;
  }

  /// Clears conversation history and memory.
  void reset() {
    _history.clear();
    memory.clear();
    _pendingClarification = null;
  }
}
