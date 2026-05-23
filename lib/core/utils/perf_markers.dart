// ============================================================
// PERFORMANCE TEST [PT-03] — START
// Purpose: Global stopwatch for post-splash initialisation time
// Remove this block after testing is complete
// ============================================================

/// Shared static markers for graduation performance tests.
///
/// All fields are static so any file can read/write them without
/// dependency injection. State resets automatically on hot restart.
class PerfMarkers {
  PerfMarkers._(); // non-instantiable

  /// Started the moment the splash screen is dismissed.
  /// Stopped at the very first audio playback after launch.
  static final Stopwatch postSplashWatch = Stopwatch();

  /// Flipped to true once the first post-splash audio has been timed.
  /// Prevents subsequent audio plays from re-triggering the log.
  static bool firstAudioPlayed = false;
}

// ============================================================
// PERFORMANCE TEST [PT-03] — END
// ============================================================
