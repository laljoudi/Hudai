import 'dart:math' as math;

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

    _playWelcome();
  }

  Future<void> _playWelcome() async {
    try {
      await _audioPlayer.play(
          AssetSource('audio/onboarding/welcome_instructions.mp3'));
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background gradient — linear, top-to-bottom
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end:   Alignment.bottomCenter,
                    colors: [
                      Color(0xFF030A20), // 0%
                      Color(0xFF071540), // 50%
                      Color(0xFF0E2360), // 75%
                      Color(0xFF1A3A8A), // 100%
                    ],
                    stops: [0.0, 0.50, 0.75, 1.0],
                  ),
                ),
              ),
            ),

            // Orb + arcs
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

                          // Outer glow bloom — subtle cyan halo
                          Opacity(
                            opacity: _glowAnim.value * 0.18,
                            child: Container(
                              width:  orbDiameter + 80,
                              height: orbDiameter + 80,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color:        Color(0x0D70F0FF), // cyan ~5%
                                    blurRadius:   80,
                                    spreadRadius: 8,
                                  ),
                                  BoxShadow(
                                    color:        Color(0x0670F0FF), // cyan ~2%
                                    blurRadius:   120,
                                    spreadRadius: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Arc 1 — #70F0FF
                          Transform.rotate(
                            angle: _arc1Ctrl.value * 2 * math.pi,
                            child: CustomPaint(
                              size: Size(orbDiameter + 46, orbDiameter + 46),
                              painter: _NeonArcPainter(
                                startAngle:  -math.pi * 0.78,
                                sweepAngle:  math.pi * 1.12,
                                color:       const Color(0xFF70F0FF),
                                strokeWidth: 2.2,
                                glowWidth:   9.0,
                              ),
                            ),
                          ),

                          // Arc 2 — #70F0FF
                          Transform.rotate(
                            angle: -_arc2Ctrl.value * 2 * math.pi,
                            child: CustomPaint(
                              size: Size(orbDiameter + 70, orbDiameter + 70),
                              painter: _NeonArcPainter(
                                startAngle:  math.pi * 0.18,
                                sweepAngle:  math.pi * 0.82,
                                color:       const Color(0xFF70F0FF),
                                strokeWidth: 1.6,
                                glowWidth:   6.5,
                              ),
                            ),
                          ),

                          // The blue glassy orb
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
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color:        Color(0x991E5FFF),
            blurRadius:   45,
            spreadRadius: 5,
          ),
          BoxShadow(
            color:        Color(0x4700B8FF),
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

            // Bottom cyan reflected light
            Positioned(
              bottom: -diameter * 0.08,
              left:   diameter * 0.12,
              right:  diameter * 0.12,
              child: Container(
                height: diameter * 0.58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(diameter),
                  gradient: const RadialGradient(
                    colors: [
                      Color(0x8000DDFF),
                      Color(0x380090FF),
                      Color(0x000090FF),
                    ],
                  ),
                ),
              ),
            ),

            // Small sharp highlight dot (top-left)
            Positioned(
              top:  diameter * 0.18,
              left: diameter * 0.26,
              child: Container(
                width:  diameter * 0.10,
                height: diameter * 0.06,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(diameter),
                  color: Colors.white.withOpacity(0.55),
                ),
              ),
            ),

            // Edge darkening
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

            // Glass rim
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