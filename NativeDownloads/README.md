# Pixie Download Manager — Eevee-Pixie v1

English-only manager for the exact Spotify 9.1.88 ARM64 image, integrated into
EeveeSpotify 7.0.0. IPA/ZIP basename: `Spotify-9.1.88-Eevee-Pixie-v1`.
The footer displays **Eevee-Pixie v1**.

This revision ports the menu and applicable fixes from [Vitrine-Pixie](https://github.com/Glongq/Vitrine-Pixie)
commit `0e00970f5ad2decc2aa7ed87286c96f2013785ed`, plus local journal/trace-reset
race fixes. It does not use Pixie's Spotify 9.1.90 addresses. Exact 9.1.88 guards,
the v7.3 readiness rule, native queue, storage and fixed key-request mode 0 remain.

- Download current track or its album; check status or cancel the manual request.
- Read compatibility state; review devices and confirm individual offline-registration changes.
- Export one `SpriteSupportLog.json` from the root or manager menu.
- Reset journal files, trace files and retained history. Diagnostics default off.
- Optional passive native request/success/failure traces preserve the native ABI
  and do not read audio-key material. The mode stays fixed; no runtime selector.
- Reuse already observed Eevee authentication headers in memory for explicit
  device requests; no persistent token store or background token polling.

[Source hashes](provenance-pixie-v1.json) identify the current revision. Previous
v7/v7.3 manifests remain historical snapshots. [Release notes](../RELEASE_NOTES-pixie-v1.md)
record the port and its testing limits.

Implementation, integration, documentation and local builds: **OpenAI Codex**,
under **Glongq**'s direction. Device testing and feedback: Glongq.
Upstream EeveeSpotify contributors retain credit for the base project.

## Tested configuration

The maintainer reports successful LiveContainer testing of the fixed v1 menu and full jailbreak testing of the pre-rename fixed v1 packages. The Pixie rename changes display strings only; these renamed binaries have local signature/package/UI validation. The jailbreak and iOS versions for the reported jailbreak test were not supplied.

- EeveeSpotify base: 7.0.0.
- Spotify: **9.1.88**, ARM64 Mach-O UUID `f51dbd933b8f3a12943196c606e3afc2`.
- LiveContainer: installation, native downloads and offline playback verified by the maintainer on iPhone 15 Pro Max, iOS 27.0.1.
- SideStore: installation, native downloads and offline playback also verified by the maintainer on the same device.
- Manager language: English only.
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
THEOS_PACKAGE_SCHEME=rootless make -j2 all FINALPACKAGE=1 NATIVE_DOWNLOADS_JAILBREAK=1
python3 NativeDownloads/tools/prepare_ipa.py /absolute/path/to/EeveeSpotify-7.0.0-9.1.88.ipa Spotify-9.1.88-Eevee-Pixie-v1.ipa --core .theos/obj/EeveeSpotify.dylib
```

This produces `Spotify-9.1.88-Eevee-Pixie-v1.ipa` and its `.build.json` manifest. Sign/install the IPA with your installation tool. Choose another output location with the positional output argument. The legacy `tools/build.py` companion-overlay route requires an upstream-only Eevee core; it rejects a unified native core to prevent two backends.
The input file is never overwritten. No Spotify binary or IPA is included in Git.
The builder rejects unrecognised binaries; exact prepared patches are verified idempotently. It verifies
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
python3 NativeDownloads/tools/prepare_ipa.py base.ipa Spotify-9.1.88-Eevee-Pixie-v1.ipa --core /path/to/rootless/EeveeSpotify.dylib
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
- Open **EeveeSpotify → Pixie Download Manager** for the single-track action and status.
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
