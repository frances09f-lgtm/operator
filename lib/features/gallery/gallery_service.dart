import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';

/// Result of a native gallery-video dispatch.
class GalleryResult {
  final bool success;
  final String? videoName;
  final String? errorMessage;

  const GalleryResult({required this.success, this.videoName, this.errorMessage});
}

/// Opens the gallery and plays the Nth video via MediaStore.
///
/// [index] is 1-based: 1 = most recent video.
abstract class GalleryService {
  Future<GalleryResult> playVideoAt({required int index});
}

class MethodChannelGalleryService implements GalleryService {
  final MethodChannel _channel;

  MethodChannelGalleryService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.galleryChannel);

  @override
  Future<GalleryResult> playVideoAt({required int index}) async {
    final safeIndex = index.clamp(1, 50);
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'playVideoAt',
        {'index': safeIndex},
      );

      if (result == null) {
        throw const GalleryException('No response from native gallery handler.');
      }

      final success = result['success'] as bool? ?? false;
      if (success) {
        return GalleryResult(
          success: true,
          videoName: result['videoName'] as String?,
        );
      }

      final status = result['status'] as String? ?? 'UNKNOWN';
      final errorMessage = result['errorMessage'] as String?;
      switch (status) {
        case 'VIDEO_NOT_FOUND':
          throw GalleryVideoNotFoundException(safeIndex);
        case 'PERMISSION_DENIED':
          throw GalleryException(
            errorMessage ?? 'Gallery permission is required to play videos.',
          );
        case 'INVALID_REQUEST':
          throw const InvalidIntentException();
        default:
          throw GalleryException(errorMessage ?? "Couldn't open gallery videos.");
      }
    } on PlatformException catch (e) {
      throw GalleryException('Platform error: ${e.message}');
    } on AppException {
      rethrow;
    }
  }
}
