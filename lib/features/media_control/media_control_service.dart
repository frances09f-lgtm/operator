import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';
import 'package:friday_app/features/assistant/domain/intent_model.dart';

/// Result of a native media-control dispatch.
class MediaControlResult {
  /// True when the native layer dispatched the media command. This does NOT
  /// guarantee a media session is actively playing.
  final bool success;
  final String? errorMessage;

  const MediaControlResult({required this.success, this.errorMessage});
}

abstract class MediaControlService {
  /// Sends [action] to the currently active Android media session.
  ///
  /// Returns a [MediaControlResult]. Throws [MediaControlException] when no
  /// usable response comes back from the native layer.
  Future<MediaControlResult> perform(MediaAction action);
}

class MethodChannelMediaControlService implements MediaControlService {
  final MethodChannel _channel;

  MethodChannelMediaControlService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.mediaControlChannel);

  @override
  Future<MediaControlResult> perform(MediaAction action) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'perform',
        {'action': action.wireName},
      );

      if (result == null) {
        throw const MediaControlException('No response from native media control.');
      }

      return MediaControlResult(
        success: result['success'] as bool? ?? false,
        errorMessage: result['errorMessage'] as String?,
      );
    } on PlatformException catch (e) {
      throw MediaControlException('Platform error: ${e.message}');
    }
  }
}