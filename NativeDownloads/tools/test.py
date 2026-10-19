import os
from pathlib import Path
import subprocess
import sys

from patch_imports import patch

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
build = ROOT / "build/tests"
build.mkdir(parents=True, exist_ok=True)


def run(*args):
    subprocess.run([str(x) for x in args], check=True)


flags = ["xcrun", "clang", "-arch", "arm64", "-std=gnu11", "-O1", "-g", "-Isrc", "-DSAP_ENABLE_WAV_CAPTURE=1", "-framework", "AudioToolbox", "-framework", "Foundation"]
run(*flags, "-DSAP_TESTING", "-fsanitize=address,undefined", "src/AudioProbe.c", "src/CaptureRing.c", "tests/test_probe.c", "src/Diagnostics.m", "src/Localization.m", "-o", build / "test_probe")
run(build / "test_probe")
release_flags = [x for x in flags if x != "-DSAP_ENABLE_WAV_CAPTURE=1"]
run(*release_flags, "-DSAP_ENABLE_WAV_CAPTURE=0", "-DSAP_TESTING", "-fsanitize=address,undefined",
    "src/AudioProbe.c", "src/CaptureRing.c", "tests/capture_disabled.c", "src/Diagnostics.m", "src/Localization.m", "-o", build / "capture_disabled")
run(build / "capture_disabled")
symbols = subprocess.check_output(["nm", "-a", str(build / "capture_disabled")], text=True)
assert not any(line.split()[-1] in {"_samples", "_writeIndex", "_captureFormat"} for line in symbols.splitlines() if line.split())
print("PASS: no WAV sample ring or capture state in release binary")
frameworks = build / "Frameworks"
frameworks.mkdir(exist_ok=True)
run(*flags, "-dynamiclib", "-fvisibility=hidden", "src/AudioProbe.c", "src/CaptureRing.c", "-Wl,-install_name,@rpath/SpotifyAudioProbe.dylib", "src/Diagnostics.m", "src/Localization.m", "-o", frameworks / "SpotifyAudioProbe.dylib")
run(*flags, "tests/offline_unit.c", "-Wl,-headerpad,0x1000", "-o", build / "offline-original")
data, manifest = patch((build / "offline-original").read_bytes())
patched = build / "offline-patched"
patched.write_bytes(data); patched.chmod(0o755)
run("codesign", "--force", "--sign", "-", "--timestamp=none", patched)
run("xcrun", "dyld_info", "-validate_only", patched)
run(patched)
print("PASS: all five import ordinals redirected and runnable on the host")

run(*flags, "-fobjc-arc", "-fsanitize=address,undefined", "src/AudioProbe.c", "src/CaptureRing.c",
    "src/AVAudioHooks.m", "tests/av_hooks.m", "-framework", "AVFoundation", "-framework", "CoreMedia",
    "-framework", "Foundation", "src/Diagnostics.m", "src/Localization.m", "-o", build / "av_hooks")
run(build / "av_hooks")

run(*flags, "tests/converter_graph.c", "-Wl,-headerpad,0x1000", "-o", build / "converter-original")
data, manifest = patch((build / "converter-original").read_bytes())
patched = build / "converter-patched"
patched.write_bytes(data); patched.chmod(0o755)
run("codesign", "--force", "--sign", "-", "--timestamp=none", patched)
run(patched)

run("xcrun", "clang", "-arch", "arm64", "-fobjc-arc", "-std=gnu11", "-O1", "-g", "-Isrc",
    "-fsanitize=address,undefined", "src/OfflineFlags.m", "tests/offline_flags.m", "-framework", "Foundation",
    "src/Diagnostics.m", "src/Localization.m", "-o", build / "offline_flags")
run(build / "offline_flags")
run("xcrun", "clang", "-arch", "arm64", "-fobjc-arc", "-std=gnu11", "-O1", "-g", "-Isrc",
    "-fsanitize=address,undefined", "src/WireProto.m", "src/OfflineConfig.m", "tests/offline_config.m", "-framework", "Foundation",
    "src/Diagnostics.m", "src/Localization.m", "-o", build / "offline_config")
run(build / "offline_config")
run("xcrun", "clang", "-arch", "arm64", "-fobjc-arc", "-std=gnu11", "-O1", "-g", "-Isrc", "-DSAP_TESTING",
    "-fsanitize=address,undefined", "src/WireProto.m", "src/PlayerTrace.m", "tests/player_trace.m", "-framework", "Foundation",
    "src/Diagnostics.m", "src/Localization.m", "-o", build / "player_trace")
run(build / "player_trace")
from patch_offline import patch_reminder, TARGET, DISABLED
from zipfile import ZipFile
test_ipa = os.environ.get("SPOTIFY_TEST_IPA")
if test_ipa:
    with ZipFile(test_ipa) as ipa:
        original = ipa.read("Payload/Spotify.app/Frameworks/EeveeSpotify.dylib")
    changed, reminder = patch_reminder(original)
    assert len(original) == len(changed)
    assert sum(a != b for a, b in zip(original, changed)) == 1
    assert TARGET not in changed and changed.count(DISABLED) == 1
    print("PASS: supplied Eevee reminder target disabled with exactly one byte changed")
else:
    print("SKIP: real-IPA reminder check (set SPOTIFY_TEST_IPA to enable)")

run("xcrun", "clang", "-arch", "arm64", "-fobjc-arc", "-std=gnu11", "-O1", "-g", "-Isrc", "-DSAP_TESTING",
    "-fsanitize=address,undefined", "src/WireProto.m", "src/PlayerTrace.m", "src/TrackDownload.m", "tests/track_download.m", "-framework", "Foundation",
    "src/Diagnostics.m", "src/Localization.m", "-o", build / "track_download")
run(build / "track_download", "-AppleLanguages", "(ru)")
run(build / "track_download", "-AppleLanguages", "(en)")

run("xcrun", "clang", "-arch", "arm64", "-fobjc-arc", "-std=gnu11", "-O1", "-g", "-Isrc", "-DSAP_TESTING",
    "-fsanitize=address,undefined", "src/WireProto.m", "src/PlayerTrace.m", "src/TrackJournal.m", "src/NativeErrorLog.m", "tests/track_journal.m", "-framework", "Foundation",
    "src/Diagnostics.m", "src/Localization.m", "-o", build / "track_journal")
# SAP_TESTING keeps the journal's files inside TMPDIR instead of the real Documents directory.
journal_home = build / "journal-home"
journal_home.mkdir(exist_ok=True)
subprocess.run([str(build / "track_journal"), "-AppleLanguages", "(ru)"], check=True, env={**os.environ, "TMPDIR": str(journal_home)})
subprocess.run([str(build / "track_journal"), "-AppleLanguages", "(en)"], check=True, env={**os.environ, "TMPDIR": str(journal_home)})

run(sys.executable, ROOT / "tools/test_native_restrictions.py")

run("xcrun", "clang", "-fobjc-arc", "-Isrc", "src/Localization.m", "tests/localization.m", "-framework", "Foundation", "-o", build / "localization")
run(build / "localization", "English", "-AppleLanguages", "(en-GB)")
run(build / "localization", "Русский", "-AppleLanguages", "(ru-RU)")
