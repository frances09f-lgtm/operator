import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';

/// Bridge for Android ACTION_ASSIST / VOICE_COMMAND launches
/// (long-press power / swipe corner when FRIDAY is the default assistant).
class AssistService {
  final MethodChannel _channel;

  AssistService({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(AppConstants.assistChannel);

  /// True if the app was launched (or re-invoked) via assist. Does not clear.
  Future<bool> isAssistLaunch() async {
    try {
      final v = await _channel.invokeMethod<bool>('isAssistLaunch');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Returns true once if launched via assist, clearing the native flag.
  Future<bool> consumeAssistLaunch() async {
    try {
      final v = await _channel.invokeMethod<bool>('consumeAssistLaunch');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearAssistLaunch() async {
    try {
      await _channel.invokeMethod('clearAssistLaunch');
    } catch (_) {}
  }

  /// Closes the translucent assist overlay (native finish()).
  /// No-op in the full app / on platforms without the channel.
  Future<void> closeAssist() async {
    try {
      await _channel.invokeMethod('closeAssist');
    } catch (_) {}
  }

  /// Backgrounds the assist task instead of destroying it, keeping the
  /// engine/model warm so the next long-press is fast.
  Future<void> dismissAssist() async {
    try {
      await _channel.invokeMethod('dismissAssist');
    } catch (_) {}
  }

  /// Drives native window translucency from Dart so the overlay can
  /// guarantee a transparent dimmed background even if the Activity was
  /// not started via ACTION_ASSIST (e.g. recreated).
  Future<void> setAssistWindow(bool enabled) async {
    try {
      await _channel.invokeMethod('setAssistWindow', {'enabled': enabled});
    } catch (_) {}
  }

  /// Wires native callbacks for ACTION_ASSIST (power button hold)
  /// and launcher open (user tapping the app icon).
  void setAssistHandlers({
    required void Function() onAssist,
    required void Function() onLauncherOpen,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAssist') {
        onAssist();
      } else if (call.method == 'onLauncherOpen') {
        onLauncherOpen();
      }
    });
  }

  /// Called when assist fires while the app is already alive (singleTop).
  void onAssist(void Function() callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAssist') callback();
    });
  }

  void clearHandler() {
    _channel.setMethodCallHandler(null);
  }
}
