import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:gp_hudai/app/app_routes.dart';
import 'package:gp_hudai/features/setup/setup_controller.dart';

/// Setup screen — UI only.
///
/// Interaction rules:
///   - Single tap → start voice flow (or stop mic if listening, or retry
///     when in awaitingSave)
///   - Double tap → switch to manual (silent) mode (or save+navigate when
///     in awaitingSave)
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
      Navigator.pushReplacementNamed(context, AppRoutes.camera);
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
    Navigator.pushReplacementNamed(context, AppRoutes.camera);
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
  // Voice mode — full-screen tap zone
  // ───────────────────────────────────────────────────────────────────
  Widget _buildVoiceMode() {
    return GestureDetector(
      key: const ValueKey('voice'),
      behavior: HitTestBehavior.opaque,
      onTap: _controller.onSingleTap,
      onDoubleTap: _controller.onDoubleTap,
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
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              'اضغط ضغطة واحدة لبدء التحدث، وضغطة اخرى للايقاف. ضغطتين للإدخال اليدوي',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 14,
                height: 1.5,
              ),
            ),

            const Spacer(),

            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final t = _controller.isListening ? _pulse.value : 0.0;
                return _MicOrb(
                  pulse: t,
                  listening: _controller.isListening,
                  dim: _controller.stage == SetupStage.intro,
                );
              },
            ),

            const SizedBox(height: 32),

            Text(
              _controller.statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 18),

            // Live recognition feedback:
            //   - while listening → show raw heard text
            //   - confirming/awaitingSave/saving → show the parsed digits
            Builder(
              builder: (_) {
                final showLive =
                    _controller.stage == SetupStage.listening &&
                    _controller.heardText.isNotEmpty;
                final showFinal =
                    _controller.recognizedNumber.isNotEmpty &&
                    (_controller.stage == SetupStage.confirming ||
                        _controller.stage == SetupStage.awaitingSave ||
                        _controller.stage == SetupStage.saving);
                if (!showLive && !showFinal) return const SizedBox.shrink();

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.20)),
                  ),
                  child: Text(
                    showFinal
                        ? _controller.recognizedNumber
                        : _controller.heardText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: showFinal
                          ? const Color(0xFF40E0FF)
                          : Colors.white.withOpacity(0.85),
                      fontSize: showFinal ? 22 : 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: showFinal ? 2.5 : 0.5,
                    ),
                  ),
                );
              },
            ),

            const Spacer(),
          ],
        ),
      ),
    );
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
//  Mic orb — pulses while listening, dimmed during intro
// ─────────────────────────────────────────────────────────────────────────────

class _MicOrb extends StatelessWidget {
  const _MicOrb({
    required this.pulse,
    required this.listening,
    required this.dim,
  });

  final double pulse;
  final bool listening;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final glow = 0.35 + pulse * 0.45;
    final scale = 1.0 + pulse * 0.10;
    return Opacity(
      opacity: dim ? 0.4 : 1.0,
      child: SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (listening)
              Container(
                width: 220 * scale,
                height: 220 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(
                    0xFF40E0FF,
                  ).withOpacity(0.10 + pulse * 0.10),
                ),
              ),
            Container(
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
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: const Color(0xFF00CFFF).withOpacity(glow * 0.5),
                    blurRadius: 70,
                    spreadRadius: 12,
                  ),
                ],
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 64),
            ),
          ],
        ),
      ),
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
