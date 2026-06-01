import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:gp_hudai/app/app_routes.dart';
import 'package:gp_hudai/core/widgets/tap_feedback_overlay.dart';
import 'package:gp_hudai/features/settings/settings_controller.dart';

/// Settings screen — UI only.
///
/// Two tap zones (per spec):
///   - Top-right corner → small "back" tap area → Navigator.pop
///   - Anywhere else    → opens the dedicated emergency-edit screen
///
/// All audio + state lives in [SettingsController]. The emergency-edit
/// flow itself lives in `SettingsEmergencyScreen`, which is independent
/// of the first-launch Setup flow.
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
    debugPrint('👆 settings: open emergency edit (→ /settings/emergency)');
    // Fully release the Settings AudioPlayer BEFORE pushing the edit
    // screen, so its voice sequence doesn't have to compete with
    // Settings' (now-idle) player for the Android audio focus.
    await _controller.releaseAudio();
    if (!mounted) return;
    await Navigator.pushNamed(context, AppRoutes.settingsEmergency);
    if (!mounted) return;
    // User backed out of the edit screen without saving (the save path
    // pops Settings as well via popUntil). Refresh the displayed number
    // in case anything changed.
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

          // Main full-screen tap zone → opens the emergency-edit screen.
          // (Whole area is tappable for blind-user accessibility, but
          // visually it's a normal settings page with an option card.)
          TapFeedbackOverlay(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onEditEmergencyTap,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 18),
                      const _AppName(),
                      const SizedBox(height: 72),

                      AnimatedBuilder(
                        animation: _glowAnim,
                        builder: (_, __) => _SettingsTile(
                          icon: Icons.edit_rounded,
                          iconColor: Colors.white,
                          title: ' رقـم الطـوارئ',
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
          ),

          // Back tap zone — small top-right corner.
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: TapFeedbackOverlay(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onBackTap,
                  child: const _BackBadge(),
                ),
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
        color: Colors.white.withValues(alpha: 0.45),
        fontWeight: FontWeight.w400,
        height: 1.0,
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
    required this.iconColor,
    required this.title,
    required this.currentNumber,
    required this.glow,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? currentNumber;
  final double glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapFeedbackOverlay(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: [
                // Leading glassy icon chip — on the right in RTL
                _GlassyCircleButton(icon: icon, iconColor: iconColor),

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
              ],
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
    return Text(
      hasNumber ? number! : 'غير محفوظ',
      textDirection: TextDirection.ltr,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: hasNumber
            ? const Color(0xFF40E0FF)
            : Colors.white.withValues(alpha: 0.45),
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: hasNumber ? 1.5 : 0.2,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Glassy back badge in the top-right corner.
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
            child: Transform.translate(
              // Optical centering for the iOS-style back chevron.
              offset: const Offset(3, 0),
              child: const _GlassyCircleButton(
                icon: Icons.arrow_back_ios_rounded,
                iconColor: Colors.white,
                iconSize: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Matches the camera screen's circular glass action buttons.
class _GlassyCircleButton extends StatelessWidget {
  const _GlassyCircleButton({
    required this.icon,
    required this.iconColor,
    this.iconSize = 28,
  });

  final IconData icon;
  final Color iconColor;
  final double iconSize;

  static const double _size = 68;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 16,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          ),
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.28),
                      Colors.white.withValues(alpha: 0.10),
                      Colors.white.withValues(alpha: 0.06),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
                child: Center(
                  child: Icon(icon, color: iconColor, size: iconSize),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
