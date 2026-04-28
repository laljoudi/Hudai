import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:gp_hudai/app/app_routes.dart';
import 'package:audioplayers/audioplayers.dart';

class VoiceInstructionsScreen extends StatefulWidget {
  const VoiceInstructionsScreen({super.key});

  @override
  State<VoiceInstructionsScreen> createState() =>
      _VoiceInstructionsScreenState();
}

class _VoiceInstructionsScreenState extends State<VoiceInstructionsScreen>
    with TickerProviderStateMixin {

  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;
  late final AnimationController _arc1Ctrl;
  late final AnimationController _arc2Ctrl;
  late final AnimationController _glowCtrl;
  late final Animation<double>   _glowAnim;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _arc1Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _arc2Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _glowAnim = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    // Start welcome audio when screen opens
    _playWelcome();
  }

  Future<void> _playWelcome() async {
    try {
      await _audioPlayer.play(AssetSource('audio/onboarding/welcome_instructions.mp3'));
    } catch (e) {
      debugPrint('Audio error: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _pulseCtrl.dispose();
    _arc1Ctrl.dispose();
    _arc2Ctrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  void _proceed() {
    if (!mounted) return;
    _audioPlayer.stop();
    Navigator.pushReplacementNamed(context, AppRoutes.setup);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final orbDiameter = size.width * 0.62;

    return Scaffold(
      backgroundColor: const Color(0xFF030A20),
      body: GestureDetector(
        onTap: _proceed,
        child: SizedBox.expand(
          child: Stack(
            clipBehavior: Clip.none,
            children: [

              // ── Background radial gradient ─────────────────────────────
              Positioned.fill(
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.0, 0.0),
                      radius: 1.0,
                      colors: [
                        Color(0xFF1A3A8A),
                        Color(0xFF0E2360),
                        Color(0xFF071540),
                        Color(0xFF030A20),
                      ],
                      stops: [0.0, 0.30, 0.65, 1.0],
                    ),
                  ),
                ),
              ),

              // ── Orb + arcs ─────────────────────────────────────────────
              Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _pulseAnim,
                    _arc1Ctrl,
                    _arc2Ctrl,
                    _glowAnim,
                  ]),
                  builder: (context, _) {
                    return Transform.scale(
                      scale: _pulseAnim.value,
                      child: SizedBox(
                        width:  orbDiameter + 90,
                        height: orbDiameter + 90,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [

                            Opacity(
                              opacity: _glowAnim.value,
                              child: Container(
                                width:  orbDiameter + 80,
                                height: orbDiameter + 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF1855FF)
                                          .withOpacity(0.30),
                                      blurRadius:   90,
                                      spreadRadius: 20,
                                    ),
                                    BoxShadow(
                                      color: const Color(0xFF00CFFF)
                                          .withOpacity(0.15),
                                      blurRadius:   130,
                                      spreadRadius: 35,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            Transform.rotate(
                              angle: _arc1Ctrl.value * 2 * math.pi,
                              child: CustomPaint(
                                size: Size(
                                    orbDiameter + 46, orbDiameter + 46),
                                painter: _NeonArcPainter(
                                  startAngle:  -math.pi * 0.78,
                                  sweepAngle:  math.pi * 1.12,
                                  color:       const Color(0xFF40E0FF),
                                  strokeWidth: 2.2,
                                  glowWidth:   9.0,
                                ),
                              ),
                            ),

                            Transform.rotate(
                              angle: -_arc2Ctrl.value * 2 * math.pi,
                              child: CustomPaint(
                                size: Size(
                                    orbDiameter + 70, orbDiameter + 70),
                                painter: _NeonArcPainter(
                                  startAngle:  math.pi * 0.18,
                                  sweepAngle:  math.pi * 0.82,
                                  color:       const Color(0xFF70F0FF),
                                  strokeWidth: 1.6,
                                  glowWidth:   6.5,
                                ),
                              ),
                            ),

                            _GlassOrb(diameter: orbDiameter),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Glass Orb
// ─────────────────────────────────────────────────────────────────────────────

class _GlassOrb extends StatelessWidget {
  const _GlassOrb({required this.diameter});
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color:        const Color(0xFF1E5FFF).withOpacity(0.60),
            blurRadius:   45,
            spreadRadius: 5,
          ),
          BoxShadow(
            color:        const Color(0xFF00B8FF).withOpacity(0.28),
            blurRadius:   80,
            spreadRadius: 12,
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.18, -0.22),
                  radius: 1.0,
                  colors: [
                    Color(0xFF3E82FF),
                    Color(0xFF1A44CC),
                    Color(0xFF0A1E88),
                    Color(0xFF060D52),
                  ],
                  stops: [0.0, 0.32, 0.65, 1.0],
                ),
              ),
            ),

            Positioned(
              bottom: -diameter * 0.08,
              left:   diameter * 0.12,
              right:  diameter * 0.12,
              child: Container(
                height: diameter * 0.58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(diameter),
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF00DDFF).withOpacity(0.50),
                      const Color(0xFF0090FF).withOpacity(0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.88,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.35),
                  ],
                  stops: const [0.0, 0.62, 1.0],
                ),
              ),
            ),

            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.20),
                  width: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Neon Arc Painter
// ─────────────────────────────────────────────────────────────────────────────

class _NeonArcPainter extends CustomPainter {
  const _NeonArcPainter({
    required this.startAngle,
    required this.sweepAngle,
    required this.color,
    required this.strokeWidth,
    required this.glowWidth,
  });

  final double startAngle;
  final double sweepAngle;
  final Color  color;
  final double strokeWidth;
  final double glowWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide / 2) - glowWidth;
    final rect   = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect, startAngle, sweepAngle, false,
      Paint()
        ..color       = color.withOpacity(0.38)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = glowWidth
        ..strokeCap   = StrokeCap.round
        ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    canvas.drawArc(
      rect, startAngle, sweepAngle, false,
      Paint()
        ..color       = color
        ..style       = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap   = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _NeonArcPainter old) => false;
}