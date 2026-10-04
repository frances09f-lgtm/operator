import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/custom_command.dart';

/// Persists user-teachable commands to file storage.
///
/// Reuses path_provider pattern from ModelManager.
class TapSequenceStorage {
  static const String _fileName = 'tap_sequences.json';

  Future<File> _getFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final automationDir = Directory('${dir.path}/automation');
      if (!await automationDir.exists()) {
        await automationDir.create(recursive: true);
      }
      return File('${automationDir.path}/$_fileName');
    } catch (_) {
      // Fallback to temp
      final tmp = Directory.systemTemp;
      return File('${tmp.path}/friday_$_fileName');
    }
  }

  Future<List<CustomCommand>> loadAll() async {
    final file = await _getFile();
    if (!await file.exists()) return [];
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final decoded = jsonDecode(content);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((j) => CustomCommand.fromJson(j))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<CustomCommand> commands) async {
    final file = await _getFile();
    final jsonList = commands.map((c) => c.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  Future<void> save(CustomCommand command) async {
    final all = await loadAll();
    final idx = all.indexWhere((c) => c.id == command.id);
    if (idx >= 0) {
      all[idx] = command;
    } else {
      all.add(command);
    }
    await saveAll(all);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((c) => c.id == id);
    await saveAll(all);
  }

  Future<CustomCommand?> getById(String id) async {
    final all = await loadAll();
    try {
      return all.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Heuristic match: score-based like AppLauncher, returns best match with params.
  Future<CustomCommandMatch?> findBestMatch(String input) async {
    final all = await loadAll();
    if (all.isEmpty) return null;
    final lowerInput = input.toLowerCase().trim();
    if (lowerInput.isEmpty) return null;

    CustomCommand? best;
    Map<String, String>? bestParams;
    int bestScore = -1;

    for (final cmd in all) {
      final params = cmd.match(lowerInput);
      if (params != null) {
        // Exact template match with param extraction = highest score 100
        // Score bonus for fewer params? Prefer more specific templates
        final score = 100 + cmd.phraseTemplate.length;
        if (score > bestScore) {
          bestScore = score;
          best = cmd;
          bestParams = params;
        }
        continue;
      }

      // Fuzzy fallback: normalized contains / levenshtein
      final normalizedInput = lowerInput.replaceAll(RegExp(r'[^\w\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      final normalizedTemplate = cmd.normalizedTemplate;

      int score = 0;
      if (normalizedInput == normalizedTemplate) {
        score = 90;
      } else if (normalizedInput.contains(normalizedTemplate) || normalizedTemplate.contains(normalizedInput)) {
        score = 70;
      } else {
        // Word overlap
        final inputWords = normalizedInput.split(' ').where((w) => w.length > 2).toSet();
        final templateWords = normalizedTemplate.split(' ').where((w) => w != '__param__' && w.length > 2).toSet();
        if (inputWords.isNotEmpty && templateWords.isNotEmpty) {
          final overlap = inputWords.intersection(templateWords).length;
          final ratio = overlap / templateWords.length;
          if (ratio >= 0.6) score = (60 + ratio * 20).round();
          // Also levenshtein fallback for small phrases
          if (score == 0) {
            final dist = _levenshtein(normalizedInput, normalizedTemplate);
            final maxLen = normalizedInput.length > normalizedTemplate.length ? normalizedInput.length : normalizedTemplate.length;
            if (maxLen > 0 && dist <= 3 && maxLen <= 30) {
              if (dist == 1) score = 62;
              else if (dist == 2) score = 60;
              else if (dist == 3 && maxLen >= 10) score = 58;
            }
          }
        }
      }

      // For fuzzy, attempt simple param extraction: take remaining words as param
      if (score >= 60) {
        // If cmd has params but exact match failed, try to extract by removing template keywords
        if (cmd.paramNames.isNotEmpty && params == null) {
          // Heuristic: remove template keywords from input, remainder is param value
          var remainder = normalizedInput;
          for (final word in normalizedTemplate.split(' ')) {
            if (word == '__param__') continue;
            remainder = remainder.replaceAll(word, ' ');
          }
          remainder = remainder.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (remainder.isNotEmpty && remainder.length <= 100) {
            final heuristicParams = {for (final p in cmd.paramNames) p: remainder};
            if (score > bestScore) {
              bestScore = score;
              best = cmd;
              bestParams = heuristicParams;
            }
            continue;
          }
        }
        if (score > bestScore) {
          bestScore = score;
          best = cmd;
          bestParams = {};
        }
      }
    }

    if (best == null || bestScore < 58) return null;
    return CustomCommandMatch(command: best, params: bestParams ?? {}, score: bestScore);
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
      for (var j = 0; j <= b.length; j++) prev[j] = curr[j];
    }
    return prev[b.length];
  }
}

class CustomCommandMatch {
  final CustomCommand command;
  final Map<String, String> params;
  final int score;

  const CustomCommandMatch({required this.command, required this.params, required this.score});
}
