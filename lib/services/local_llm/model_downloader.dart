import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:friday_app/core/errors/app_exceptions.dart';

/// Downloads the local AI model over HTTP into app storage so the assistant
/// can be set up without manually copying a .gguf file to the device.
class ModelDownloader {
  final http.Client _client;
  final String url;

  /// Minimum expected size in bytes for a valid model file (10 MB). Anything
  /// smaller than this is treated as a failure (e.g. an HTML error page).
  static const int minimumValidFileBytes = 10 * 1024 * 1024;

  ModelDownloader({required this.url, http.Client? client})
      : _client = client ?? http.Client();

  /// Streams the model into [destinationPath], reporting 0.0..1.0 progress
  /// through [onProgress] whenever it ticks.
  Future<String> downloadTo({
    required String destinationPath,
    void Function(double progress)? onProgress,
    void Function()? onComplete,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw ModelDownloadException(
        'Download failed (HTTP ${response.statusCode}). Check your connection.',
      );
    }

    final totalBytes = response.contentLength;
    final file = File(destinationPath);

    try {
      await file.create(recursive: true);
      final sink = file.openWrite();
      var received = 0;

      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (totalBytes != null && totalBytes > 0) {
            onProgress?.call((received / totalBytes).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.close();
      }

      final fileSize = await file.length();
      if (fileSize < minimumValidFileBytes) {
        throw const ModelDownloadException(
          'Downloaded file was too small to be a valid model.',
        );
      }

      onComplete?.call();
      return destinationPath;
    } catch (e) {
      // Clean up a partial download so it is not mistaken for a valid model.
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      if (e is AppException) rethrow;
      throw const ModelDownloadException();
    }
  }
}