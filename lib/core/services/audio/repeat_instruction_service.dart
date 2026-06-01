import 'package:flutter/foundation.dart';

import 'audio_service.dart';

/// Owns the "repeat last instruction" behavior.
///
/// AudioService reports every asset as it starts playing, and this service
/// stores the latest path. When the user taps repeat, the stored path is
/// replayed through the same AudioService instance.
class RepeatInstructionService {
  RepeatInstructionService({required AudioService audioService})
    : _audioService = audioService {
    _audioService.onAssetPlaybackStarted = rememberPlayedAsset;
  }

  final AudioService _audioService;
  String? _lastPlayedPath;

  bool get hasLastInstruction =>
      _lastPlayedPath != null && _lastPlayedPath!.trim().isNotEmpty;

  void rememberPlayedAsset(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    _lastPlayedPath = normalized;
  }

  Future<bool> repeatLast({String? fallbackPath}) async {
    final path = _lastPlayedPath ?? fallbackPath;
    if (path == null || path.trim().isEmpty) {
      debugPrint('RepeatInstructionService: no audio available to repeat');
      return false;
    }

    debugPrint('RepeatInstructionService: replaying $path');
    await _audioService.playAssetNow(path);
    return true;
  }

  void clear() {
    _lastPlayedPath = null;
  }

  void dispose() {
    _audioService.onAssetPlaybackStarted = null;
  }
}
