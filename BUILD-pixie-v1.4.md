# EeveeSpotify 7.0.0 / Spotify 9.1.92 + Pixie Manager 1.4

Requires Apple Silicon macOS, full Xcode with an iOS 26+ SDK for Eevee's glass controls, Python 3, GNU make, and Theos with Orion/EeveeSwiftProtobuf. Supply the compatible decrypted Spotify 9.1.92 / EeveeSpotify 7.0.0 IPA. Target ARM64 UUID: `2acd33ee445b326d8b75b3e32403790a`.

## Build

From this project directory:

```sh
python3 NativeDownloads/tools/validate_eevee_9192.py
python3 NativeDownloads/tools/test.py
python3 NativeDownloads/tools/build.py /path/to/input.ipa --theos /path/to/theos
```

The last command rebuilds the Eevee UI library, signs that library ad hoc, builds Pixie from the target manifest and creates the IPA in a fresh root `outputs/build-<timestamp>/`. Logs stay alongside it. It handles the space in this project directory through a temporary Theos path alias. It never installs or launches on a phone.

The input resources/extensions are retained; the guarded Spotify executable and Eevee library change, and the companion is added. Installation requires the user's signing tool. No certificate or account credentials are bundled.

The lower-level `tools/build_eevee_9192.py --eevee-dylib ...` packages an already rebuilt Eevee library; CI uses it when both artifacts are supplied. Never supply an old unified native core alongside the companion.

## Target and generated files

`NativeDownloads/targets/spotify-9.1.92.json` is the current identity and source manifest. After intentionally reviewing a target/source change:

```sh
python3 NativeDownloads/tools/generate_target.py
python3 NativeDownloads/tools/source_provenance.py
python3 NativeDownloads/tools/validate_eevee_9192.py
```

Changing the target JSON does not discover or validate new offsets. Exact original instruction guards and the independent supplied-binary verifier remain required. Current refactoring keeps the previous patch output unchanged.

For supplied input/output IPA verification:

```sh
python3 NativeDownloads/tools/verify_eevee_9192.py /path/to/input.ipa --output /path/to/output.ipa --report /path/to/verification.json
```

CI validates sources and host fixtures. Manual packaging uploads an Actions artifact without publishing a release. Old 9.1.88/9.1.90 and jailbreak routes remain in Git history; this 9.1.92 tree does not claim a tested DEB target.

## Rebuild Pixie in an assembled IPA

For Pixie-only source changes, preserve an already assembled compatible IPA's
Spotify executable, Eevee library and resources:

```sh
python3 NativeDownloads/tools/source_provenance.py
python3 NativeDownloads/tools/validate_eevee_9192.py
python3 NativeDownloads/tools/rebuild_companion.py /path/to/assembled.ipa --output outputs/new-build/Spotify-9.1.92-EeveeSpotify-Pixie-v1.4.ipa
```

This route validates the target version/UUID and replaces only
`Frameworks/SpotifyAudioProbe.dylib`. It does not turn a stock IPA into a patched
build; use the full builder above for that. The report records the source snapshot,
input/output hashes and changed entry. Device verification remains separate.

## Pixie 1.4: audio export in an assembled IPA

Pixie 1.4 adds native export observations to the Spotify executable (cache and
media-key boundaries, `NativeDownloads/tools/patch_export.py`) and replaces the
companion. EeveeSpotify and every other file in the assembled IPA are preserved.
The input is the assembled EeveeSpotify 7.0.0 / Spotify 9.1.92 IPA that already
carries the Pixie 1.3 native patches:

```sh
python3 NativeDownloads/tools/generate_export_headers.py --check
python3 NativeDownloads/tools/build_pixie14_9192.py /path/to/assembled.ipa --output outputs/new-build/Spotify-9.1.92-EeveeSpotify-7.0.0-Pixie-v1.4.ipa
python3 NativeDownloads/tools/verify_pixie14_9192.py /path/to/assembled.ipa outputs/new-build/Spotify-9.1.92-EeveeSpotify-7.0.0-Pixie-v1.4.ipa --report outputs/new-build/verification.json
```

`targets/spotify-9.1.92.json` (`export`) is the single source of the export
sites: entry addresses and original bytes, code windows and cave layout. The
export headers in `src/Generated` are generated from it
(`generate_export_headers.py`); never edit them by hand. A new Spotify build needs
every site re-derived and re-verified, not only this file edited.
`tests/export_patch.py` checks the headers and cave layout; with
`PIXIE_9192_EXECUTABLE=/path/to/Spotify` it also applies the patch to the real
executable and rejects repeated, mismatched or occupied patches.

The full builder (`build_eevee_9192.py`, from a clean Eevee IPA) applies the same
export patch after the Pixie 1.3 native patches. `rebuild_companion.py` only
replaces the companion and is for a 1.4 IPA whose executable is already patched.
