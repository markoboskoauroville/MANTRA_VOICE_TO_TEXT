#!/bin/bash
# Builds Voice to Text (Mantra).app: Swift + whisper.cpp (Metal, embedded), signed "Mantra Apps", zipped as dist/VoiceToTextMantra-vN-mac.zip.
#   ./build.sh               build, zip and publish (tools/publish.sh: release, page, live check; MANTRA_MANIFEST download-always-latest)
#   ./build.sh --no-publish  build and zip only
#   every build is installed in /Applications (v3, Marko 1.11.2026: "in the Star menu ... and also inside the application
#   folder"): the running copy is asked to quit (refused while it listens or writes down), the new one is opened
# WHISPER: a whisper.cpp checkout built as static libraries (see README), default ~/Developer/VOICE_ENGINES/src/whisper.cpp
set -euo pipefail
cd "$(dirname "$0")"
PUBLISH=1
for a in "$@"; do case "$a" in --install) ;; --no-publish) PUBLISH=0;; *) echo "unknown option $a"; exit 1;; esac; done
W="${WHISPER:-$HOME/Developer/VOICE_ENGINES/src/whisper.cpp}"
B="$W/build-static"
if [ ! -f "$B/src/libwhisper.a" ]; then
  cmake -S "$W" -B "$B" -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_NATIVE=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_C_FLAGS="-ffile-prefix-map=$W=whisper.cpp" -DCMAKE_CXX_FLAGS="-ffile-prefix-map=$W=whisper.cpp" -DCMAKE_OBJC_FLAGS="-ffile-prefix-map=$W=whisper.cpp"
  cmake --build "$B" -j 8 --config Release
fi
V=$(grep -E '^let appVersion' Sources/Engines.swift | grep -oE '[0-9]+')
NAME="Voice to Text (Mantra)"
APP="build/$NAME.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift \
  -import-objc-header Sources/Bridge.h -I "$W/include" -I "$W/ggml/include" \
  "$B/src/libwhisper.a" "$B/ggml/src/libggml.a" "$B/ggml/src/libggml-base.a" "$B/ggml/src/libggml-cpu.a" \
  "$B/ggml/src/ggml-metal/libggml-metal.a" "$B/ggml/src/ggml-blas/libggml-blas.a" -lc++ \
  -framework AppKit -framework AVFoundation -framework Carbon -framework Speech -framework Metal -framework MetalKit \
  -framework Foundation -framework Accelerate \
  -o "$APP/Contents/MacOS/$NAME"
sed "s/__VERSION__/$V/g" Resources/Info.plist > "$APP/Contents/Info.plist"
swift Tools/make_icon.swift build/AppIcon.iconset "$V"
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep -s "Mantra Apps" "$APP"
codesign --verify --deep "$APP"
rm -f "dist/VoiceToTextMantra-v$V-mac.zip"
ditto -c -k --keepParent "$APP" "dist/VoiceToTextMantra-v$V-mac.zip"
echo "built v$V: $APP and dist/VoiceToTextMantra-v$V-mac.zip ($(du -h "dist/VoiceToTextMantra-v$V-mac.zip" | cut -f1))"
running() { pgrep -qf "/Contents/MacOS/(Voice to Text \(Mantra\)|Transcribe Voice to Text RT)( |$)"; }
WAS=0
if running; then
  WAS=1
  osascript -l JavaScript -e 'ObjC.import("Foundation"); $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("com.mantra.voicetotext.quit", $(), $(), true)' >/dev/null
  for i in $(seq 1 30); do running || break; sleep 0.2; done
  if running; then echo "it is still running (a take in progress): not installed"; exit 1; fi
  echo "the running copy quit"
fi
rm -rf "/Applications/$NAME.app"; cp -R "$APP" /Applications/; echo "installed /Applications/$NAME.app"
[ "$WAS" = 1 ] && open "/Applications/$NAME.app" && echo "opened the new one"
if [ $PUBLISH = 1 ]; then ../tools/publish.sh; else echo "not published (--no-publish)"; fi
