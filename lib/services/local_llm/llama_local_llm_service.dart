import 'dart:async';
import 'dart:io';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';
import 'package:friday_app/features/assistant/domain/intent_parser.dart';
import 'package:friday_app/services/local_llm/local_llm_service.dart';

class LlamaLocalLLMService implements LocalLLMService {
  final LlamaController _controller;
  bool _isReady = false;
  String? _activeMode;
  String? _loadedPath;

  LlamaLocalLLMService({LlamaController? controller})
      : _controller = controller ?? LlamaController();

  @override
  bool get isReady => _isReady;

  @override
  String? get activeMode => _activeMode;

  @override
  bool get isChatModelLoaded => _activeMode == 'chat';

  @override
  Future<void> loadModel(String modelPath) =>
      loadCommandModel(modelPath);

  @override
  Future<void> unload() async {
    _isReady = false;
    _activeMode = null;
    _loadedPath = null;
    try {
      await _controller.dispose();
    } catch (_) {}
  }

  @override
  Future<void> loadCommandModel(String modelPath) async {
    if (_isReady && _activeMode == 'command' && _loadedPath == modelPath) {
      return;
    }
    // Free RAM from the big model before loading the small one.
    if (_activeMode == 'chat') {
      await unload();
    }
    await _loadIntoEngine(
      modelPath: modelPath,
      contextSize: AppConstants.inferenceContextSize,
      mode: 'command',
      warmupSystem: AppConstants.systemPrompt,
    );
  }

  @override
  Future<void> loadChatModel(String modelPath) async {
    if (_isReady && _activeMode == 'chat' && _loadedPath == modelPath) {
      return;
    }
    // Unload small model first to avoid OOM (single-slot engine).
    if (_activeMode == 'command') {
      await unload();
    }
    await _loadIntoEngine(
      modelPath: modelPath,
      // Big model gets a larger context for conversation history.
      // ignore: avoid_redundant_argument_values
      contextSize: AppConstants.chatInferenceContextSize,
      mode: 'chat',
      warmupSystem: AppConstants.chatSystemPrompt,
      // Chat model: CPU-only is safer (big Vulkan allocs OOM on low RAM).
      cpuOnly: true,
    );
  }

  Future<void> _loadIntoEngine({
    required String modelPath,
    required int contextSize,
    required String mode,
    required String warmupSystem,
    bool cpuOnly = false,
  }) async {
    final file = File(modelPath);
    if (!await file.exists()) {
      _isReady = false;
      throw ModelNotAvailableException('Model file does not exist at: $modelPath');
    }

    final fileSizeBytes = await file.length();
    // ignore: avoid_print
    print('[Friday LLM] Loading model from: $modelPath ($fileSizeBytes bytes, ${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB)');
    // ignore: avoid_print
    print('[Friday LLM] Config: contextSize=$contextSize, threads=${AppConstants.inferenceThreads}, mode=$mode');

    try {
      try {
        final isAlreadyLoaded = await _controller.isModelLoaded();
        if (isAlreadyLoaded && _loadedPath == modelPath) {
          _isReady = true;
          _activeMode = mode;
          return;
        }
      } catch (_) {}
      // Engine may still hold the other model — dispose first.
      try {
        await _controller.dispose();
      } catch (_) {}

      int gpuLayers = 0;
      if (!cpuOnly) {
        try {
          final gpu = await _controller.detectGpu();
          if (gpu.vulkanSupported && gpu.recommendedGpuLayers > 0) {
            gpuLayers = gpu.recommendedGpuLayers;
          }
        } catch (_) {
          gpuLayers = 0;
        }
      }

      try {
        await _controller.loadModel(
          modelPath: modelPath,
          threads: AppConstants.inferenceThreads,
          contextSize: contextSize,
          gpuLayers: gpuLayers > 0 ? gpuLayers : null,
        );
      } catch (e) {
        // GPU load failed (e.g. OOM or Vulkan issue) — retry CPU-only
        if (gpuLayers > 0) {
          await _controller.loadModel(
            modelPath: modelPath,
            threads: AppConstants.inferenceThreads,
            contextSize: contextSize,
            gpuLayers: null,
          );
        } else {
          rethrow;
        }
      }
      _isReady = true;
      _activeMode = mode;
      _loadedPath = modelPath;

      // Warm up so the first real query does not pay cold-start latency.
      try {
        await _warmup(warmupSystem).timeout(const Duration(seconds: 10));
      } catch (_) {}
    } catch (e) {
      _isReady = false;
      _activeMode = null;
      if (e is AppException) rethrow;
      throw ModelNotAvailableException('Failed to load local model: $e');
    }
  }

  /// Runs a single-token generation to warm up the model in the background.
  Future<void> _warmup(String system) async {
    if (!_isReady) return;

    try {
      final stream = _controller.generateChat(
        messages: [
          ChatMessage(role: 'system', content: 'You are an assistant.'),
          ChatMessage(role: 'user', content: 'hi'),
        ],
        template: 'chatml',
        maxTokens: 1,
        temperature: 0.1,
      );
      await stream.drain<void>();
    } catch (_) {
      // Warmup failures shouldn't prevent model usage
    } finally {
      try {
        await _controller.clearContext();
      } catch (_) {}
    }
  }

  @override
  Future<String> infer(String userCommand) async {
    if (!_isReady) {
      throw const ModelNotAvailableException();
    }

    final messages = [
      ChatMessage(role: 'system', content: AppConstants.systemPrompt),
      ChatMessage(role: 'user', content: userCommand),
    ];

    final buffer = StringBuffer();
    final completer = Completer<String>();

    StreamSubscription<String>? subscription;

    // ignore: avoid_print
    print('[Friday LLM] infer() start: command="$userCommand", systemPromptChars=${AppConstants.systemPrompt.length}');
    try {
      // Clear previous turn's tokens from KV cache so prompt starts at position 0
      try {
        await _controller.clearContext();
      } catch (_) {}

      final stream = _controller.generateChat(
        messages: messages,
        template: 'chatml',
        maxTokens: 256,
        temperature: 0.1,
        topP: 0.9,
      );

      // Early stop: our prompt is a closed set of JSON intents. As soon as a
      // complete JSON object (or JSON array for ordered sequences) has been
      // produced, stop sampling instead of waiting for end-of-sequence — this
      // returns the reply noticeably faster.
      var stoppedEarly = false;
      subscription = stream.listen(
        (token) {
          buffer.write(token);
          if (!stoppedEarly && IntentParser.hasCompleteJson(buffer.toString())) {
            stoppedEarly = true;
            _controller.stop();
          }
        },
        onError: (error) {
          // ignore: avoid_print
          print('[Friday LLM] Native inference error: $error (Check `adb logcat -s LlamaJNI:V` for detail)');
          if (!completer.isCompleted) {
            completer.completeError(
              InvalidIntentException('Inference error: $error'),
            );
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(buffer.toString());
          }
        },
      );

      // Protect against a hang; on slower devices first inference can take
      // a while, so allow generous time before returning partial output.
      return await completer.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          _controller.stop();
          return buffer.toString();
        },
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw InvalidIntentException('Local inference failed: $e');
    } finally {
      await subscription?.cancel();
    }
  }

  /// Raw single-shot generation with a caller-supplied system prompt.
  /// Used by the Friday agent loop (small prompts, tiny replies like
  /// `TAP 3`). Not part of [LocalLLMService] so existing fakes/tests
  /// are unaffected. Throws [ModelNotAvailableException] when no model
  /// is loaded; never fabricates output.
  Future<String> generateRaw({
    required String system,
    required String user,
    int maxTokens = 32,
  }) async {
    if (!_isReady) {
      throw const ModelNotAvailableException();
    }
    final buffer = StringBuffer();
    final completer = Completer<String>();
    StreamSubscription<String>? subscription;
    try {
      try {
        await _controller.clearContext();
      } catch (_) {}
      final stream = _controller.generateChat(
        messages: [
          ChatMessage(role: 'system', content: system),
          ChatMessage(role: 'user', content: user),
        ],
        template: 'chatml',
        maxTokens: maxTokens,
        temperature: 0.1,
        topP: 0.9,
      );
      subscription = stream.listen(
        (token) {
          buffer.write(token);
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(
              InvalidIntentException('Inference error: $error'),
            );
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(buffer.toString());
          }
        },
      );
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _controller.stop();
          return buffer.toString();
        },
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw InvalidIntentException('Local inference failed: $e');
    } finally {
      await subscription?.cancel();
    }
  }

  @override
  Future<String> chat(
    String userMessage, {
    List<Map<String, String>> history = const [],
    void Function(String token)? onToken,
  }) async {
    if (!_isReady || _activeMode != 'chat') {
      throw const ModelNotAvailableException(
          'Smart chat model is not loaded.');
    }
    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: AppConstants.chatSystemPrompt),
      // Keep only the last 10 turns to fit the context window.
      for (final h in history.take(10))
        ChatMessage(
          role: h['role'] == 'assistant' ? 'assistant' : 'user',
          content: (h['text'] ?? '').trim(),
        ),
      ChatMessage(role: 'user', content: userMessage),
    ];

    final buffer = StringBuffer();
    final completer = Completer<String>();
    StreamSubscription<String>? subscription;
    try {
      final stream = _controller.generateChat(
        messages: messages,
        template: 'chatml',
        maxTokens: 512,
        temperature: 0.7,
        topP: 0.9,
      );
      subscription = stream.listen(
        (token) {
          buffer.write(token);
          try {
            onToken?.call(token);
          } catch (_) {}
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(
              InvalidIntentException('Chat inference error: $error'),
            );
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(buffer.toString());
        },
      );
      final raw = await completer.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          _controller.stop();
          return buffer.toString();
        },
      );
      var text = raw.trim();
      // Strip accidental code fences / leading labels the instruct model echoes.
      if (text.startsWith('```')) {
        text = text.replaceAll(RegExp(r'^```\w*\n?'), '').replaceAll(RegExp(r'```$'), '').trim();
      }
      if (text.length > 2000) text = '${text.substring(0, 1997).trim()}...';
      // Empty generation can happen on low-RAM OOM or truncated context;
      // return a friendly fallback instead of throwing InvalidIntent which
      // the UI was mapping to "couldn't understand".
      if (text.isEmpty) {
        if (buffer.toString().trim().isNotEmpty) {
          text = buffer.toString().trim();
        } else {
          return 'Sorry, I had trouble generating a reply. Please try again with a shorter question.';
        }
      }
      return text;
    } catch (e) {
      if (e is AppException) rethrow;
      throw InvalidIntentException('Local chat failed: $e');
    } finally {
      await subscription?.cancel();
    }
  }

  @override
  Future<void> dispose() async {
    _isReady = false;
    _activeMode = null;
    _loadedPath = null;
    await _controller.dispose();
  }
}
