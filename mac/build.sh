#!/bin/bash
# Builds Voice to Text (Mantra).app: Swift + whisper.cpp (Metal, embedded), signed "Mantra Apps", zipped as dist/VoiceToTextMantra-vN-mac.zip.
#   ./build.sh               build, zip and publish (tools/publish.sh: release, page, live check; MANTRA_MANIFEST download-always-latest)
#   ./build.sh --no-publish  build and zip only
#   ./build.sh --install     also copy into /Applications (never installs over anything otherwise)
# WHISPER: a whisper.cpp checkout built as static libraries (see README), default ~/Developer/VOICE_ENGINES/src/whisper.cpp
set -euo pipefail
cd "$(dirname "$0")"
INSTALL=0; PUBLISH=1
for a in "$@"; do case "$a" in --install) INSTALL=1;; --no-publish) PUBLISH=0;; *) echo "unknown option $a"; exit 1;; esac; done
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
if [ $INSTALL = 1 ]; then rm -rf "/Applications/$NAME.app"; cp -R "$APP" /Applications/; echo "installed /Applications/$NAME.app"; fi
if [ $PUBLISH = 1 ]; then ../tools/publish.sh; else echo "not published (--no-publish)"; fi
