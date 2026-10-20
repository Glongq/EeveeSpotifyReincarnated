# Experimental Native Downloads — v7.3

This directory contains the native-download extension for this unofficial fork.
v7.3 fixes preparation/readiness checks for both the companion IPA overlay and
unified jailbreak core. `ready` now requires the verified quota trampoline, key
request mode 0 and target quotas. Unsupported or incompletely patched builds
report failure before the manual download request is sent. Native queueing,
transport, callbacks, cache and persistence remain v7 implementations.
`provenance-ui-v7.json` preserves the historical source hashes;
`provenance-ui-v7.3.json` records this readiness revision.

Implementation, integration, documentation and local builds: **OpenAI Codex**,
under **Glongq**'s direction. Device testing and feedback: Glongq.
Upstream EeveeSpotify contributors retain credit for the base project.

## Tested configuration

These are historical baseline results. The v7.3 changes have local validation
only and have not yet been verified on a real iPhone or jailbreak.

- EeveeSpotify base: 7.0.0.
- Spotify: **9.1.88**, ARM64 Mach-O UUID `f51dbd933b8f3a12943196c606e3afc2`.
- LiveContainer: installation, native downloads and offline playback verified by the maintainer on iPhone 15 Pro Max, iOS 27.0.1.
- SideStore: installation, native downloads and offline playback also verified by the maintainer on the same device.
- Languages: English and Russian, following the app language.
- WAV recording: **disabled in release builds**.

Other Spotify binaries, iPads, long-term licence renewal and
cellular-only downloads have not been independently validated for this
extension. A matching version label alone does not establish compatibility:
the native patchers verify the Mach-O UUID and instruction bytes.

## Installation and distribution (sideloading)

Project announcements: **[@glongqforks](https://t.me/glongqforks)**. Source code and build documentation remain in this GitHub repository.

This repository hosts the extension's sources and reproducible build scripts,
not a public modified Spotify IPA release. The maintainer has verified installation,
native downloads and offline playback through **both LiveContainer and SideStore**.
The detailed native diagnostics in the verification report were collected with
LiveContainer. No separate Patched/Non-Patched v4 variants have been verified.

## Build the checked overlay

Requires macOS, Python 3, full Xcode, and the iPhoneOS SDK. Select Xcode with
`xcode-select` if your active developer directory points to Command Line Tools.
Supply your own **unmodified EeveeSpotify 7.0.0 / Spotify 9.1.88 IPA**. A vanilla
Spotify IPA, or an already modified v1–v4 IPA, is not the input for this command.

```sh
python3 NativeDownloads/tools/test_patchers.py
THEOS_PACKAGE_SCHEME=rootless make -j2 all FINALPACKAGE=1
python3 NativeDownloads/tools/build.py /absolute/path/to/EeveeSpotify-7.0.0-9.1.88.ipa --eevee-dylib .theos/obj/EeveeSpotify.dylib
```

Outputs are in `NativeDownloads/outputs/`:

- `spotify-ui-v7.3.ipa`: output of a current source build; sign/install with your installation tool. The previously published v4 has the recorded SideStore/LiveContainer verification.
- `SpotifyAudioProbe.dylib`: the companion library.
- `build-manifest.json`: input/output hashes, source hashes and patch details.

Use `--output-dir /absolute/path/to/output` to choose another output directory.
The input file is never overwritten. No Spotify binary or IPA is included in Git.
The builder rejects unrecognised or already patched native binaries. It verifies
archive integrity, native instruction guards, generated quota constants, dyld
imports, and source hashes. The output is ad-hoc signed for packaging; installation
still requires the receiving installation tool's normal signing process.
The v7 glass controls require a rebuilt Eevee library. The builder rejects an old
library without the new action-row markers. When the supplied IPA already contains
the newly compiled Eevee UI, `--eevee-dylib` can be omitted.

## GitHub Actions

Use **Native Downloads — Validate / Build IPA**. Validation runs on pushes and
pull requests without an IPA. To build, select **Run workflow** and supply an HTTPS
direct-download URL for your own compatible EeveeSpotify base IPA. The output is
an Actions artifact; this workflow does not create a public release. Leave the URL
empty to run validation only. With an original 7.0.0 base, also supply the URL of
an Eevee library compiled from the current sources. The workflow does not compile
the Theos project itself.

### Unified core and DEB injection

The ordinary **Build IPA (PATCHED)** and **Build IPA (NO PATCH)** workflows now
include a `native_downloads` option (enabled by default, exact 9.1.88 image only).
Both prepare and verify the executable after injecting the native core. Their
Patched/No Patch distinction concerns the upstream sideload compatibility shim;
both native-download variants need the native executable patches.
**Create IPA Packages** also detects a unified native DEB and prepares the image.
Upstream-only DEBs pass through unchanged.

For a local full build:

```sh
./build-ipa-local.sh /absolute/path/to/decrypted-Spotify-9.1.88.ipa
# For an upstream-only build without native downloads:
NATIVE_DOWNLOADS=0 ./build-ipa-local.sh /absolute/path/to/decrypted-Spotify.ipa
```

Copying a native DEB's dylib into an IPA using an arbitrary injector does **not**
apply these main-executable patches. A stock-iOS app cannot apply them by calling
an app-bundled `MSHookMemory`. Prepare such an injected IPA before installation
signing, using this repository's code:

```sh
python3 NativeDownloads/tools/prepare_ipa.py injected.ipa prepared.ipa
```

To build from an existing compatible Eevee base and a newly compiled unified core:

```sh
python3 NativeDownloads/tools/prepare_ipa.py base.ipa spotify-v7.3.ipa --core /path/to/rootless/EeveeSpotify.dylib
```

This builder verifies both original guard windows or exact known prepared bytes,
rejects unknown code/RootHide cores/duplicate backends, patches before signing,
checks the final archive, and records input/output hashes in `.build.json`.
It preserves the input. Reprocessing an already prepared image is idempotent.
Installation still requires the installation tool's normal signing process.
Jailbreak DEBs instead apply the same guarded patches once through the jailbreak
engine; see [jailbreak packages](jailbreak/README.md).

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

The glass action-row fixture compiles the actual production row and the shared
native tap helper. It checks widths 320–768 pt, horizontal scrolling, Play staying
at the right edge, native download state changes and one action per control. It
also reproduces the artist header’s initially hidden 8 pt preview and its delayed
appearance without a second controller layout:

```sh
python3 Tests/PlaylistActionRow/test.py
```

## UI v7

Spotify's original download control receives Eevee's shared `GlassKit.pane`
background. Its native foreground, outline, animations, accessibility, icon subtree
and handlers are preserved. No replacement download button, icon snapshot,
forwarded download tap or download-model hook is used.

The native header lookup handles `DownloadButton.Granular.*` states verified in
the running iPhone, as well as `Components.UI.DownloadIcon` and the older
`Components.UI.DownloadButton`. Binding is cached per header, including missing
results. A new lookup is allowed when a native control is replaced; a header
without a control gets one retry when it enters a window. There is no periodic
search or timer.

The native download control is mounted once into the horizontal action area.
On playlist/album pages the native preview is mounted after its initial hidden
state completes. Play stays separately at the right. No download control is
fabricated on pages where Spotify has none.

Artist previews stay entirely in Spotify's native Element/OverflowStack layout:
no reparenting, frame changes, new glass background or replacement tap handler.
The custom action strip starts after the preview's current native drawing/hit
area, including content extending beyond its layout shell. Scoped native
hidden/bounds/center notifications coalesce geometry updates onto one main-queue
turn. No timer, display-link, full-screen scan or repeated reparenting is used.

The original v4–v6 provenance files and local archives are preserved.

## Source map and verification

- `src/TrackDownload.m`: native single-track requests and completion checks.
- `src/NativeOffline.m`: native-manager preparation and observations.
- `src/OfflineFlags.m`, `src/OfflineConfig.m`: local offline configuration.
- `src/TrackJournal.m`, `src/NativeErrorLog.m`: optional diagnostics.
- `src/DownloadSettingsUI.m`: settings UI; the manual mute row is removed in UI v7.
- `tools/patch_*.py`: version-guarded packaging changes.

See [architecture and recorded verification](../docs/native-downloads.md) and the
root [GPLv3 licence](../LICENSE). Upstream attribution is retained. Publishing the
v7 source revision does not replace the ready-made v4 IPA linked on the main page.
