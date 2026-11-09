#!/usr/bin/env bash
# Offline Unix voice authoring; needs Python 3.10+, eSpeak NG and ffmpeg.
set -euo pipefail
script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON:-python3}" - "$script_dir" "$@" <<'PY'
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


TOOLS = Path(sys.argv.pop(1)).resolve()


def prompts() -> dict[str, str]:
    bank = {
        "ready": "Ready. Tap a tag to start.",
        "recall": "Recall!", "round": "Round.", "score": "Score.",
        "round_won": "Round cleared!", "clean_wave": "Clean sweep!",
        "run_over": "Experiment complete.", "assisted": "Assisted.",
        "binding": "Tag roll call. Tap your phone's upper back against each tag.",
        "need_tags": "Bind three colours, or choose keys and touch.",
        "bound": "Bound.", "skipped": "Skipped.",
        "shades_on": "Shades on.", "shades_off": "Shades off.",
        "touch_on": "Touch pad shown.", "touch_off": "Touch pad hidden.",
        "settings_changed": "Settings changed.",
        "nfc_off": "N. F. C. unavailable. Keys and touch are ready.",
        "not_yet": "Not yet.", "unknown": "Unknown tag.",
        "practice": "Learn the sounds.",
        "gestures": (
            "Double tap red for shades, yellow for the touch pad, "
            "or violet to bind tags again."
        ),
    }
    numbers = (
        "zero", "one", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
        "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
    )
    for number, text in enumerate(numbers):
        bank[f"number_{number}"] = text + "."
    for number, text in enumerate(
        ("thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"), 3,
    ):
        bank[f"number_{number * 10}"] = text + "."
    bank.update(number_100="Hundred.", number_1000="Thousand.")
    for number in range(1, 21):
        bank[f"round_{number}"] = f"Round {numbers[number]}."
    for hue in ("red", "orange", "yellow", "green", "blue", "indigo", "violet"):
        for shade in ("base", "dark", "light"):
            key = hue if shade == "base" else f"{hue}_{shade}"
            text = hue if shade == "base" else f"{shade} {hue}"
            bank[key] = text + "."
            bank[f"bind_{key}"] = f"Scan the tag for {text}."
    return bank


def executable(value: str) -> str:
    found = shutil.which(os.path.expanduser(value))
    if found is None:
        raise FileNotFoundError(f"Cannot run '{value}'; supply an executable path.")
    return found


def words_per_minute(rate: int) -> int:
    # Keep the PowerShell rate levels, not a claim of matching Windows speech.
    return min(max(175 + 25 * rate, 80), 450)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Bake original prompts with offline eSpeak NG, not Microsoft Zira. "
            "--check requires a bank baked with the same voice/engine version."
        ),
    )
    parser.add_argument("--voice", default="en-us")
    parser.add_argument("--rate", type=int, default=3)
    parser.add_argument("--round-rate", type=int, default=6)
    parser.add_argument("--espeak-ng", default="espeak-ng")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--check", action="store_true")
    parser.add_argument(
        "--destination", type=Path,
        default=TOOLS.parent / "assets" / "audio" / "voice",
        help="alternate bank for reviewing a Unix voice without replacing Zira",
    )
    args = parser.parse_args()
    if not -10 <= args.rate <= 10 or not -10 <= args.round_rate <= 10:
        parser.error("--rate and --round-rate must be between -10 and 10")
    espeak = executable(args.espeak_ng)
    ffmpeg = executable(args.ffmpeg)
    with tempfile.TemporaryDirectory(prefix="lazer-nfc-voice-") as temporary:
        work = Path(temporary)
        raw = work / "raw"
        source = work / "source"
        raw.mkdir()
        source.mkdir()
        for name, text in prompts().items():
            rate = args.rate
            if re.fullmatch(r"round_\d+", name):
                rate = args.round_rate
            elif name.startswith("number_"):
                rate = min(args.rate + 2, 10)
            wav = raw / f"{name}.wav"
            finished = source / wav.name
            subprocess.run([
                espeak, "-v", args.voice, "-s", str(words_per_minute(rate)),
                "-a", "100", "-w", str(wav), text,
            ], check=True)
            subprocess.run([
                ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
                "-i", str(wav), "-ac", "1", "-ar", "44100",
                "-c:a", "pcm_s16le", str(finished),
            ], check=True)
            if not finished.is_file() or finished.stat().st_size == 0:
                raise RuntimeError(f"Voice authoring did not create '{finished}'.")
        arguments = [
            sys.executable, str(TOOLS / "bake_colors.py"),
            "--voice-source", str(source),
            "--voice-destination", str(args.destination.expanduser().resolve()),
        ]
        if args.check:
            arguments.append("--check")
        subprocess.run(arguments, check=True)
    print(f"Voice authoring: {args.voice}; eSpeak NG; "
          f"core rate {args.rate}, round rate {args.round_rate}.")


try:
    main()
except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
    print(f"Offline voice authoring failed: {error}", file=sys.stderr)
    sys.exit(1)
except KeyboardInterrupt:
    print("Offline voice authoring interrupted.", file=sys.stderr)
    sys.exit(130)
PY
