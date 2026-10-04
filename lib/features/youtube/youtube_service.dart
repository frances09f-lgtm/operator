import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';

/// Result of a native YouTube search dispatch.
class YouTubeResult {
  final bool success;
  final String? errorMessage;

  /// True when the native layer also auto-tapped the Nth result via
  /// the accessibility service. False means search results were opened
  /// and the user taps the video manually.
  final bool autoPlayed;

  /// True when the accessibility service is enabled (required for
  /// auto-play). False means the user must tap manually or enable it.
  final bool accessibilityEnabled;

  const YouTubeResult({
    required this.success,
    this.errorMessage,
    this.autoPlayed = false,
    this.accessibilityEnabled = false,
  });
}

/// Opens YouTube with a search query and plays the Nth result.
///
/// [index] is 1-based: 1 = first result.
abstract class YouTubeService {
  Future<YouTubeResult> searchAndPlay({
    required String query,
    required int index,
  });
}

class MethodChannelYouTubeService implements YouTubeService {
  final MethodChannel _channel;

  MethodChannelYouTubeService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.youTubeChannel);

  @override
  Future<YouTubeResult> searchAndPlay({
    required String query,
    required int index,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty || cleanQuery.length > 200) {
      throw const InvalidIntentException();
    }
    final safeIndex = index.clamp(1, 50);
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'searchAndPlay',
        {'query': cleanQuery, 'index': safeIndex},
      );

      if (result == null) {
        throw const YouTubeException('No response from native YouTube handler.');
      }

      final success = result['success'] as bool? ?? false;
      if (success) {
        return YouTubeResult(
          success: true,
          autoPlayed: result['autoPlayed'] as bool? ?? false,
          accessibilityEnabled:
              result['accessibilityEnabled'] as bool? ?? false,
        );
      }

      final status = result['status'] as String? ?? 'UNKNOWN';
      final errorMessage = result['errorMessage'] as String?;
      switch (status) {
        case 'YOUTUBE_NOT_INSTALLED':
          throw YouTubeNotInstalledException();
        case 'INVALID_REQUEST':
          throw const InvalidIntentException();
        default:
          throw YouTubeException(errorMessage ?? "Couldn't search YouTube.");
      }
    } on PlatformException catch (e) {
      throw YouTubeException('Platform error: ${e.message}');
    } on AppException {
      rethrow;
    }
  }
}
