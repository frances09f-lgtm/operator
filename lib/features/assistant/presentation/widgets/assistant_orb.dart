import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friday_app/features/assistant/presentation/assistant_controller.dart';

/// Visual state the orb should express.
enum AssistantOrbState {
  idle,
  listening,
  thinking,
  responding,
  error,
}

/// A Jarvis-style glowing orb that reacts to the assistant's state and, while
/// the microphone listens, to the live voice level so it feels like it is
/// responding to speech.
class AssistantOrb extends StatefulWidget {
  final AssistantController controller;
  final double size;

  const AssistantOrb({
    super.key,
    required this.controller,
    this.size = 220,
  });

  @override
  State<AssistantOrb> createState() => _AssistantOrbState();
}

class _AssistantOrbState extends State<AssistantOrb>
    with TickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _rotation.dispose();
    _pulse.dispose();
    super.dispose();
  }

  AssistantOrbState get _phase {
    final ctrl = widget.controller;
    if (ctrl.isSpeaking || ctrl.isOpening) return AssistantOrbState.responding;
    if (ctrl.isProcessing) return AssistantOrbState.thinking;
    if (ctrl.isListening) return AssistantOrbState.listening;
    if (ctrl.isResponding) return AssistantOrbState.responding;
    return ctrl.modelStatus == ModelStatus.ready
        ? AssistantOrbState.idle
        : AssistantOrbState.error;
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phase;

    final rotationSpeed = switch (phase) {
      AssistantOrbState.thinking => 2.4,
      AssistantOrbState.responding => 1.5,
      AssistantOrbState.listening => 1.0,
      AssistantOrbState.error => 0.25,
      AssistantOrbState.idle => 0.4,
    };
    final pulseSpeed = switch (phase) {
      AssistantOrbState.thinking => 2.2,
      AssistantOrbState.responding => 2.6,
      AssistantOrbState.listening => 1.6,
      AssistantOrbState.error => 0.5,
      AssistantOrbState.idle => 1.0,
    };

    _rotation.duration = Duration(milliseconds: (6000 / rotationSpeed).round());
    _pulse.duration = Duration(milliseconds: (1600 / pulseSpeed).round());

    final active = phase != AssistantOrbState.error;
    final baseColor = active
        ? const Color(0xFF4DD8FF)
        : const Color(0xFFFF6A6A);
    final secondaryColor = active
        ? const Color(0xFF1E90FF)
        : const Color(0xFFB03A3A);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_rotation, _pulse, widget.controller.soundLevel]),
          builder: (context, _) {
            return CustomPaint(
              painter: _OrbPainter(
                state: phase,
                rotationAngle: _rotation.value * 2 * math.pi,
                pulseValue: _pulse.value,
                soundLevel: widget.controller.soundLevel.value,
                baseColor: baseColor,
                secondaryColor: secondaryColor,
                dampened: !active,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final AssistantOrbState state;
  final double rotationAngle;
  final double pulseValue;
  final double soundLevel;
  final Color baseColor;
  final Color secondaryColor;
  final bool dampened;

  const _OrbPainter({
    required this.state,
    required this.rotationAngle,
    required this.pulseValue,
    required this.soundLevel,
    required this.baseColor,
    required this.secondaryColor,
    required this.dampened,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // breath: 0..1 sinusoidal heartbeat.
    final breath = 0.5 + 0.5 * math.sin(pulseValue * 2 * math.pi);
    final isListening = state == AssistantOrbState.listening;
    final isThinking = state == AssistantOrbState.thinking;
    final isResponding = state == AssistantOrbState.responding;
    final level = dampened ? 0.0 : soundLevel;

    // ---- Ambient glow behind everything ----
    final glowRadius = r * (1.35 + 0.25 * breath + 0.6 * level);
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = RadialGradient(colors: [
          baseColor.withAlpha(70),
          baseColor.withAlpha(0),
        ]).createShader(Rect.fromCircle(center: center, radius: glowRadius)),
    );

    // ---- Outer master ring ----
    canvas.drawCircle(
      center,
      r * 0.97,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = (dampened ? secondaryColor : baseColor).withAlpha(35),
    );

    // ---- Rotating arc segments (the Jarvis signature) ----
    final baseSweep = switch (state) {
      AssistantOrbState.thinking => 1.45,
      AssistantOrbState.listening => 0.85 + level * 0.9,
      AssistantOrbState.responding => 1.1 + 0.7 * breath,
      AssistantOrbState.error => 0.8,
      AssistantOrbState.idle => 0.62 + 0.25 * breath,
    };
    final arcAlpha = isThinking ? 200 + 40 * breath : 210;

    for (var i = 0; i < 3; i++) {
      final start = rotationAngle + i * 2 * math.pi / 3;
      final dwell = isThinking && i == 0 ? -0.12 : 0.0;
      final arcRadius =
          r * 0.66 + (isListening ? level * 0.10 * r : 0.0) + dwell * r;
      final rect = Rect.fromCircle(center: center, radius: arcRadius);

      // wide soft glow pass
      canvas.drawArc(
        rect,
        start,
        baseSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8 + 3 * level
          ..strokeCap = StrokeCap.round
          ..color = baseColor.withAlpha(isThinking ? (16 + 26 * breath).toInt() : 30),
      );
      // crisp leading pass
      canvas.drawArc(
        rect,
        start,
        baseSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 + level * 1.5
          ..strokeCap = StrokeCap.round
          ..color = (isListening && level > 0.25 ? Colors.white : baseColor)
              .withAlpha(arcAlpha.toInt()),
      );
    }

    // ---- Voice-reactive inner arc while listening ----
    if (isListening && level > 0.35) {
      final innerArc = r * 0.40 + 0.1 * breath * r;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: innerArc),
        -math.pi / 2 + rotationAngle * 1.8,
        math.min(level * 2.2, 1.6),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 + 2 * level
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withAlpha((90 + 160 * level).toInt()),
      );
    }

    // ---- Expanding ripple rings when thinking/responding ----
    if (isThinking || isResponding) {
      for (var i = 0; i < 2; i++) {
        final ripplePhase = (pulseValue + i * 0.5) % 1.0;
        final rippleRadius = r * (0.45 + ripplePhase * 0.5);
        canvas.drawCircle(
          center,
          rippleRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = baseColor.withAlpha((30 * (1 - ripplePhase)).toInt()),
        );
      }
    }

    // ---- Core sphere with radial gradient ----
    final corePulse = isResponding
        ? 1 + 0.18 * breath
        : isThinking
            ? 1 + 0.08 * breath
            : isListening
                ? 1 + 0.16 * level
                : 1 + 0.05 * breath;
    final coreR = r * 0.30 * corePulse;
    final coreRect = Rect.fromCircle(center: center, radius: coreR);
    canvas.drawCircle(
      center,
      coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withAlpha(dampened ? 150 : 255),
          baseColor.withAlpha(dampened ? 120 : 230),
          secondaryColor.withAlpha(dampened ? 60 : 180),
        ]).createShader(coreRect),
    );

    // bright hot center
    canvas.drawCircle(
      center,
      coreR * 0.38,
      Paint()..color = Colors.white.withAlpha(dampened ? 90 : 235),
    );

    // ---- Small orbiting satellites ----
    if (isListening || isResponding) {
      for (var i = 0; i < 2; i++) {
        final angle = -rotationAngle * 0.6 + i * math.pi;
        final sx = center.dx + math.cos(angle) * r * 0.52;
        final sy = center.dy + math.sin(angle) * r * 0.52;
        canvas.drawCircle(
          Offset(sx, sy),
          2.2 + level * 1.4,
          Paint()..color = baseColor.withAlpha(180),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.rotationAngle != rotationAngle ||
      oldDelegate.pulseValue != pulseValue ||
      oldDelegate.soundLevel != soundLevel ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.dampened != dampened;
}