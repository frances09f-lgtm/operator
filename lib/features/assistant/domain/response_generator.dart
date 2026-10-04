/// Generates the canonical spoken responses for the assistant.
///
/// The local LLM is only responsible for understanding the command; the
/// application builds these final sentences so voice output stays predictable
/// (raw model JSON is never sent to TTS).
class ResponseGenerator {
  const ResponseGenerator();

  /// Response for a validated, installed app that is about to open.
  String opening(String appLabel) => 'Opening $appLabel.';

  /// Response when the requested app is not installed. [appName] is the
  /// user-facing name (e.g. "Telegram"); a bare lower-case target like
  /// "telegram" is capitalized for presentation.
  String appNotInstalled(String appName) =>
      "${displayName(appName)} isn't installed.";

  /// Response for commands the assistant cannot handle (calls, messaging,
  /// weather, etc.).
  String unsupportedCommand() =>
      'I can only open apps and control media, volume, brightness, alarms and reminders right now.';

  /// Returns a conversational reply as-is, sanitized for speech.
  ///
  /// [message] normally comes from the LLM `chat` intent or from the
  /// offline small-talk heuristic. It is trimmed, collapsed to a single
  /// line and capped so TTS never speaks a runaway generation.
  String chat(String message) {
    var text = message.trim().replaceAll(RegExp(r'\s+'), ' ');
    // Strip surrounding quotes the small model sometimes echoes.
    if (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      text = text.substring(1, text.length - 1).trim();
    }
    if (text.isEmpty) return chatFallback();
    if (text.length > 300) text = '${text.substring(0, 297).trim()}...';
    return text;
  }

  /// Offline fallback when the model is unavailable but the user just said
  /// hello / small-talk. Keeps greeting working without any LLM call.
  String chatFallback() =>
      "Hello! I'm FRIDAY, your local assistant. How can I help?";

  /// Offline small-talk replies keyed by kind. Used before any LLM call so
  /// greetings answer instantly, even offline.
  String chatForKind(String kind) {
    switch (kind) {
      case 'greeting':
        return "Hello! I'm FRIDAY. How can I help you today?";
      case 'how_are_you':
        return "I'm running great! How can I help you today?";
      case 'who_are_you':
        return "I'm FRIDAY, your on-device assistant. I can open apps, control media, volume and brightness, set alarms and reminders, send WhatsApp messages, and run your custom commands.";
      case 'help':
        return 'I can open apps, toggle flashlight, Wi-Fi and Bluetooth, control media, volume and brightness, set alarms and reminders, search YouTube, play gallery videos, and send WhatsApp messages. Just tell me what to do!';
      case 'thanks':
        return "You're welcome! Anything else I can do for you?";
      case 'bye':
        return 'Goodbye! Just say my name when you need me.';
      case 'morning':
        return 'Good morning! How can I help you today?';
      case 'afternoon':
        return 'Good afternoon! How can I help you today?';
      case 'evening':
        return 'Good evening! How can I help you today?';
      default:
        return chatFallback();
    }
  }

  /// Short spoken confirmation for volume/brightness adjustments; the full
  /// detail (e.g. "Volume set to 50 percent.") is shown on screen only.
  String done() => 'Done.';

  /// Spoken confirmation after a multi-step sequence completes fully.
  /// [count] is the number of tasks run in order.
  String sequenceDone(int count) =>
      count <= 1 ? 'Done.' : 'Done. All $count tasks completed.';

  /// Shown on screen after a sequence (also used for TTS summary).
  /// [lines] are per-step results like "1. Opened WhatsApp."
  String sequenceSummary(List<String> lines) => lines.join('\n');

  /// Spoken + shown when only some sequence steps succeeded.
  String sequencePartial(int done, int total) =>
      'Completed $done of $total tasks.';

  /// Confirmation after a media play command is dispatched.
  String mediaPlaying() => 'Playing.';

  /// Confirmation after a media pause command is dispatched.
  String mediaPaused() => 'Paused.';

  /// Confirmation after a media resume command is dispatched.
  String mediaResuming() => 'Resuming.';

  /// Confirmation after a media next command is dispatched.
  String mediaSkipping() => 'Skipping.';

  /// Confirmation after a media previous command is dispatched.
  String mediaGoingBack() => 'Going back.';

  /// Confirmation after a media stop command is dispatched.
  String mediaStopped() => 'Stopped.';

  /// Response when the native layer reports it could not execute the media
  /// command.
  String mediaControlFailed() => "I couldn't control the media.";

  /// Confirmation after the volume is set to an absolute level.
  String volumeSet(int level) => 'Volume set to $level percent.';

  /// Confirmation after the volume is raised relative to its old level.
  String volumeUpResult(int level) => 'Volume is now $level percent.';

  /// Confirmation after the volume is lowered relative to its old level.
  String volumeDownResult(int level) => 'Volume is now $level percent.';

  /// Confirmation after the volume is muted.
  String volumeMuted() => 'Muted.';

  /// Confirmation after the previous volume level is restored.
  String volumeUnmuted(int level) => 'Volume restored to $level percent.';

  /// Response when just the current volume is reported.
  String volumeQuery(int level) => 'Volume is at $level percent.';

  /// Response when the native layer could not adjust the volume.
  String volumeControlFailed() => "I couldn't adjust the volume.";

  /// Confirmation after the brightness is set to an absolute level.
  String brightnessSet(int level) => 'Brightness set to $level percent.';

  /// Confirmation after the brightness is raised relative to its old level.
  String brightnessUpResult(int level) => 'Brightness is now $level percent.';

  /// Confirmation after the brightness is lowered relative to its old level.
  String brightnessDownResult(int level) => 'Brightness is now $level percent.';

  /// Response when just the current brightness is reported.
  String brightnessQuery(int level) => 'Brightness is at $level percent.';

  /// Response when system write permission is missing and the permissions
  /// settings page has been opened for the user to grant it.
  String brightnessPermissionRequired() =>
      'Brightness control needs a system setting. I opened the settings page - please allow it and try again.';

  /// Response when the native layer could not change the brightness.
  String brightnessControlFailed() =>
      "I couldn't change the screen brightness.";

  /// Response when the LLM output could not be turned into a valid intent.
  String cannotUnderstand() => 'I couldn\'t understand that command.';

  /// Response for empty/blank input.
  String emptyInput() => 'Please tell me which app to open.';

  /// Response when the local AI model is unavailable.
  String modelUnavailable() => 'The local AI model isn\'t available.';

  /// Response when a question needs the big smart model but it isn't downloaded.
  String smartModelUnavailable() =>
      'Smart model not downloaded. Tap "Download Smart Model" (~1GB) for ChatGPT-like answers.';

  /// Response before opening WhatsApp chat for a contact.
  String openingWhatsApp(String contactName) =>
      'Opening WhatsApp chat with ${displayName(contactName)}.';

  /// Response when contact is not found.
  String contactNotFound(String contactName) =>
      'Contact ${displayName(contactName)} not found.';

  /// Response when WhatsApp is not installed.
  String whatsAppNotInstalled() => "WhatsApp isn't installed.";

  /// Response when contact has no phone number.
  String contactHasNoPhone(String contactName) =>
      'Contact ${displayName(contactName)} has no phone number.';

  /// Spoken confirmation before placing a direct phone call.
  String calling(String contactName) =>
      'Calling ${displayName(contactName)}.';

  /// Generic phone-call failure.
  String callFailed() => "I couldn't place that call.";

  /// Response when phone/contacts permission is denied for calls.
  String callPermissionDenied() =>
      'I need phone and contacts permission to place calls.';

  /// Response when contacts permission is denied.
  String contactsPermissionDenied() =>
      'I need contacts permission to find that contact.';

  /// Generic WhatsApp failure.
  String whatsAppFailed() => "I couldn't send that WhatsApp message.";

  /// Response before sending an SMS / command to FO or another contact.
  String smsSending(String recipient) => recipient.toUpperCase() == 'FO'
      ? 'Sending command to FO.'
      : 'Sending message to ${displayName(recipient)}.';

  /// Response after SMS / FO command is sent.
  String smsSent(String recipient) => recipient.toUpperCase() == 'FO'
      ? 'Command sent to FO.'
      : 'Message sent to ${displayName(recipient)}.';

  /// Generic SMS failure.
  String smsFailed() => "I couldn't send that message.";

  /// Response when starting a custom automation.
  String customExecuting(String displayName) => 'Running ${displayName}.';

  /// Response when custom automation succeeds and collected texts are shown.
  String customCollected(String displayName) => '${displayName} completed.';

  /// Response when custom automation fails.
  String customFailed(String displayName, String reason) => "I couldn't run ${displayName}: $reason.";

  /// Response when accessibility service is disabled.
  String accessibilityDisabled() => 'Accessibility service is disabled. Please enable it in settings.';

  /// Response for read chat success.
  String readChatResult(String contact) => 'Here are the latest messages from ${displayName(contact)}.';

  /// Spoken confirmation before opening the gallery video at [index].
  String playingGalleryVideo(int index) =>
      'Playing ${ordinalWord(index)} video from your gallery.';

  /// Shown/spoken when the gallery has no video at [index].
  String galleryVideoNotFound(int index) =>
      "I couldn't find ${ordinalWord(index)} video in your gallery.";

  /// Shown/spoken when gallery access fails (e.g. permission denied).
  String galleryAccessFailed() => "I couldn't open your gallery videos.";

  /// Spoken confirmation before opening a YouTube search.
  String searchingYouTube(String query, int index) => index <= 1
      ? 'Searching YouTube for $query.'
      : 'Searching YouTube for $query and playing result $index.';

  /// Confirmation when the Nth result was auto-played via accessibility.
  String playingYouTubeResult(String query, int index) => index <= 1
      ? 'Playing the first result for $query.'
      : 'Playing result $index for $query.';

  /// Honest fallback when results opened but auto-play did not happen:
  /// guides the user to tap manually or enable the accessibility service.
  String youTubeOpenedTapManually(String query, int index) => index <= 1
      ? 'Opened YouTube results for $query. Tap the first video to play it. Enable the accessibility service for auto-play.'
      : 'Opened YouTube results for $query. Tap result $index to play it. Enable the accessibility service for auto-play.';

  /// Shown/spoken when YouTube is not installed.
  String youTubeNotInstalled() => "YouTube isn't installed.";

  /// Shown/spoken when the YouTube search could not be opened.
  String youTubeSearchFailed() => "I couldn't search YouTube.";

  /// Spoken confirmation before asking an AI app ([appLabel] e.g. DeepSeek).
  String askingAi(String appLabel, String query) =>
      'Asking $appLabel for $query.';

  /// Confirmation when the question was typed and sent via accessibility.
  String aiAskSent(String appLabel) => 'Sent to $appLabel.';

  /// Honest fallback when the app opened but auto-send did not happen:
  /// guides the user to tap send manually or enable accessibility.
  String aiAskOpenedTapSend(String appLabel, String query) =>
      'Opened $appLabel with "$query". Tap Send to ask. Enable the accessibility service for auto-send.';

  /// Shown/spoken when the requested AI app is not installed.
  /// App-only: no browser fallback per product decision.
  String aiNotInstalled(String appLabel) =>
      "${displayName(appLabel)} isn't installed.";

  /// Shown/spoken when asking the AI app failed.
  String aiAskFailed(String appLabel) =>
      "I couldn't ask ${displayName(appLabel)}.";

  /// Confirmation after an alarm is scheduled. [whenSpeech] is a short
  /// human phrase like "tomorrow at 7 AM" or "in 10 minutes".
  String alarmSet(String whenSpeech, {String label = ''}) {
    final l = label.trim();
    if (l.isEmpty) return 'Alarm set for $whenSpeech.';
    return 'Alarm set for $whenSpeech: $l.';
  }

  /// Confirmation after a reminder is scheduled.
  String reminderSet(String message, String whenSpeech) {
    final m = message.trim();
    if (m.isEmpty) return 'Reminder set for $whenSpeech.';
    return 'Reminder set for $whenSpeech: $m.';
  }

  /// Shown/spoken when scheduled alarms + reminders are listed.
  /// [lines] are per-item rows like "1. Alarm tomorrow at 7 AM".
  String alarmsListed(List<String> lines) {
    if (lines.isEmpty) return 'You have no alarms or reminders set.';
    if (lines.length == 1) return 'You have 1 alarm or reminder:\n${lines.first}';
    return 'You have ${lines.length} alarms and reminders:\n${lines.join('\n')}';
  }

  /// Confirmation after matching alarms/reminders are cancelled.
  String alarmsCancelled(int count) {
    if (count <= 0) return "I couldn't find a matching alarm or reminder.";
    if (count == 1) return 'Cancelled 1 alarm.';
    return 'Cancelled $count alarms.';
  }

  /// Shown/spoken when no alarm/reminder time could be understood.
  String alarmNoTime() =>
      'What time should I set it for? Try "set an alarm for 7 am" or "remind me in 10 minutes".';

  /// Shown/spoken when a reminder has no message body.
  String reminderNoMessage() =>
      'What should I remind you about? Try "remind me to drink water in 10 minutes".';

  /// Shown/spoken when the native alarm layer fails.
  String alarmFailed() => "I couldn't set that alarm.";

  /// Spoken while Gmail is being fetched in background.
  String readingEmails() => 'Checking your mails...';

  /// Shown/spoken when unread mails are listed.
  /// [lines] are rows like "1. Boss — Meeting at 4pm".
  String emailsListed(List<String> lines) {
    if (lines.isEmpty) return 'You have no unread mails.';
    if (lines.length == 1) return 'You have 1 unread mail:\n${lines.first}';
    return 'You have ${lines.length} unread mails:\n${lines.join('\n')}';
  }

  /// Shown/spoken when Gmail is not linked yet.
  String gmailNotConnected() =>
      'Gmail is not connected. Tap Connect Gmail to allow read-only access.';

  /// Shown/spoken when Gmail fetch needs internet.
  String gmailNeedsInternet() =>
      'I need internet to check mails. Please turn on internet and try again.';

  /// Shown/spoken when Gmail fetch fails generically.
  String gmailFailed() => "I couldn't check your mails. Please try again.";

  /// "1" -> "first", "2" -> "second", ... fallback "video 4".
  String ordinalWord(int index) {
    const words = {
      1: 'first',
      2: 'second',
      3: 'third',
      4: 'fourth',
      5: 'fifth',
      6: 'sixth',
      7: 'seventh',
      8: 'eighth',
      9: 'ninth',
      10: 'tenth',
    };
    return words[index] ?? 'video $index';
  }

  /// Capitalizes the first letter of [raw], used to display bare LLM targets
  /// in a friendlier form (e.g. "telegram" -> "Telegram").
  String displayName(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}