#!/bin/bash
set -euo pipefail

# Generates real native product views with isolated sample data. This does not
# replace the installed app, use real credentials, or publish anything.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/docs/media/ui-redesign}"
DERIVED_DIR="${PULSE_DEMO_DERIVED_DATA:-/tmp/PulseUIDemoDerivedData}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
command -v ffmpeg >/dev/null

for language in en zh-Hans; do
  region=US
  if [[ "$language" == "zh-Hans" ]]; then region=CN; fi
  TEST_RUNNER_PULSE_UI_DEMO_OUTPUT="$OUTPUT_DIR" \
  TEST_RUNNER_PULSE_UI_DEMO_LANGUAGE="$language" \
  xcodebuild -quiet -project "$PROJECT_ROOT/Pulse.xcodeproj" -scheme Pulse \
    -testLanguage "$language" -testRegion "$region" \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DIR" CODE_SIGNING_ALLOWED=NO \
    -only-testing:PulseTests/UIDemoExportTests/testExportNativeScreenshotsAndMotionFrames test

  ffmpeg -y -loglevel error -framerate 30 -i "$OUTPUT_DIR/frames-$language/%04d.png" \
    -c:v libx264 -crf 18 -pix_fmt yuv420p -movflags +faststart \
    "$OUTPUT_DIR/pulse-demo-$language.mp4"
  ffmpeg -y -loglevel error -i "$OUTPUT_DIR/pulse-demo-$language.mp4" \
    -filter_complex '[0:v]fps=15,scale=768:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse' \
    "$OUTPUT_DIR/pulse-demo-$language.gif"
  # Intermediate frames are safe to remove: they were created only by this
  # exporter, and the compact video/GIF plus still screenshots remain.
  rm -f "$OUTPUT_DIR/frames-$language/"[0-9][0-9][0-9][0-9].png
  rmdir "$OUTPUT_DIR/frames-$language"
done

printf 'Native demo artifacts: %s\n' "$OUTPUT_DIR"
