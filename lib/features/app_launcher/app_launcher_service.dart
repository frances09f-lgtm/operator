import 'package:flutter/services.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';

abstract class AppLauncherService {
  /// Launches the installed app matching [target].
  ///
  /// Returns the launched app's display label on success.
  /// Throws [AppNotInstalledException] if app is not found on device.
  /// Throws [AppLaunchException] if app cannot be launched.
  Future<String> launchApp(String target);

  /// Resolves [target] to an installed, launchable app and returns its display
  /// label WITHOUT launching it.
  ///
  /// Runs the exact same native validation/resolution as [launchApp] so the
  /// assistant can confirm the app exists (and learn its real label) before
  /// speaking a response. Throws the same exceptions as [launchApp] when the
  /// app is missing or cannot be launched.
  Future<String> resolveApp(String target);
}

class MethodChannelAppLauncherService implements AppLauncherService {
  final MethodChannel _channel;

  MethodChannelAppLauncherService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.appLauncherChannel);

  @override
  Future<String> launchApp(String target) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'launchApp',
        {'target': target},
      );

      if (result == null) {
        throw const AppLaunchException('No response from native app launcher.');
      }

      final success = result['success'] as bool? ?? false;
      final status = result['status'] as String? ?? 'UNKNOWN';
      final appLabel = result['appLabel'] as String? ?? target;
      final errorMessage = result['errorMessage'] as String?;

      if (success) {
        return appLabel;
      }

      switch (status) {
        case 'APP_NOT_FOUND':
          throw AppNotInstalledException(target);
        case 'NOT_LAUNCHABLE':
          throw AppLaunchException('$appLabel cannot be launched directly.');
        case 'INVALID_REQUEST':
          throw const InvalidIntentException();
        default:
          throw AppLaunchException(errorMessage ?? 'Failed to launch $target.');
      }
    } on PlatformException catch (e) {
      throw AppLaunchException('Platform error: ${e.message}');
    }
  }

  @override
  Future<String> resolveApp(String target) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'resolveApp',
        {'target': target},
      );

      if (result == null) {
        throw const AppLaunchException('No response from native app launcher.');
      }

      final success = result['success'] as bool? ?? false;
      final status = result['status'] as String? ?? 'UNKNOWN';
      final appLabel = result['appLabel'] as String? ?? target;
      final errorMessage = result['errorMessage'] as String?;

      if (success) {
        return appLabel;
      }

      switch (status) {
        case 'APP_NOT_FOUND':
          throw AppNotInstalledException(target);
        case 'NOT_LAUNCHABLE':
          throw AppLaunchException('$appLabel cannot be launched directly.');
        case 'INVALID_REQUEST':
          throw const InvalidIntentException();
        default:
          throw AppLaunchException(errorMessage ?? 'Failed to resolve $target.');
      }
    } on PlatformException catch (e) {
      throw AppLaunchException('Platform error: ${e.message}');
    }
  }
}
