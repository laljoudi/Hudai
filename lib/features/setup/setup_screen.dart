import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:gp_hudai/app/app_routes.dart';
import 'package:gp_hudai/features/setup/setup_controller.dart';

/// Setup screen — UI only.
///
/// Interaction rules:
///   - Single tap → start voice flow (or stop mic if listening, or retry
///     when in awaitingSave)
///   - Double tap → switch to manual (silent) keyboard mode
///   - Long press → save + navigate (only meaningful in awaitingSave)
///   - Taps are ignored while the intro audio is playing
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emergencyController = TextEditingController();
  late final SetupController _controller;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _controller = SetupController();
    _controller.addListener(_onControllerUpdate);
    _controller.initialize();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _emergencyController.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (!mounted) return;

    if (_controller.shouldNavigate) {
      _controller.clearNavigationFlag();
      _navigateToCamera();
      return;
    }

    setState(() {});
  }

  // ───────────────────────────────────────────────────────────────────
  // Manual save handler — UI side because navigation needs context.
  // ───────────────────────────────────────────────────────────────────
  Future<void> _onManualSave() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await _controller.saveManualNumber(_emergencyController.text);
    if (!mounted || !ok) return;
    _navigateToCamera();
  }

  /// Returns the user to the Camera screen after a successful save.
  ///
  /// Two entry paths reach this code:
  ///   - First-time flow: Splash → VoiceInstructions → Setup. No Camera
  ///     route exists yet, so we push-replace into one.
  ///   - Settings flow:   Camera → Settings → Setup. A Camera route is
  ///     already underneath us; pop the stack back to it so we don't
  ///     stack a second Camera instance on top (which would re-init the
  ///     camera, reload the model, and replay the intro). Popping
  ///     Settings also resolves CameraScreen's awaited pushNamed and
  ///     triggers `resumeFromSettings()` on the original CameraController.
  void _navigateToCamera() {
    debugPrint('🧭 _navigateToCamera() called');
    final navigator = Navigator.of(context);

    bool cameraInStack = false;
    navigator.popUntil((route) {
      final name = route.settings.name ?? '<unnamed>';
      if (route.settings.name == AppRoutes.camera) {
        cameraInStack = true;
        debugPrint('🧭   → found camera at "$name", stopping pop');
        return true;
      }
      if (route.isFirst) {
        debugPrint('🧭   → bottom reached at "$name", stopping pop');
        return true;
      }
      debugPrint('🧭   → popping "$name"');
      return false;
    });

    if (!cameraInStack) {
      debugPrint('🧭   → no Camera in stack, pushReplacement(/camera)');
      navigator.pushReplacementNamed(AppRoutes.camera);
    } else {
      debugPrint('🧭   → reused existing Camera, no new instance created');
    }
  }

  // ───────────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030A20),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _Background(),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: _controller.isManual
                  ? _buildManualMode()
                  : _buildVoiceMode(),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────
  // Voice mode — audio-first. The only persistent visible elements are:
  //   - the page title at the top
  //   - one (and only one) mic button in the centre
  //   - three animated dots BELOW the mic while the system is busy
  // No status text, no instructions, no recognition chip — all spoken.
  // ───────────────────────────────────────────────────────────────────
  Widget _buildVoiceMode() {
    return GestureDetector(
      key: const ValueKey('voice'),
      behavior: HitTestBehavior.opaque,
      onTap: _controller.onSingleTap,
      onDoubleTap: _controller.onDoubleTap,
      onLongPress: _controller.onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          children: [
            const SizedBox(height: 70),

            const Text(
              'رقم الطوارئ',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'IBMPlexSansArabic',
                fontWeight: FontWeight.w400,
                fontSize: 32,
                letterSpacing: -0.5,
              ),
            ),

            const Spacer(),

            // The mic — always visible, never duplicated, never dimmed.
            // (Intro stage uses the same rendering as idle so the screen
            // looks "ready" the moment it opens, while the intro audio
            // plays in the background.)
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final t = _controller.isListening ? _pulse.value : 0.0;
                return _MicOrb(
                  pulse: t,
                  listening: _controller.isListening,
                );
              },
            ),

            const SizedBox(height: 28),

            // Under-mic area:
            //   - While listening with partial speech → chip showing what
            //     was just heard, so the user (or sighted helper) can
            //     visually verify the digits in real time.
            //   - After parsing → chip with the formatted final number.
            //   - Busy with nothing to show → small white loading dots.
            //   - Otherwise → empty.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _buildSubMic(),
            ),

            const Spacer(),
          ],
        ),
      ),
    );
  }

  /// Picks what to render directly under the mic:
  ///   - `listening` with non-empty partial → live chip
  ///   - `confirming` / `awaitingSave` / `saving` with a recognised number
  ///     → final chip (formatted "050 017 0709")
  ///   - `processing` / `invalid` (or saving with no number) → dots
  ///   - otherwise → empty
  Widget _buildSubMic() {
    final stage = _controller.stage;
    final heard = _controller.heardText;
    final recognized = _controller.recognizedNumber;

    if (stage == SetupStage.listening && heard.isNotEmpty) {
      return _NumberChip(
        key: const ValueKey('chip-live'),
        text: heard,
        isFinal: false,
      );
    }

    final hasFinal = recognized.isNotEmpty &&
        (stage == SetupStage.confirming ||
            stage == SetupStage.awaitingSave ||
            stage == SetupStage.saving);
    if (hasFinal) {
      return _NumberChip(
        key: const ValueKey('chip-final'),
        text: _formatSaudiNumber(recognized),
        isFinal: true,
      );
    }

    final isBusy = stage == SetupStage.processing ||
        stage == SetupStage.invalid ||
        stage == SetupStage.saving;
    if (isBusy) {
      return const _ProcessingDots(key: ValueKey('dots'));
    }

    return const SizedBox.shrink(key: ValueKey('empty'));
  }

  /// Formats a 10-digit Saudi mobile number as "050 017 0709".
  /// Falls back to the raw input if it isn't exactly 10 digits.
  static String _formatSaudiNumber(String digits) {
    if (digits.length != 10) return digits;
    return '${digits.substring(0, 3)} '
        '${digits.substring(3, 6)} '
        '${digits.substring(6)}';
  }

  // ───────────────────────────────────────────────────────────────────
  // Manual mode — completely silent
  // ───────────────────────────────────────────────────────────────────
  Widget _buildManualMode() {
    return Padding(
      key: const ValueKey('manual'),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 70),

            const Text(
              'رقم الطوارئ',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              'يرجى إدخال رقم هاتف يدويًا.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 14,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 50),

            _GlassyTextField(
              controller: _emergencyController,
              validator: _controller.validateManualNumber,
            ),

            const SizedBox(height: 30),

            _GlowingSaveButton(
              saving: _controller.stage == SetupStage.saving,
              onTap: _onManualSave,
            ),

            const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Background gradient — same as the voice instructions screen
// ─────────────────────────────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  const _Background();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Mic orb — a SINGLE circular button. The listening "pulse" is rendered as
//  an animated outer glow (boxShadow), not as a second concentric circle, so
//  the user always sees exactly one button on screen.
// ─────────────────────────────────────────────────────────────────────────────

class _MicOrb extends StatelessWidget {
  const _MicOrb({
    required this.pulse,
    required this.listening,
  });

  final double pulse;   // 0.0 (resting) ─→ 1.0 (peak of listening pulse)
  final bool   listening;

  @override
  Widget build(BuildContext context) {
    // Base glow when idle, intensified while listening.
    final base = listening ? 0.45 : 0.30;
    final glow = base + pulse * 0.45;

    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF40E0FF), Color(0xFF1855FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1855FF).withOpacity(glow),
            blurRadius: 40 + pulse * 18,
            spreadRadius: 4 + pulse * 6,
          ),
          BoxShadow(
            color: const Color(0xFF00CFFF).withOpacity(glow * 0.5),
            blurRadius: 70 + pulse * 24,
            spreadRadius: 12 + pulse * 8,
          ),
        ],
      ),
      child: const Icon(Icons.mic, color: Colors.white, size: 64),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Number chip — glassy rounded box that shows either the partial speech
//  text (while listening) or the final formatted number (after parsing).
// ─────────────────────────────────────────────────────────────────────────────

class _NumberChip extends StatelessWidget {
  const _NumberChip({
    super.key,
    required this.text,
    required this.isFinal,
  });

  final String text;
  final bool isFinal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: isFinal ? Colors.white : Colors.white.withOpacity(0.85),
          fontSize: isFinal ? 24 : 18,
          fontWeight: FontWeight.w700,
          letterSpacing: isFinal ? 2.0 : 0.5,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Processing dots — shown while the system is busy and there is nothing
//  meaningful to display in the chip (e.g. processing/invalid).
//  Loop is . → .. → ... → repeat.
// ─────────────────────────────────────────────────────────────────────────────

class _ProcessingDots extends StatefulWidget {
  const _ProcessingDots({super.key});

  @override
  State<_ProcessingDots> createState() => _ProcessingDotsState();
}

class _ProcessingDotsState extends State<_ProcessingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final step = (_ctrl.value * 3).floor().clamp(0, 2);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final on = i <= step;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on
                      ? Colors.white
                      : Colors.white.withOpacity(0.20),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Glassy text field (manual mode)
// ─────────────────────────────────────────────────────────────────────────────

class _GlassyTextField extends StatelessWidget {
  const _GlassyTextField({required this.controller, required this.validator});
  final TextEditingController controller;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.phone,
            textAlign: TextAlign.center,
            cursorColor: const Color(0xFF40E0FF),
            validator: validator,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 22,
                horizontal: 16,
              ),
              hintText: '+966',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.30),
                fontSize: 18,
              ),
              errorStyle: const TextStyle(
                color: Color(0xFFFF8A8A),
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Glowing save button (manual mode)
// ─────────────────────────────────────────────────────────────────────────────

class _GlowingSaveButton extends StatelessWidget {
  const _GlowingSaveButton({required this.saving, required this.onTap});
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: saving ? null : onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          gradient: const LinearGradient(
            colors: [Color(0xFF40E0FF), Color(0xFF1855FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1855FF).withOpacity(0.55),
              blurRadius: 32,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: const Color(0xFF00CFFF).withOpacity(0.30),
              blurRadius: 60,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Center(
          child: saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'حفظ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}
