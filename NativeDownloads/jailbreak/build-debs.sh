#!/usr/bin/env bash
# Local-only builds. This script never pushes or creates a GitHub release.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
: "${THEOS_ROOTLESS:?Set THEOS_ROOTLESS to a standard Theos checkout}"
: "${THEOS_ROOTHIDE:?Set THEOS_ROOTHIDE to a RootHide Theos checkout}"
MAKE="${MAKE:-gmake}"
VERSION="${PACKAGE_VERSION:-7.0.0+sprite.v1-2}"
OUTPUT="$ROOT/NativeDownloads/outputs/pixie-v1"
mkdir -p "$OUTPUT"
python3 NativeDownloads/jailbreak/generate_guards.py --check
python3 NativeDownloads/tools/test_patchers.py
bash NativeDownloads/jailbreak/test.sh
for scheme in rootless roothide; do
    if [ "$scheme" = rootless ]; then export THEOS="$THEOS_ROOTLESS"; else export THEOS="$THEOS_ROOTHIDE"; fi
    export THEOS_PACKAGE_SCHEME="$scheme"
    framework="$THEOS/lib/iphone/$scheme/EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf"
    if [ ! -f "$framework" ]; then
        DEPLOY_TARGET=16.1 bash Tools/SwiftProtobufBuild/build-eeveeswiftprotobuf.sh
    fi
    "$MAKE" clean _THEOS_RELATIVE_DATA_DIR="NativeDownloads/build/theos-$scheme"
    "$MAKE" package FINALPACKAGE=1 NATIVE_DOWNLOADS_JAILBREAK=1 \
        THEOS_PACKAGE_BASE_VERSION="$VERSION" _THEOS_RELATIVE_DATA_DIR="NativeDownloads/build/theos-$scheme" REPO_SLUG=Glongq/EeveeSpotifyReincarnated BRANCH_NAME=Master
    if [ "$scheme" = rootless ]; then arch=iphoneos-arm64; else arch=iphoneos-arm64e; fi
    source="packages/com.eevee.spotify_${VERSION}_${arch}.deb"
    test -f "$source"
    target="$OUTPUT/Spotify-9.1.88-Eevee-Pixie-v1-$scheme.deb"
    cp "$source" "$target"
    python3 NativeDownloads/jailbreak/verify_deb.py "$target" "$scheme"
done
(cd "$OUTPUT" && shasum -a 256 ./*.deb > SHA256SUMS)
printf 'Local packages: %s\n' "$OUTPUT"
