import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';

/// Result of a native volume-control dispatch.
class VolumeControlResult {
  /// True when the native layer adjusted the volume.
  final bool success;

  /// Resulting media volume as a percentage (0-100).
  final int level;

  final String? errorMessage;

  const VolumeControlResult({
    required this.success,
    required this.level,
    this.errorMessage,
  });
}

/// Adjusts the device media volume through the Android native layer.
abstract class VolumeControlService {
  /// Sets the media volume to an absolute [level] (0-100).
  Future<VolumeControlResult> setVolume(int level);

  /// Raises the media volume by one step.
  Future<VolumeControlResult> volumeUp();

  /// Lowers the media volume by one step.
  Future<VolumeControlResult> volumeDown();

  /// Mutes the media volume.
  Future<VolumeControlResult> mute();

  /// Restores the last non-zero media volume level.
  Future<VolumeControlResult> unmute();

  /// Reports the current media volume without changing anything.
  Future<VolumeControlResult> query();
}

class MethodChannelVolumeControlService implements VolumeControlService {
  final MethodChannel _channel;

  MethodChannelVolumeControlService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.volumeControlChannel);

  @override
  Future<VolumeControlResult> setVolume(int level) =>
      _adjust('set', level: level.clamp(0, 100));

  @override
  Future<VolumeControlResult> volumeUp() => _adjust('up');

  @override
  Future<VolumeControlResult> volumeDown() => _adjust('down');

  @override
  Future<VolumeControlResult> mute() => _adjust('mute');

  @override
  Future<VolumeControlResult> unmute() => _adjust('unmute');

  @override
  Future<VolumeControlResult> query() => _adjust('query');

  Future<VolumeControlResult> _adjust(String command, {int? level}) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'adjust',
        {
          'command': command,
          'level': ?level,
        },
      );

      if (result == null) {
        throw const VolumeControlException('No response from native volume control.');
      }

      return VolumeControlResult(
        success: result['success'] as bool? ?? false,
        level: (result['level'] as num?)?.round() ?? 0,
        errorMessage: result['errorMessage'] as String?,
      );
    } on PlatformException catch (e) {
      throw VolumeControlException('Platform error: ${e.message}');
    }
  }
}