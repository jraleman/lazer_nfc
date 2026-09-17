"""Author LaZer NFC's original PCM bank offline, using Python 3.10's stdlib.

Run ``python tools\\bake_colors.py`` from the game directory; ``--check``
re-renders in memory and checks byte-for-byte reproducibility without writing.
No recordings, downloaded samples, external melodies, numpy, or runtime
synthesizer are used. Each noise source has its own stable, named seed.

The 21 400 ms instruments follow DESIGN's C3/E3/G3/C4/E4/G4/C5 mapping.
Dark is one semitone lower, with a 2*f Butterworth low-pass and slower attack.
Light is one semitone higher, with a +6 dB high shelf at 2*f and faster attack.
Peak/RMS normalization leaves headroom; it never clips or uses a hard limiter.
Music and motion are authored as periodic loops, including wrapped tails.
Per-file Godot import profiles pin PCM16 instead of 4.7's default QOA; rebaking
preserves generated import UIDs/remaps and enforces the authored sample layout.

``--voice-source DIR --voice-destination DIR`` only finishes WAVs produced by
bake_voice.ps1: silence trimming, short edge fades and PCM normalization. Those
voices are local Microsoft System.Speech synthesis, NOT human recordings or
voices created by this mathematical instrument authoring code. Reproducing
speech requires the same installed Windows voice/engine; no web service is used.
"""

from __future__ import annotations

import argparse
from array import array
from configparser import ConfigParser
from hashlib import sha256
from io import BytesIO, StringIO
from math import cos, exp, isfinite, pi, sin, sqrt
from pathlib import Path
from random import Random
import sys
from typing import Callable
import wave


RATE = 44100
TAU = 2.0 * pi
NOTE_SECONDS = 0.4
DESTINATION = Path(__file__).resolve().parents[1] / "assets" / "audio"
HUES = (
    ("red", 48, 0.020, 2.0),
    ("orange", 52, 0.012, 3.0),
    ("yellow", 55, 0.003, 5.0),
    ("green", 60, 0.002, 0.7),
    ("blue", 64, 0.018, 1.5),
    ("indigo", 67, 0.026, 1.6),
    ("violet", 72, 0.005, 2.4),
)
SHADES = ("base", "dark", "light")


def noise_source(name: str) -> Random:
    """An unrelated new sound must not change any existing noise realization."""
    seed = int.from_bytes(sha256(("LaZer NFC / " + name).encode("ascii")).digest()[:8],
                          "little")
    return Random(seed)


def frequency(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


def silence(seconds: float) -> list[float]:
    return [0.0] * round(seconds * RATE)


def smooth(value: float) -> float:
    value = min(max(value, 0.0), 1.0)
    return value * value * (3.0 - 2.0 * value)


def envelope(t: float, seconds: float, attack: float, decay: float,
             release: float = 0.035) -> float:
    return smooth(t / attack) * exp(-decay * t) * smooth((seconds - t) / release)


def biquad(samples: list[float], cutoff: float, shelf: bool = False) -> list[float]:
    """RBJ low-pass / +6 dB high shelf, baked rather than shared-bus filtering."""
    omega = TAU * cutoff / RATE
    cosine = cos(omega)
    if shelf:
        gain = 10.0 ** (6.0 / 40.0)
        alpha = sin(omega) / sqrt(2.0)
        beta = 2.0 * sqrt(gain) * alpha
        b0 = gain * ((gain + 1) + (gain - 1) * cosine + beta)
        b1 = -2 * gain * ((gain - 1) + (gain + 1) * cosine)
        b2 = gain * ((gain + 1) + (gain - 1) * cosine - beta)
        a0 = (gain + 1) - (gain - 1) * cosine + beta
        a1 = 2 * ((gain - 1) - (gain + 1) * cosine)
        a2 = (gain + 1) - (gain - 1) * cosine - beta
    else:
        alpha = sin(omega) / sqrt(2.0)
        b0 = (1.0 - cosine) * 0.5
        b1 = 1.0 - cosine
        b2 = b0
        a0 = 1.0 + alpha
        a1 = -2.0 * cosine
        a2 = 1.0 - alpha
    b0, b1, b2, a1, a2 = (value / a0 for value in (b0, b1, b2, a1, a2))
    result = []
    x1 = x2 = y1 = y2 = 0.0
    for sample in samples:
        value = b0 * sample + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        result.append(value)
        x2, x1, y2, y1 = x1, sample, y1, value
    return result


def string_pluck(hz: float, seconds: float, name: str) -> list[float]:
    """Fractional-delay Karplus-Strong, compensating the averaging filter delay."""
    samples = silence(seconds)
    delay = RATE / hz - 0.5
    whole = int(delay)
    fraction = delay - whole
    rng = noise_source(name)
    excitation = [rng.uniform(-1.0, 1.0) for _ in range(whole + 1)]
    mean = sum(excitation) / len(excitation)
    for i, value in enumerate(excitation):
        samples[i] = (value - mean) * 0.65 + sin(TAU * i / (whole + 1)) * 0.35
    previous = samples[0]
    for i in range(whole + 1, len(samples)):
        delayed = samples[i - whole] * (1.0 - fraction)
        delayed += samples[i - whole - 1] * fraction
        samples[i] = (delayed + previous) * 0.4985
        previous = delayed
    return samples


def instrument(hue: str, midi: int, shade: str, attack: float,
               decay: float) -> list[float]:
    semitones = {"base": 0, "dark": -1, "light": 1}[shade]
    hz = frequency(midi + semitones)
    samples = silence(NOTE_SECONDS)
    rng = noise_source(hue)
    breath = 0.0
    if hue == "green":
        samples = string_pluck(hz, NOTE_SECONDS, "green string")
    else:
        for i in range(len(samples)):
            t = i / RATE
            phase = TAU * hz * t
            if hue == "red":
                value = (sin(phase) + 0.27 * sin(3 * phase) + 0.10 * sin(5 * phase)
                         + 0.045 * sin(7 * phase) + 0.10 * sin(phase * 0.5))
            elif hue == "orange":
                growl = phase + 0.035 * sin(TAU * 31.0 * t)
                value = sum(sin(growl * h) * 0.86 ** (h - 1) / h
                            for h in range(1, 12))
                value *= 0.94 + 0.06 * sin(TAU * 43.0 * t)
            elif hue == "yellow":
                value = 0.62 * sin(phase)
                value += 0.48 * sin(phase + 1.9 * exp(-8 * t) * sin(2.76 * phase))
                value += 0.12 * sin(3.97 * phase) * exp(-13 * t)
            elif hue == "blue":
                vibrato = phase + hz * 0.006 / 5.0 * (1.0 - cos(TAU * 5.0 * t))
                breath = breath * 0.82 + rng.uniform(-1.0, 1.0) * 0.18
                value = (sin(vibrato) + 0.085 * sin(2 * vibrato)
                         + 0.025 * sin(3 * vibrato) + 0.025 * breath)
            elif hue == "indigo":
                value = (0.29 * sin(phase * 0.995) + 0.42 * sin(phase)
                         + 0.29 * sin(phase * 1.005)
                         + 0.12 * sin(phase * 2.002)
                         + 0.055 * sin(phase * 2.998))
            elif hue == "violet":
                value = (sin(phase) + 0.23 * sin(phase * 2.01) * exp(-12 * t)
                         + 0.08 * sin(phase * 4.02) * exp(-18 * t)
                         + 0.035 * sin(phase * 8.0) * exp(-25 * t))
            else:
                raise ValueError(f"Unknown authored hue: {hue}")
            samples[i] = value
    if shade == "dark":
        samples = biquad(samples, 2.0 * hz)
        attack = attack * 1.8 + 0.008
    elif shade == "light":
        samples = biquad(samples, 2.0 * hz, shelf=True)
        attack = max(attack * 0.45, 0.001)
    for i in range(len(samples)):
        samples[i] *= envelope(i / RATE, NOTE_SECONDS, attack, decay,
                               0.055 if hue == "violet" else 0.035)
    return samples


def toy_note(midi: float, decay: float = 8.0) -> Callable[[float], float]:
    hz = frequency(midi)

    def sound(t: float) -> float:
        phase = TAU * hz * t
        return smooth(t / 0.0025) * exp(-decay * t) * (
            sin(phase) + 0.22 * sin(phase * 2.006) * exp(-8 * t)
            + 0.07 * sin(phase * 3.99) * exp(-15 * t)
        )

    return sound


def add(samples: list[float], at: float, seconds: float,
        sound: Callable[[float], float], gain: float = 1.0,
        wrap: bool = False) -> None:
    first = round(at * RATE)
    count = round(seconds * RATE)
    for i in range(count):
        offset = first + i
        if not wrap and offset >= len(samples):
            break
        tail = smooth((count - 1 - i) / (RATE * 0.012))
        samples[offset % len(samples)] += sound(i / RATE) * gain * tail


def motif(seconds: float, pitches: tuple[int, ...], step: float) -> list[float]:
    samples = silence(seconds)
    for i, midi in enumerate(pitches):
        add(samples, i * step, seconds - i * step, toy_note(midi, 10.0),
            0.8 if i == len(pitches) - 1 else 0.65)
    return samples


def effects() -> dict[str, list[float]]:
    result = {
        "ready": motif(0.52, (72, 79, 76), 0.11),
        "round": motif(0.30, (67, 72), 0.09),
        "round_won": motif(0.63, (67, 72, 76), 0.105),
        "clean_wave": motif(0.82, (72, 79, 76, 84, 88), 0.095),
        "combo_5": motif(0.36, (72, 76, 79), 0.065),
        "combo_10": motif(0.44, (72, 76, 79, 84), 0.065),
        "combo_20": motif(0.54, (72, 76, 79, 84, 88), 0.065),
        "fail": motif(0.80, (67, 64, 62, 60), 0.145),
        "binding_ping": motif(0.10, (79,), 0.0),
    }
    for name, seconds in (("zap", 0.18), ("pop", 0.14), ("wrong", 0.25),
                          ("escape", 0.35), ("go", 0.42), ("tick", 0.035),
                          ("not_yet", 0.065), ("unknown", 0.20)):
        samples = silence(seconds)
        rng = noise_source(name)
        air = 0.0
        for i in range(len(samples)):
            t = i / RATE
            air = air * 0.62 + rng.uniform(-1.0, 1.0) * 0.38
            if name == "zap":
                phase = TAU * (190 * t + 1650 / 23 * (1.0 - exp(-23 * t)))
                value = (sin(phase) + 0.18 * sin(phase * 1.51) + 0.07 * air)
                value *= envelope(t, seconds, 0.0015, 18.0, 0.025)
            elif name == "pop":
                phase = TAU * (58 * t + 160 / 30 * (1.0 - exp(-30 * t)))
                value = (sin(phase) + 0.22 * sin(phase * 2.35) + 0.11 * air)
                value *= envelope(t, seconds, 0.002, 30.0, 0.02)
            elif name == "wrong":
                phase = TAU * frequency(52) * t
                other = phase * 2.0 ** (1.0 / 12.0)
                value = (sin(phase) + sin(other) + 0.16 * sin(3 * phase))
                value *= 0.82 + 0.18 * sin(TAU * 32 * t)
                value *= envelope(t, seconds, 0.007, 1.8)
            elif name == "escape":
                phase = TAU * (80 * t + 780 / 7 * (1.0 - exp(-7 * t)))
                value = sin(phase) * 0.8 + air * (0.25 + 0.8 * t)
                value *= envelope(t, seconds, 0.004, 5.0, 0.06)
            elif name == "go":
                phase = TAU * (440 * t + 1500 * t * t)
                value = air * exp(-30 * t) + 0.4 * sin(phase) * exp(-9 * t)
                value += 0.35 * sin(TAU * 185 * t) * exp(-38 * t)
                value *= envelope(t, seconds, 0.002, 1.0, 0.06)
            elif name == "tick":
                value = sin(TAU * 1580 * t) + 0.4 * sin(TAU * 570 * t)
                value *= envelope(t, seconds, 0.0008, 145.0, 0.008)
            elif name == "not_yet":
                value = sin(TAU * 205 * t) + 0.15 * sin(TAU * 410 * t)
                value *= envelope(t, seconds, 0.002, 70.0, 0.015)
            else:
                value = sin(TAU * frequency(58) * t)
                value *= envelope(t, seconds, 0.006, 0.0, 0.009)
            samples[i] = value
        result[name] = samples
    return result


def motion_loop() -> list[float]:
    """A periodic, unpitched air/servo texture; not another memorization melody."""
    samples = silence(2.0)
    rng = noise_source("motion air")
    partials = [(rng.randrange(320, 2400) / 2.0, rng.random() * TAU,
                 rng.uniform(0.3, 1.0)) for _ in range(48)]
    for i in range(len(samples)):
        t = i / RATE
        air = sum(sin(TAU * hz * t + phase) * gain for hz, phase, gain in partials)
        breath = 0.72 + 0.18 * cos(TAU * t / 2.0) + 0.1 * sin(TAU * t)
        samples[i] = air * breath / 12.0 + 0.035 * sin(TAU * 71 * t)
    return samples


def laboratory_music() -> list[list[float]]:
    """'Little Photon Workshop': original 8-bar, 80 BPM wooden-celesta miniature."""
    beat = 0.75
    seconds = 32 * beat
    left, right = silence(seconds), silence(seconds)
    melody = (
        (0.0, 76), (1.25, 79), (2.5, 74),
        (4.0, 77), (5.5, 81), (6.75, 79),
        (8.0, 77), (9.0, 74), (10.5, 69),
        (12.0, 74), (13.25, 71), (15.0, 67),
        (16.0, 72), (17.25, 76), (18.5, 79),
        (20.0, 81), (21.5, 76), (23.0, 72),
        (24.0, 77), (25.25, 74), (26.5, 72),
        (28.0, 71), (29.5, 74), (31.0, 72),
    )
    for i, (at, midi) in enumerate(melody):
        pan = 0.18 if i % 3 == 0 else -0.12
        sound = toy_note(midi, 4.7)
        for delay, level in ((0.0, 1.0), (0.083, 0.12), (0.173, 0.07), (0.337, 0.035)):
            add(left, at * beat + delay, 1.4, sound, 0.13 * level * (1.0 - pan), True)
            add(right, at * beat + delay, 1.4, sound, 0.13 * level * (1.0 + pan), True)
            pan = -pan
    for bar, root in enumerate((48, 53, 50, 55, 48, 57, 53, 55)):
        for pulse, interval in ((0.0, 0), (2.0, 7)):
            sound = toy_note(root + interval, 3.8)
            add(left, (bar * 4 + pulse) * beat, 1.8, sound, 0.075, True)
            add(right, (bar * 4 + pulse) * beat, 1.8, sound, 0.071, True)
        third = 3 if root in (50, 57) else 4
        for interval in (12, 12 + third, 19):
            hz = frequency(root + interval)

            def pad(t: float, hz: float = hz) -> float:
                return (sin(TAU * hz * t) + 0.12 * sin(TAU * hz * 2 * t)) * (
                    smooth(t / 0.19) * smooth((3.25 - t) / 0.48)
                )

            add(left, bar * 4 * beat, 3.25, pad, 0.013, True)
            add(right, bar * 4 * beat + 0.009, 3.25, pad, 0.014, True)
    # Integer cycle counts close the quiet two-second breathing room tone.
    room_hz = [round(frequency(midi) * seconds) / seconds for midi in (48, 55, 64)]
    for i in range(len(left)):
        t = i / RATE
        room = sum(sin(TAU * hz * t) for hz in room_hz) * 0.002
        room *= 0.7 + 0.3 * cos(TAU * t / 2.0)
        left[i] += room
        right[i] += room
    return [left, right]


def pcm_wave(channels: list[list[float]], peak: float, rms: float,
             fade_seconds: float = 0.004) -> bytes:
    if not channels or not channels[0] or any(len(c) != len(channels[0]) for c in channels):
        raise ValueError("PCM needs nonempty, equal-length channels")
    count = len(channels[0])
    for channel in channels:
        if not all(isfinite(value) for value in channel):
            raise ValueError("Non-finite synthesized sample")
        mean = sum(channel) / count
        for i in range(count):
            edge = (min(i, count - 1 - i) / (RATE * fade_seconds)
                    if fade_seconds > 0 else 1.0)
            channel[i] = (channel[i] - mean) * smooth(edge)
    maximum = max(abs(value) for channel in channels for value in channel)
    measured_rms = sqrt(sum(value * value for c in channels for value in c)
                        / (count * len(channels)))
    if maximum == 0.0 or measured_rms == 0.0:
        raise ValueError("Refusing to normalize silent audio")
    gain = min(peak / maximum, rms / measured_rms)
    output = array("h")
    for frame in zip(*channels):
        for value in frame:
            sample = round(value * gain * 32767.0)
            if not -32767 < sample < 32767:
                raise ValueError("Normalization would clip")
            output.append(sample)
    if sys.byteorder != "little":
        output.byteswap()
    container = BytesIO()
    with wave.open(container, "wb") as wav:
        wav.setnchannels(len(channels))
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(output.tobytes())
    return container.getvalue()


def publish(path: Path, contents: bytes, check: bool) -> None:
    if check:
        if not path.is_file() or path.read_bytes() != contents:
            raise ValueError(f"Missing or non-reproducible WAV: {path}")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
    import_profile(path, check)


def import_profile(path: Path, check: bool) -> None:
    """Keep resource-local PCM settings, without importing a partial Godot project."""
    profile = path.with_suffix(".wav.import")
    config = ConfigParser(interpolation=None, delimiters=("=",))
    config.optionxform = str
    if profile.is_file():
        config.read_string(profile.read_text(encoding="utf-8"))
    settings = {
        "force/8_bit": "false",
        "force/mono": "false",
        "force/max_rate": "false",
        "force/max_rate_hz": str(RATE),
        "edit/trim": "false",
        "edit/normalize": "false",
        "edit/loop_mode": "0",
        "edit/loop_begin": "0",
        "edit/loop_end": "-1",
        "compress/mode": "0",
    }
    changed = [key for key, value in settings.items()
               if config.get("params", key, fallback=None) != value]
    if check:
        if changed:
            raise ValueError(f"Missing/changed PCM import settings in {profile}: {changed}")
        return
    if not profile.is_file():
        config["remap"] = {"importer": '"wav"', "type": '"AudioStreamWAV"'}
        uri = f"res://games/lazer_nfc/assets/audio/{path.parent.name}/{path.name}"
        config["deps"] = {"source_file": f'"{uri}"'}
    elif config.get("remap", "importer", fallback="") != '"wav"':
        raise ValueError(f"Unexpected importer in {profile}")
    if not changed:
        return
    if not config.has_section("params"):
        config.add_section("params")
    for key, value in settings.items():
        config["params"][key] = value
    output = StringIO()
    config.write(output, space_around_delimiters=False)
    profile.write_text(output.getvalue(), encoding="utf-8", newline="\n")


def finish_voices(source: Path, destination: Path, check: bool) -> None:
    paths = sorted(source.glob("*.wav"))
    if not paths:
        raise ValueError(f"No System.Speech WAVs in {source}")
    longest_round = 0.0
    for path in paths:
        with wave.open(str(path), "rb") as wav:
            if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (1, 2, RATE):
                raise ValueError(f"Voice must be mono PCM16 at {RATE} Hz: {path}")
            samples = array("h", wav.readframes(wav.getnframes()))
        if sys.byteorder != "little":
            samples.byteswap()
        peak = max(abs(value) for value in samples)
        if peak == 0:
            raise ValueError(f"Silent System.Speech output: {path}")
        audible = [i for i, value in enumerate(samples) if abs(value) >= peak * 0.008]
        first = max(audible[0] - round(RATE * 0.025), 0)
        last = min(audible[-1] + round(RATE * 0.035) + 1, len(samples))
        trimmed = [value / 32768.0 for value in samples[first:last]]
        if path.stem.startswith("round_") and path.stem[6:].isdigit():
            longest_round = max(longest_round, len(trimmed) / RATE)
        publish(destination / path.name, pcm_wave([trimmed], 0.56, 0.16, 0.004), check)
    verb = "Checked" if check else "Baked"
    print(f"{verb} {len(paths)} offline System.Speech prompts; "
          f"longest numbered round {longest_round:.3f} s.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--voice-source", type=Path)
    parser.add_argument("--voice-destination", type=Path)
    args = parser.parse_args()
    if args.voice_source is not None:
        if args.voice_destination is None:
            parser.error("--voice-source also needs --voice-destination")
        finish_voices(args.voice_source, args.voice_destination, args.check)
        return
    if args.voice_destination is not None:
        parser.error("--voice-destination also needs --voice-source")
    for hue, midi, attack, decay in HUES:
        for shade in SHADES:
            samples = instrument(hue, midi, shade, attack, decay)
            publish(DESTINATION / "colors" / f"{hue}_{shade}.wav",
                    pcm_wave([samples], 0.56, 0.16), args.check)
    cues = effects()
    for name, samples in cues.items():
        publish(DESTINATION / "cues" / f"{name}.wav",
                pcm_wave([samples], 0.50, 0.14, 0.0007), args.check)
    publish(DESTINATION / "loops" / "motion_riser.wav",
            pcm_wave([motion_loop()], 0.28, 0.075, 0.0), args.check)
    publish(DESTINATION / "loops" / "toy_lab.wav",
            pcm_wave(laboratory_music(), 0.38, 0.105, 0.0), args.check)
    verb = "Checked" if args.check else "Baked"
    print(f"{verb} {21 + len(cues) + 2} original WAVs: "
          f"21 instruments, {len(cues)} cues, 2 seamless loops; {RATE} Hz PCM16.")


if __name__ == "__main__":
    main()
