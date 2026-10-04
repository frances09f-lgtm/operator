abstract class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => message;
}

class ModelNotAvailableException extends AppException {
  const ModelNotAvailableException([super.message = 'Local AI model is not available.']);
}

class InvalidIntentException extends AppException {
  const InvalidIntentException([super.message = 'I couldn\'t understand that command.']);
}

class UnsupportedActionException extends AppException {
  const UnsupportedActionException([
    super.message =
        'I can only open apps and control media, volume, and brightness right now.',
  ]);
}

class EmptyCommandException extends AppException {
  const EmptyCommandException([super.message = 'Please enter an app-opening command.']);
}

class AppNotInstalledException extends AppException {
  final String appName;
  const AppNotInstalledException(this.appName) : super('$appName is not installed.');
}

class AppLaunchException extends AppException {
  const AppLaunchException([super.message = 'Failed to launch application.']);
}

class FlashlightException extends AppException {
  const FlashlightException([super.message = 'Could not toggle the flashlight.']);
}

class DeviceControlException extends AppException {
  const DeviceControlException([super.message = 'Could not toggle that setting.']);
}

class MediaControlException extends AppException {
  const MediaControlException([super.message = "I couldn't control the media."]);
}

class VolumeControlException extends AppException {
  const VolumeControlException([super.message = "I couldn't adjust the volume."]);
}

class BrightnessControlException extends AppException {
  const BrightnessControlException([super.message = "I couldn't change the screen brightness."]);
}

class ModelDownloadException extends AppException {
  const ModelDownloadException([super.message = 'Could not download the local AI model.']);
}

class WhatsAppException extends AppException {
  const WhatsAppException([super.message = 'Failed to send WhatsApp message.']);
}

class CallException extends AppException {
  const CallException([super.message = "I couldn't place that call."]);
}

class SmsException extends AppException {
  const SmsException([super.message = "Failed to send message."]);
}

class WhatsAppNotInstalledException extends AppException {
  const WhatsAppNotInstalledException([super.message = "WhatsApp isn't installed."]);
}

class ContactNotFoundException extends AppException {
  final String contactName;
  const ContactNotFoundException(this.contactName)
      : super('Contact "$contactName" not found.');
}

class AutomationException extends AppException {
  const AutomationException(super.message);
}

class AccessibilityDisabledException extends AppException {
  const AccessibilityDisabledException([
    super.message = 'Accessibility service is disabled. Please enable it in settings.',
  ]);
}

class CustomCommandNotFoundException extends AppException {
  final String phrase;
  const CustomCommandNotFoundException(this.phrase) : super('No saved command matches "$phrase".');
}

class GalleryException extends AppException {
  const GalleryException([super.message = "I couldn't open your gallery videos."]);
}

class GalleryVideoNotFoundException extends AppException {
  final int index;
  const GalleryVideoNotFoundException(this.index)
      : super("I couldn't find that video in your gallery.");
}

class YouTubeException extends AppException {
  const YouTubeException([super.message = "I couldn't search YouTube."]);
}

class YouTubeNotInstalledException extends AppException {
  const YouTubeNotInstalledException([super.message = "YouTube isn't installed."]);
}

class AiAskException extends AppException {
  const AiAskException([super.message = "I couldn't ask that app."]);
}

class AiAskNotInstalledException extends AppException {
  final String appName;
  const AiAskNotInstalledException(this.appName)
      : super('$appName is not installed.');
}

class AlarmException extends AppException {
  const AlarmException([super.message = "I couldn't set that alarm."]);
}

class GmailException extends AppException {
  /// Technical detail (HTTP status, Google reason codes) shown in the debug
  /// panel. Never spoken — [message] is the short user-facing sentence.
  final String? detail;
  const GmailException([
    super.message = "I couldn't check your mails.",
    this.detail,
  ]);
}

class GmailNotConnectedException extends AppException {
  const GmailNotConnectedException([
    super.message =
        'Gmail is not connected. Tap Connect Gmail to allow read-only access.',
  ]);
}

class GmailNetworkException extends AppException {
  const GmailNetworkException([
    super.message =
        'I need internet to check mails. Please turn on internet and try again.',
  ]);
}
