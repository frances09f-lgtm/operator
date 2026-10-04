import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';

/// Result of a native phone-call dispatch.
class CallResult {
  final bool success;
  final String? errorMessage;
  final String? resolvedPhone;
  final String? resolvedName;

  const CallResult({
    required this.success,
    this.errorMessage,
    this.resolvedPhone,
    this.resolvedName,
  });
}

abstract class CallService {
  /// Places a direct phone call to [contactName].
  ///
  /// [contactName] is a display name like "Mom" or a raw number like
  /// "9876543210". The native layer resolves it via ContactsContract and
  /// places the call with ACTION_CALL (requires CALL_PHONE permission).
  Future<CallResult> makeCall({required String contactName});
}

class MethodChannelCallService implements CallService {
  final MethodChannel _channel;

  MethodChannelCallService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.phoneCallChannel);

  @override
  Future<CallResult> makeCall({required String contactName}) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'makeCall',
        {'contactName': contactName},
      );

      if (result == null) {
        throw const CallException('No response from native call handler.');
      }

      final success = result['success'] as bool? ?? false;
      final status = result['status'] as String? ?? 'UNKNOWN';
      final errorMessage = result['errorMessage'] as String?;
      final resolvedPhone = result['resolvedPhone'] as String?;
      final resolvedName = result['resolvedName'] as String?;

      if (success) {
        return CallResult(
          success: true,
          resolvedPhone: resolvedPhone,
          resolvedName: resolvedName,
        );
      }

      switch (status) {
        case 'CONTACT_NOT_FOUND':
          throw ContactNotFoundException(contactName);
        case 'CONTACT_HAS_NO_PHONE':
          throw CallException('Contact "$contactName" has no phone number.');
        case 'PERMISSION_DENIED':
          throw CallException(
            errorMessage ?? 'Phone and contacts permission is required to call "$contactName".',
          );
        case 'INVALID_REQUEST':
          throw const InvalidIntentException();
        default:
          throw CallException(errorMessage ?? 'Failed to place the call.');
      }
    } on PlatformException catch (e) {
      throw CallException('Platform error: ${e.message}');
    }
  }
}
