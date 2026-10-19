# EeveeSpotifyReincarnated — UNOFFICIAL FORK

> [!IMPORTANT]
> **This is Glongq's independently maintained fork**, not an official EeveeSpotify or Spotify release.
> Original project: **[SideloadLabs/EeveeSpotifyReincarnated](https://github.com/SideloadLabs/EeveeSpotifyReincarnated)**.
> This fork adds experimental native downloads and maintains its changes separately.

**Fork maintainer:** [Glongq](https://github.com/Glongq)  
**Native-download development, integration and local builds:** OpenAI Codex, under Glongq's direction.  
**Upstream:** [SideloadLabs/EeveeSpotifyReincarnated](https://github.com/SideloadLabs/EeveeSpotifyReincarnated)  
**License:** [GPLv3](LICENSE), with the upstream Git history and contributor attribution retained.

## Experimental Native Downloads — v4

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

### News and announcements

- **Official channel for this fork:** [@glongqforks](https://t.me/glongqforks) — updates and release announcements.
- **Source code:** [Glongq/EeveeSpotifyReincarnated](https://github.com/Glongq/EeveeSpotifyReincarnated).

### Source code and building

This repository contains **source code, build scripts and tests**, not a publicly hosted modified Spotify IPA. The [Releases page](https://github.com/Glongq/EeveeSpotifyReincarnated/releases) contains no published IPA release at the time of this documentation update.

For the checked overlay, supply your own **unmodified EeveeSpotify 7.0.0 / Spotify 9.1.88 base IPA** (not a vanilla Spotify IPA and not an already modified v1–v4 IPA). On macOS with full Xcode, iPhoneOS SDK and Python 3:

```sh
python3 NativeDownloads/tools/test_patchers.py
python3 NativeDownloads/tools/build.py /absolute/path/to/EeveeSpotify-7.0.0-9.1.88.ipa
```

Alternatively, use [GitHub Actions → Native Downloads — Validate / Build IPA](https://github.com/Glongq/EeveeSpotifyReincarnated/actions/workflows/native-downloads.yml): run the workflow manually with a direct HTTPS URL to your compatible base IPA. The built IPA and manifest are uploaded as **temporary Actions artifacts**. A green validation result alone does **not** mean an IPA was built; the build job runs only when the IPA URL is supplied.

See the complete [build and installation guide](NativeDownloads/README.md), [technical verification](docs/native-downloads.md), [v4 changelog](CHANGELOG-native-downloads.md), and [source hashes](NativeDownloads/provenance.json).

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
