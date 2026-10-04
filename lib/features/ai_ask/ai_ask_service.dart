import 'package:flutter/services.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';
import 'package:friday_app/features/app_launcher/app_launcher_service.dart';
import 'package:friday_app/features/automation/models/tap_step.dart';
import 'package:friday_app/features/automation/services/automation_service.dart'
    as auto_svc;

/// Result of asking an installed AI app (DeepSeek / ChatGPT / Gemini).
class AiAskResult {
  final bool success;
  final String appLabel;
  final String? errorMessage;

  /// True when the automation layer typed + tapped Send via accessibility.
  /// False means the app was opened with the question ready and the user
  /// must tap Send manually (accessibility disabled or Send not found).
  final bool autoSent;

  /// True when accessibility is enabled (required for auto-send).
  final bool accessibilityEnabled;

  const AiAskResult({
    required this.success,
    required this.appLabel,
    this.errorMessage,
    this.autoSent = false,
    this.accessibilityEnabled = false,
  });
}

/// Asks an installed AI app a question: open app, type query, tap Send.
///
/// App-only, no browser fallback. Throws [AiAskNotInstalledException] when
/// the app is missing, [AccessibilityDisabledException] is surfaced as
/// manual-send (caller decides), [InvalidIntentException] on bad input.
abstract class AiAskService {
  Future<AiAskResult> ask({required String target, required String query});
}

class MethodChannelAiAskService implements AiAskService {
  final AppLauncherService _appLauncher;
  final auto_svc.AutomationService _automation;

  MethodChannelAiAskService({
    AppLauncherService? appLauncher,
    auto_svc.AutomationService? automationService,
  })  : _appLauncher = appLauncher ?? MethodChannelAppLauncherService(),
        _automation = automationService ?? auto_svc.MethodChannelAutomationService();

  /// Canonical display labels for the three supported AI apps.
  static String displayLabel(String target) {
    switch (target) {
      case 'chatgpt':
        return 'ChatGPT';
      case 'gemini':
        return 'Gemini';
      case 'deepseek':
      default:
        return 'DeepSeek';
    }
  }

  /// Resolve label used for launcher lookup (fuzzy match handles variants,
  /// but canonical labels are most reliable).
  static String launcherTarget(String target) => displayLabel(target);

  @override
  Future<AiAskResult> ask(
      {required String target, required String query}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty || cleanQuery.length > 500) {
      throw const InvalidIntentException();
    }
    final normalized = target.trim().toLowerCase();
    if (normalized != 'deepseek' &&
        normalized != 'chatgpt' &&
        normalized != 'gemini') {
      throw const InvalidIntentException();
    }
    final label = displayLabel(normalized);
    final lookup = launcherTarget(normalized);

    // 1. Validate installed (app-only, no browser fallback).
    String appLabel;
    try {
      appLabel = await _appLauncher.resolveApp(lookup);
    } on AppNotInstalledException {
      // Try raw target as fallback (e.g. user said "chat gpt").
      try {
        appLabel = await _appLauncher.resolveApp(normalized);
      } catch (_) {
        throw AiAskNotInstalledException(label);
      }
    }

    // 2. Check accessibility upfront for honest reporting.
    bool accessibilityEnabled = false;
    try {
      accessibilityEnabled = await _automation.isAccessibilityEnabled();
    } catch (_) {
      accessibilityEnabled = false;
    }

    // 3. Launch immediately (resolve already validated).
    try {
      await _appLauncher.launchApp(lookup);
    } on AppNotInstalledException {
      throw AiAskNotInstalledException(label);
    } on AppException {
      rethrow;
    } on PlatformException catch (e) {
      throw AiAskException('Platform error: ${e.message}');
    }

    // 4. Type + send in PHASES so one missing hint never aborts typing.
    //
    // Why phased: the old single-batch `findByText('Ask')` worked for
    // ChatGPT/Gemini but DeepSeek's composer hint is different
    // ("Message DeepSeek" / "Talk with DeepSeek" depending on version), so
    // the batch TIMEOUT-ed before inputText ever ran — DeepSeek just opened
    // with nothing typed. Phases guarantee: focus (best-effort) -> type
    // (always attempted) -> send (best-effort, honest manual fallback).
    final initialWaitMs = normalized == 'deepseek' ? 2500 : 1500;

    try {
      await _automation.executeSteps([
        TapStep(type: TapStepType.wait, durationMs: initialWaitMs),
      ]);
    } catch (_) {}

    // Phase A: focus the composer. Try per-app hints one-by-one (each in its
    // own call so a miss doesn't abort the rest), then coordinate fallback
    // at bottom-center where all three composers live.
    await _focusComposer(normalized);

    // Phase B: type the query. Always attempted — inputText acts on the
    // focused node, and the native layer falls back to the first editable
    // node when nothing is focused (see AutomationAccessibilityService).
    try {
      await _automation.executeSteps([
        TapStep(type: TapStepType.inputText, inputValue: cleanQuery),
        const TapStep(type: TapStepType.wait, durationMs: 500),
      ]);
    } on auto_svc.AccessibilityDisabledException {
      return AiAskResult(
        success: true,
        appLabel: appLabel,
        autoSent: false,
        accessibilityEnabled: false,
      );
    } on AppException catch (e) {
      if (e is AppNotInstalledException) {
        throw AiAskNotInstalledException(label);
      }
      // App is open but typing failed — honest manual result.
      return AiAskResult(
        success: true,
        appLabel: appLabel,
        autoSent: false,
        accessibilityEnabled: accessibilityEnabled,
        errorMessage: e.message,
      );
    } on PlatformException catch (e) {
      throw AiAskException('Platform error: ${e.message}');
    }

    // Phase C: tap Send. Try desc/text variants, then bottom-right fallback.
    // Failure here is fine — the text is already typed, user taps Send.
    final sent = await _tapSend();
    try {
      await _automation.executeSteps([
        const TapStep(type: TapStepType.wait, durationMs: 800),
      ]);
    } catch (_) {}
    return AiAskResult(
      success: true,
      appLabel: appLabel,
      autoSent: sent,
      accessibilityEnabled: accessibilityEnabled,
      errorMessage: sent ? null : 'Send button not found — query is typed.',
    );
  }

  /// Best-effort composer focus. Each hint is tried in its own
  /// [executeSteps] call so a miss never aborts the remaining hints.
  /// Falls back to a bottom-center coordinate tap (0.5, 0.92) where all
  /// three AI composers live.
  Future<void> _focusComposer(String target) async {
    final hints = _composerHints(target);
    for (final hint in hints) {
      try {
        await _automation.executeSteps([
          TapStep(
              type: TapStepType.findByText,
              selectorValue: hint,
              contains: true),
        ]);
        return; // focused via hint.
      } catch (_) {
        // Try next hint.
      }
    }
    // Coordinate fallback — always "succeeds" (gesture dispatch), giving
    // inputText a focused node even when hints all miss (DeepSeek case).
    try {
      await _automation.executeSteps([
        const TapStep(type: TapStepType.tap, xPct: 0.5, yPct: 0.92),
        const TapStep(type: TapStepType.wait, durationMs: 400),
      ]);
    } catch (_) {}
  }

  /// Per-app composer hint priority. First hit wins.
  static List<String> _composerHints(String target) {
    switch (target) {
      case 'deepseek':
        return const [
          'Message DeepSeek',
          'Talk with DeepSeek',
          'Ask DeepSeek',
          'Ask anything',
          'Ask me anything',
          'Message',
          'Type a message',
          'Ask',
        ];
      case 'chatgpt':
        return const [
          'Ask anything',
          'Message ChatGPT',
          'Message',
          'Ask',
        ];
      case 'gemini':
        return const [
          'Ask Gemini',
          'Ask anything',
          'Message',
          'Ask',
        ];
      default:
        return const ['Ask', 'Message', 'Type'];
    }
  }

  /// Best-effort Send tap. Returns true when a Send tap was dispatched.
  Future<bool> _tapSend() async {
    const candidates = [
      TapStep(
          type: TapStepType.findByDesc, selectorValue: 'Send', contains: true),
      TapStep(
          type: TapStepType.findByText, selectorValue: 'Send', contains: true),
      TapStep(
          type: TapStepType.findByDesc, selectorValue: 'Submit', contains: true),
      TapStep(type: TapStepType.findByText, selectorValue: '>', contains: false),
    ];
    for (final step in candidates) {
      try {
        await _automation.executeSteps([step]);
        return true;
      } catch (_) {
        // Try next selector.
      }
    }
    // Bottom-right fallback where Send arrows live in all three apps.
    try {
      await _automation.executeSteps([
        const TapStep(type: TapStepType.tap, xPct: 0.9, yPct: 0.92),
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }
}
