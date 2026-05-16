import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:gp_hudai/app/app_routes.dart';
import 'package:gp_hudai/features/settings/settings_controller.dart';

/// Settings screen — UI only.
///
/// Two tap zones (per spec):
///   - Top-left corner  → small "back" tap area  → Navigator.pop
///   - Anywhere else    → opens emergency-number edit (reuses SetupScreen)
///
/// All audio + state lives in [SettingsController].
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  late final SettingsController _controller;

  // Subtle ambient glow — view-only, no app state.
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    _controller = SettingsController();
    _controller.addListener(_onControllerUpdate);
    _controller.initialize();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(
      begin: 0.55,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  // ── Tap handlers ──────────────────────────────────────────────────────

  Future<void> _onBackTap() async {
    debugPrint('👆 settings: back');
    await _controller.stopAudio();
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _onEditEmergencyTap() async {
    debugPrint('👆 settings: open emergency edit');
    // Fully release the Settings AudioPlayer BEFORE pushing Setup. If we
    // only call stopAudio(), three live AudioPlayer instances (Camera's
    // AudioService + Settings + Setup) compete for the Android audio
    // focus and Setup's confirm sequence can fail silently — which is
    // why the user previously reported the screen "going silent after
    // recognition" and long-press doing nothing.
    //
    // We keep Settings in the route stack (so CameraScreen._onSettingsTap
    // stays suspended on its awaited pushNamed), but free its audio.
    await _controller.releaseAudio();
    if (!mounted) return;
    await Navigator.pushNamed(context, AppRoutes.setup);
    // Settings will only be reached again if the user backs out of Setup
    // without saving. Nothing to refresh: SetupScreen._navigateToCamera
    // pops Settings on a successful save, so this line never runs in the
    // save path.
    if (!mounted) return;
    _controller.refreshCurrentNumber();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030A20),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _Background(),

          // Main full-screen tap zone → opens emergency-number edit.
          // (Whole area is tappable for blind-user accessibility, but
          // visually it's a normal settings page with an option card.)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onEditEmergencyTap,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 90),

                    const Text(
                      'الإعدادات',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),

                    const SizedBox(height: 36),

                    AnimatedBuilder(
                      animation: _glowAnim,
                      builder: (_, __) => _SettingsTile(
                        icon: Icons.phone_in_talk_rounded,
                        title: 'تعديل رقم الطوارئ',
                        currentNumber: _controller.currentNumber,
                        glow: _glowAnim.value,
                        onTap: _onEditEmergencyTap,
                      ),
                    ),

                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),

          // Back tap zone — small top-right corner (RTL layout).
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onBackTap,
                child: const _BackBadge(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Background — same as the voice instructions screen
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
//  Glassy settings option tile (list-style, with leading icon + chevron).
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.currentNumber,
    required this.glow,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? currentNumber;
  final double glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.20)),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF1855FF,
                  ).withOpacity(0.20 + 0.15 * glow),
                  blurRadius: 28,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: const Color(0xFF00CFFF).withOpacity(0.12 * glow),
                  blurRadius: 45,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  // Leading glassy icon chip — on the right in RTL
                  _UnifiedIconBadge(icon: icon, size: 56, iconSize: 28),

                  const SizedBox(width: 14),

                  // Title + current number (or "not set" hint)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _CurrentNumberLine(number: currentNumber),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  Icon(
                    Icons.chevron_left,
                    color: Colors.white.withOpacity(0.55),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Inline display of the currently saved emergency number (or hint if none).
// ─────────────────────────────────────────────────────────────────────────────

class _CurrentNumberLine extends StatelessWidget {
  const _CurrentNumberLine({required this.number});
  final String? number;

  @override
  Widget build(BuildContext context) {
    final hasNumber = number != null && number!.trim().isNotEmpty;
    return Row(
      children: [
        Text(
          'الرقم الحالي:',
          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            hasNumber ? number! : 'غير محفوظ',
            // Force LTR for the number so digits read left-to-right even
            // inside an RTL row.
            textDirection: TextDirection.ltr,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hasNumber
                  ? const Color(0xFF40E0FF)
                  : Colors.white.withOpacity(0.45),
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: hasNumber ? 1.5 : 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Glassy back badge in the top-right corner (RTL).
//  Visually hints at "back" without being a tiny iOS-style chevron — the
//  actual hit area extends well past the visible chip.
// ─────────────────────────────────────────────────────────────────────────────

class _BackBadge extends StatelessWidget {
  const _BackBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 10),
      child: SizedBox(
        // Generous tap area for blind/low-vision users.
        width: 110,
        height: 110,
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: const SizedBox(
                  width: 64,
                  height: 64,
                  child: Center(
                    child: _UnifiedIconBadge(
                      icon: Icons.arrow_forward_ios_rounded,
                      size: 46,
                      iconSize: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Unified icon style shared with the camera screen.
class _UnifiedIconBadge extends StatelessWidget {
  const _UnifiedIconBadge({
    required this.icon,
    this.size = 46,
    this.iconSize = 22,
  });

  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.22),
                const Color(0xFF40E0FF).withOpacity(0.10),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.32),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1855FF).withOpacity(0.18),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }
}
