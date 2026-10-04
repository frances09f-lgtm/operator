import 'package:friday_app/features/eyes/eyes_service.dart';
import 'package:friday_app/features/hands/hands_service.dart';
import 'package:friday_app/services/local_llm/friday_brain.dart';

/// Minimal Friday agent loop: Eyes -> Brain -> Hands.
///
/// Manual-trigger only: the caller (test-screen Run button) starts it, and
/// every mutating step requires Hands to be armed — mid-run Disarm stops
/// the loop. Banking/payment refusals stop it too. Bounded by [maxSteps].
/// The Brain replies with exactly one line: `TAP <n>`, `TYPE <n> <text>`,
/// or `DONE`. Anything else stops the loop with `PARSE_FAILED` and the raw
/// reply is surfaced verbatim — never fabricated.

// Narrow interfaces so the loop is unit-testable with fakes.
abstract class AgentEyes {
  Future<String> getSummary({int maxNodes});
}

abstract class AgentHands {
  Future<bool> isArmed();
  Future<Map<String, dynamic>> tap(double xPct, double yPct);
  Future<Map<String, dynamic>> enterText(String text);
}

abstract class AgentModel {
  Future<String> generateRaw({
    required String system,
    required String user,
    int maxTokens,
  });
}

/// One tappable line parsed from an Eyes summary.
class AgentCandidate {
  final int index;
  final String label;
  final bool canTap;
  final bool canEdit;
  final double fx;
  final double fy;

  const AgentCandidate({
    required this.index,
    required this.label,
    required this.canTap,
    required this.canEdit,
    required this.fx,
    required this.fy,
  });
}

class AgentResult {
  final bool done;
  final String status;
  final String message;
  final int stepsTaken;

  const AgentResult({
    required this.done,
    required this.status,
    required this.message,
    required this.stepsTaken,
  });
}

/// Parsed decision from the Brain reply: `TAP <n>`, `TYPE <n> <text>`, or `DONE`.
class AgentDecision {
  final String verb;
  final int? index;
  final String? text;

  const AgentDecision({required this.verb, this.index, this.text});
}

class FridayAgent {
  static const String systemPrompt =
      'You are a phone automation agent. Reply with ONLY one action line:\n'
      'TAP <n>\n'
      'TYPE <n> <text>\n'
      'DONE\n\n'
      'Examples:\n'
      'Goal: search for cats\n'
      'Screen:\n'
      '[1] "Search" tap\n'
      '[2] "Home" tap\n'
      'Decision: TAP 1\n\n'
      'Goal: type hello in search box\n'
      'Screen:\n'
      '[1] "Search bar" edit\n'
      'Decision: TYPE 1 hello\n\n'
      'Goal: done\n'
      'Decision: DONE\n\n'
      'Rules: Output ONLY the decision line (e.g. "TAP 1" or "DONE"). Do not explain, apologize, or say anything else.';

  final AgentEyes eyes;
  final AgentHands hands;
  final AgentModel model;

  FridayAgent({
    required this.eyes,
    required this.hands,
    required this.model,
  });

  /// Parses `-[Cls] "label" [tags] @[fx,fy]` lines; only lines carrying
  /// tap fractions become candidates, numbered 1..n in order.
  static List<AgentCandidate> parseCandidates(String summary) {
    final out = <AgentCandidate>[];
    final fracExp = RegExp(r'@\[([\d.]+),([\d.]+)\]');
    final labelExp = RegExp(r'"([^"]*)"');
    for (final line in summary.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('- ')) continue;
      final frac = fracExp.firstMatch(trimmed);
      if (frac == null) continue;
      final fx = double.tryParse(frac.group(1) ?? '');
      final fy = double.tryParse(frac.group(2) ?? '');
      if (fx == null || fy == null) continue;
      final label = labelExp.firstMatch(trimmed)?.group(1) ?? '';
      final lower = trimmed.toLowerCase();
      out.add(AgentCandidate(
        index: out.length + 1,
        label: label,
        canTap: lower.contains('tap'),
        canEdit: lower.contains('edit'),
        fx: fx,
        fy: fy,
      ));
    }
    return out;
  }

  static String buildPrompt(String goal, List<AgentCandidate> items) {
    final buf = StringBuffer()..writeln('Goal: $goal')..writeln('Screen buttons:');
    for (final c in items) {
      final tags = [
        if (c.canTap) 'tap',
        if (c.canEdit) 'edit',
      ].join(',');
      buf.writeln('[${c.index}] "${c.label}" $tags');
    }
    buf.writeln('\nWhich action? Reply with only: TAP <id>, TYPE <id> <text>, or DONE.');
    return buf.toString();
  }

  /// Extracts the decision from the LLM reply.
  /// Handles clean action lines, `Decision: <action>`, and trailing actions.
  /// Never matches "tap" without a digit to prevent false positives from the goal.
  static AgentDecision? parseDecision(String raw) {
    // 1. Look for explicit "Decision: <action>" anywhere in output (highest priority)
    final decisionMatch = RegExp(
      r'decision:\s*(?:(TAP)\s+(\d+)|(TYPE)\s+(\d+)\s+([^\n]+)|(DONE)\b)',
      caseSensitive: false,
    ).firstMatch(raw);

    if (decisionMatch != null) {
      if (decisionMatch.group(1) != null) {
        return AgentDecision(
          verb: 'TAP',
          index: int.tryParse(decisionMatch.group(2) ?? ''),
        );
      }
      if (decisionMatch.group(3) != null) {
        return AgentDecision(
          verb: 'TYPE',
          index: int.tryParse(decisionMatch.group(4) ?? ''),
          text: (decisionMatch.group(5) ?? '').trim(),
        );
      }
      if (decisionMatch.group(6) != null) {
        return const AgentDecision(verb: 'DONE');
      }
    }

    // 2. Check each line for a clean action
    for (final line in raw.split('\n')) {
      var t = line.trim();
      if (t.toLowerCase().startsWith('decision:')) {
        t = t.substring(9).trim();
      }
      if (t.isEmpty) continue;

      final tap = RegExp(r'^TAP\s+(\d+)\b', caseSensitive: false).firstMatch(t);
      if (tap != null) {
        return AgentDecision(verb: 'TAP', index: int.tryParse(tap.group(1)!));
      }

      final type = RegExp(r'^TYPE\s+(\d+)\s+(.+)$', caseSensitive: false).firstMatch(t);
      if (type != null) {
        return AgentDecision(
          verb: 'TYPE',
          index: int.tryParse(type.group(1)!),
          text: (type.group(2) ?? '').trim(),
        );
      }

      if (RegExp(r'^DONE\b', caseSensitive: false).hasMatch(t)) {
        return const AgentDecision(verb: 'DONE');
      }
    }

    // 3. Fallback: search anywhere in text for TAP <digit> or TYPE <digit> <text> or DONE
    // Note: TAP MUST have a digit, so "Goal: tap Get summary" will never match!
    final tapAny = RegExp(r'\bTAP\s+(\d+)\b', caseSensitive: false).firstMatch(raw);
    if (tapAny != null) {
      return AgentDecision(verb: 'TAP', index: int.tryParse(tapAny.group(1)!));
    }

    final typeAny = RegExp(r'\bTYPE\s+(\d+)\s+([^\n]+)', caseSensitive: false).firstMatch(raw);
    if (typeAny != null) {
      return AgentDecision(
        verb: 'TYPE',
        index: int.tryParse(typeAny.group(1)!),
        text: (typeAny.group(2) ?? '').trim(),
      );
    }

    if (RegExp(r'\bDONE\b', caseSensitive: false).hasMatch(raw)) {
      return const AgentDecision(verb: 'DONE');
    }

    return null;
  }

  Future<AgentResult> runGoal(
    String goal, {
    int maxSteps = 5,
    void Function(String line)? onLog,
  }) async {
    void log(String s) {
      try {
        onLog?.call(s);
      } catch (_) {}
    }

    if (goal.trim().isEmpty) {
      return const AgentResult(
          done: false,
          status: 'INVALID_REQUEST',
          message: 'Goal is blank.',
          stepsTaken: 0);
    }
    final safeMax = maxSteps.clamp(1, 10);

    for (var step = 1; step <= safeMax; step++) {
      if (!await hands.isArmed()) {
        return AgentResult(
            done: false,
            status: 'DISARMED',
            message: 'Stopped: Hands is not armed. Tap Arm first.',
            stepsTaken: step - 1);
      }

      final summary = await eyes.getSummary(maxNodes: 15);
      final items = parseCandidates(summary);
      if (items.isEmpty) {
        final first = summary.split('\n').first.trim();
        return AgentResult(
            done: false,
            status: 'NO_CANDIDATES',
            message:
                'Stopped: no tappable items. ${first.isEmpty ? summary.trim() : first}',
            stepsTaken: step - 1);
      }

      String raw;
      try {
        raw = await model.generateRaw(
          system: systemPrompt,
          user: buildPrompt(goal, items),
          maxTokens: 64,
        );
      } catch (e) {
        return AgentResult(
            done: false,
            status: 'MODEL_MISSING',
            message: 'Stopped: brain failed: $e',
            stepsTaken: step - 1);
      }

      final decision = parseDecision(raw);
      if (decision == null) {
        return AgentResult(
            done: false,
            status: 'PARSE_FAILED',
            message: 'Stopped: unparseable brain reply: ${raw.trim()}',
            stepsTaken: step - 1);
      }
      final verb = decision.verb;
      final n = decision.index;
      final rest = decision.text ?? '';

      if (verb == 'DONE') {
        log('Step $step: DONE');
        return AgentResult(
            done: true,
            status: 'SUCCESS',
            message: 'Goal complete after ${step - 1} action(s).',
            stepsTaken: step - 1);
      }

      if (n == null || n < 1 || n > items.length) {
        return AgentResult(
            done: false,
            status: 'PARSE_FAILED',
            message: 'Stopped: item out of range in: ${raw.trim()}',
            stepsTaken: step - 1);
      }
      final target = items[n - 1];

      if (verb == 'TAP') {
        log('Step $step: TAP ${target.index} "${target.label}"');
        final res = await hands.tap(target.fx, target.fy);
        if (res['success'] != true) {
          return AgentResult(
              done: false,
              status: '${res['status'] ?? 'ERROR'}',
              message:
                  'Stopped: tap failed (${res['status']}) ${res['errorMessage'] ?? ''}'
                      .trim(),
              stepsTaken: step);
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
      } else {
        // TYPE — native set-text targets the focused/first editable field;
        // the index only selects which screen item the brain meant.
        if (rest.isEmpty) {
          return AgentResult(
              done: false,
              status: 'PARSE_FAILED',
              message: 'Stopped: TYPE with empty text: ${raw.trim()}',
              stepsTaken: step - 1);
        }
        log('Step $step: TYPE ${target.index} "$rest"');
        final res = await hands.enterText(rest);
        if (res['success'] != true) {
          return AgentResult(
              done: false,
              status: '${res['status'] ?? 'ERROR'}',
              message:
                  'Stopped: set-text failed (${res['status']}) ${res['errorMessage'] ?? ''}'
                      .trim(),
              stepsTaken: step);
        }
      }
    }

    return AgentResult(
        done: false,
        status: 'MAX_STEPS',
        message: 'Stopped: reached $safeMax steps without DONE.',
        stepsTaken: safeMax);
  }
}

// Adapters wiring the real skeleton services to the loop interfaces.
class EyesAdapter implements AgentEyes {
  final EyesService _eyes;
  EyesAdapter(this._eyes);

  @override
  Future<String> getSummary({int maxNodes = 15}) =>
      _eyes.getSummary(maxNodes: maxNodes);
}

class HandsAdapter implements AgentHands {
  final HandsService _hands;
  HandsAdapter(this._hands);

  @override
  Future<bool> isArmed() => _hands.isArmed();

  @override
  Future<Map<String, dynamic>> tap(double xPct, double yPct) =>
      _hands.tap(xPct, yPct);

  @override
  Future<Map<String, dynamic>> enterText(String text) =>
      _hands.enterText(text);
}

class BrainAdapter implements AgentModel {
  final FridayBrain _brain;
  BrainAdapter(this._brain);

  @override
  Future<String> generateRaw({
    required String system,
    required String user,
    int maxTokens = 32,
  }) =>
      _brain.generateRaw(system: system, user: user, maxTokens: maxTokens);
}
