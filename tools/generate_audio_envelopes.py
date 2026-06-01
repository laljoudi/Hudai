#!/usr/bin/env python3
"""
Generates per-clip RMS amplitude envelopes for the setup audio files.

This script analyses each MP3 in assets/audio/setup/, computes the
root-mean-square amplitude for every 60 ms window, normalises the
values to the [0.0, 1.0] range, and writes them out as a Dart file
that the setup and settings emergency controllers load at runtime
to drive the orb equaliser in sync with the audio.

Requirements:
  - macOS (uses the built-in `afconvert` to decode MP3 to PCM).
  - Python 3 standard library only (wave, struct, math, subprocess).

Usage:
  python3 tools/generate_audio_envelopes.py

Output:
  lib/core/constants/setup_audio_envelopes.dart
"""

import math
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AUDIO_DIR = ROOT / 'assets' / 'audio' / 'setup'
OUTPUT_DART = ROOT / 'lib' / 'core' / 'constants' / 'setup_audio_envelopes.dart'

# Matches voice_instructions_screen._binMs so the visual cadence feels the
# same between screens.
BIN_MS = 60

# Sample rate used for amplitude analysis (mono).
TARGET_SR = 22050

# Maps Dart identifier -> (filename, audio path used at runtime).
# The audio path string MUST match the value passed to _playAndWait so the
# controller can look the envelope up at play time.
CLIPS = {
    'intro':            ('setup_intro.mp3',          'audio/setup/setup_intro.mp3'),
    'startListening':   ('start_listening.mp3',      'audio/setup/start_listening.mp3'),
    'confirmNumber':    ('confirm_number.mp3',       'audio/setup/confirm_number.mp3'),
    'processing':       ('processing_number.mp3',    'audio/setup/processing_number.mp3'),
    'invalidVoice':     ('invalid_voice_input.mp3',  'audio/setup/invalid_voice_input.mp3'),
    'manualIntro':      ('manual_input_intro.mp3',   'audio/setup/manual_input_intro.mp3'),
    'tapToSave':        ('tap_to_save.mp3',          'audio/setup/tap_to_save.mp3'),
}
for i in range(10):
    CLIPS[f'digit{i}'] = (f'{i}.mp3', f'audio/setup/{i}.mp3')


def decode_to_wav(mp3_path: Path, wav_path: Path) -> None:
    """Use macOS `afconvert` to decode an MP3 into a mono 16-bit PCM WAV."""
    subprocess.run(
        [
            'afconvert',
            '-f', 'WAVE',
            '-d', f'LEI16@{TARGET_SR}',
            '-c', '1',
            str(mp3_path),
            str(wav_path),
        ],
        check=True,
        capture_output=True,
    )


def compute_envelope(wav_path: Path) -> list:
    """Read the decoded WAV and compute per-window RMS, normalised to [0, 1]."""
    with wave.open(str(wav_path), 'rb') as wav:
        sr = wav.getframerate()
        n_channels = wav.getnchannels()
        sampwidth = wav.getsampwidth()
        n_frames = wav.getnframes()
        raw = wav.readframes(n_frames)

    assert sampwidth == 2, f'expected 16-bit samples, got {sampwidth * 8}-bit'
    assert n_channels == 1, f'expected mono, got {n_channels} channels'

    samples = struct.unpack(f'<{n_frames}h', raw)
    samples_per_bin = sr * BIN_MS // 1000

    envelope = []
    for i in range(0, n_frames, samples_per_bin):
        window = samples[i:i + samples_per_bin]
        if not window:
            continue
        sum_sq = sum(s * s for s in window)
        rms = math.sqrt(sum_sq / len(window)) / 32768.0
        envelope.append(rms)

    # Peak-normalise so every clip uses the full [0, 1] range. Without this,
    # quieter clips would barely move the equaliser.
    peak = max(envelope, default=0.0)
    if peak > 0:
        envelope = [v / peak for v in envelope]
    return envelope


def format_envelope(values) -> str:
    """Format a list of floats as Dart, ten per line, three decimals each."""
    lines = []
    for i in range(0, len(values), 10):
        chunk = values[i:i + 10]
        lines.append('    ' + ', '.join(f'{v:.3f}' for v in chunk) + ',')
    return '\n'.join(lines)


def main() -> int:
    if not AUDIO_DIR.is_dir():
        print(f'ERROR: audio directory not found: {AUDIO_DIR}', file=sys.stderr)
        return 1

    try:
        subprocess.run(['afconvert', '--help'], capture_output=True)
    except FileNotFoundError:
        print('ERROR: afconvert not found (this script requires macOS).',
              file=sys.stderr)
        return 1

    print(f'Processing {len(CLIPS)} clips from {AUDIO_DIR} ...')

    envelopes = {}
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        for name, (filename, _path) in CLIPS.items():
            src = AUDIO_DIR / filename
            if not src.is_file():
                print(f'  WARN: missing {filename}, skipping')
                continue
            wav_path = tmp_path / f'{name}.wav'
            try:
                decode_to_wav(src, wav_path)
                env = compute_envelope(wav_path)
                envelopes[name] = env
                duration = len(env) * BIN_MS / 1000.0
                print(f'  ok  {filename:30s} {len(env):4d} bins  {duration:.1f}s')
            except Exception as e:
                print(f'  ERR {filename}: {e}', file=sys.stderr)

    if not envelopes:
        print('ERROR: no envelopes generated', file=sys.stderr)
        return 1

    print(f'\nWriting {OUTPUT_DART} ...')
    with OUTPUT_DART.open('w') as f:
        f.write('// AUTO-GENERATED by tools/generate_audio_envelopes.py.\n')
        f.write('// Regenerate whenever any setup MP3 is re-recorded.\n')
        f.write('//\n')
        f.write('// Per-clip RMS amplitude envelopes for the setup audio files.\n')
        f.write('// Each list holds normalised loudness values (0.0 to 1.0)\n')
        f.write(f'// sampled at {BIN_MS} ms intervals. The setup and settings\n')
        f.write('// emergency controllers look up the envelope for whichever\n')
        f.write('// clip is currently playing and write the matching amplitude\n')
        f.write('// into `speakingAmplitude`, which the screens read to drive\n')
        f.write('// the orb equaliser in sync with the spoken audio.\n')
        f.write('\n')
        f.write('// ignore_for_file: lines_longer_than_80_chars\n')
        f.write('\n')
        f.write('class SetupAudioEnvelopes {\n')
        f.write('  SetupAudioEnvelopes._();\n')
        f.write('\n')
        f.write('  /// Duration (ms) covered by each value in an envelope list.\n')
        f.write(f'  static const int binMs = {BIN_MS};\n')
        f.write('\n')
        f.write('  /// Look up the envelope for the audio asset at [path].\n')
        f.write('  /// Returns null for unknown paths (which causes the screen\n')
        f.write('  /// to fall back to a flat amplitude instead of silence).\n')
        f.write('  static List<double>? forPath(String path) => _byPath[path];\n')
        f.write('\n')
        f.write('  static final Map<String, List<double>> _byPath = {\n')
        for name in envelopes:
            _filename, audio_path = CLIPS[name]
            f.write(f"    '{audio_path}': _{name},\n")
        f.write('  };\n\n')

        for name, values in envelopes.items():
            duration = len(values) * BIN_MS / 1000.0
            f.write(f'  // {name}: {len(values)} bins, {duration:.1f}s\n')
            f.write(f'  static const List<double> _{name} = [\n')
            f.write(format_envelope(values))
            f.write('\n  ];\n\n')

        f.write('}\n')

    total_bins = sum(len(v) for v in envelopes.values())
    print(f'Done. {len(envelopes)} clips, {total_bins} total bins.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
