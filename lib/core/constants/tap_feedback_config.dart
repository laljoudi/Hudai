/// Global toggle for the on-screen tap feedback (ripple + glow).
///
/// This is a **demo-only visual aid**. The app is audio-first and designed for
/// blind users, so taps normally respond silently. For recording demo videos we
/// want a brief, subtle visual confirmation that a tap happened.
///
/// Set to `false` after the demo to disable the effect without removing any
/// code — the [TapFeedbackOverlay] wrapper then passes straight through to its
/// child.
bool kShowTapFeedback = true;

/// Accent colour used for the ripple + glow (project cyan).
const int kTapFeedbackColorValue = 0xFF70F0FF;

/// Total duration of a single tap effect. Kept under 300ms so it never lingers
/// over the audio-first interaction.
const Duration kTapFeedbackDuration = Duration(milliseconds: 280);
