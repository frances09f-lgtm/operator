import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:friday_app/core/constants/app_constants.dart';

class ModelManager {
  final String modelFileName;

  ModelManager({this.modelFileName = AppConstants.defaultModelFileName});

  /// Finds the small fast command model (135M).
  Future<String?> findCommandModelPath() => findModelPath(
        fileNames: [
          modelFileName,
          modelFileName.toLowerCase(),
          'smollm2-135m-instruct-q4_k_m.gguf',
          'SmolLM2-135M-Instruct-Q4_K_M.gguf',
        ],
      );

  /// Finds the large smart chat model (Qwen 1.5B/3B), or null if not downloaded.
  Future<String?> findChatModelPath() => findModelPath(
        fileNames: [
          AppConstants.chatModelFileName,
          AppConstants.chatModelFileName.toLowerCase(),
          'qwen2.5-1.5b-instruct-q4_k_m.gguf',
          'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
          'qwen3-instruct-q4_k_m.gguf',
          'Qwen3-Instruct-Q4_K_M.gguf',
          'qwen3.gguf',
          'Qwen3.gguf',
          'qwen2.5-3b-instruct-q4_k_m.gguf',
          'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
          'smollm2-1.7b-instruct-q4_k_m.gguf',
          'SmolLM2-1.7B-Instruct-Q4_K_M.gguf',
        ],
      );

  /// Primary location where the smart chat model should be downloaded.
  Future<String> getPrimaryChatModelPath() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDocDir.path}/models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return '${modelDir.path}/${AppConstants.chatModelFileName}';
  }

  /// Finds the first existing model file in standard device storage directories.
  /// When [fileNames] is given, only those files match (used to tell the
  /// small command model apart from the big chat model).
  Future<String?> findModelPath({List<String>? fileNames}) async {
    // 1. Check explicit candidate paths
    final candidatePaths = await getCandidateModelPaths(fileNames: fileNames);
    for (final path in candidatePaths) {
      final file = File(path);
      if (await file.exists() && await file.length() > 10 * 1024 * 1024) {
        return path;
      }
    }

    // 2. Scan model directories for any valid .gguf file
    final searchDirectories = <String>[];
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      searchDirectories.add('${appDocDir.path}/models');
      searchDirectories.add(appDocDir.path);
    } catch (_) {}

    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        searchDirectories.add('${externalDir.path}/models');
        searchDirectories.add(externalDir.path);
      }
    } catch (_) {}

    searchDirectories.add('/sdcard/Android/data/com.operator.app.operator_app/files/models');
    searchDirectories.add('/sdcard/Android/data/com.operator.app.operator_app/files');
    searchDirectories.add('/sdcard/Download/models');
    searchDirectories.add('/sdcard/Download');
    searchDirectories.add('/data/local/tmp');

    for (final dirPath in searchDirectories) {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        try {
          final entities = await dir.list().toList();
          for (final entity in entities) {
            if (entity is File && entity.path.toLowerCase().endsWith('.gguf')) {
              if (fileNames != null && fileNames.isNotEmpty) {
                final base = entity.path.split('/').last.toLowerCase();
                if (!fileNames.map((e) => e.toLowerCase()).contains(base)) {
                  continue;
                }
              }
              final length = await entity.length();
              if (length > 10 * 1024 * 1024) {
                return entity.path;
              }
            }
          }
        } catch (_) {}
      }
    }

    return null;
  }

  /// Returns the primary location where models should be placed.
  Future<String> getPrimaryModelPath() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDocDir.path}/models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return '${modelDir.path}/$modelFileName';
  }

  /// List of candidate paths to look for the model.
  Future<List<String>> getCandidateModelPaths({List<String>? fileNames}) async {
    final paths = <String>[];
    final names = fileNames ??
        [
          modelFileName,
          modelFileName.toLowerCase(),
          'smollm2-135m-instruct-q4_k_m.gguf',
          'SmolLM2-135M-Instruct-Q4_K_M.gguf',
          'model.gguf',
        ];

    final dirPaths = <String>[];
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      dirPaths.add('${appDocDir.path}/models');
      dirPaths.add(appDocDir.path);
    } catch (_) {}

    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        dirPaths.add('${externalDir.path}/models');
        dirPaths.add(externalDir.path);
      }
    } catch (_) {}

    dirPaths.add('/sdcard/Android/data/com.operator.app.operator_app/files/models');
    dirPaths.add('/sdcard/Android/data/com.operator.app.operator_app/files');
    dirPaths.add('/sdcard/Download/models');
    dirPaths.add('/sdcard/Download');
    dirPaths.add('/data/local/tmp');

    for (final dir in dirPaths) {
      for (final name in names) {
        paths.add('$dir/$name');
      }
    }

    return paths;
  }
}
