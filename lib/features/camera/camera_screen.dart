import 'dart:ui';

import 'package:camera/camera.dart' show CameraPreview;
import 'package:flutter/material.dart';

import 'package:gp_hudai/app/app_routes.dart';
import 'package:gp_hudai/core/models/detection.dart';
import 'package:gp_hudai/features/camera/camera_controller.dart';
import 'package:gp_hudai/widgets/detection_overlay.dart';

/// Camera screen — UI only.
///
/// All logic (camera, audio, AI, location) lives in CameraController.
/// This file is responsible only for:
///   - Displaying the camera preview
///   - Drawing the 4 quadrant tap zones
///   - Drawing the glassy header / footer overlays
///   - Forwarding user taps to the controller
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final CameraController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CameraController();
    _controller.addListener(_onControllerUpdate);
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  /// Called whenever the controller publishes a state change.
  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  // ───────────────────────────────────────────────────────────────────
  //  Settings — handled in the view because navigation needs context.
  // ───────────────────────────────────────────────────────────────────
  Future<void> _onSettingsTap() async {
    await _controller.suspendForSettings();
    if (!mounted) return;

    await Navigator.pushNamed(context, AppRoutes.settings);

    if (!mounted) return;
    await _controller.resumeFromSettings();
  }

  // ───────────────────────────────────────────────────────────────────
  //  Build
  // ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030A20),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 0 — Camera feed
          _buildCamera(),

          // Layer 1 - Live detection boxes
          Positioned.fill(child: _buildDetectionOverlay()),

          // Layer 1 — 4 invisible quadrant tap zones (entire screen)
          Positioned.fill(child: _buildQuadrants()),

          // Layer 2 — Visual glassy header (top corners icons)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: _buildGlassyHeader(),
            ),
          ),

          // Layer 3 — Visual glassy footer (bottom corners icons)
          Align(alignment: Alignment.bottomCenter, child: _buildGlassyFooter()),
        ],
      ),
    );
  }

  Widget _buildDetectionOverlay() {
    final cam = _controller.cameraController;
    if (cam == null || !cam.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<List<Detection>>(
      valueListenable: _controller.detectionsListenable,
      builder: (context, detections, _) {
        return DetectionOverlay(
          detections: detections,
          cameraAspectRatio: cam.value.aspectRatio,
        );
      },
    );
  }

  /// Three-section tap layout (replaces the old 2x2 quadrant grid).
  ///
  /// Top section    (top 30%):  Settings (left) + Emergency call (right)
  /// Middle section (middle 40%): Dead zone — taps ignored on purpose
  /// Bottom section (bottom 30%): Replay (left) + Location (right)
  ///
  /// Heights are flex values — they auto-scale to any iPhone screen size.
  Widget _buildQuadrants() {
    return Column(
      children: [
        // ── TOP SECTION (30% of height) ─────────────────────────────
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Expanded(child: _quadrant(onTap: _onSettingsTap)),
              Expanded(child: _quadrant(onTap: _controller.onEmergencyTap)),
            ],
          ),
        ),

        // ── MIDDLE DEAD ZONE (40% of height) ────────────────────────
        // Uses IgnorePointer so taps pass through to nothing — no action.
        const Expanded(flex: 4, child: IgnorePointer(child: SizedBox.expand())),

        // ── BOTTOM SECTION (30% of height) ──────────────────────────
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Expanded(
                child: _quadrant(onTap: _controller.onReplayInstructionsTap),
              ),
              Expanded(child: _quadrant(onTap: _controller.onLocationTap)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quadrant({required Function() onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => onTap(),
      child: const SizedBox.expand(),
    );
  }

  // ───────────────────────────────────────────────────────────────────
  //  Glassy header — Settings (left) + Emergency (right)
  // ───────────────────────────────────────────────────────────────────
  Widget _buildGlassyHeader() {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        height: 64,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withOpacity(0.20),
                  width: 1.0,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  _GlassyIconBadge(icon: Icons.settings),
                  _GlassyIconBadge(icon: Icons.call),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────
  //  Glassy footer — Replay (left) + Location (right)
  // ───────────────────────────────────────────────────────────────────
  Widget _buildGlassyFooter() {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        height: 76,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(38),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(38),
                border: Border.all(
                  color: Colors.white.withOpacity(0.20),
                  width: 1.0,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _GlassyIconBadge(icon: Icons.replay),
                  _controller.locationBusy
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const _GlassyIconBadge(icon: Icons.location_on),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────
  //  Camera feed
  // ───────────────────────────────────────────────────────────────────
  Widget _buildCamera() {
    if (_controller.useMockCamera) return _buildMockCamera();

    final initFuture = _controller.initializeFuture;
    final cam = _controller.cameraController;

    if (initFuture == null || cam == null) {
      return const ColoredBox(color: Color(0xFF030A20));
    }

    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(color: Color(0xFF030A20));
        }

        return _buildFullScreenPreview(
          CameraPreview(cam),
          cam.value.aspectRatio,
        );
      },
    );
  }

  Widget _buildFullScreenPreview(Widget preview, double cameraAspectRatio) {
    final screenSize = MediaQuery.sizeOf(context);
    final screenAspectRatio = screenSize.width / screenSize.height;

    // CameraPreview reports landscape-oriented aspect ratios on many devices.
    // In portrait, invert it before cover-scaling so the preview fills the
    // screen instead of rendering as a small letterboxed rectangle.
    final portraitCameraAspectRatio = 1 / cameraAspectRatio;
    final scale = portraitCameraAspectRatio / screenAspectRatio;

    return ClipRect(
      child: Transform.scale(
        scale: scale < 1 ? 1 / scale : scale,
        child: Center(child: preview),
      ),
    );
  }

  Widget _buildMockCamera() {
    return Container(
      decoration: const BoxDecoration(
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
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: Colors.white38, size: 52),
            const SizedBox(height: 14),
            Text(
              _controller.cameraError ?? 'وضع تجريبي بدون كاميرا',
              style: const TextStyle(color: Colors.white60, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Glassy icon badge — small frosted circular icon with cyan tint
// ─────────────────────────────────────────────────────────────────────────────

class _GlassyIconBadge extends StatelessWidget {
  const _GlassyIconBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 46,
          height: 46,
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
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
