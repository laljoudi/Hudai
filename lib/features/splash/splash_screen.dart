import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gp_hudai/app/app_routes.dart';
import 'package:gp_hudai/core/storage/prefs.dart';
// ============================================================
// PERFORMANCE TEST [PT-03] — START
// Purpose: Import PerfMarkers to start the post-splash stopwatch
// Remove this block after testing is complete
// ============================================================
import 'package:gp_hudai/core/utils/perf_markers.dart';
// ============================================================
// PERFORMANCE TEST [PT-03] — END
// ============================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  Timer? _navigateTimer;

  /// Kicked off in initState so the SharedPreferences read overlaps with
  /// the 6-second intro animation. By the time the timer fires this is
  /// almost always already resolved.
  late final Future<bool> _hasSavedNumberFuture;

  // Body (white figure) fade-in
  late AnimationController _bodyCtrl;
  late Animation<double> _bodyOpacity;

  // Wave 1 – small/blue  → first
  late AnimationController _w1Ctrl;
  late Animation<double> _w1Progress;

  // Wave 2 – medium/gradient → second
  late AnimationController _w2Ctrl;
  late Animation<double> _w2Progress;

  // Wave 3 – large/cyan → third
  late AnimationController _w3Ctrl;
  late Animation<double> _w3Progress;

  // Text fade-in
  late AnimationController _textCtrl;
  late Animation<double> _textOpacity;

  @override
  void initState() {
    super.initState();

    _bodyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _bodyOpacity = CurvedAnimation(parent: _bodyCtrl, curve: Curves.easeIn);

    _w1Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _w1Progress = CurvedAnimation(parent: _w1Ctrl, curve: Curves.easeInOut);

    _w2Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _w2Progress = CurvedAnimation(parent: _w2Ctrl, curve: Curves.easeInOut);

    _w3Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _w3Progress = CurvedAnimation(parent: _w3Ctrl, curve: Curves.easeInOut);

    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _textOpacity = CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn);

    _startSequence();

    // Start the prefs check immediately so it overlaps with the animation.
    _hasSavedNumberFuture = Prefs.hasValidEmergencyNumber();

    // Navigate after the intro animation. The destination depends on
    // whether a valid emergency number is already saved.
    _navigateTimer = Timer(const Duration(milliseconds: 6000), _decideNextRoute);
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    _bodyCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    _w1Ctrl.forward();

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _w2Ctrl.forward();

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _w3Ctrl.forward();

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _textCtrl.forward();
  }

  @override
  void dispose() {
    _navigateTimer?.cancel();
    _bodyCtrl.dispose();
    _w1Ctrl.dispose();
    _w2Ctrl.dispose();
    _w3Ctrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  /// First launch (no valid saved number)  → Voice Instructions → Setup → Camera.
  /// Later launches (valid number stored) → Camera directly.
  Future<void> _decideNextRoute() async {
    if (!mounted) return;

    bool hasSaved;
    try {
      hasSaved = await _hasSavedNumberFuture;
    } catch (e) {
      debugPrint('🚨 splash: prefs read failed, falling back to onboarding: $e');
      hasSaved = false;
    }
    if (!mounted) return;

    final route = hasSaved ? AppRoutes.camera : AppRoutes.voiceInstructions;
    debugPrint('🧭 splash → $route (hasSavedNumber=$hasSaved)');
    // ============================================================
    // PERFORMANCE TEST [PT-03] — START
    // Purpose: Mark splash dismissal so post-splash init time can be measured
    // Remove this block after testing is complete
    // ============================================================
    PerfMarkers.postSplashWatch.start();
    debugPrint('[PT-03] Splash dismissed — stopwatch started');
    // ============================================================
    // PERFORMANCE TEST [PT-03] — END
    // ============================================================
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.5, 0.75, 1.0],
            colors: [
              Color(0xFF030A20),
              Color(0xFF071540),
              Color(0xFF0E2360),
              Color(0xFF1A3A8A),
            ],
          ),
        ),
        child: Stack(
          children: [
            // ── Logo + Text centered ──
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 150,
                    height: 121,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _bodyOpacity,
                        _w1Progress,
                        _w2Progress,
                        _w3Progress,
                      ]),
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _HdayLogoPainter(
                            bodyOpacity: _bodyOpacity.value,
                            w1Progress: _w1Progress.value,
                            w2Progress: _w2Progress.value,
                            w3Progress: _w3Progress.value,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 36),
                  FadeTransition(
                    opacity: _textOpacity,
                    child: const Column(
                      children: [
                        Text(
                          'هُــداي',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 4,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'هُــداي، هًداك لأداء النسك',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: Color(0xBFA0D2FF),
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Version pinned to bottom ──
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _textOpacity,
                child: const Text(
                  'v1.0.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0x66FFFFFF),
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Painter (private to this file)
// ─────────────────────────────────────────────
class _HdayLogoPainter extends CustomPainter {
  final double bodyOpacity;
  final double w1Progress;
  final double w2Progress;
  final double w3Progress;

  const _HdayLogoPainter({
    required this.bodyOpacity,
    required this.w1Progress,
    required this.w2Progress,
    required this.w3Progress,
  });

  static const double _svgW = 597;
  static const double _svgH = 483;

  @override
  void paint(Canvas canvas, Size size) {
    final double sx = size.width / _svgW;
    final double sy = size.height / _svgH;
    canvas.scale(sx, sy);

    _drawBody(canvas);
    _drawWave1(canvas);
    _drawWave2(canvas);
    _drawWave3(canvas);
  }

  void _clipTopToBottom(Canvas canvas, double progress) {
    canvas.clipRect(Rect.fromLTWH(0, 0, _svgW, _svgH * progress));
  }

  void _drawBody(Canvas canvas) {
    if (bodyOpacity <= 0) return;
    final paint = Paint()
      ..color = Colors.white.withOpacity(bodyOpacity)
      ..style = PaintingStyle.fill;

    // Path 1 – main figure
    final p1 = Path()..fillType = PathFillType.evenOdd;
    p1.moveTo(18.89, 482.198);
    p1.cubicTo(17.2876, 481.828, 11.9873, 481.705, 9.02898, 479.733);
    p1.cubicTo(6.07068, 477.761, 2.3728, 473.447, 1.01692, 470.488);
    p1.cubicTo(-0.338972, 467.53, -0.338972, 464.818, 1.01692, 461.86);
    p1.cubicTo(2.3728, 458.902, 1.75649, 455.45, 9.02898, 452.615);
    p1.cubicTo(16.3015, 449.78, 33.435, 448.548, 44.7751, 445.219);
    p1.cubicTo(56.1153, 441.891, 67.8252, 436.838, 76.8234, 432.893);
    p1.cubicTo(85.8215, 428.949, 89.1496, 427.963, 99.0106, 421.8);
    p1.cubicTo(108.872, 415.636, 125.882, 404.173, 135.989, 395.914);
    p1.cubicTo(146.097, 387.656, 154.602, 377.795, 160.026, 371.878);
    p1.cubicTo(165.449, 365.962, 163.723, 368.55, 168.654, 360.785);
    p1.cubicTo(173.584, 353.019, 184.062, 336.379, 189.609, 325.038);
    p1.cubicTo(195.155, 313.698, 198.483, 303.837, 201.935, 292.99);
    p1.cubicTo(205.386, 282.143, 207.851, 272.898, 210.563, 259.709);
    p1.cubicTo(213.275, 246.52, 215.247, 226.798, 217.959, 214.102);
    p1.cubicTo(220.671, 201.406, 223.259, 192.285, 226.587, 183.287);
    p1.cubicTo(229.915, 174.288, 233.367, 167.016, 237.681, 159.867);
    p1.cubicTo(241.995, 152.717, 245.94, 146.554, 252.472, 140.145);
    p1.cubicTo(259.005, 133.735, 270.469, 125.23, 276.509, 121.039);
    p1.cubicTo(282.549, 116.848, 283.658, 116.725, 288.835, 114.876);
    p1.cubicTo(294.012, 113.027, 300.915, 110.931, 307.324, 109.945);
    p1.cubicTo(313.734, 108.959, 321.253, 108.466, 327.046, 108.713);
    p1.cubicTo(332.84, 108.959, 335.428, 108.959, 341.838, 111.178);
    p1.cubicTo(348.247, 113.397, 358.355, 116.971, 365.258, 122.272);
    p1.cubicTo(372.16, 127.572, 379.063, 136.94, 383.131, 142.61);
    p1.cubicTo(387.198, 148.28, 387.815, 152.101, 389.294, 156.169);
    p1.cubicTo(390.773, 160.236, 391.389, 162.332, 391.759, 167.262);
    p1.cubicTo(392.129, 172.193, 392.129, 180.575, 391.759, 185.752);
    p1.cubicTo(391.389, 190.929, 391.513, 192.285, 389.294, 198.078);
    p1.cubicTo(387.075, 203.871, 380.542, 216.074, 378.2, 220.265);
    p1.cubicTo(375.858, 224.456, 376.228, 222.854, 375.119, 223.347);
    p1.cubicTo(374.009, 223.84, 372.53, 223.84, 371.421, 223.347);
    p1.cubicTo(370.311, 222.854, 368.832, 226.552, 368.339, 220.265);
    p1.cubicTo(367.846, 213.979, 369.572, 194.134, 368.339, 185.752);
    p1.cubicTo(367.107, 177.37, 363.902, 174.165, 360.944, 169.728);
    p1.cubicTo(357.985, 165.29, 354.411, 162.085, 350.466, 159.25);
    p1.cubicTo(346.522, 156.415, 341.468, 154.32, 336.907, 153.087);
    p1.cubicTo(332.347, 151.855, 327.663, 151.608, 323.348, 151.855);
    p1.cubicTo(319.034, 152.101, 315.09, 152.841, 311.022, 154.32);
    p1.cubicTo(306.955, 155.799, 303.503, 156.908, 298.696, 160.483);
    p1.cubicTo(293.889, 164.058, 286.863, 169.604, 282.055, 175.891);
    p1.cubicTo(277.248, 182.177, 272.811, 190.929, 269.729, 198.078);
    p1.cubicTo(266.648, 205.227, 266.894, 203.871, 263.566, 219.033);
    p1.cubicTo(260.238, 234.194, 254.938, 270.187, 250.007, 289.292);
    p1.cubicTo(245.077, 308.398, 239.53, 320.971, 233.983, 333.667);
    p1.cubicTo(228.436, 346.363, 223.752, 354.991, 216.726, 365.715);
    p1.cubicTo(209.7, 376.439, 200.209, 388.642, 192.074, 397.763);
    p1.cubicTo(183.939, 406.885, 174.447, 414.897, 168.038, 420.567);
    p1.cubicTo(161.628, 426.237, 159.656, 427.346, 153.246, 431.661);
    p1.cubicTo(146.836, 435.975, 137.838, 441.891, 129.826, 446.452);
    p1.cubicTo(121.814, 451.013, 115.651, 454.464, 105.174, 458.778);
    p1.cubicTo(94.6964, 463.093, 81.3841, 468.393, 66.9624, 472.337);
    p1.cubicTo(52.5407, 476.282, 26.902, 480.596, 18.89, 482.198);
    p1.close();
    canvas.drawPath(p1, paint);

    // Path 2 – second leg
    final p2 = Path()..fillType = PathFillType.evenOdd;
    p2.moveTo(265.415, 467.407);
    p2.cubicTo(264.306, 467.284, 256.047, 470.242, 258.636, 466.791);
    p2.cubicTo(261.224, 463.339, 274.906, 453.478, 280.823, 447.069);
    p2.cubicTo(286.74, 440.659, 290.438, 435.112, 294.382, 428.579);
    p2.cubicTo(298.326, 422.046, 301.778, 414.404, 304.243, 407.625);
    p2.cubicTo(306.708, 400.845, 308.187, 395.668, 309.173, 387.903);
    p2.cubicTo(310.16, 380.137, 310.653, 368.427, 310.406, 360.785);
    p2.cubicTo(310.16, 353.143, 310.16, 352.773, 307.941, 342.295);
    p2.cubicTo(305.722, 331.818, 298.943, 312.096, 296.847, 297.921);
    p2.cubicTo(294.752, 283.746, 294.998, 267.722, 295.615, 257.244);
    p2.cubicTo(296.231, 246.767, 298.203, 242.206, 300.545, 235.057);
    p2.cubicTo(302.887, 227.908, 307.941, 214.719, 309.79, 214.719);
    p2.cubicTo(311.639, 214.719, 310.036, 227.415, 311.639, 235.057);
    p2.cubicTo(313.241, 242.699, 313.118, 246.397, 319.034, 260.942);
    p2.cubicTo(324.951, 275.487, 341.591, 307.535, 347.385, 322.573);
    p2.cubicTo(353.178, 337.611, 352.562, 341.309, 353.548, 350.924);
    p2.cubicTo(354.534, 360.538, 354.534, 371.632, 353.548, 380.507);
    p2.cubicTo(352.562, 389.382, 349.604, 397.517, 347.385, 403.927);
    p2.cubicTo(345.166, 410.336, 344.55, 412.309, 339.989, 418.718);
    p2.cubicTo(335.428, 425.128, 327.17, 436.098, 319.651, 442.754);
    p2.cubicTo(312.132, 449.411, 303.996, 454.711, 294.998, 458.779);
    p2.cubicTo(286, 462.846, 270.346, 465.928, 265.415, 467.407);
    p2.close();
    canvas.drawPath(p2, paint);

    // Path 3 – head
    final p3 = Path()..fillType = PathFillType.evenOdd;
    p3.moveTo(340.605, 81.5951);
    p3.cubicTo(338.387, 81.5951, 332.223, 82.8277, 327.046, 81.5951);
    p3.cubicTo(321.869, 80.3624, 314.474, 77.1576, 309.79, 74.1993);
    p3.cubicTo(305.106, 71.241, 302.147, 68.1594, 299.312, 63.722);
    p3.cubicTo(296.477, 59.2845, 294.135, 52.8749, 293.149, 47.6979);
    p3.cubicTo(292.163, 42.5208, 292.163, 37.8369, 293.149, 32.9064);
    p3.cubicTo(294.135, 27.9759, 296.477, 22.3058, 299.312, 18.1149);
    p3.cubicTo(302.147, 13.9239, 305.845, 10.4726, 309.79, 7.63753);
    p3.cubicTo(313.734, 4.8025, 318.665, 2.70703, 323.349, 1.47441);
    p3.cubicTo(328.033, 0.241782, 332.963, -0.37453, 338.14, 0.241782);
    p3.cubicTo(343.317, 0.858095, 349.11, 2.21398, 354.164, 5.17228);
    p3.cubicTo(359.218, 8.13058, 365.011, 13.9239, 368.339, 18.1149);
    p3.cubicTo(371.667, 22.3058, 373.27, 26.3734, 374.503, 30.4411);
    p3.cubicTo(375.735, 34.5088, 376.598, 37.4671, 375.735, 42.7674);
    p3.cubicTo(374.872, 48.0676, 372.777, 57.0658, 369.572, 62.4894);
    p3.cubicTo(366.367, 67.9129, 361.437, 72.2271, 356.629, 75.4319);
    p3.cubicTo(351.822, 78.6368, 343.317, 80.609, 340.605, 81.5951);
    p3.close();
    canvas.drawPath(p3, paint);
  }

  void _drawWave1(Canvas canvas) {
    if (w1Progress <= 0) return;
    canvas.save();
    _clipTopToBottom(canvas, w1Progress);
    final paint = Paint()
      ..color = const Color(0xFF1855FF)
      ..style = PaintingStyle.fill;
    final path = Path()..fillType = PathFillType.evenOdd;
    path.moveTo(460.17, 187.601);
    path.cubicTo(459.183, 187.231, 455.979, 186.738, 454.006, 185.136);
    path.cubicTo(452.034, 183.533, 449.322, 180.698, 448.46, 178.356);
    path.cubicTo(447.597, 176.014, 446.98, 174.905, 448.46, 170.96);
    path.cubicTo(449.939, 167.016, 455.486, 161.962, 457.088, 154.936);
    path.cubicTo(458.69, 147.91, 458.937, 136.077, 458.321, 129.051);
    path.cubicTo(457.704, 122.025, 456.102, 118.327, 453.39, 113.027);
    path.cubicTo(450.678, 107.727, 444.145, 100.701, 442.297, 97.0028);
    path.cubicTo(440.448, 93.3049, 441.557, 92.8119, 442.297, 90.8397);
    path.cubicTo(443.036, 88.8675, 445.132, 86.6487, 446.611, 85.2929);
    path.cubicTo(448.09, 83.937, 449.076, 83.0741, 451.541, 82.8276);
    path.cubicTo(454.006, 82.5811, 458.197, 82.088, 461.402, 84.0602);
    path.cubicTo(464.607, 86.0324, 467.812, 90.3466, 470.647, 94.5376);
    path.cubicTo(473.482, 98.7285, 475.947, 103.782, 478.043, 109.329);
    path.cubicTo(480.138, 114.876, 482.11, 120.792, 482.973, 127.818);
    path.cubicTo(483.836, 134.844, 483.589, 144.829, 482.973, 151.238);
    path.cubicTo(482.357, 157.648, 481.124, 161.099, 479.275, 166.03);
    path.cubicTo(477.426, 170.96, 473.852, 177.616, 471.88, 180.821);
    path.cubicTo(469.907, 184.026, 469.538, 184.026, 467.565, 185.136);
    path.cubicTo(465.593, 186.245, 461.402, 187.231, 460.17, 187.601);
    path.close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _drawWave2(Canvas canvas) {
    if (w2Progress <= 0) return;
    canvas.save();
    _clipTopToBottom(canvas, w2Progress);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF40E0FF), Color(0xFF1855FF)],
      ).createShader(const Rect.fromLTWH(511.095, 40.4912, 0, 185.704))
      ..style = PaintingStyle.fill;
    final path = Path()..fillType = PathFillType.evenOdd;
    path.moveTo(505.777, 225.812);
    path.cubicTo(504.914, 225.812, 503.065, 226.675, 500.846, 225.812);
    path.cubicTo(498.627, 224.949, 494.436, 222.977, 492.834, 220.265);
    path.cubicTo(491.232, 217.553, 489.999, 213.732, 491.601, 209.172);
    path.cubicTo(493.204, 204.611, 499.367, 199.311, 502.695, 193.147);
    path.cubicTo(506.023, 186.984, 509.228, 178.602, 511.323, 172.193);
    path.cubicTo(513.419, 165.783, 514.405, 162.702, 515.021, 154.936);
    path.cubicTo(515.638, 147.171, 516.5, 135.584, 515.021, 125.353);
    path.cubicTo(513.542, 115.122, 509.105, 101.07, 506.393, 93.3048);
    path.cubicTo(503.681, 85.5392, 502.695, 84.0601, 498.997, 78.5133);
    path.cubicTo(495.299, 72.9665, 487.041, 64.0916, 484.206, 60.0239);
    path.cubicTo(481.371, 55.9562, 481.74, 56.326, 481.74, 53.8608);
    path.cubicTo(481.74, 51.3955, 482.603, 47.4511, 484.206, 45.2324);
    path.cubicTo(485.808, 43.0137, 488.643, 41.6578, 490.985, 40.9182);
    path.cubicTo(493.327, 40.1786, 496.285, 40.5484, 498.381, 40.9182);
    path.cubicTo(500.476, 41.288, 499.49, 38.8227, 503.311, 43.3835);
    path.cubicTo(507.133, 47.9442, 515.884, 59.0378, 521.184, 68.6523);
    path.cubicTo(526.485, 78.2668, 531.662, 91.0861, 534.743, 100.701);
    path.cubicTo(537.825, 110.315, 538.811, 117.588, 539.674, 126.586);
    path.cubicTo(540.537, 135.584, 540.906, 144.829, 539.674, 154.936);
    path.cubicTo(538.441, 165.044, 536.222, 176.507, 532.278, 186.984);
    path.cubicTo(528.334, 197.462, 520.075, 211.514, 516.254, 217.8);
    path.cubicTo(512.433, 224.086, 511.2, 223.223, 509.475, 224.579);
    path.cubicTo(507.749, 225.935, 506.393, 225.565, 505.777, 225.812);
    path.close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _drawWave3(Canvas canvas) {
    if (w3Progress <= 0) return;
    canvas.save();
    _clipTopToBottom(canvas, w3Progress);
    final paint = Paint()
      ..color = const Color(0xFF40E0FF)
      ..style = PaintingStyle.fill;
    final path = Path()..fillType = PathFillType.evenOdd;
    path.moveTo(548.919, 262.791);
    path.cubicTo(547.686, 262.544, 543.495, 262.421, 541.523, 261.558);
    path.cubicTo(539.551, 260.695, 538.318, 259.463, 537.209, 257.244);
    path.cubicTo(536.099, 255.025, 532.525, 254.162, 534.743, 248.616);
    path.cubicTo(536.962, 243.069, 545.59, 234.071, 550.767, 223.963);
    path.cubicTo(555.944, 213.856, 562.108, 199.311, 565.559, 188.217);
    path.cubicTo(569.01, 177.123, 570.736, 167.879, 571.722, 157.401);
    path.cubicTo(572.708, 146.924, 572.708, 136.2, 571.722, 125.353);
    path.cubicTo(570.736, 114.506, 568.024, 101.563, 565.559, 92.0722);
    path.cubicTo(563.094, 82.581, 560.875, 77.0342, 556.931, 68.6523);
    path.cubicTo(552.986, 60.2705, 547.932, 50.5327, 542.139, 41.5346);
    path.cubicTo(536.346, 32.5364, 525.499, 20.2101, 522.417, 14.4168);
    path.cubicTo(519.335, 8.62346, 521.924, 9.36304, 523.65, 7.02105);
    path.cubicTo(525.375, 4.67906, 529.69, 0.981184, 532.894, 0.241609);
    path.cubicTo(536.099, -0.497966, 540.167, 1.35097, 542.755, 2.70686);
    path.cubicTo(545.344, 4.06275, 544.235, 3.07665, 548.302, 8.25367);
    path.cubicTo(552.37, 13.4307, 561.861, 26.3733, 566.792, 34.1388);
    path.cubicTo(571.722, 41.9043, 574.187, 46.7116, 577.885, 55.0934);
    path.cubicTo(581.583, 63.4753, 585.897, 72.3502, 588.979, 84.6764);
    path.cubicTo(592.06, 97.0027, 595.388, 115.739, 596.375, 129.051);
    path.cubicTo(597.361, 142.363, 597.237, 151.485, 595.142, 164.797);
    path.cubicTo(593.046, 178.109, 587.5, 198.078, 584.048, 209.172);
    path.cubicTo(580.597, 220.265, 577.639, 224.579, 574.187, 231.359);
    path.cubicTo(570.736, 238.138, 566.668, 244.794, 563.094, 249.848);
    path.cubicTo(559.519, 254.902, 554.958, 259.463, 552.616, 261.558);
    path.cubicTo(550.274, 263.654, 549.535, 262.544, 548.919, 262.791);
    path.close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HdayLogoPainter old) =>
      old.bodyOpacity != bodyOpacity ||
      old.w1Progress != w1Progress ||
      old.w2Progress != w2Progress ||
      old.w3Progress != w3Progress;
}