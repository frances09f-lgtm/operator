import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';

/// Result of a native WhatsApp dispatch.
class WhatsAppResult {
  final bool success;
  final String? errorMessage;
  final String? resolvedPhone;
  final String? resolvedName;

  const WhatsAppResult({
    required this.success,
    this.errorMessage,
    this.resolvedPhone,
    this.resolvedName,
  });
}

abstract class WhatsAppService {
  /// Sends WhatsApp message to contact [contactName] with [message].
  ///
  /// [contactName] is a display name like "Mom", "Rahul".
  /// The native layer resolves it to a phone number via ContactsContract.
  /// On success it opens WhatsApp chat with pre-filled [message].
  /// The user still needs to tap send in WhatsApp (Android security).
  Future<WhatsAppResult> sendWhatsApp({
    required String contactName,
    required String message,
  });
}

class MethodChannelWhatsAppService implements WhatsAppService {
  final MethodChannel _channel;

  MethodChannelWhatsAppService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.whatsAppChannel);

  @override
  Future<WhatsAppResult> sendWhatsApp({
    required String contactName,
    required String message,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'sendWhatsApp',
        {'contactName': contactName, 'message': message},
      );

      if (result == null) {
        throw const WhatsAppException('No response from native WhatsApp handler.');
      }

      final success = result['success'] as bool? ?? false;
      final status = result['status'] as String? ?? 'UNKNOWN';
      final errorMessage = result['errorMessage'] as String?;
      final resolvedPhone = result['resolvedPhone'] as String?;
      final resolvedName = result['resolvedName'] as String?;

      if (success) {
        return WhatsAppResult(
          success: true,
          resolvedPhone: resolvedPhone,
          resolvedName: resolvedName,
        );
      }

      switch (status) {
        case 'CONTACT_NOT_FOUND':
          throw ContactNotFoundException(contactName);
        case 'CONTACT_HAS_NO_PHONE':
          throw WhatsAppException('Contact "$contactName" has no phone number.');
        case 'WHATSAPP_NOT_INSTALLED':
          throw WhatsAppNotInstalledException();
        case 'PERMISSION_DENIED':
          throw WhatsAppException(
            errorMessage ?? 'Contacts permission is required to find "$contactName".',
          );
        case 'INVALID_REQUEST':
          throw const InvalidIntentException();
        default:
          throw WhatsAppException(errorMessage ?? 'Failed to send WhatsApp message.');
      }
    } on PlatformException catch (e) {
      throw WhatsAppException('Platform error: ${e.message}');
    }
  }
}


