import 'dart:async';

import 'package:flutter/material.dart';
import 'package:friday_app/features/assistant/presentation/assistant_controller.dart';
import 'package:friday_app/features/assistant/presentation/widgets/mini_globe.dart';
import 'package:friday_app/services/assist/assist_service.dart';

/// Compact floating animated assistant bar for long-press power (ACTION_ASSIST).
///
/// Features an animated glowing 3D mini-globe and a sleek rounded rectangle box
/// that displays live transcribed speech in real-time as the user talks,
/// followed by Friday's response / action status.
class AssistOverlayScreen extends StatefulWidget {
  final AssistantController controller;

  const AssistOverlayScreen({super.key, required this.controller});

  @override
  State<AssistOverlayScreen> createState() => _AssistOverlayScreenState();
}

class _AssistOverlayScreenState extends State<AssistOverlayScreen>
    with SingleTickerProviderStateMixin {
  final AssistService _assistService = AssistService();
  late final AnimationController _enterController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _closeTimer;
  String? _seenCommand;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..forward();
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _enterController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeOut,
    );

    // Snapshot existing command so we only auto-close after a NEW command runs
    // during this overlay session, never on stale prior commands.
    _seenCommand = widget.controller.lastUserCommand;

    if (widget.controller.modelStatus == ModelStatus.notChecked) {
      widget.controller.initializeModel();
    }
    if (!widget.controller.isSpeechAvailable) {
      widget.controller.initializeSpeech();
    }
    widget.controller.initializeTts();
    widget.controller.initializeAutomation();
    widget.controller.initializeAssist();
    widget.controller.addListener(_maybeScheduleClose);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_maybeScheduleClose);
    _closeTimer?.cancel();
    _enterController.dispose();
    super.dispose();
  }

  /// Schedules overlay close after a command reaches a final state.
  void _maybeScheduleClose() {
    final ctrl = widget.controller;
    if (!mounted) return;

    // Only auto-close if a NEW command was executed in this overlay session.
    if (ctrl.lastUserCommand == null || ctrl.lastUserCommand == _seenCommand) {
      return;
    }

    // Wait until listening / processing / speaking settles.
    if (ctrl.isListening || ctrl.isProcessing || ctrl.isSpeaking) {
      _closeTimer?.cancel();
      return;
    }
    if (_closeTimer?.isActive ?? false) return;

    // Give the user a brief moment to see the result before auto-dismissing.
    _closeTimer = Timer(const Duration(milliseconds: 1600), () async {
      if (!mounted) return;
      final c = widget.controller;
      if (c.isListening || c.isProcessing || c.isSpeaking) return;
      await _close();
    });
  }

  Future<void> _close() async {
    _closeTimer?.cancel();
    await _assistService.dismissAssist();
    widget.controller.exitAssistMode();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final isListening = ctrl.isListening;
        final isProcessing = ctrl.isProcessing;
        final isSpeaking = ctrl.isSpeaking;
        final active = isListening || isProcessing || isSpeaking;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _close();
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                // Dimmed background backdrop. Tap outside dismisses.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: Container(
                      color: Colors.black.withOpacity(0.35),
                    ),
                  ),
                ),
                // Compact floating bar anchored at bottom center.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          child: _FloatingAssistPill(
                            controller: ctrl,
                            active: active,
                            onClose: _close,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A compact, sleek floating rounded rectangle pill displaying the mini globe
/// and real-time live transcribed voice command or response.
class _FloatingAssistPill extends StatelessWidget {
  final AssistantController controller;
  final bool active;
  final VoidCallback onClose;

  const _FloatingAssistPill({
    required this.controller,
    required this.active,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 460,
        minHeight: 58,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: active
              ? const [
                  Color(0xFF38BDF8),
                  Color(0xFF818CF8),
                  Color(0xFFEC4899),
                ]
              : [
                  Colors.white.withOpacity(0.24),
                  Colors.white.withOpacity(0.08),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          if (active)
            BoxShadow(
              color: const Color(0xFF818CF8).withOpacity(0.3),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      padding: const EdgeInsets.all(1.2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(29),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xF012131A),
            borderRadius: BorderRadius.circular(29),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Moving Globe Animation
              MiniGlobe(
                controller: controller,
                size: 38,
              ),
              const SizedBox(width: 12),
              // 2. Animated Live Speech & Status Rectangle Box
              Expanded(
                child: _LiveSpeechContentBox(controller: controller),
              ),
              const SizedBox(width: 8),
              // 3. Close / Dismiss button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onClose,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.06),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white60,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dynamic content box that displays live words as user talks,
/// or thinking state, or the final response status.
class _LiveSpeechContentBox extends StatelessWidget {
  final AssistantController controller;

  const _LiveSpeechContentBox({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isListening = controller.isListening;
    final isProcessing = controller.isProcessing;
    final isSpeaking = controller.isSpeaking;
    final liveText = controller.liveSpeechText;
    final lastCommand = controller.lastUserCommand;

    // 1. Listening State
    if (isListening) {
      if (liveText != null && liveText.isNotEmpty) {
        // User has started talking -> Show live transcribed words in rectangle box!
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              liveText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 3),
            _MiniLiveWaveform(controller: controller),
          ],
        );
      }

      // Mic is open, waiting for user to start speaking
      return Row(
        children: [
          const Text(
            'Listening…',
            style: TextStyle(
              color: Color(0xFF38BDF8),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MiniLiveWaveform(controller: controller),
          ),
        ],
      );
    }

    // 2. Processing / Thinking State
    if (isProcessing) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lastCommand != null && lastCommand.isNotEmpty)
            Text(
              '“$lastCommand”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          const SizedBox(height: 1),
          const Row(
            children: [
              Text(
                'Thinking…',
                style: TextStyle(
                  color: Color(0xFFA78BFA),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFA78BFA)),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // 3. Speaking / Responding / Action Executed State
    if (isSpeaking || controller.isOpening || controller.isResponding) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lastCommand != null && lastCommand.isNotEmpty)
            Text(
              '“$lastCommand”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          Text(
            controller.statusMessage,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF34D399),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      );
    }

    // 4. Default / Settled State (Show status or prompt)
    final msg = controller.statusMessage;
    final displayMsg = (msg == 'Ready' || msg == 'Initializing...')
        ? 'How can I help?'
        : msg;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lastCommand != null && lastCommand.isNotEmpty)
          Text(
            '“$lastCommand”',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        Text(
          displayMsg,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Compact sound-level audio waveform shown while listening and speaking.
class _MiniLiveWaveform extends StatelessWidget {
  final AssistantController controller;

  const _MiniLiveWaveform({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: ValueListenableBuilder<double>(
        valueListenable: controller.soundLevel,
        builder: (context, level, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(14, (i) {
              final wave =
                  (0.35 + 0.65 * ((i % 5 + 1) / 5)) * (0.2 + level * 2.5);
              final h = (3.0 + wave * 11).clamp(2.5, 14.0);
              return Container(
                width: 2.2,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 1.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1.5),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF38BDF8),
                      Color(0xFFEC4899),
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
