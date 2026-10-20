#!/bin/bash
# Double-click to compile the app (simulator build, no signing). Writes build.log next to this file.
cd "$(dirname "$0")"
LOG="$PWD/build.log"
: > "$LOG"
xcodebuild -project Lookout.xcodeproj -target Lookout -configuration Debug -sdk iphonesimulator \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tee -a "$LOG" | grep -E "error:|warning: unre|BUILD|Compiling|Linking" | tail -60
echo "BUILD EXIT: ${PIPESTATUS[0]}" | tee -a "$LOG"
