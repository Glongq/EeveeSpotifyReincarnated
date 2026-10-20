#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
BUILD="$PWD/NativeDownloads/build/jailbreak-tests"
mkdir -p "$BUILD"
python3 NativeDownloads/jailbreak/generate_guards.py --check
xcrun clang -fobjc-arc -std=gnu11 -Imodules/fishhook \
    -framework Foundation -framework AudioToolbox -fsanitize=address,undefined \
    NativeDownloads/jailbreak/test_runtime.m -o "$BUILD/test-runtime"
UBSAN_OPTIONS=halt_on_error=1 "$BUILD/test-runtime"
xcrun clang -dynamiclib -arch arm64 -fobjc-arc -std=gnu11 -O1 \
    -DSAP_JB_IMPORT_TEST -DSAP_ENABLE_WAV_CAPTURE=0 -Imodules/fishhook -INativeDownloads/src \
    NativeDownloads/jailbreak/Runtime.m modules/fishhook/fishhook.c \
    NativeDownloads/src/AudioProbe.c NativeDownloads/src/CaptureRing.c \
    NativeDownloads/src/Diagnostics.m NativeDownloads/src/Localization.m \
    -framework AudioToolbox -framework Foundation -o "$BUILD/adapter.dylib"
xcrun clang -arch arm64 -std=gnu11 -INativeDownloads/src \
    NativeDownloads/jailbreak/test_imports.c -framework AudioToolbox -framework Foundation -o "$BUILD/test-imports"
"$BUILD/test-imports" "$BUILD/adapter.dylib"
