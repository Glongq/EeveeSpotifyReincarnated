# EeveeSpotifyReincarnated — UNOFFICIAL FORK

> [!IMPORTANT]
> **This is Glongq's independently maintained fork**, not an official EeveeSpotify or Spotify release.
> Original project: **[SideloadLabs/EeveeSpotifyReincarnated](https://github.com/SideloadLabs/EeveeSpotifyReincarnated)**.
> This fork adds experimental native downloads and maintains its changes separately.

**Fork maintainer:** [Glongq](https://github.com/Glongq)  
**Native-download development, integration and local builds:** OpenAI Codex, under Glongq's direction.  
**Upstream:** [SideloadLabs/EeveeSpotifyReincarnated](https://github.com/SideloadLabs/EeveeSpotifyReincarnated)  
**License:** [GPLv3](LICENSE), with the upstream Git history and contributor attribution retained.

## Experimental Native Downloads

**Current source revision:** `spotify-ui-v7` — glass download controls and header-layout updates, plus removal of the manual mute row. The native-download backend remains the recorded v4 implementation. This is a source update; the ready-made IPA linked below remains **v4**.

### Verified v4 download baseline

Native Spotify album/playlist downloads and a **Track downloads** section in EeveeSpotify settings. Downloads use Spotify's own offline storage; the extension does **not** export MP3 or WAV files. The user interface supports English and Russian; WAV recording is disabled.

### Compatibility and tested sideloading methods

| Installation method | Installation | Native downloads | Offline playback |
| --- | --- | --- | --- |
| **SideStore** | Verified by maintainer | Verified by maintainer | Verified by maintainer |
| **LiveContainer** | Verified by maintainer | Verified by maintainer | Verified by maintainer |

**Tested configuration:** Spotify **9.1.88**, EeveeSpotify **7.0.0**, iPhone 15 Pro Max running **iOS 27.0.1**. This extension specifically checks the Spotify ARM64 Mach-O UUID `f51dbd933b8f3a12943196c606e3afc2` and guarded instruction bytes. Matching version numbers alone **do not** guarantee compatibility.

The maintainer confirms that downloads and offline playback work through both SideStore and LiveContainer. The detailed native diagnostic/device observations documented in [the verification report](docs/native-downloads.md#verified-results) were captured during the LiveContainer tests.

### Features and limitations

- Download albums and playlists with Spotify's built-in Download action.
- Use **EeveeSpotify → Track downloads** for current-track downloads and optional diagnostics.
- Play downloaded music offline in Spotify; no separate MP3/WAV export.
- Diagnostics are off by default; some read requests may still time out.
- Other Spotify binaries, long-term licence renewal and cellular-only downloading are **not verified**.

### Download the ready-made IPA

**[Download Native Downloads v4 IPA — Telegram post](https://t.me/glongqforks/2)**. Open the post and download the attached `.ipa` file. Use SideStore to install it, or import it into LiveContainer. Both methods were tested by the maintainer as described above.

**Do not download `Source code (zip)` or `Source code (tar.gz)` to install the app.** Those are source-code archives, not an installable IPA. To examine or build the code, use the [native-v4 source release](https://github.com/Glongq/EeveeSpotifyReincarnated/releases/tag/native-v4).

### News and announcements

- **Official channel for this fork:** [@glongqforks](https://t.me/glongqforks) — updates and release announcements.
- **Source code:** [Glongq/EeveeSpotifyReincarnated](https://github.com/Glongq/EeveeSpotifyReincarnated).

### Source code and building

This repository contains **source code, build scripts and tests**, not a publicly hosted modified Spotify IPA. The [Releases page](https://github.com/Glongq/EeveeSpotifyReincarnated/releases) contains no published IPA release at the time of this documentation update.

For the checked overlay, supply your own **unmodified EeveeSpotify 7.0.0 / Spotify 9.1.88 base IPA** (not a vanilla Spotify IPA and not an already modified v1–v4 IPA). For the current v7 UI, rebuild Eevee using the [documented Theos dependencies](NativeDownloads/README.md#build-the-checked-overlay) and pass that library to the overlay builder. On macOS with the configured toolchain:

```sh
python3 NativeDownloads/tools/test_patchers.py
THEOS_PACKAGE_SCHEME=rootless make -j2 all FINALPACKAGE=1
python3 NativeDownloads/tools/build.py /absolute/path/to/EeveeSpotify-7.0.0-9.1.88.ipa --eevee-dylib .theos/obj/EeveeSpotify.dylib
```

Alternatively, use [GitHub Actions → Native Downloads — Validate / Build IPA](https://github.com/Glongq/EeveeSpotifyReincarnated/actions/workflows/native-downloads.yml): run the workflow manually with a direct HTTPS URL to your compatible base IPA. For v7 UI builds from an original base IPA, also supply `eevee_dylib_url` pointing to a library built from the current sources. The workflow does not compile Theos itself. The built IPA and manifest are uploaded as **temporary Actions artifacts**. A green validation result alone does **not** mean an IPA was built; the build job runs only when the IPA URL is supplied.

See the complete [build and installation guide](NativeDownloads/README.md), [technical verification](docs/native-downloads.md), [source changelog](CHANGELOG-native-downloads.md), and [v7 source hashes](NativeDownloads/provenance-ui-v7.json).

### Jailbreak packages — v7.2 development port

> [!WARNING]
> **NOT TESTED ON A REAL JAILBROKEN DEVICE.** These experimental packages passed
> local tests and package validation only. SideStore/LiveContainer results do not
> verify this jailbreak port.

**[Download v7.2 jailbreak pre-release — rootless / RootHide](https://github.com/Glongq/EeveeSpotifyReincarnated/releases/tag/native-v7.2-jailbreak)**

v7.2 moves executable patching out of library initialization and into the first
native offline-manager construction. Previous launch failures have **not** been
confirmed resolved on the affected device. This pre-release contains DEBs only.

The [local jailbreak build guide](NativeDownloads/jailbreak/README.md) builds
complete rootless and RootHide packages including the native downloader and v7
settings UI. Minimum iOS is **16.1**; Liquid Glass requires **iOS 26**. Downloads
still require the exact Spotify 9.1.88 binary identified above. This new runtime
adapter requires separate testing on a jailbroken device; sideloading results do
not verify it. The build script does not publish or push anything.

### Reporting issues

For native-download problems, enable diagnostics if needed and report redacted logs through [this fork's issue tracker](https://github.com/Glongq/EeveeSpotifyReincarnated/issues), not upstream. Please specify whether the issue occurred in SideStore or LiveContainer, the Spotify build and the iOS version.

## Upstream project and credits

The original EeveeSpotifyReincarnated project is maintained by [jaydenjcpy](https://github.com/jaydenjcpy), [faroukbmiled](https://github.com/faroukbmiled), and [Mod4](https://github.com/M0d-4). The upstream history and contributions also include [estrogencat](https://github.com/estrogencat), [Skye](https://github.com/Meeep1), [whoeevee](https://github.com/whoeevee), and [Spikerko](https://github.com/Spikerko).

- [Upstream README and features](https://github.com/SideloadLabs/EeveeSpotifyReincarnated#readme)
- [Upstream common issues](https://github.com/SideloadLabs/EeveeSpotifyReincarnated/blob/Master/common_issues.md)
- [Contributor guide](CONTRIBUTING.md) · [Translations](TRANSLATING.md) · [License](LICENSE)

**OpenAI Codex** produced the native-download implementation, fork integration, documentation and local builds under **Glongq's direction**. Glongq performed device testing and supplied feedback. Upstream authorship is retained; this fork is independent of the upstream maintainers.

## Disclaimer

This is an unofficial independent modification, not affiliated with, authorized by, or endorsed by Spotify. Use at your own risk. No Spotify application binaries are included in the source repository.
