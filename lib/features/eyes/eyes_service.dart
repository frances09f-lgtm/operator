import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';

/// Friday Eyes: read-only summary of the active window's accessibility tree.
///
/// Calls [AutomationAccessibilityService.getEyesSummary] via the existing
/// `friday/automation` channel. No capture happens unless the user taps
/// the manual-test button.
class EyesService {
  static const MethodChannel _channel =
      MethodChannel(AppConstants.automationChannel);

  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('requestAccessibilitySettings');
    } catch (_) {}
  }

  /// Returns lines like `EYES pkg=...` or `EYES_EMPTY: ...` / `EYES_ERROR: ...`.
  Future<String> getSummary({int maxNodes = 40}) async {
    try {
      final res = await _channel.invokeMethod<String>(
        'getScreenSummary',
        {'maxNodes': maxNodes},
      );
      return res ?? 'EYES_ERROR: empty reply';
    } catch (e) {
      return 'EYES_ERROR: $e';
    }
  }
}
