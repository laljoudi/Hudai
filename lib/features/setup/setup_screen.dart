import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:gp_hudai/app/app_routes.dart';
import 'package:gp_hudai/core/storage/prefs.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emergencyController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _emergencyController.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    await Prefs.saveEmergencyNumber(_emergencyController.text.trim());

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.camera);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030A20),
      body: Stack(
        children: [
          // ── Background gradient — matches voice instructions screen ──
          const Positioned.fill(
            child: DecoratedBox(
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

          // ── Soft ambient color blobs (matching voice instructions glow) ──
          Positioned(
            top: -80,
            right: -60,
            child: _ambientBlob(
              260,
              const Color(0xFF1855FF).withOpacity(0.18),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -80,
            child: _ambientBlob(
              300,
              const Color(0xFF00CFFF).withOpacity(0.14),
            ),
          ),

          // ── Main content ─────────────────────────────────────────────
          SafeArea(
            child: Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 90),

                    // ── Title ────────────────────────────────────────
                    const Text(
                      'رقم الطوارئ',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color:      Colors.white,
                        fontSize:   34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Subtitle ─────────────────────────────────────
                    Text(
                      'يرجى إدخال رقم هاتف للاتصال به في حالات الطوارئ.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color:    Colors.white.withOpacity(0.55),
                        fontSize: 14,
                        height:   1.5,
                      ),
                    ),

                    const SizedBox(height: 60),

                    // ── Glassy input field ──────────────────────────
                    _GlassyTextField(
                      controller: _emergencyController,
                      validator: (v) {
                        final input = (v ?? '').trim();
                        if (input.isEmpty) {
                          return 'الرجاء إدخال رقم الطوارئ';
                        }
                        final normalized =
                            input.replaceAll(RegExp(r'[^\d+]'), '');
                        if (normalized.length < 6) {
                          return 'الرقم المدخل غير صالح';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 30),

                    // ── Glowing cyan save button ────────────────────
                    _GlowingSaveButton(
                      saving: _saving,
                      onTap: _saveAndContinue,
                    ),

                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ambientBlob(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width:  size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius:   90,
              spreadRadius: 30,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Glassy Text Field — rounded frosted input
// ─────────────────────────────────────────────────────────────────────────────

class _GlassyTextField extends StatelessWidget {
  const _GlassyTextField({
    required this.controller,
    required this.validator,
  });

  final TextEditingController         controller;
  final String? Function(String?)?    validator;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color:        Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.20),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color:      Colors.black.withOpacity(0.12),
                blurRadius: 20,
                offset:     const Offset(0, 8),
              ),
            ],
          ),
          child: TextFormField(
            controller:    controller,
            keyboardType:  TextInputType.phone,
            textAlign:     TextAlign.center,
            cursorColor:   const Color(0xFF40E0FF),
            validator:     validator,
            style: const TextStyle(
              color:        Colors.white,
              fontSize:     20,
              letterSpacing: 1.2,
              fontWeight:   FontWeight.w500,
            ),
            decoration: InputDecoration(
              border:           InputBorder.none,
              contentPadding:   const EdgeInsets.symmetric(
                vertical: 22, horizontal: 16,
              ),
              hintText:  '+966',
              hintStyle: TextStyle(
                color:    Colors.white.withOpacity(0.30),
                fontSize: 18,
              ),
              errorStyle: const TextStyle(
                color:    Color(0xFFFF8A8A),
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
//  Glowing Save Button — cyan capsule with glow
// ─────────────────────────────────────────────────────────────────────────────

class _GlowingSaveButton extends StatelessWidget {
  const _GlowingSaveButton({required this.saving, required this.onTap});

  final bool         saving;
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
            begin:  Alignment.topLeft,
            end:    Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color:      const Color(0xFF1855FF).withOpacity(0.55),
              blurRadius: 32,
              spreadRadius: 1,
              offset:     const Offset(0, 6),
            ),
            BoxShadow(
              color:      const Color(0xFF00CFFF).withOpacity(0.30),
              blurRadius: 60,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Center(
          child: saving
              ? const SizedBox(
                  width:  22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color:       Colors.white,
                  ),
                )
              : const Text(
                  'حفظ',
                  style: TextStyle(
                    color:      Colors.white,
                    fontSize:   20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}