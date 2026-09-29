#!/usr/bin/env python3
"""Render the authored narration with macOS's installed local Samantha voice.

Run from any directory. Generated audio and its measured manifest stay in build/.
Requires macOS system speech services; sandboxed `say` can return empty audio.
No network service or package dependency is used.
"""
from __future__ import annotations

import argparse
import array
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile


REPO = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = Path(__file__).resolve().parent / "assets" / "narration.json"
DEFAULT_OUTPUT = REPO / "native" / "build" / "qa" / "walkthrough-audio"


def inspect_audio(path: Path) -> dict:
    result = subprocess.run(
        ["/usr/bin/afinfo", str(path)], check=True, capture_output=True, text=True
    ).stdout

    def number(pattern: str) -> float:
        match = re.search(pattern, result)
        if not match:
            raise ValueError(f"Cannot read audio metadata for {path.name}: {pattern}")
        return float(match.group(1))

    duration = number(r"estimated duration:\s*([\d.]+)")
    data_count = int(number(r"audio bytes:\s*(\d+)"))
    offset = int(number(r"audio data file offset:\s*(\d+)"))
    sample_rate = int(number(r"Data format:\s*\d+ ch,\s*(\d+) Hz"))
    channels = int(number(r"Data format:\s*(\d+) ch,"))
    if duration <= 0 or data_count == 0:
        raise ValueError(
            f"{path.name} is empty. Run outside the sandbox so macOS speech services are available."
        )
    if "16-bit big-endian signed integer" not in result:
        raise ValueError(f"Unexpected AIFF sample format for {path.name}")
    samples = array.array("h", path.read_bytes()[offset : offset + data_count])
    if sys.byteorder == "little":
        samples.byteswap()
    peak = max(abs(value) for value in samples) / 32768
    rms = math.sqrt(sum(value * value for value in samples) / len(samples)) / 32768
    if peak < 0.01 or rms < 0.001:
        raise ValueError(f"{path.name} contains no usable speech signal")
    return {
        "durationSeconds": duration,
        "sampleRate": sample_rate,
        "channels": channels,
        "peakAmplitude": peak,
        "rmsAmplitude": rms,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="Verify existing audio without rendering again.")
    args = parser.parse_args()
    lines = json.loads(args.source.read_text())
    if not lines:
        raise ValueError("Narration source has no lines")
    seen = set()
    for line in lines:
        if not re.fullmatch(r"[0-9]{2}\.aiff", line["file"]):
            raise ValueError("Audio filenames must use NN.aiff")
        if line["file"] in seen or not line["text"].strip():
            raise ValueError("Duplicate filename or empty narration")
        if not 0 <= line["at"] < line["until"]:
            raise ValueError("Invalid narration timing")
        seen.add(line["file"])
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="dabin-narration-", dir=args.output) as folder:
        staging = Path(folder)
        measured = []
        for index, line in enumerate(lines):
            target = args.output / line["file"] if args.check else staging / line["file"]
            if not args.check:
                text_path = staging / (target.stem + ".txt")
                text_path.write_text(line["text"] + "\n")
                subprocess.run(
                    ["/usr/bin/say", "-v", "Samantha", "-r", "170", "-f", str(text_path), "-o", str(target)],
                    check=True,
                )
            metadata = inspect_audio(target)
            end = line["at"] + metadata["durationSeconds"]
            if end > line["until"]:
                raise ValueError(f"{line['file']} exceeds its caption: {end:.3f}s > {line['until']:.3f}s")
            if index + 1 < len(lines) and end > lines[index + 1]["at"]:
                raise ValueError(f"{line['file']} overlaps the next narration line")
            measured.append({"index": index + 1, **line, "voice": "Samantha", "rateWPM": 170,
                             **metadata, "endSeconds": end})
        # Only replace previous outputs after every clip passes validation.
        if not args.check:
            for line in lines:
                (staging / line["file"]).replace(args.output / line["file"])
        manifest = staging / "narration.json"
        manifest.write_text(json.dumps(measured, indent=2, ensure_ascii=False) + "\n")
        manifest.replace(args.output / "narration.json")
    print(f"PASS: {len(lines)} non-silent local voice clips; no overlaps; final end {measured[-1]['endSeconds']:.3f}s")
    print(args.output.resolve())


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Narration generation failed: {error}", file=sys.stderr)
        sys.exit(1)
