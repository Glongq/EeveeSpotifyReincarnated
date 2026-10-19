# Experimental Native Downloads — source release v4

This directory contains the native-download extension used in `spotify-ui-v4`.
It is an independently built companion library for EeveeSpotifyReincarnated.
The release runtime sources are preserved byte-for-byte from the recorded v4
snapshot. `provenance.json` lists their SHA-256 hashes and the upstream base.
The packaging and test scripts have been adapted for this repository.

Implementation, integration, documentation and local builds: **OpenAI Codex**,
under **Glongq**'s direction. Device testing and feedback: Glongq.
Upstream EeveeSpotify contributors retain credit for the base project.

## Tested configuration

- EeveeSpotify base: 7.0.0.
- Spotify: **9.1.88**, ARM64 Mach-O UUID `f51dbd933b8f3a12943196c606e3afc2`.
- Device verification: iPhone 15 Pro Max, iOS 27.0.1, inside LiveContainer.
- Languages: English and Russian, following the app language.
- WAV recording: **disabled in release builds**.

Other Spotify binaries, signing methods, jailbreak packages, iPads, long-term
licence renewal, and cellular-only downloads have not been independently
validated for this extension. An identical version label alone does not establish
compatibility: the native patchers verify the Mach-O UUID and instruction bytes.

## Build the checked overlay

Requires macOS, Python 3, full Xcode, and the iPhoneOS SDK. Select Xcode with
`xcode-select` if your active developer directory points to Command Line Tools.
Supply your own **unmodified EeveeSpotify 7.0.0 / Spotify 9.1.88 IPA**. A vanilla
Spotify IPA, or an already modified v1–v4 IPA, is not the input for this command.

```sh
python3 NativeDownloads/tools/test_patchers.py
python3 NativeDownloads/tools/build.py /absolute/path/to/EeveeSpotify-7.0.0-9.1.88.ipa
```

Outputs are in `NativeDownloads/outputs/`:

- `spotify-ui-v4.ipa`: import and sign through LiveContainer in the normal way.
- `SpotifyAudioProbe.dylib`: the companion library.
- `build-manifest.json`: input/output hashes, source hashes and patch details.

Use `--output-dir /absolute/path/to/output` to choose another output directory.
The input file is never overwritten. No Spotify binary or IPA is included in Git.
The builder rejects unrecognised or already patched native binaries. It verifies
archive integrity, native instruction guards, generated quota constants, dyld
imports, and source hashes. The output is ad-hoc signed for packaging; installation
still requires the receiving installation tool's normal signing process.

## GitHub Actions

Use **Native Downloads — Validate / Build IPA**. Validation runs on pushes and
pull requests without an IPA. To build, select **Run workflow** and supply an HTTPS
direct-download URL for your own compatible EeveeSpotify base IPA. The output is
an Actions artifact; this workflow does not create a public release. Leave the URL
empty to run validation only.

The older upstream IPA workflows produce upstream builds. They do not implicitly
include this overlay. For a local full upstream rebuild followed by the overlay:

```sh
NATIVE_DOWNLOADS=1 ./build-ipa-local.sh /absolute/path/to/decrypted-Spotify.ipa
```

This second route needs the upstream Theos/cyan/ipapatch dependencies. It compiles
the upstream Eevee tweak before adding the overlay. Its input Spotify binary must
still match the guarded UUID. A newly compiled upstream base is not claimed to be
byte-identical to the Eevee 7.0.0 base used in the original device verification.

## Use

- Use Spotify's regular album or playlist Download button for native bulk downloads.
- Open **EeveeSpotify → Track downloads** for the single-track action and status.
- Enable diagnostics there when collecting a report. Diagnostics are off by default.
- Downloads remain in Spotify's own offline storage. This release does not export
  MP3/WAV files and does not need to play every track before downloading it.
- A successful `AddDownload` reply means accepted, not completed. The single-track
  action confirms completion through two consecutive native downloaded states.

## Tests

The portable checks require Python only:

```sh
python3 NativeDownloads/tools/test_patchers.py
```

The full host tests require Apple Silicon macOS and full Xcode. Set the optional
IPA path to include the real-binary checks; without it those checks explicitly skip.

```sh
SPOTIFY_TEST_IPA=/absolute/path/to/EeveeSpotify-7.0.0-9.1.88.ipa python3 NativeDownloads/tools/test.py
```

The UIKit fixture requires a booted ARM64 iPhone simulator with iOS 27 or later:

```sh
python3 NativeDownloads/tools/test_settings_ui.py
```

The fixture checks settings layout, RU/EN, page protocols and mini-player clearance.
It does not simulate Spotify downloading or prove device playback.

## Source map

- `src/TrackDownload.m`: single-track command, transport selection and confirmation.
- `src/NativeOffline.m`: native-manager integration, quota preparation and observations.
- `src/OfflineFlags.m`, `src/OfflineConfig.m`: local offline configuration.
- `src/TrackJournal.m`, `src/NativeErrorLog.m`: optional diagnostic observations.
- `src/DownloadSettingsUI.m`: embedded settings entry and UIKit pages.
- `src/AudioProbe.c`: audio diagnostics and manual mute; capture is disabled in release.
- `tools/patch_*.py`: guarded packaging-time changes to the provided binaries.

See [architecture and verification](../docs/native-downloads.md) and the root
[GPLv3 licence](../LICENSE). Original upstream attribution is retained.
