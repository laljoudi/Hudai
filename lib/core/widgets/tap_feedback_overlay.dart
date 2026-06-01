import 'package:flutter/material.dart';

import 'package:gp_hudai/core/constants/tap_feedback_config.dart';

/// Wraps any tap zone and draws a brief **ripple + glow** at the touch point.
///
/// This is a demo-only visual aid for recording videos — the app itself is
/// audio-first and built for blind users. The effect is gated behind
/// [kShowTapFeedback]; when that flag is `false` the wrapper returns its [child]
/// unchanged.
///
/// Behaviour is deliberately preserved: the effect is driven by a [Listener]
/// on pointer-down, which never joins the gesture arena. The child's own
/// `GestureDetector` (onTap / onDoubleTap / onLongPress) therefore keeps
/// receiving every event exactly as before — this overlay is purely visual.
class TapFeedbackOverlay extends StatefulWidget {
  const TapFeedbackOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<TapFeedbackOverlay> createState() => _TapFeedbackOverlayState();
}

class _TapFeedbackOverlayState extends State<TapFeedbackOverlay>
    with TickerProviderStateMixin {
  final List<_Pulse> _pulses = [];

  void _spawn(Offset position) {
    final controller = AnimationController(
      vsync: this,
      duration: kTapFeedbackDuration,
    );
    final pulse = _Pulse(position: position, controller: controller);
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
        if (mounted) setState(() => _pulses.remove(pulse));
      }
    });
    setState(() => _pulses.add(pulse));
    controller.forward();
  }

  @override
  void dispose() {
    for (final pulse in _pulses) {
      pulse.controller.dispose();
    }
    _pulses.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kShowTapFeedback) return widget.child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _spawn(event.localPosition),
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _TapFeedbackPainter(
                  _pulses,
                  const Color(kTapFeedbackColorValue),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pulse {
  _Pulse({required this.position, required this.controller});

  final Offset position;
  final AnimationController controller;
}

class _TapFeedbackPainter extends CustomPainter {
  _TapFeedbackPainter(this._pulses, this._accent) : super(repaint: null);

  final List<_Pulse> _pulses;
  final Color _accent;

  static const double _maxRippleRadius = 90;
  static const double _maxGlowRadius = 64;

  @override
  void paint(Canvas canvas, Size size) {
    for (final pulse in _pulses) {
      final t = pulse.controller.value; // 0 → 1

      // ── Glow: a soft halo that fades in then out within the duration. ──
      // sin(pi * t) peaks at the midpoint (~140ms) and returns to 0.
      final glowFade = _glowCurve(t);
      if (glowFade > 0) {
        final glowRadius = _maxGlowRadius * (0.6 + 0.4 * t);
        final glowPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              _accent.withOpacity(0.70 * glowFade),
              _accent.withOpacity(0.0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(
            Rect.fromCircle(center: pulse.position, radius: glowRadius),
          )
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pulse.position, glowRadius, glowPaint);
      }

      // ── Ripple: an expanding ring that fades as it grows outward. ──
      final rippleT = Curves.easeOut.transform(t);
      final rippleRadius = _maxRippleRadius * rippleT;
      final rippleOpacity = (1.0 - t) * 0.60;
      if (rippleOpacity > 0 && rippleRadius > 0) {
        final ringPaint = Paint()
          ..color = _accent.withOpacity(rippleOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1.0 - t) + 1.0;
        canvas.drawCircle(pulse.position, rippleRadius, ringPaint);
      }
    }
  }

  /// Fade-in/out envelope for the glow, peaking mid-animation.
  double _glowCurve(double t) {
    // A symmetric ease that rises then falls; clamps the tails to 0.
    final v = (t <= 0.5)
        ? Curves.easeIn.transform(t / 0.5)
        : Curves.easeOut.transform((1.0 - t) / 0.5);
    return v.clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(_TapFeedbackPainter oldDelegate) => true;
}
