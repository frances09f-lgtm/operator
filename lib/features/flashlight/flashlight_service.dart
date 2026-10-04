import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';

abstract class FlashlightService {
  /// Toggles the device flashlight.
  ///
  /// Returns true if the flashlight is now on, false if it is now off.
  /// Throws [FlashlightException] if the flashlight cannot be toggled.
  Future<bool> toggleFlashlight();
}

class MethodChannelFlashlightService implements FlashlightService {
  final MethodChannel _channel;

  MethodChannelFlashlightService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.flashlightChannel);

  @override
  Future<bool> toggleFlashlight() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'toggleFlashlight',
      );

      if (result == null) {
        throw const FlashlightException('No response from native flashlight.');
      }

      final success = result['success'] as bool? ?? false;
      if (success) {
        return result['torchOn'] as bool? ?? true;
      }

      throw FlashlightException(
        result['errorMessage'] as String? ?? 'Failed to toggle the flashlight.',
      );
    } on PlatformException catch (e) {
      throw FlashlightException('Platform error: ${e.message}');
    }
  }
}