#!/bin/bash
set -euo pipefail
native_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$native_root/.." && pwd)"
output_root="${1:-$repo_root/docs/qa/island-playground-2026-09-29}"
ffmpeg_bin="${DABIN_FFMPEG:-$native_root/build/walkthrough-tools/imageio_ffmpeg/binaries/ffmpeg-macos-aarch64-v7.1}"
if [[ ! -x "$ffmpeg_bin" ]]; then
  echo "Set DABIN_FFMPEG to an existing local FFmpeg executable." >&2
  exit 1
fi
mkdir -p "$native_root/build/island-preview/ModuleCache" "$output_root"
# Render into a fresh directory. Existing review artifacts are left untouched
# until the new native frames and complete MP4 both pass verification.
run_dir="$(mktemp -d "$native_root/build/island-preview/run.XXXXXX")"
sources=(
  "$native_root/Sources/DaBin/RobotMotion.swift"
  "$native_root/Sources/DaBin/AutoCaptureRobotCelebration.swift"
  "$native_root/Sources/DaBin/IslandRobotChoreography.swift"
  "$native_root/Sources/DaBin/RobotCharacterView.swift"
)
shasum -a 256 "${sources[@]}" "$native_root/Tests/IslandPlaygroundRender.swift" \
  "$native_root/scripts/render_island_playground.sh" > "$run_dir/source-hashes.txt"
xcrun swiftc -swift-version 5 -O -whole-module-optimization \
  -target arm64-apple-macosx14.0 -warnings-as-errors -parse-as-library \
  -module-cache-path "$native_root/build/island-preview/ModuleCache" \
  "${sources[@]}" "$native_root/Tests/IslandPlaygroundRender.swift" \
  -o "$run_dir/IslandPlaygroundRender"
"$run_dir/IslandPlaygroundRender" "$run_dir" | tee "$run_dir/render.log"
"$ffmpeg_bin" -hide_banner -y -framerate 30 -i "$run_dir/frames/frame-%05d.png" \
  -an -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -movflags +faststart \
  "$run_dir/DaBin-Island-Playground.mp4" 2> "$run_dir/ffmpeg.log"
sample_times="$(python3 - "$run_dir/native-render.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    manifest = json.load(source)
print(",".join(f"{time:.6f}" for time in manifest["contactSheetTimes"]))
PY
)"
swift -module-cache-path "$native_root/build/island-preview/ModuleCache" \
  "$repo_root/design/walkthrough/inspect_video.swift" \
  "$run_dir/DaBin-Island-Playground.mp4" "$run_dir/encoded-qa" \
  --times "$sample_times" --decode > "$run_dir/inspection.log"
python3 - "$run_dir/native-render.json" "$run_dir/encoded-qa/metadata.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    native = json.load(source)
with open(sys.argv[2], encoding="utf-8") as source:
    media = json.load(source)
track = next(item for item in media["tracks"] if item["type"] == "vide")
decoded = next(item for item in media["decode"] if item["type"] == "vide")
assert (track["width"], track["height"]) == (900, 600), track
assert abs(track["fps"] - 30) < 0.01, track
assert decoded["status"] == "completed" and decoded["timestampsMonotonic"], decoded
assert decoded["sampleBuffers"] == native["frameCount"], (decoded, native["frameCount"])
assert abs(media["durationSeconds"] - native["durationSeconds"]) < 0.05, media["durationSeconds"]
assert media["playable"] and media["audioTrackCount"] == 0, media
print("PASS: encoded MP4 dimensions, timing, frame count and full decode")
PY
shasum -a 256 "${sources[@]}" "$native_root/Tests/IslandPlaygroundRender.swift" \
  "$native_root/scripts/render_island_playground.sh" > "$run_dir/source-hashes-after.txt"
if ! cmp -s "$run_dir/source-hashes.txt" "$run_dir/source-hashes-after.txt"; then
  echo "Sources changed during rendering; intermediate frames were preserved in $run_dir. Rerun on stable sources." >&2
  exit 1
fi
for artifact in DaBin-Island-Playground.mp4 contact-sheet.png native-render.json source-hashes.txt render.log ffmpeg.log; do
  cp "$run_dir/$artifact" "$output_root/$artifact"
done
mkdir -p "$output_root/encoded-qa"
cp "$run_dir/encoded-qa/"*.png "$run_dir/encoded-qa/metadata.json" "$output_root/encoded-qa/"
printf '%s\n' "$run_dir" > "$output_root/frame-directory.txt"
printf '%s\n' 'Native production Core Animation preview in an isolated offscreen process.' \
  'The desktop and laptop are fictional vector backdrops. This is not the installed app or a screen recording.' \
  'Both scales use the same live presentation-layer frame. No editorial robot movement was added.' \
  'Silent 900 × 600, 30 fps MP4; native frame timings/deltas and full encoded decode are recorded alongside it.' \
  > "$output_root/README.txt"
printf 'Preview: %s\n' "$output_root/DaBin-Island-Playground.mp4"
printf 'Encoded contact sheet: %s\n' "$output_root/encoded-qa/contact-sheet.png"
