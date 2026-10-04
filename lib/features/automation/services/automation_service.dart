import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';
import '../models/custom_command.dart';
import '../models/tap_step.dart';

class AutomationResult {
  final bool success;
  final String status;
  final List<String> collectedTexts;
  final String? errorMessage;

  const AutomationResult({
    required this.success,
    required this.status,
    this.collectedTexts = const [],
    this.errorMessage,
  });

  factory AutomationResult.fromMap(Map<String, dynamic> m) {
    return AutomationResult(
      success: m['success'] as bool? ?? false,
      status: m['status'] as String? ?? 'UNKNOWN',
      collectedTexts: ((m['collectedTexts'] as List?) ?? []).whereType<String>().toList(),
      errorMessage: m['errorMessage'] as String?,
    );
  }
}

abstract class AutomationService {
  Future<bool> isAccessibilityEnabled();
  Future<bool> isOverlayGranted();
  Future<void> requestAccessibilitySettings();
  Future<void> requestOverlayPermission();
  Future<AutomationResult> executeCommand(CustomCommand command, Map<String, String> params);
  Future<AutomationResult> executeSteps(List<TapStep> steps, {String? targetPackage});
  Future<void> startRecording();
  Future<List<TapStep>> stopRecording();
  Future<void> cancelRecording();
}

class AutomationException extends AppException {
  const AutomationException(super.message);
}

class AccessibilityDisabledException extends AppException {
  const AccessibilityDisabledException([super.message = 'Accessibility service is disabled. Please enable it in settings.']);
}

class OverlayPermissionException extends AppException {
  const OverlayPermissionException([super.message = 'Overlay permission is required to record taps.']);
}

class MethodChannelAutomationService implements AutomationService {
  final MethodChannel _channel;

  MethodChannelAutomationService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.automationChannel);

  @override
  Future<bool> isAccessibilityEnabled() async {
    try {
      final res = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isOverlayGranted() async {
    try {
      final res = await _channel.invokeMethod<bool>('isOverlayGranted');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> requestAccessibilitySettings() async {
    try {
      await _channel.invokeMethod<void>('requestAccessibilitySettings');
    } on PlatformException catch (e) {
      throw AutomationException(e.message ?? 'Failed to open accessibility settings');
    }
  }

  @override
  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod<void>('requestOverlayPermission');
    } on PlatformException catch (e) {
      throw AutomationException(e.message ?? 'Failed to open overlay settings');
    }
  }

  @override
  Future<AutomationResult> executeCommand(CustomCommand command, Map<String, String> params) async {
    final steps = command.substitutedSteps(params);
    return executeSteps(steps, targetPackage: command.targetPackage);
  }

  @override
  Future<AutomationResult> executeSteps(List<TapStep> steps, {String? targetPackage}) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'executeSteps',
        {
          'steps': steps.map((s) => s.toJson()).toList(),
          'targetPackage': targetPackage,
        },
      );
      if (result == null) {
        throw const AutomationException('No response from automation service');
      }
      final success = result['success'] as bool? ?? false;
      final status = result['status'] as String? ?? 'UNKNOWN';
      final collected = ((result['collectedTexts'] as List?) ?? []).whereType<String>().toList();
      final error = result['errorMessage'] as String?;

      if (success) {
        return AutomationResult(success: true, status: status, collectedTexts: collected);
      }

      switch (status) {
        case 'ACCESSIBILITY_DISABLED':
          throw const AccessibilityDisabledException();
        case 'OVERLAY_PERMISSION_REQUIRED':
          throw const OverlayPermissionException();
        case 'APP_NOT_FOUND':
          throw AppNotInstalledException(targetPackage ?? 'target app');
        case 'TIMEOUT':
          throw AutomationException(error ?? 'Timed out waiting for UI element');
        default:
          throw AutomationException(error ?? 'Automation failed: $status');
      }
    } on PlatformException catch (e) {
      throw AutomationException('Platform error: ${e.message}');
    } on AppException {
      rethrow;
    }
  }

  @override
  Future<void> startRecording() async {
    try {
      await _channel.invokeMethod<void>('startRecording');
    } on PlatformException catch (e) {
      final code = e.code;
      if (code == 'ACCESSIBILITY_DISABLED') throw const AccessibilityDisabledException();
      if (code == 'OVERLAY_PERMISSION_REQUIRED') throw const OverlayPermissionException();
      throw AutomationException(e.message ?? 'Failed to start recording');
    }
  }

  @override
  Future<List<TapStep>> stopRecording() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('stopRecording');
      if (result == null) return [];
      return result
          .whereType<Map>()
          .map((m) => TapStep.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList();
    } on PlatformException catch (e) {
      throw AutomationException(e.message ?? 'Failed to stop recording');
    }
  }

  @override
  Future<void> cancelRecording() async {
    try {
      await _channel.invokeMethod<void>('cancelRecording');
    } catch (_) {}
  }
}
