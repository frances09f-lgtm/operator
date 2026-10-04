import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';

/// Result of a native brightness-control dispatch.
class BrightnessControlResult {
  /// True when the native layer applied the brightness change.
  final bool success;

  /// Resulting screen brightness as a percentage (0-100).
  final int level;

  /// True when system write permission is missing and the settings page was
  /// opened so the user can grant it.
  final bool permissionRequired;

  final String? errorMessage;

  const BrightnessControlResult({
    required this.success,
    required this.level,
    this.permissionRequired = false,
    this.errorMessage,
  });
}

/// Controls the system screen brightness through the Android native layer.
abstract class BrightnessControlService {
  /// Sets the screen brightness to an absolute [level] (0-100).
  Future<BrightnessControlResult> setBrightness(int level);

  /// Brightens the screen by one step.
  Future<BrightnessControlResult> brightnessUp();

  /// Dims the screen by one step.
  Future<BrightnessControlResult> brightnessDown();

  /// Reports the current screen brightness without changing anything.
  Future<BrightnessControlResult> query();
}

class MethodChannelBrightnessControlService implements BrightnessControlService {
  final MethodChannel _channel;

  MethodChannelBrightnessControlService({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel(AppConstants.brightnessControlChannel);

  @override
  Future<BrightnessControlResult> setBrightness(int level) =>
      _adjust('set', level: level);

  @override
  Future<BrightnessControlResult> brightnessUp() => _adjust('up');

  @override
  Future<BrightnessControlResult> brightnessDown() => _adjust('down');

  @override
  Future<BrightnessControlResult> query() => _adjust('query');

  Future<BrightnessControlResult> _adjust(String command, {int? level}) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'adjust',
        {
          'command': command,
          'level': ?level,
        },
      );

      if (result == null) {
        throw const BrightnessControlException('No response from native brightness control.');
      }

      return BrightnessControlResult(
        success: result['success'] as bool? ?? false,
        level: (result['level'] as num?)?.round() ?? 0,
        permissionRequired: result['permissionRequired'] as bool? ?? false,
        errorMessage: result['errorMessage'] as String?,
      );
    } on PlatformException catch (e) {
      throw BrightnessControlException('Platform error: ${e.message}');
    }
  }
}