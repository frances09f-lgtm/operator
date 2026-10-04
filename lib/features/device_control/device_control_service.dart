import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';
import 'package:friday_app/features/assistant/domain/intent_model.dart';

enum SystemToggle { bluetooth, wifi }

class SystemToggleResult {
  final bool success;
  final bool panelOpened;
  final bool isOn;
  final bool wasOn;
  final String? errorMessage;
  final bool permissionRequired;

  const SystemToggleResult({
    required this.success,
    required this.panelOpened,
    required this.isOn,
    required this.wasOn,
    this.errorMessage,
    this.permissionRequired = false,
  });
}

abstract class DeviceControlService {
  /// Toggles [toggle] on the device with optional [desired] state.
  ///
  /// When [SystemToggleResult.panelOpened] is true, the OS blocked a direct
  /// toggle and the system settings panel was opened instead for the user to
  /// complete with a tap.
  ///
  /// When [SystemToggleResult.permissionRequired] is true, the operation
  /// requires a runtime permission (e.g., BLUETOOTH_CONNECT on Android 12+).
  Future<SystemToggleResult> toggle(SystemToggle toggle, {ToggleDesired desired = ToggleDesired.toggle});
}

class MethodChannelDeviceControlService implements DeviceControlService {
  final MethodChannel _channel;

  MethodChannelDeviceControlService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.deviceControlChannel);

  @override
  Future<SystemToggleResult> toggle(SystemToggle toggle, {ToggleDesired desired = ToggleDesired.toggle}) async {
    final target = switch (toggle) {
      SystemToggle.bluetooth => 'bluetooth',
      SystemToggle.wifi => 'wifi',
    };

    final desiredStr = switch (desired) {
      ToggleDesired.on => 'on',
      ToggleDesired.off => 'off',
      ToggleDesired.toggle => 'toggle',
    };

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'toggle',
        {'target': target, 'desired': desiredStr},
      );

      if (result == null) {
        throw const DeviceControlException('No response from native device control.');
      }

      return SystemToggleResult(
        success: result['success'] as bool? ?? false,
        panelOpened: result['panelOpened'] as bool? ?? false,
        isOn: result['isOn'] as bool? ?? false,
        wasOn: result['wasOn'] as bool? ?? false,
        errorMessage: result['errorMessage'] as String?,
        permissionRequired: result['permissionRequired'] as bool? ?? false,
      );
    } on PlatformException catch (e) {
      throw DeviceControlException('Platform error: ${e.message}');
    }
  }
}
