import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friday_app/features/assistant/presentation/assistant_controller.dart';

/// A 3D wireframe & glowing energy mini-globe with rotating meridians,
/// atmospheric aura, and live voice sound-level reactivity.
class MiniGlobe extends StatefulWidget {
  final AssistantController controller;
  final double size;

  const MiniGlobe({
    super.key,
    required this.controller,
    this.size = 38.0,
  });

  @override
  State<MiniGlobe> createState() => _MiniGlobeState();
}

class _MiniGlobeState extends State<MiniGlobe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _animController,
        widget.controller.soundLevel,
      ]),
      builder: (context, _) {
        final ctrl = widget.controller;
        final isListening = ctrl.isListening;
        final isProcessing = ctrl.isProcessing;
        final isSpeaking = ctrl.isSpeaking;
        final soundLevel = isListening ? ctrl.soundLevel.value : 0.0;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _MiniGlobePainter(
              animationValue: _animController.value,
              soundLevel: soundLevel,
              isListening: isListening,
              isProcessing: isProcessing,
              isSpeaking: isSpeaking,
            ),
          ),
        );
      },
    );
  }
}

class _MiniGlobePainter extends CustomPainter {
  final double animationValue;
  final double soundLevel;
  final bool isListening;
  final bool isProcessing;
  final bool isSpeaking;

  _MiniGlobePainter({
    required this.animationValue,
    required this.soundLevel,
    required this.isListening,
    required this.isProcessing,
    required this.isSpeaking,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) * 0.82;
    final speedMultiplier = isProcessing ? 3.0 : (isSpeaking ? 1.5 : 1.0);
    final rot = (animationValue * speedMultiplier * 2 * math.pi) % (2 * math.pi);
    final voiceBoost = (soundLevel * 0.35).clamp(0.0, 0.35);

    // Primary & Secondary palette
    final Color colorA;
    final Color colorB;
    final Color glowColor;

    if (isProcessing) {
      colorA = const Color(0xFF60A5FA); // Blue
      colorB = const Color(0xFFA855F7); // Purple
      glowColor = const Color(0xFF818CF8);
    } else if (isSpeaking) {
      colorA = const Color(0xFF34D399); // Emerald
      colorB = const Color(0xFF38BDF8); // Sky
      glowColor = const Color(0xFF10B981);
    } else if (isListening) {
      colorA = const Color(0xFF38BDF8); // Cyan
      colorB = const Color(0xFFF472B6); // Pink
      glowColor = const Color(0xFFEC4899);
    } else {
      colorA = const Color(0xFF60A5FA);
      colorB = const Color(0xFF818CF8);
      glowColor = const Color(0xFF3B82F6);
    }

    // 1. Atmospheric Outer Glow
    final glowRadius = radius * (1.25 + voiceBoost * 1.2);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          glowColor.withOpacity(0.45 + voiceBoost * 0.4),
          glowColor.withOpacity(0.12),
          glowColor.withOpacity(0.0),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    canvas.drawCircle(center, glowRadius, glowPaint);

    // 2. Core Globe Background Sphere
    final sphereRect = Rect.fromCircle(center: center, radius: radius);
    final spherePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        colors: [
          Colors.white.withOpacity(0.4),
          colorA.withOpacity(0.85),
          colorB.withOpacity(0.95),
          const Color(0xFF0F172A),
        ],
        stops: const [0.0, 0.35, 0.75, 1.0],
      ).createShader(sphereRect);
    canvas.drawCircle(center, radius, spherePaint);

    // 3. Globe Clip to keep internal lines within sphere
    canvas.save();
    final clipPath = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.clipPath(clipPath);

    // 4. Latitude Lines (Parallels)
    final latPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withOpacity(0.28 + voiceBoost * 0.3);

    final latitudes = [-0.6, -0.3, 0.0, 0.3, 0.6];
    for (final lat in latitudes) {
      final y = center.dy + radius * lat;
      final latWidth = radius * math.cos(math.asin(lat.abs()));
      final latHeight = radius * 0.22;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(center.dx, y), width: latWidth * 2, height: latHeight),
        latPaint,
      );
    }

    // 5. Longitude Meridians (Rotating with rot)
    final meridianPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withOpacity(0.4 + voiceBoost * 0.4);

    const int meridianCount = 5;
    for (int i = 0; i < meridianCount; i++) {
      final angle = rot + (i * math.pi / meridianCount);
      final cosA = math.cos(angle);
      final xOffset = center.dx + (cosA * radius * 0.1);
      final width = (cosA.abs() * radius * 2).clamp(1.0, radius * 2);
      
      // Draw meridian ellipse
      canvas.drawOval(
        Rect.fromCenter(center: Offset(xOffset, center.dy), width: width, height: radius * 2),
        meridianPaint,
      );
    }

    canvas.restore();

    // 6. Outer Spherical Rim & Specular Edge
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..shader = SweepGradient(
        colors: [
          Colors.white.withOpacity(0.8),
          colorA.withOpacity(0.9),
          colorB.withOpacity(0.9),
          Colors.white.withOpacity(0.8),
        ],
        transform: GradientRotation(rot),
      ).createShader(sphereRect);
    canvas.drawCircle(center, radius, rimPaint);

    // 7. Orbiting Energy Satellite Particle
    final orbitRadiusX = radius * 1.32;
    final orbitRadiusY = radius * 0.55;
    final orbitAngle = -rot * 1.4;
    final px = center.dx + math.cos(orbitAngle) * orbitRadiusX;
    final py = center.dy + math.sin(orbitAngle) * orbitRadiusY;

    final particlePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.5);
    canvas.drawCircle(Offset(px, py), 2.2 + voiceBoost * 2.0, particlePaint);

    // 8. Hotspot Specular Highlight on Top Left
    final highlightPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.65),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(center.dx - radius * 0.38, center.dy - radius * 0.38),
          radius: radius * 0.45,
        ),
      );
    canvas.drawCircle(
      Offset(center.dx - radius * 0.38, center.dy - radius * 0.38),
      radius * 0.45,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniGlobePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.soundLevel != soundLevel ||
        oldDelegate.isListening != isListening ||
        oldDelegate.isProcessing != isProcessing ||
        oldDelegate.isSpeaking != isSpeaking;
  }
}
