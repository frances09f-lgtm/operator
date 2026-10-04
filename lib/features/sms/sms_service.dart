import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';

class SmsResult {
  final bool success;
  final String status;
  final String recipient;
  final String? resolvedPhone;
  final String? errorMessage;
  final bool isDirectSend;

  const SmsResult({
    required this.success,
    required this.status,
    required this.recipient,
    this.resolvedPhone,
    this.errorMessage,
    this.isDirectSend = false,
  });
}

abstract class SmsService {
  /// Sends an SMS or message to [recipient] with [message].
  ///
  /// [recipient] can be "FO", a contact name, or a raw phone number.
  /// If [phoneNumber] is explicitly provided, it is dialed/messaged directly.
  Future<SmsResult> sendSms({
    required String recipient,
    required String message,
    String? phoneNumber,
  });
}

class MethodChannelSmsService implements SmsService {
  final MethodChannel _channel;

  MethodChannelSmsService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.smsChannel);

  @override
  Future<SmsResult> sendSms({
    required String recipient,
    required String message,
    String? phoneNumber,
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'sendSms',
        {
          'recipient': recipient,
          'message': message,
          if (phoneNumber != null) 'phoneNumber': phoneNumber,
        },
      );

      if (res == null) {
        throw const SmsException('No response from native SMS handler.');
      }

      final success = res['success'] as bool? ?? false;
      final status = res['status'] as String? ?? 'UNKNOWN';
      final errorMessage = res['errorMessage'] as String?;
      final resolvedPhone = res['resolvedPhone'] as String?;
      final isDirectSend = res['isDirectSend'] as bool? ?? false;

      if (success) {
        return SmsResult(
          success: true,
          status: status,
          recipient: recipient,
          resolvedPhone: resolvedPhone,
          isDirectSend: isDirectSend,
        );
      }

      switch (status) {
        case 'CONTACT_NOT_FOUND':
          throw ContactNotFoundException(recipient);
        case 'CONTACT_HAS_NO_PHONE':
          throw SmsException('Contact "$recipient" has no valid phone number.');
        case 'PERMISSION_DENIED':
          throw SmsException(
            errorMessage ?? 'SMS permission is required to send messages.',
          );
        case 'INVALID_REQUEST':
          throw const InvalidIntentException();
        default:
          throw SmsException(errorMessage ?? 'Failed to send message.');
      }
    } on PlatformException catch (e) {
      throw SmsException('Platform error: ${e.message}');
    }
  }
}
