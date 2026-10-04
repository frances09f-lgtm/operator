import 'package:friday_app/services/local_llm/llama_local_llm_service.dart';
import 'package:friday_app/services/local_llm/model_manager.dart';

/// Friday Brain skeleton (Part 2): local GGUF inference only.
///
/// Binding: `llama_flutter_android ^0.2.6` (llama.cpp, Android-only).
/// Expected manual-test model: `SmolLM2-135M-Instruct-Q4_K_M.gguf` (~100MB).
/// No DeepSeek/OpenRouter/PrivateLM/Telegram, no API keys, no network
/// fallback, no fake replies. Missing model/load failure is reported
/// plainly as `MODEL_MISSING:` / `LOAD_FAILED:`.
///
/// Note: the underlying engine is single-slot. This manual-test instance
/// shares the device engine with the main assistant; loading here may swap
/// the main assistant's loaded model (it reloads on next command).
class FridayBrain {
  final ModelManager _models;
  final LlamaLocalLLMService _llm;

  FridayBrain({ModelManager? models, LlamaLocalLLMService? llm})
      : _models = models ?? ModelManager(),
        _llm = llm ?? LlamaLocalLLMService();

  /// Absolute path of the 135M command model, or null when not on device.
  Future<String?> findCommandModel() => _models.findCommandModelPath();

  /// Primary destination path for the 135M model file.
  Future<String> getPrimaryModelPath() => _models.getPrimaryModelPath();

  bool get isReady => _llm.isReady;

  String? get mode => _llm.activeMode;

  Future<void> loadCommandModel(String path) =>
      _llm.loadCommandModel(path);

  Future<String> infer(String prompt) => _llm.infer(prompt);

  /// Raw generation for the agent loop (caller-supplied system prompt).
  Future<String> generateRaw({
    required String system,
    required String user,
    int maxTokens = 32,
  }) =>
      _llm.generateRaw(system: system, user: user, maxTokens: maxTokens);
}
