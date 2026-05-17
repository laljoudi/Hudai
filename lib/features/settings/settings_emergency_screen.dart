import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:gp_hudai/app/app_routes.dart';
import 'package:gp_hudai/features/settings/settings_emergency_controller.dart';

/// Settings → Edit-emergency-number screen.
///
/// Dedicated, standalone counterpart to [SetupScreen]. Looks and behaves
/// identically to the first-launch Setup, but owns its own controller,
/// audio player, and STT session — no shared mutable state.
///
/// Gestures:
///   - Single tap → start voice flow / stop mic / retry in awaitingSave
///   - Double tap → switch to silent manual keyboard mode
///   - Long press → save + pop back to the existing Camera (awaitingSave only)
class SettingsEmergencyScreen extends StatefulWidget {
  const SettingsEmergencyScreen({super.key});

  @override
  State<SettingsEmergencyScreen> createState() =>
      _SettingsEmergencyScreenState();
}

class _SettingsEmergencyScreenState extends State<SettingsEmergencyScreen>
    with SingleTickerProviderStateMixin {
  final _formKey             = GlobalKey<FormState>();
  final _emergencyController = TextEditingController();
  late final SettingsEmergencyController _controller;
  late final AnimationController         _pulse;

  @override
  void initState() {
    super.initState();
    _controller = SettingsEmergencyController();
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
      debugPrint('🧭 SE listener: shouldNavigate=true → scheduling pop');
      _controller.clearNavigationFlag();
      // Defer to the next frame so we don't pop while a build/listener
      // is still in flight (which can swallow the call on some devices).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _navigateToCamera();
      });
      return;
    }
    setState(() {});
  }

  Future<void> _onManualSave() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await _controller.saveManualNumber(_emergencyController.text);
    if (!mounted || !ok) return;
    _navigateToCamera();
  }

  /// Pops everything above the existing Camera route. Camera is always
  /// in the stack when this screen runs (Camera → Settings → here), so
  /// the predicate is guaranteed to find it.
  void _navigateToCamera() {
    debugPrint('🧭 SE _navigateToCamera() called');
    final navigator = Navigator.of(context);

    bool cameraFound = false;
    navigator.popUntil((route) {
      final name = route.settings.name ?? '<unnamed>';
      if (route.settings.name == AppRoutes.camera) {
        cameraFound = true;
        debugPrint('🧭 SE   → found camera, stopping pop');
        return true;
      }
      if (route.isFirst) {
        debugPrint('🧭 SE   → bottom reached at "$name", stopping pop');
        return true;
      }
      debugPrint('🧭 SE   → popping "$name"');
      return false;
    });

    if (!cameraFound) {
      debugPrint('🧭 SE   → no Camera, pushReplacement(/camera)');
      navigator.pushReplacementNamed(AppRoutes.camera);
    }
  }

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
<<<<<<< HEAD
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
=======
            const SizedBox(height: 18),
            const _AppName(),
>>>>>>> 654d437 (Camera + Integration improvements)
            const Spacer(),
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final t = _controller.isListening ? _pulse.value : 0.0;
                return _MicOrb(pulse: t, listening: _controller.isListening);
              },
            ),
            const SizedBox(height: 28),
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

  Widget _buildSubMic() {
    final stage      = _controller.stage;
    final heard      = _controller.heardText;
    final recognized = _controller.recognizedNumber;

    if (stage == SettingsEmergencyStage.listening && heard.isNotEmpty) {
      return _NumberChip(
        key: const ValueKey('chip-live'),
        text: heard,
        isFinal: false,
      );
    }

    final hasFinal = recognized.isNotEmpty &&
        (stage == SettingsEmergencyStage.confirming ||
            stage == SettingsEmergencyStage.awaitingSave ||
            stage == SettingsEmergencyStage.saving);
    if (hasFinal) {
      return _NumberChip(
        key: const ValueKey('chip-final'),
        text: _formatSaudiNumber(recognized),
        isFinal: true,
      );
    }

    final isBusy = stage == SettingsEmergencyStage.processing ||
        stage == SettingsEmergencyStage.invalid ||
        stage == SettingsEmergencyStage.saving;
    if (isBusy) {
      return const _ProcessingDots(key: ValueKey('dots'));
    }

    return const SizedBox.shrink(key: ValueKey('empty'));
  }

  static String _formatSaudiNumber(String digits) {
    if (digits.length != 10) return digits;
    return '${digits.substring(0, 3)} '
        '${digits.substring(3, 6)} '
        '${digits.substring(6)}';
  }

  Widget _buildManualMode() {
    return Padding(
      key: const ValueKey('manual'),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
<<<<<<< HEAD
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
=======
            const SizedBox(height: 18),
            const _AppName(),
            const SizedBox(height: 28),
>>>>>>> 654d437 (Camera + Integration improvements)
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
              saving: _controller.stage == SettingsEmergencyStage.saving,
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
//  Local helper widgets (no source dependency on the Setup screen)
// ─────────────────────────────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  const _Background();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
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

<<<<<<< HEAD
=======
class _AppName extends StatelessWidget {
  const _AppName();

  @override
  Widget build(BuildContext context) {
    return Text(
      'هُــــــداي',
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 17,
            color: Colors.white.withOpacity(0.45),
            fontWeight: FontWeight.w400,
            height: 1.0,
          ),
    );
  }
}

>>>>>>> 654d437 (Camera + Integration improvements)
class _MicOrb extends StatelessWidget {
  const _MicOrb({required this.pulse, required this.listening});
  final double pulse;
  final bool   listening;

  @override
  Widget build(BuildContext context) {
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
          end:   Alignment.bottomRight,
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

class _NumberChip extends StatelessWidget {
  const _NumberChip({super.key, required this.text, required this.isFinal});
  final String text;
  final bool   isFinal;

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
                  color: on ? Colors.white : Colors.white.withOpacity(0.20),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

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
            end:   Alignment.bottomRight,
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
