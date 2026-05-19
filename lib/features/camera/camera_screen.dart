import 'dart:async';
import 'dart:ui';

import 'package:camera/camera.dart' show CameraPreview;
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:gp_hudai/app/app_routes.dart';
import 'package:gp_hudai/core/models/detection.dart';
import 'package:gp_hudai/features/camera/camera_controller.dart';
import 'package:gp_hudai/widgets/detection_overlay.dart';

/// Camera screen — UI only.
///
/// All logic (camera, audio, AI, location) lives in CameraController.
/// This file is responsible only for:
///   - Displaying the camera preview
///   - Drawing the 4 corner glassy buttons (visual only — they don't catch taps)
///   - Forwarding user taps to the controller via the 3-section tap layout
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
    unawaited(WakelockPlus.enable());
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

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

          // Layer 1 — Live detection boxes
          Positioned.fill(child: _buildDetectionOverlay()),

          // Layer 2 — 3-section invisible tap layout (entire screen)
          Positioned.fill(child: _buildTapLayout()),

          // Layer 3 — Four glassy corner buttons (visual only)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Top-left: Settings
                  const Align(
                    alignment: Alignment.topLeft,
                    child: IgnorePointer(
                      child: _GlassyButton(
                        icon: Icons.settings,
                        iconColor: Color(0xFF70F0FF),
                      ),
                    ),
                  ),

                  // Top-right: Emergency call
                  const Align(
                    alignment: Alignment.topRight,
                    child: IgnorePointer(
                      child: _GlassyButton(
                        icon: Icons.call,
                        iconColor: Color(0xFFFF6B6B),
                      ),
                    ),
                  ),

                  // Bottom-left: Replay instructions
                  const Align(
                    alignment: Alignment.bottomLeft,
                    child: IgnorePointer(
                      child: _GlassyButton(
                        icon: Icons.replay,
                        iconColor: Color(0xFF70F0FF),
                      ),
                    ),
                  ),

                  // Bottom-right: Location (shows spinner when GPS is busy)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: IgnorePointer(
                      child: _GlassyButton(
                        icon: Icons.location_on,
                        iconColor: const Color(0xFF70F0FF),
                        busy: _controller.locationBusy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
              _controller.cameraError ?? '.',  // ← Arabic placeholder
              style: const TextStyle(color: Colors.white60, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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

  // ───────────────────────────────────────────────────────────────────
  //  Tap layout (unchanged from original)
  //  Top 30%   : Settings (L) + Emergency (R)
  //  Middle 40%: Dead zone
  //  Bottom 30%: Replay (L)   + Location (R)
  // ───────────────────────────────────────────────────────────────────
  Widget _buildTapLayout() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              Expanded(child: _tapZone(onTap: _onSettingsTap)),
              Expanded(child: _tapZone(onTap: _controller.onEmergencyTap)),
            ],
          ),
        ),
        const Expanded(flex: 4, child: IgnorePointer(child: SizedBox.expand())),
        Expanded(
          flex: 3,
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              Expanded(
                child: _tapZone(onTap: _controller.onReplayInstructionsTap),
              ),
              Expanded(child: _tapZone(onTap: _controller.onLocationTap)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tapZone({required Function() onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => onTap(),
      child: const SizedBox.expand(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Glassy corner button — Liquid-Glass / glossy 3D style
//
//  Layers (bottom → top):
//   1. Outer soft shadow for depth
//   2. Frosted blur backdrop
//   3. Translucent gradient body (light at top, dim at bottom)
//   4. Top-edge bright highlight (the "gloss")
//   5. Inner colored inner-glow at the bottom (subtle lit-from-inside feel)
//   6. White rim border
//   7. Icon (no label)
// ─────────────────────────────────────────────────────────────────────────────

class _GlassyButton extends StatelessWidget {
  const _GlassyButton({
    required this.icon,
    required this.iconColor,
    this.busy = false,
  });

  final IconData icon;
  final Color iconColor;
  final bool busy;

  static const double _size = 68;
  static const double _radius = 18;
  static const double _iconSize = 28;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        children: [
          // Outer drop shadow for lift
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.30),
                  blurRadius: 16,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: iconColor.withOpacity(0.18),
                  blurRadius: 18,
                  spreadRadius: -4,
                ),
              ],
            ),
          ),

          // Frosted glass body + gradient + highlight + inner glow + rim
          ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_radius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.28),
                      Colors.white.withOpacity(0.10),
                      Colors.white.withOpacity(0.06),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.32),
                    width: 1.0,
                  ),
                ),
                child: Stack(
                  children: [
                    // Top-edge bright gloss highlight
                    Positioned(
                      top: 1,
                      left: 1,
                      right: 1,
                      height: _size * 0.45,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(_radius - 2),
                            topRight: Radius.circular(_radius - 2),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.40),
                              Colors.white.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Inner colored glow at the bottom — "lit from inside"
                    Positioned(
                      bottom: -10,
                      left: _size * 0.15,
                      right: _size * 0.15,
                      height: _size * 0.45,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              iconColor.withOpacity(0.30),
                              iconColor.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Icon
                    Center(
                      child: busy
                          ? SizedBox(
                              width: _iconSize,
                              height: _iconSize,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: iconColor,
                              ),
                            )
                          : Icon(
                              icon,
                              color: iconColor,
                              size: _iconSize,
                              shadows: [
                                Shadow(
                                  color: iconColor.withOpacity(0.55),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
