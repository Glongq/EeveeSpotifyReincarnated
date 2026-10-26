"""Build the guarded SpotifyAudioProbe overlay for the supplied EeveeSpotify 7.0.0 / Spotify 9.1.90 IPA."""
import argparse
import hashlib
import json
import plistlib
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path
from zipfile import ZipFile

from patch_imports import patch as patch_audio_imports
from patch_native_restrictions import patch as patch_limits, guard_header, limits_header, layout
from patch_key_request_mode import patch as patch_key_mode, key_header
from patch_native_trace import patch as patch_native_trace,header as native_trace_header
from patch_offline import patch_reminder
from signing_metadata import sign_preserving_entitlements

ROOT = Path(__file__).resolve().parents[1]
UUID = bytes.fromhex("fbce22c17e1b3e0d9be866ff9291943e")
SOURCE_FILES = [
    "AudioProbe.c", "Diagnostics.m", "Localization.m",
    "AVAudioHooks.m", "SourceGraph.c", "OfflineFlags.m", "WireProto.m",
    "OfflineConfig.m", "TrackJournal.m", "NativeErrorLog.m", "PlayerTrace.m",
    "NativeOffline.m", "NativeAlbumCommand.m", "TrackDownload.m", "AudioProbeUI.m", "DownloadSettingsUI.m",
    "EncodedAudio.m", "AlbumMetadata.m", "ArtistMetadata.m", "ArtistDownloadQueue.m", "ArtistDownloadSession.m", "ArtistDownloadsUI.m", "PlaylistDownloads.m",
    "SupportLog.m", "DownloadCompatibility.m", "OfflineDevices.m",
    "DiagnosticTrace.m", "TracePlatform.m", "NativeKeyTrace.m",
]


def run(*command):
    subprocess.run([str(part) for part in command], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--eevee-dylib", type=Path, help="EeveeSpotify rebuilt from the local sources")
    parser.add_argument("--fixed-key-mode-zero", action="store_true", help="Recovery rollback: use the direct mode-0 instruction from the last working build, without the runtime selector")
    parser.add_argument("--output", type=Path, default=ROOT.parent / "outputs" /
        datetime.now().strftime("build-%Y%m%d-%H%M%S-%f") / "Spotify-9.1.90-EeveeSpotify-Pixie-v1.3.ipa")
    args = parser.parse_args()
    source = args.ipa.resolve()
    output = args.output.resolve()
    if output.exists():
        parser.error("Choose a new output folder; the output IPA already exists")
    eevee = args.eevee_dylib.resolve() if args.eevee_dylib else None
    if eevee:
        run("codesign", "--verify", "--strict", eevee)
        run("xcrun", "dyld_info", "-validate_only", eevee)
        if b"EeveePixieUpdateArtistDownloads" not in eevee.read_bytes():
            raise RuntimeError("The rebuilt EeveeSpotify lacks the Pixie artist controls")
    if not source.is_file():
        parser.error("Input IPA not found")
    if (ROOT / "src/NativeRestrictionsPatch.h").read_text() != guard_header():
        raise RuntimeError("Native restriction header is out of sync")
    if (ROOT / "src/OfflineLimits.h").read_text() != limits_header():
        raise RuntimeError("Offline limits header is out of sync")
    if (ROOT / "src/NativeKeyModePatch.h").read_text() != key_header():
        raise RuntimeError("Native key-mode header is out of sync")
    if (ROOT / "src/NativeTracePatch.h").read_text() != native_trace_header():
        raise RuntimeError("Native trace header is out of sync")

    with ZipFile(source) as archive:
        info_name = "Payload/Spotify.app/Info.plist"
        info = plistlib.loads(archive.read(info_name))
        if info.get("CFBundleShortVersionString") != "9.1.90":
            raise RuntimeError("Expected Spotify 9.1.90")
        executable = "Payload/Spotify.app/Spotify"
        native = archive.read(executable)
        if layout(native)[3] != UUID:
            raise RuntimeError("Unsupported Spotify 9.1.90 executable UUID")
        if "Payload/Spotify.app/Frameworks/EeveeSpotify.dylib" not in archive.namelist():
            raise RuntimeError("Expected EeveeSpotify's EeveeSpotify.dylib")
        eevee_bytes = eevee.read_bytes() if eevee else archive.read("Payload/Spotify.app/Frameworks/EeveeSpotify.dylib")

    patched, audio = patch_audio_imports(native)
    patched, limits = patch_limits(patched)
    patched, key = patch_key_mode(patched, runtime_selectable=False)
    patched, native_trace = patch_native_trace(patched)
    key['implementation']='verified static observation boundary restores fixed w2=0 before the original indirect call'
    key['configuration_source']='verified_static_trace_argument'
    output.parent.mkdir(parents=True, exist_ok=True)
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="eevee-9190-") as temporary:
        temporary = Path(temporary)
        staged_eevee = temporary / "EeveeSpotify.dylib"
        eevee_bytes, reminder = patch_reminder(eevee_bytes)
        staged_eevee.write_bytes(eevee_bytes)
        run("codesign", "--force", "--sign", "-", "--timestamp=none", staged_eevee)
        run("codesign", "--verify", "--strict", staged_eevee)
        run("xcrun", "dyld_info", "-validate_only", staged_eevee)
        eevee = staged_eevee
        companion = temporary / "SpotifyAudioProbe.dylib"
        run("xcrun", "clang", "-dynamiclib", "-arch", "arm64", "-target", "arm64-apple-ios15.0",
            "-isysroot", sdk, "-fobjc-arc", "-std=gnu11", "-O2", "-fvisibility=hidden",
            "-Wall", "-Wextra", "-Wno-unused-parameter", "-Wno-nullability-completeness",
            "-Werror=implicit-function-declaration", "-I" + str(ROOT / "src"),
            *(ROOT / "src" / name for name in SOURCE_FILES),
            "-framework", "AudioToolbox", "-framework", "Foundation", "-framework", "UIKit",
            "-framework", "AVFAudio", "-framework", "CoreGraphics", "-framework", "AVFoundation",
            "-framework", "CoreMedia", "-framework", "Network", "-framework", "ImageIO", "-framework", "QuartzCore", "-Wl,-install_name,@rpath/SpotifyAudioProbe.dylib", "-o", companion)
        run("codesign", "--force", "--sign", "-", "--timestamp=none", companion)
        binary = temporary / "Spotify"
        binary.write_bytes(patched)
        binary.chmod(0o755)
        signing_metadata = sign_preserving_entitlements(binary, native, temporary / "Spotify.entitlements.plist")
        run("xcrun", "dyld_info", "-validate_only", binary)
        imports = subprocess.check_output(["xcrun", "dyld_info", "-imports", str(binary)], text=True)
        for change in audio["changes"]:
            matches = [line for line in imports.splitlines() if change["symbol"] in line]
            if not matches or not all("SpotifyAudioProbe" in line for line in matches):
                raise RuntimeError(f"Audio import not redirected: {change['symbol']}")
        with ZipFile(source) as original, ZipFile(output, "w", allowZip64=True) as result:
            for member in original.infolist():
                replacement = binary.read_bytes() if member.filename == executable else eevee.read_bytes() if eevee and member.filename == "Payload/Spotify.app/Frameworks/EeveeSpotify.dylib" else original.read(member.filename)
                result.writestr(member, replacement)
            result.write(companion, "Payload/Spotify.app/Frameworks/SpotifyAudioProbe.dylib")

    with ZipFile(output) as check:
        if check.testzip() is not None:
            raise RuntimeError("IPA ZIP integrity check failed")
    print(json.dumps({"output": str(output), "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                      "spotify_uuid": UUID.hex(), "audio_imports": audio,
                      "native_limits": limits, "key_request_mode": key, "native_observation": native_trace,
                      "signing_metadata": signing_metadata,
                      "eevee_native_download_reminder": reminder}, indent=2))


if __name__ == "__main__":
    main()
