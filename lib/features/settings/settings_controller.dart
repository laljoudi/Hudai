import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Brain of the Settings screen.
///
/// Owns the audio player and the intro-sequence state. The view only
/// renders and forwards taps; it has no audio logic of its own.
///
/// Audio sequence on screen open (chained automatically via onPlayerComplete):
///   1. settings_page_intro.mp3
///   2. back_navigation_instruction.mp3
///   3. open_emergency_edit.mp3
///
/// Any tap on the screen calls [stopAudio] before navigating, so the user
/// is never spoken over.
class SettingsController extends ChangeNotifier {
  /// Audio paths used by the screen.
  /// audioplayers paths are RELATIVE to `assets/`, no leading prefix.
  static const List<String> _introSequence = [
    'audio/settings/settings_page_intro.mp3',
    'audio/settings/back_navigation_instruction.mp3',
    'audio/settings/open_emergency_edit.mp3',
  ];

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;

  int  _seqIndex = 0;
  bool _disposed = false;

  /// Index of the clip currently playing (or just played). Useful for
  /// debugging / future UI like "now playing" hints.
  int get currentClipIndex => _seqIndex;

  // ──────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────

  /// Configure the player and kick off the intro sequence.
  Future<void> initialize() async {
    debugPrint('SettingsController: initialize()');
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
    } catch (e) {
      debugPrint('🔊 settings player config error: $e');
    }

    // When one clip ends, automatically advance to the next.
    _completeSub = _player.onPlayerComplete.listen((_) => _playNextInSequence());

    await _playAt(0);
  }

  @override
  void dispose() {
    debugPrint('SettingsController: dispose()');
    _disposed = true;
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────

  /// Stop any audio that may still be playing and prevent any queued
  /// onComplete handler from auto-advancing.
  Future<void> stopAudio() async {
    // Push the index past the end so _playNextInSequence becomes a no-op
    // even if onPlayerComplete fires after we've called stop().
    _seqIndex = _introSequence.length;
    try { await _player.stop(); } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────────────
  // Internal sequence helpers
  // ──────────────────────────────────────────────────────────────────

  Future<void> _playAt(int i) async {
    if (_disposed || i >= _introSequence.length) return;
    _seqIndex = i;
    debugPrint('🔊 settings play [$i]: ${_introSequence[i]}');
    try {
      await _player.stop();
      await _player.play(AssetSource(_introSequence[i]));
    } catch (e) {
      debugPrint('🔊 settings audio error: $e');
    }
  }

  Future<void> _playNextInSequence() async {
    if (_disposed) return;
    final next = _seqIndex + 1;
    if (next < _introSequence.length) {
      await _playAt(next);
    }
  }
}
