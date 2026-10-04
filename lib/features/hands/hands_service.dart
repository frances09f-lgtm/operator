import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';

/// Friday Hands: armed-only manual test actions.
///
/// Every mutating call refuses unless the user tapped Arm on the manual
/// test screen, and banking/payment apps are refused native-side.
/// Returns the native status map (`success`/`status`/`errorMessage`).
class HandsService {
  static const MethodChannel _channel =
      MethodChannel(AppConstants.automationChannel);

  Future<Map<String, dynamic>> arm() async {
    try {
      final res = await _channel.invokeMethod<Map>('armManualTest');
      return res == null
          ? {'success': false, 'status': 'ERROR'}
          : Map<String, dynamic>.from(res);
    } catch (e) {
      return {'success': false, 'status': 'ERROR', 'errorMessage': '$e'};
    }
  }

  Future<Map<String, dynamic>> disarm() async {
    try {
      final res = await _channel.invokeMethod<Map>('disarmManualTest');
      return res == null
          ? {'success': true, 'status': 'DISARMED'}
          : Map<String, dynamic>.from(res);
    } catch (e) {
      return {'success': true, 'status': 'DISARMED'};
    }
  }

  /// Whether the user has armed manual-test actions. The agent loop
  /// checks this before every step so mid-run Disarm stops it.
  Future<bool> isArmed() async {
    try {
      return await _channel.invokeMethod<bool>('isManualArmed') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> tap(double xPct, double yPct) async {
    try {
      final res = await _channel.invokeMethod<Map>(
        'manualTap',
        {'xPct': xPct, 'yPct': yPct},
      );
      return res == null
          ? {'success': false, 'status': 'ERROR'}
          : Map<String, dynamic>.from(res);
    } catch (e) {
      return {'success': false, 'status': 'ERROR', 'errorMessage': '$e'};
    }
  }

  Future<Map<String, dynamic>> enterText(String text) async {
    try {
      final res = await _channel.invokeMethod<Map>(
        'manualEnterText',
        {'text': text},
      );
      return res == null
          ? {'success': false, 'status': 'ERROR'}
          : Map<String, dynamic>.from(res);
    } catch (e) {
      return {'success': false, 'status': 'ERROR', 'errorMessage': '$e'};
    }
  }
}
