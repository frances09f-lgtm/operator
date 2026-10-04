/// Dual-model contract: small fast model for commands, big model for chat.
///
/// The command path (`infer`) must stay instant — the big chat model is only
/// loaded on demand via [loadChatModel], then swapped out again.
abstract class LocalLLMService {
  /// Whether any model is loaded and ready for inference
  bool get isReady;

  /// Which slot is currently loaded: 'command', 'chat', or null.
  String? get activeMode;

  /// Whether the currently loaded model is the big chat model.
  bool get isChatModelLoaded => activeMode == 'chat';

  /// Loads the GGUF model from the specified file path (legacy single-model).
  Future<void> loadModel(String modelPath);

  /// Unloads the current model so the other slot can be loaded (frees RAM).
  Future<void> unload();

  /// Loads the small command model (fast path).
  Future<void> loadCommandModel(String modelPath);

  /// Loads the big chat model (slow, on demand only).
  Future<void> loadChatModel(String modelPath);

  /// Generates a completion for the given prompt or user command
  Future<String> infer(String userCommand);

  /// Free-form ChatGPT-like answer using the big model.
  /// [history] holds prior turns as maps {'role': 'user'|'assistant', 'text': ...}.
  Future<String> chat(
    String userMessage, {
    List<Map<String, String>> history = const [],
    void Function(String token)? onToken,
  });

  /// Releases loaded model resources from memory
  Future<void> dispose();
}
