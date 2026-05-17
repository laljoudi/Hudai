import 'dart:async';
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
  // ── Pulse: driven by the audio-amplitude envelope below, with an
  // ──       attack/release smoothing filter applied on top.
  //
  // The amplitude keyframes give us the raw "loudness" of each moment
  // of the audio, but raw amplitude is too twitchy. So we apply
  // asymmetric smoothing: the orb grows quickly when voice rises
  // (attack), and shrinks slowly when voice falls (release).
  // This is the standard technique used in professional audio
  // visualizers like Apple's Voice Memos waveform and Siri's orb.

  late final AnimationController _calmPulseCtrl;
  static const double _calmScaleMin = 0.97;
  static const double _calmScaleMax = 1.03;

  static const double _activeScaleMin = 0.94;
  static const double _activeScaleMax = 1.10;

  // Smoothing coefficients — higher = faster follow, lower = slower.
  // Attack is faster than release so the orb feels responsive on rises
  // but graceful on falls — like breathing, not twitching.
  static const double _attackCoeff = 0.25;  // ~150ms to track a rise
  static const double _releaseCoeff = 0.06; // ~600ms to track a fall

  // Ticker for audio-driven pulse
  Timer? _audioTicker;
  double _smoothedAmplitude = 0.0;
  bool _isAudioPlaying = false;

  late final AnimationController _arc1Ctrl;
  late final AnimationController _arc2Ctrl;
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();

    _calmPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    // Slower arc rotations — feels calmer, more meditative.
    _arc1Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _arc2Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _audioPlayer.onPlayerComplete.listen((_) => _stopAudioTicker());

    _playWelcome();
  }

  Future<void> _playWelcome() async {
    try {
      _startAudioTicker();
      await _audioPlayer.play(
        AssetSource('audio/onboarding/welcome_instructions.mp3'),
      );
    } catch (e) {
      debugPrint('Audio error: $e');
      _stopAudioTicker();
    }
  }

  /// Poll the audio position at 30Hz, look up the raw amplitude,
  /// then apply asymmetric attack/release smoothing.
  void _startAudioTicker() {
    _audioTicker?.cancel();
    setState(() => _isAudioPlaying = true);
    _audioTicker = Timer.periodic(
      const Duration(milliseconds: 33), // ~30 fps
      (_) async {
        final pos = await _audioPlayer.getCurrentPosition();
        if (pos == null) return;
        final ms = pos.inMilliseconds;
        final idx = ms ~/ _binMs;
        double raw;
        if (idx < 0 || idx >= _intensities.length) {
          raw = 0.0;
        } else {
          final t = (ms % _binMs) / _binMs;
          final a = _intensities[idx];
          final b = idx + 1 < _intensities.length ? _intensities[idx + 1] : a;
          raw = a + (b - a) * t;
        }

        // Attack/release smoothing — the secret to "good looking" sync.
        // If new value is higher, move toward it quickly (attack).
        // If lower, move slowly (release). Standard envelope-follower.
        final coeff = raw > _smoothedAmplitude ? _attackCoeff : _releaseCoeff;
        _smoothedAmplitude += (raw - _smoothedAmplitude) * coeff;

        if (mounted) setState(() {});
      },
    );
  }

  void _stopAudioTicker() {
    _audioTicker?.cancel();
    _audioTicker = null;
    if (mounted) {
      setState(() {
        _isAudioPlaying = false;
        _smoothedAmplitude = 0.0;
      });
    }
  }

  /// Current orb scale — either driven by smoothed audio amplitude
  /// or by the calm idle pulse controller.
  double _currentPulseScale() {
    if (_isAudioPlaying) {
      return _activeScaleMin +
          (_activeScaleMax - _activeScaleMin) * _smoothedAmplitude;
    }
    final t = Curves.easeInOut.transform(_calmPulseCtrl.value);
    return _calmScaleMin + (_calmScaleMax - _calmScaleMin) * t;
  }

  @override
  void dispose() {
    _audioTicker?.cancel();
    _audioPlayer.dispose();
    _calmPulseCtrl.dispose();
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
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF030A20),
                      Color(0xFF071540),
                      Color(0xFF0E2360),
                      Color(0xFF1A3A8A),
                    ],
                    stops: [0.0, 0.50, 0.75, 1.0],
                  ),
                ),
              ),
            ),

            // ── App name — Arabic only, elongated with tatweel ────────
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Text(
                    'هُــــــداي',
                    textDirection: TextDirection.rtl,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 17,
                          color: Colors.white.withOpacity(0.45),
                          fontWeight: FontWeight.w400,
                          height: 1.0,
                        ),
                  ),
                ),
              ),
            ),

            Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _calmPulseCtrl,
                  _arc1Ctrl,
                  _arc2Ctrl,
                  _glowAnim,
                ]),
                builder: (context, _) {
                  return Transform.scale(
                    scale: _currentPulseScale(),
                    child: SizedBox(
                      width: orbDiameter + 90,
                      height: orbDiameter + 90,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: _glowAnim.value *
                                (_isAudioPlaying
                                    ? (0.18 + 0.15 * _smoothedAmplitude)
                                    : 0.18),
                            child: Container(
                              width: orbDiameter + 80,
                              height: orbDiameter + 80,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x0D70F0FF),
                                    blurRadius: 80,
                                    spreadRadius: 8,
                                  ),
                                  BoxShadow(
                                    color: Color(0x0670F0FF),
                                    blurRadius: 120,
                                    spreadRadius: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Transform.rotate(
                            angle: _arc1Ctrl.value * 2 * math.pi,
                            child: CustomPaint(
                              size: Size(orbDiameter + 46, orbDiameter + 46),
                              painter: _NeonArcPainter(
                                startAngle: -math.pi * 0.78,
                                sweepAngle: math.pi * 1.12,
                                color: const Color(0xFF70F0FF),
                                strokeWidth: 2.2,
                                glowWidth: 9.0,
                              ),
                            ),
                          ),
                          Transform.rotate(
                            angle: -_arc2Ctrl.value * 2 * math.pi,
                            child: CustomPaint(
                              size: Size(orbDiameter + 70, orbDiameter + 70),
                              painter: _NeonArcPainter(
                                startAngle: math.pi * 0.18,
                                sweepAngle: math.pi * 0.82,
                                color: const Color(0xFF70F0FF),
                                strokeWidth: 1.6,
                                glowWidth: 6.5,
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
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  Audio amplitude envelope, baked from welcome_instructions.mp3
  //  Each value is normalized RMS amplitude (0..1) for a 60ms window.
  //  Total duration: ~31.1s, 519 keyframes.
  //  If you re-record the audio, regenerate this list.
  // ─────────────────────────────────────────────────────────────────

  static const int _binMs = 60;

  static const List<double> _intensities = [
  0.004, 0.137, 0.470, 0.766, 0.686, 0.436, 0.300, 0.493, 0.744, 0.888,
  0.871, 0.815, 0.565, 0.557, 0.437, 0.427, 0.471, 0.472, 0.586, 0.654,
  0.605, 0.747, 0.659, 0.710, 0.544, 0.397, 0.272, 0.137, 0.040, 0.005,
  0.002, 0.000, 0.000, 0.000, 0.000, 0.002, 0.005, 0.040, 0.363, 0.377,
  0.514, 0.523, 0.792, 0.630, 0.500, 0.547, 0.766, 0.769, 0.586, 0.372,
  0.360, 0.519, 0.783, 0.901, 0.853, 0.825, 0.841, 0.677, 0.443, 0.397,
  0.429, 0.671, 0.557, 0.713, 0.470, 0.635, 0.506, 0.790, 0.602, 0.617,
  0.366, 0.253, 0.281, 0.417, 0.460, 0.560, 0.628, 0.571, 0.556, 0.560,
  0.565, 0.454, 0.439, 0.465, 0.303, 0.393, 0.548, 0.839, 0.652, 0.509,
  0.540, 0.727, 0.971, 0.850, 0.624, 0.541, 0.442, 0.455, 0.437, 0.337,
  0.470, 0.485, 0.635, 0.499, 0.378, 0.325, 0.285, 0.279, 0.249, 0.390,
  0.404, 0.545, 0.482, 0.388, 0.485, 0.482, 0.786, 0.590, 0.639, 0.502,
  0.705, 0.834, 0.959, 0.807, 0.486, 0.294, 0.334, 0.336, 0.239, 0.295,
  0.512, 0.557, 0.442, 0.383, 0.454, 0.355, 0.300, 0.418, 0.378, 0.405,
  0.170, 0.383, 0.264, 0.388, 0.240, 0.277, 0.248, 0.226, 0.172, 0.076,
  0.021, 0.017, 0.005, 0.002, 0.000, 0.000, 0.000, 0.000, 0.002, 0.005,
  0.009, 0.220, 0.550, 0.814, 0.628, 0.483, 0.549, 0.660, 0.787, 0.664,
  0.543, 0.429, 0.239, 0.242, 0.235, 0.547, 0.691, 0.523, 0.523, 0.587,
  0.709, 0.382, 0.325, 0.326, 0.587, 0.630, 0.693, 0.759, 0.579, 0.539,
  0.486, 0.621, 0.666, 0.600, 0.624, 0.547, 0.477, 0.319, 0.425, 0.582,
  0.702, 0.779, 0.638, 0.731, 0.502, 0.414, 0.451, 0.630, 0.826, 0.713,
  0.505, 0.238, 0.073, 0.011, 0.037, 0.266, 0.399, 0.555, 0.387, 0.289,
  0.338, 0.607, 0.788, 0.790, 0.562, 0.524, 0.462, 0.382, 0.465, 0.303,
  0.421, 0.477, 0.566, 0.673, 0.647, 0.838, 0.897, 0.683, 0.537, 0.353,
  0.286, 0.257, 0.253, 0.314, 0.203, 0.085, 0.011, 0.003, 0.000, 0.000,
  0.000, 0.000, 0.001, 0.004, 0.009, 0.153, 0.451, 0.470, 0.363, 0.334,
  0.314, 0.525, 0.587, 0.624, 0.607, 0.315, 0.287, 0.342, 0.634, 0.825,
  0.815, 0.711, 0.693, 0.600, 0.471, 0.287, 0.105, 0.008, 0.327, 0.499,
  0.753, 0.764, 0.611, 0.385, 0.362, 0.655, 0.940, 0.863, 0.763, 0.466,
  0.299, 0.363, 0.468, 0.414, 0.239, 0.290, 0.443, 0.638, 0.790, 0.775,
  0.682, 0.381, 0.235, 0.034, 0.009, 0.010, 0.341, 0.622, 0.865, 0.823,
  0.705, 0.745, 0.555, 0.537, 0.346, 0.268, 0.454, 0.658, 0.868, 0.692,
  0.555, 0.475, 0.333, 0.177, 0.269, 0.270, 0.317, 0.292, 0.289, 0.457,
  0.401, 0.565, 0.473, 0.492, 0.491, 0.379, 0.363, 0.502, 0.744, 0.863,
  0.557, 0.578, 0.518, 0.773, 0.700, 0.754, 0.505, 0.412, 0.329, 0.571,
  0.572, 0.383, 0.297, 0.273, 0.286, 0.164, 0.299, 0.439, 0.541, 0.432,
  0.373, 0.246, 0.131, 0.028, 0.002, 0.000, 0.000, 0.000, 0.000, 0.001,
  0.004, 0.225, 0.557, 0.684, 0.639, 0.528, 0.583, 0.566, 0.617, 0.680,
  0.717, 0.586, 0.510, 0.339, 0.369, 0.303, 0.408, 0.473, 0.378, 0.433,
  0.529, 0.768, 0.840, 0.765, 0.586, 0.459, 0.533, 0.796, 0.882, 0.840,
  0.676, 0.636, 0.495, 0.338, 0.370, 0.450, 0.595, 0.650, 0.753, 0.828,
  0.762, 0.650, 0.453, 0.261, 0.058, 0.278, 0.472, 0.570, 0.462, 0.391,
  0.376, 0.278, 0.153, 0.054, 0.005, 0.001, 0.000, 0.000, 0.000, 0.000,
  0.000, 0.000, 0.000, 0.004, 0.008, 0.222, 0.551, 0.568, 0.501, 0.406,
  0.544, 0.407, 0.183, 0.277, 0.553, 0.654, 0.654, 0.613, 0.713, 0.611,
  0.547, 0.374, 0.374, 0.527, 0.817, 0.992, 0.970, 0.702, 0.569, 0.392,
  0.348, 0.357, 0.516, 0.544, 0.523, 0.491, 0.507, 0.632, 0.614, 0.748,
  0.607, 0.504, 0.363, 0.319, 0.260, 0.240, 0.366, 0.605, 0.805, 0.843,
  0.600, 0.546, 0.462, 0.673, 0.676, 0.481, 0.373, 0.202, 0.232, 0.179,
  0.361, 0.373, 0.516, 0.478, 0.460, 0.217, 0.107, 0.331, 0.566, 0.723,
  0.638, 0.541, 0.367, 0.212, 0.370, 0.481, 0.470, 0.323, 0.499, 0.790,
  0.817, 0.661, 0.474, 0.385, 0.230, 0.127, 0.012, 0.007, 0.005,
  ];
}

class _GlassOrb extends StatelessWidget {
  const _GlassOrb({required this.diameter});
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x991E5FFF),
            blurRadius: 45,
            spreadRadius: 5,
          ),
          BoxShadow(
            color: Color(0x4700B8FF),
            blurRadius: 80,
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
              left: diameter * 0.12,
              right: diameter * 0.12,
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
  final Color color;
  final double strokeWidth;
  final double glowWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide / 2) - glowWidth;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = color.withOpacity(0.38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = glowWidth
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _NeonArcPainter old) => false;
}