/// Media transport controls that FRIDAY can perform on the currently active
/// Android media session.
enum MediaAction {
  play('media_play'),
  pause('media_pause'),
  resume('media_resume'),
  next('media_next'),
  previous('media_previous'),
  stop('media_stop');

  const MediaAction(this.wireName);

  /// Name used in structured JSON intents and on the MethodChannel.
  final String wireName;

  /// Resolves a [wireName] (e.g. "media_play") back to an action, or null when
  /// the string is not one of the supported media actions.
  static MediaAction? fromWireName(String name) {
    for (final action in MediaAction.values) {
      if (action.wireName == name) return action;
    }
    return null;
  }
}

/// Desired state for a device toggle.
enum ToggleDesired {
  on('on'),
  off('off'),
  toggle('toggle');

  const ToggleDesired(this.wireName);
  final String wireName;

  static ToggleDesired? fromWireName(String name) {
    switch (name) {
      case 'on':
        return ToggleDesired.on;
      case 'off':
        return ToggleDesired.off;
      case 'toggle':
        return ToggleDesired.toggle;
      default:
        return null;
    }
  }
}

sealed class AssistantIntent {
  const AssistantIntent();
}

class OpenAppIntent extends AssistantIntent {
  final String target;

  const OpenAppIntent({required this.target});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpenAppIntent && runtimeType == other.runtimeType && target == other.target;

  @override
  int get hashCode => target.hashCode;

  @override
  String toString() => 'OpenAppIntent(target: "$target")';
}

class ToggleFlashlightIntent extends AssistantIntent {
  const ToggleFlashlightIntent();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToggleFlashlightIntent && runtimeType == other.runtimeType;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'ToggleFlashlightIntent()';
}

class ToggleDeviceIntent extends AssistantIntent {
  /// Device to toggle, e.g. 'bluetooth' or 'wifi'.
  final String device;

  /// Desired state: on, off, or toggle (default).
  final ToggleDesired desired;

  const ToggleDeviceIntent({required this.device, this.desired = ToggleDesired.toggle});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToggleDeviceIntent &&
          runtimeType == other.runtimeType &&
          device == other.device &&
          desired == other.desired;

  @override
  int get hashCode => Object.hash(device, desired);

  @override
  String toString() => 'ToggleDeviceIntent(device: "$device", desired: $desired)';
}

class MediaIntent extends AssistantIntent {
  /// The media transport action to perform.
  final MediaAction action;

  const MediaIntent(this.action);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaIntent &&
          runtimeType == other.runtimeType &&
          action == other.action;

  @override
  int get hashCode => action.hashCode;

  @override
  String toString() => 'MediaIntent(action: $action)';
}

class SendWhatsAppIntent extends AssistantIntent {
  /// Contact display name as spoken by user, e.g. "Mom", "Rahul".
  final String contactName;

  /// Message body to send.
  final String message;

  const SendWhatsAppIntent({required this.contactName, required this.message});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SendWhatsAppIntent &&
          runtimeType == other.runtimeType &&
          contactName == other.contactName &&
          message == other.message;

  @override
  int get hashCode => Object.hash(contactName, message);

  @override
  String toString() => 'SendWhatsAppIntent(contactName: "$contactName", message: "$message")';
}

class SendSmsIntent extends AssistantIntent {
  /// Recipient name or phone number as spoken by user, e.g. "FO", "Mom", "+1 628-998-5940".
  final String recipient;

  /// Message body to send.
  final String message;

  /// Optional direct phone number if known or pre-resolved (e.g. +16289985940 for FO).
  final String? phoneNumber;

  const SendSmsIntent({
    required this.recipient,
    required this.message,
    this.phoneNumber,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SendSmsIntent &&
          runtimeType == other.runtimeType &&
          recipient == other.recipient &&
          message == other.message &&
          phoneNumber == other.phoneNumber;

  @override
  int get hashCode => Object.hash(recipient, message, phoneNumber);

  @override
  String toString() =>
      'SendSmsIntent(recipient: "$recipient", message: "$message", phoneNumber: "$phoneNumber")';
}

class UnsupportedIntent extends AssistantIntent {
  const UnsupportedIntent();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UnsupportedIntent && runtimeType == other.runtimeType;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'UnsupportedIntent()';
}

/// Conversational small-talk that needs no device action.
///
/// Example: "hello" -> ChatIntent(message: "Hello! I'm FRIDAY...")
/// The message is the short friendly reply to speak + show.
class ChatIntent extends AssistantIntent {
  final String message;

  const ChatIntent({required this.message});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatIntent &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'ChatIntent(message: "$message")';
}

class CustomIntent extends AssistantIntent {
  /// Phrase that matched a teachable custom command.
  final String phrase;

  /// Extracted params for placeholders like {{contact}}.
  final Map<String, String> params;

  /// Id of the matched custom command, if known.
  final String? commandId;

  const CustomIntent({required this.phrase, this.params = const {}, this.commandId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomIntent &&
          runtimeType == other.runtimeType &&
          phrase == other.phrase &&
          commandId == other.commandId;

  @override
  int get hashCode => Object.hash(phrase, commandId);

  @override
  String toString() => 'CustomIntent(phrase: "$phrase", params: $params, commandId: $commandId)';
}

class VolumeIntent extends AssistantIntent {
  /// Absolute target level in percent (0-100). Null when only a relative
  /// adjustment or an unmute is requested.
  final int? level;

  /// Signed step for relative adjustment (positive = up, negative = down, 0 =
  /// meaning no relative adjustment).
  final int delta;

  /// True to restore the last non-zero volume level after a mute.
  final bool unmute;

  /// True to mute the media volume (the native layer remembers the last
  /// non-zero level so a later unmute can restore it).
  final bool mute;

  const VolumeIntent({
    this.level,
    this.delta = 0,
    this.unmute = false,
    this.mute = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VolumeIntent &&
          runtimeType == other.runtimeType &&
          level == other.level &&
          delta == other.delta &&
          unmute == other.unmute &&
          mute == other.mute;

  @override
  int get hashCode => Object.hash(level, delta, unmute, mute);

  @override
  String toString() =>
      'VolumeIntent(level: $level, delta: $delta, unmute: $unmute, mute: $mute)';
}

class BrightnessIntent extends AssistantIntent {
  /// Absolute target brightness in percent (0-100). Null when only a relative
  /// adjustment is requested.
  final int? level;

  /// Signed step for relative adjustment (positive = brighter, negative =
  /// dimmer, 0 = no relative adjustment).
  final int delta;

  const BrightnessIntent({this.level, this.delta = 0});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrightnessIntent &&
          runtimeType == other.runtimeType &&
          level == other.level &&
          delta == other.delta;

  @override
  int get hashCode => Object.hash(level, delta);

  @override
  String toString() => 'BrightnessIntent(level: $level, delta: $delta)';
}

class ReadChatIntent extends AssistantIntent {
  final String contactName;
  final int count;

  const ReadChatIntent({required this.contactName, this.count = 5});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadChatIntent &&
          runtimeType == other.runtimeType &&
          contactName == other.contactName &&
          count == other.count;

  @override
  int get hashCode => Object.hash(contactName, count);

  @override
  String toString() => 'ReadChatIntent(contactName: "$contactName", count: $count)';
}

/// Places a direct phone call to [contactName] (or a raw phone number).
///
/// Example: "call mom" -> contactName "mom".
/// The native layer resolves the name via ContactsContract and places the
/// call with ACTION_CALL (requires CALL_PHONE permission).
class CallIntent extends AssistantIntent {
  /// Contact display name as spoken by user, e.g. "Mom", or digits like
  /// "9876543210" when the user dictated a number directly.
  final String contactName;

  const CallIntent({required this.contactName});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallIntent &&
          runtimeType == other.runtimeType &&
          contactName == other.contactName;

  @override
  int get hashCode => contactName.hashCode;

  @override
  String toString() => 'CallIntent(contactName: "$contactName")';
}

/// Opens the gallery and plays the Nth video (1-based).
///
/// Example: "open gallery and play second video" -> index 2.
/// Index 1 means the most recent video.
class PlayGalleryVideoIntent extends AssistantIntent {
  /// 1-based position in the gallery's most-recent-first video list.
  final int index;

  const PlayGalleryVideoIntent({required this.index});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayGalleryVideoIntent &&
          runtimeType == other.runtimeType &&
          index == other.index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => 'PlayGalleryVideoIntent(index: $index)';
}

/// Opens YouTube, searches [query] and plays the Nth result (1-based).
///
/// Example: "open youtube search hindi music and play first video"
/// -> query "hindi music", index 1.
class YouTubeSearchPlayIntent extends AssistantIntent {
  final String query;

  /// 1-based position in the search results list.
  final int index;

  const YouTubeSearchPlayIntent({required this.query, this.index = 1});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YouTubeSearchPlayIntent &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          index == other.index;

  @override
  int get hashCode => Object.hash(query, index);

  @override
  String toString() => 'YouTubeSearchPlayIntent(query: "$query", index: $index)';
}

/// Sets a one-shot alarm that rings with sound + vibration at [time].
///
/// Example: "set an alarm for 7 am" -> time today/tomorrow 07:00.
class SetAlarmIntent extends AssistantIntent {
  final DateTime time;

  /// Optional spoken label ("gym", "wake up").
  final String label;

  const SetAlarmIntent({required this.time, this.label = ''});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetAlarmIntent &&
          runtimeType == other.runtimeType &&
          time.millisecondsSinceEpoch ==
              other.time.millisecondsSinceEpoch &&
          label == other.label;

  @override
  int get hashCode => Object.hash(time.millisecondsSinceEpoch, label);

  @override
  String toString() => 'SetAlarmIntent(time: $time, label: "$label")';
}

/// Sets a reminder that posts a notification with [message] at [time].
///
/// Example: "remind me to drink water in 10 minutes".
class SetReminderIntent extends AssistantIntent {
  final DateTime time;
  final String message;

  const SetReminderIntent({required this.time, required this.message});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetReminderIntent &&
          runtimeType == other.runtimeType &&
          time.millisecondsSinceEpoch ==
              other.time.millisecondsSinceEpoch &&
          message == other.message;

  @override
  int get hashCode => Object.hash(time.millisecondsSinceEpoch, message);

  @override
  String toString() =>
      'SetReminderIntent(time: $time, message: "$message")';
}

/// Lists scheduled alarms/reminders ("show my alarms").
class ListAlarmsIntent extends AssistantIntent {
  const ListAlarmsIntent();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListAlarmsIntent && runtimeType == other.runtimeType;

  @override
  int get hashCode => 7;

  @override
  String toString() => 'ListAlarmsIntent()';
}

/// Cancels alarms/reminders ("cancel my 7am alarm", "cancel all reminders").
///
/// An empty [query] cancels everything; otherwise the native layer matches
/// by label/message/time text.
class CancelAlarmIntent extends AssistantIntent {
  final String query;

  const CancelAlarmIntent({this.query = ''});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CancelAlarmIntent &&
          runtimeType == other.runtimeType &&
          query == other.query;

  @override
  int get hashCode => query.hashCode;

  @override
  String toString() => 'CancelAlarmIntent(query: "$query")';
}

/// Asks an installed AI app a question: opens the app, types [query],
/// taps Send. App-only, no browser fallback.
///
/// Example: "ask deepseek who is pm of india"
/// -> target "deepseek", query "who is pm of india".
class AiAskIntent extends AssistantIntent {
  /// Normalized target: 'deepseek', 'chatgpt' or 'gemini'.
  final String target;

  /// Question / prompt to type and send.
  final String query;

  const AiAskIntent({required this.target, required this.query});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiAskIntent &&
          runtimeType == other.runtimeType &&
          target == other.target &&
          query == other.query;

  @override
  int get hashCode => Object.hash(target, query);

  @override
  String toString() => 'AiAskIntent(target: "$target", query: "$query")';
}

/// Reads unread Gmail in background (no Gmail app opened).
///
/// Example: "read my unread mails" -> count 5.
class ReadEmailIntent extends AssistantIntent {
  /// How many unread mails to fetch (1..10).
  final int count;

  const ReadEmailIntent({this.count = 5});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadEmailIntent &&
          runtimeType == other.runtimeType &&
          count == other.count;

  @override
  int get hashCode => count.hashCode;

  @override
  String toString() => 'ReadEmailIntent(count: $count)';
}

/// Ordered list of tasks to run one-by-one, in order.
///
/// Example: "open whatsapp, set volume to 40 percent, set brightness to 30"
/// -> 3 steps executed sequentially. Each step is a normal single-task
/// [AssistantIntent]; sequences never nest.
class SequenceIntent extends AssistantIntent {
  final List<AssistantIntent> steps;

  const SequenceIntent({required this.steps});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SequenceIntent &&
          runtimeType == other.runtimeType &&
          _listEquals(steps, other.steps);

  @override
  int get hashCode => Object.hashAll(steps);

  @override
  String toString() => 'SequenceIntent(steps: $steps)';

  static bool _listEquals(List<AssistantIntent> a, List<AssistantIntent> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// On-screen context awareness intent.
///
/// Example: "what's on my screen", "summarize this page", "call the number on screen".
class ScreenContextIntent extends AssistantIntent {
  final String query;
  final String action; // 'summarize', 'read_aloud', 'extract_phone', 'qa'

  const ScreenContextIntent({
    required this.query,
    this.action = 'summarize',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenContextIntent &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          action == other.action;

  @override
  int get hashCode => Object.hash(query, action);

  @override
  String toString() => 'ScreenContextIntent(query: "$query", action: "$action")';
}

