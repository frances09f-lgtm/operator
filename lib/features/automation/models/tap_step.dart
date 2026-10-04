import 'dart:convert';

/// Types of automation steps that can be executed via AccessibilityService.
enum TapStepType {
  tap,
  swipe,
  inputText,
  wait,
  findByText,
  findByDesc,
  findById,
  openApp,
  collect,
  back,
}

/// A single step in a teachable tap sequence.
class TapStep {
  final TapStepType type;

  /// Normalized coordinates 0.0..1.0 (percentage of screen width/height).
  /// Used for tap/swipe when no selector matches.
  final double? xPct;
  final double? yPct;
  final double? x2Pct;
  final double? y2Pct;

  /// Selector value for find steps (text, desc, viewId).
  final String? selectorValue;

  /// When true, selector is a substring contains match rather than exact.
  final bool contains;

  /// Text to input for inputText steps, may contain {{param}} placeholders.
  final String? inputValue;

  /// Package name for openApp steps.
  final String? targetPackage;

  /// Duration / delay values in milliseconds.
  final int? durationMs;
  final int? delayAfterMs;

  /// For collect steps: how many items to return, or selector for collection.
  final String? collectSelector;
  final int? collectCount;

  const TapStep({
    required this.type,
    this.xPct,
    this.yPct,
    this.x2Pct,
    this.y2Pct,
    this.selectorValue,
    this.contains = false,
    this.inputValue,
    this.targetPackage,
    this.durationMs,
    this.delayAfterMs,
    this.collectSelector,
    this.collectCount,
  });

  /// Substitute {{param}} placeholders using [params].
  TapStep substitute(Map<String, String> params) {
    String sub(String? s) {
      if (s == null) return '';
      var res = s;
      params.forEach((k, v) {
        res = res.replaceAll('{{$k}}', v);
        res = res.replaceAll('{{ $k}}', v);
        res = res.replaceAll('{{$k }}', v);
      });
      return res;
    }

    if (params.isEmpty) return this;
    return TapStep(
      type: type,
      xPct: xPct,
      yPct: yPct,
      x2Pct: x2Pct,
      y2Pct: y2Pct,
      selectorValue: selectorValue != null ? sub(selectorValue) : null,
      contains: contains,
      inputValue: inputValue != null ? sub(inputValue) : null,
      targetPackage: targetPackage,
      durationMs: durationMs,
      delayAfterMs: delayAfterMs,
      collectSelector: collectSelector,
      collectCount: collectCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'xPct': xPct,
        'yPct': yPct,
        'x2Pct': x2Pct,
        'y2Pct': y2Pct,
        'selectorValue': selectorValue,
        'contains': contains,
        'inputValue': inputValue,
        'targetPackage': targetPackage,
        'durationMs': durationMs,
        'delayAfterMs': delayAfterMs,
        'collectSelector': collectSelector,
        'collectCount': collectCount,
      };

  factory TapStep.fromJson(Map<String, dynamic> j) {
    final typeName = j['type'] as String? ?? 'tap';
    final type = TapStepType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => TapStepType.tap,
    );
    return TapStep(
      type: type,
      xPct: (j['xPct'] as num?)?.toDouble(),
      yPct: (j['yPct'] as num?)?.toDouble(),
      x2Pct: (j['x2Pct'] as num?)?.toDouble(),
      y2Pct: (j['y2Pct'] as num?)?.toDouble(),
      selectorValue: j['selectorValue'] as String?,
      contains: j['contains'] as bool? ?? false,
      inputValue: j['inputValue'] as String?,
      targetPackage: j['targetPackage'] as String?,
      durationMs: j['durationMs'] as int?,
      delayAfterMs: j['delayAfterMs'] as int?,
      collectSelector: j['collectSelector'] as String?,
      collectCount: j['collectCount'] as int?,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}
