import 'dart:io' show Platform;

import 'package:gp_hudai/core/constants/yolo_config.dart';

/// Rate-limits AI inference to a target frames-per-second.
///
/// The camera produces ~30 FPS, but we only want ~3 FPS for AI.
/// This file decides which frames to process and which to drop.
///
/// Two protection rules:
///   1. Time-based: At least 333ms must pass between accepted frames
///   2. Busy-based: If AI is still processing the previous frame, drop new ones
///
/// Without this, the device would overheat, drain battery, and lag.
class InferenceThrottler {
  /// Timestamp (milliseconds since epoch) of the last accepted frame.
  /// Initialized to 0 so the first frame always passes.
  int _lastAcceptedMs = 0;

  /// True while the AI is currently processing a frame.
  /// We don't accept new frames while busy.
  bool _isBusy = false;

  /// How many milliseconds to wait between frames.
  /// Read from YoloConfig — currently 333ms (3 FPS).
  int get _intervalMs {
    // iOS: use a slightly slower inference cadence to keep preview fluid
    // on real devices during long sessions.
    if (Platform.isIOS) return 1100; // ~0.9 FPS
    return YoloConfig.throttleMs;
  }

  /// Returns true if this frame should be processed.
  /// Returns false if it should be dropped.
  ///
  /// Call this at the START of every camera frame.
  bool shouldProcess() {
    // Rule 1: Don't accept if AI is still busy
    if (_isBusy) return false;

    // Rule 2: Don't accept if not enough time has passed
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsed = nowMs - _lastAcceptedMs;
    if (elapsed < _intervalMs) return false;

    // Both checks passed — accept this frame
    _lastAcceptedMs = nowMs;
    _isBusy = true;
    return true;
  }

  /// Marks the AI as done processing.
  /// Call this AFTER inference completes (success OR failure).
  ///
  /// Without calling this, the throttler will block all future frames!
  void markDone() {
    _isBusy = false;
  }

  /// Resets the throttler state.
  /// Useful when restarting the camera or recovering from errors.
  void reset() {
    _lastAcceptedMs = 0;
    _isBusy = false;
  }

  /// Read-only access for debugging.
  bool get isBusy => _isBusy;
  int  get lastAcceptedMs => _lastAcceptedMs;
}
