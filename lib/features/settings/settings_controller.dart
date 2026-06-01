import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:gp_hudai/core/storage/prefs.dart';

/// Brain of the Settings screen.
///
/// Owns the audio player and the intro-sequence state. The view only
/// renders and forwards taps; it has no audio logic of its own.
///
/// Audio sequence on screen open (played sequentially, gapped):
///   1. settings_page_intro.mp3
///   2. (~1.5s gap)
///   3. back_navigation_instruction.mp3
///   4. (~1.5s gap)
///   5. open_emergency_edit.mp3
///
/// Any tap on the screen calls [stopAudio] before navigating, so the user
/// is never spoken over. When the user taps to open the dedicated
/// emergency-edit screen, [releaseAudio] is used instead so the player
/// is fully freed before that screen's own player starts.
class SettingsController extends ChangeNotifier {
  /// Audio paths used by the screen.
  /// audioplayers paths are RELATIVE to `assets/`, no leading prefix.
  static const List<String> _introSequence = [
    'audio/settings/settings_page_intro.mp3',
    'audio/settings/back_navigation_instruction.mp3',
    'audio/settings/open_emergency_edit.mp3',
  ];

  /// Gap between clips. Within the spec's 2–3s upper bound, but short
  /// enough to feel responsive.
  static const Duration _gapBetweenClips = Duration(milliseconds: 1500);

  /// Hard upper bound on a single clip's playback. Set high so a slightly
  /// long clip never gets cut off mid-sentence — this is a safety net
  /// against a missing `onPlayerComplete`, NOT a normal pace control.
  static const Duration _clipTimeout = Duration(seconds: 60);

  final AudioPlayer _player = AudioPlayer();

  bool    _disposed      = false;
  bool    _stopped       = false;
  bool    _audioReleased = false;
  String? _currentNumber;

  /// The emergency number currently saved in Prefs, or null if none yet.
  String? get currentNumber => _currentNumber;

  // ──────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    debugPrint('SettingsController: initialize()');

    // Match the player config used by the rest of the app.
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      await _player.setVolume(1.0);
    } catch (e) {
      debugPrint('🔊 settings player config error: $e');
    }

    // Fire-and-forget: don't block the audio sequence on prefs I/O.
    // ignore: unawaited_futures
    refreshCurrentNumber();

    // Play the three clips one after another, with a small gap.
    await _runIntroSequence();
  }

  @override
  void dispose() {
    debugPrint('SettingsController: dispose()');
    _disposed = true;
    _stopped  = true;
    // releaseAudio() may have already disposed the player.
    if (!_audioReleased) {
      _audioReleased = true;
      try { _player.dispose(); } catch (_) {}
    }
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────

  /// Stop any audio that may still be playing and prevent the sequence
  /// loop from advancing to the next clip. Safe to call after
  /// [releaseAudio] — becomes a no-op.
  Future<void> stopAudio() async {
    _stopped = true;
    if (_audioReleased) return;
    try { await _player.stop(); } catch (_) {}
  }

  /// Stop AND fully dispose the AudioPlayer. Call this before pushing
  /// the dedicated emergency-edit screen on top of Settings, so that
  /// screen's audio sequence does not have to compete with Settings'
  /// (now idle) player for the Android audio focus.
  ///
  /// Safe to call multiple times. After release, [stopAudio] and the
  /// destructor become no-ops on the player.
  Future<void> releaseAudio() async {
    if (_audioReleased) return;
    _audioReleased = true;
    _stopped = true;
    try { await _player.stop(); } catch (_) {}
    try { await _player.dispose(); } catch (_) {}
    debugPrint('SettingsController: 🔇 audio released');
  }

  /// Re-read the saved emergency number from storage. Call this on
  /// screen init and again whenever returning from the edit screen, so
  /// the UI reflects any change the user just made.
  Future<void> refreshCurrentNumber() async {
    try {
      _currentNumber = await Prefs.getEmergencyNumber();
      if (_disposed) return;
      notifyListeners();
    } catch (e) {
      debugPrint('🚨 settings refreshCurrentNumber: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Sequence
  // ──────────────────────────────────────────────────────────────────

  Future<void> _runIntroSequence() async {
    for (var i = 0; i < _introSequence.length; i++) {
      if (_disposed || _stopped) return;
      await _playAndWait(_introSequence[i]);
      if (_disposed || _stopped) return;
      // Small breathing room between clips, but only between — not after
      // the last one.
      if (i < _introSequence.length - 1) {
        await Future.delayed(_gapBetweenClips);
      }
    }
  }

  /// Play a single asset and wait until `onPlayerComplete` fires (or
  /// until [_clipTimeout] elapses as a safety net).
  Future<void> _playAndWait(String path) async {
    if (_audioReleased) return;
    debugPrint('🔊 settings play: $path');
    final completer = Completer<void>();
    final sub = _player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await _player.play(AssetSource(path));
      await completer.future.timeout(
        _clipTimeout,
        onTimeout: () => debugPrint('🔊 settings audio timeout: $path'),
      );
    } catch (e) {
      debugPrint('🔊 settings audio error ($path): $e');
    } finally {
      await sub.cancel();
    }
  }
}