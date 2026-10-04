import 'dart:convert';
import 'tap_step.dart';

/// A user-teachable command that maps a voice phrase to a tap sequence.
///
/// Example phraseTemplate: "check location of {{contact}} on snapchat"
/// Params are extracted as {{contact}} -> "john"
class CustomCommand {
  final String id;
  final String phraseTemplate;
  final String displayName;
  final String? targetPackage;
  final List<TapStep> steps;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? description;

  const CustomCommand({
    required this.id,
    required this.phraseTemplate,
    required this.displayName,
    this.targetPackage,
    required this.steps,
    required this.createdAt,
    required this.updatedAt,
    this.description,
  });

  /// Parameter names extracted from {{param}} in phraseTemplate.
  List<String> get paramNames {
    final reg = RegExp(r'\{\{\s*(\w+)\s*\}\}');
    return reg
        .allMatches(phraseTemplate)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
  }

  /// Normalized template for matching: lowercased, placeholders replaced with \S+ wildcard,
  /// punctuation stripped.
  String get normalizedTemplate {
    var s = phraseTemplate.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'\{\{\s*\w+\s*\}\}'), '__PARAM__');
    s = s.replaceAll(RegExp(r'[^\w\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Try to match [input] against this command's template.
  /// Returns extracted params map if matches, null otherwise.
  Map<String, String>? match(String input) {
    final lowerInput = input.toLowerCase().trim();
    // Build regex from template: escape, replace {{param}} with capture group (.+?)
    final paramReg = RegExp(r'\{\{\s*(\w+)\s*\}\}');
    final params = <String>[];
    var regexStr = '';
    var lastEnd = 0;
    final templateLower = phraseTemplate.toLowerCase();
    for (final m in paramReg.allMatches(templateLower)) {
      final before = templateLower.substring(lastEnd, m.start);
      regexStr += RegExp.escape(before);
      final paramName = m.group(1)!.toLowerCase();
      params.add(paramName);
      regexStr += r'(.+?)';
      lastEnd = m.end;
    }
    regexStr += RegExp.escape(templateLower.substring(lastEnd));
    // Allow flexible whitespace
    regexStr = regexStr.replaceAll(r'\ ', r'\s+');
    // Anchor
    regexStr = '^\\s*' + regexStr + r'\s*$';
    final regex = RegExp(regexStr, caseSensitive: false);
    final match = regex.firstMatch(lowerInput);
    if (match == null) return null;
    final result = <String, String>{};
    for (var i = 0; i < params.length; i++) {
      var value = match.group(i + 1) ?? '';
      value = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (value.isEmpty) return null;
      if (value.length > 100) value = value.substring(0, 100);
      result[params[i]] = value;
    }
    return result;
  }

  /// Substitute params into steps, returning new list.
  List<TapStep> substitutedSteps(Map<String, String> params) {
    if (params.isEmpty) return steps;
    // Normalize param keys lower
    final lowerParams = {for (final e in params.entries) e.key.toLowerCase(): e.value};
    return steps.map((s) => s.substitute(lowerParams)).toList();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phraseTemplate': phraseTemplate,
        'displayName': displayName,
        'targetPackage': targetPackage,
        'steps': steps.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'description': description,
      };

  factory CustomCommand.fromJson(Map<String, dynamic> j) {
    return CustomCommand(
      id: j['id'] as String,
      phraseTemplate: j['phraseTemplate'] as String,
      displayName: j['displayName'] as String? ?? (j['phraseTemplate'] as String),
      targetPackage: j['targetPackage'] as String?,
      steps: ((j['steps'] as List?) ?? [])
          .map((e) => TapStep.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      description: j['description'] as String?,
    );
  }

  CustomCommand copyWith({
    String? phraseTemplate,
    String? displayName,
    String? targetPackage,
    List<TapStep>? steps,
    String? description,
  }) {
    return CustomCommand(
      id: id,
      phraseTemplate: phraseTemplate ?? this.phraseTemplate,
      displayName: displayName ?? this.displayName,
      targetPackage: targetPackage ?? this.targetPackage,
      steps: steps ?? this.steps,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      description: description ?? this.description,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}
