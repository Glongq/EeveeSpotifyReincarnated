# EeveeSpotify + Pixie Download Manager — UNOFFICIAL FORK

> [!IMPORTANT]
> **This is Glongq's independently maintained fork**, not an official EeveeSpotify or Spotify release.
> Original project: **[SideloadLabs/EeveeSpotifyReincarnated](https://github.com/SideloadLabs/EeveeSpotifyReincarnated)**.

**Current version: Pixie Download Manager v1** · Spotify **9.1.88** · EeveeSpotify **7.0.0**

**Fork maintainer:** [Glongq](https://github.com/Glongq)

**Native-download implementation, integration, documentation and local builds:** OpenAI Codex, under Glongq's direction.

**License:** [GPLv3](LICENSE). Upstream history and contributor attribution are retained.

## Pixie v1

English-only download settings integrated into **EeveeSpotify → Pixie Download Manager**.

- Native album/playlist downloads through Spotify's own Download button.
- Download the current track or its album from the manager.
- Download status, compatibility checks and explicit offline-device slot management.
- Optional diagnostics and one support-log export. Diagnostics are off by default.
- Fixed menu-cell reuse so checking offline slots does not disable unrelated buttons.
- Spotify's native queue, encrypted offline storage and playback remain in use. No MP3/WAV export.

Pixie v1 is the latest fixed v1 build renamed from Sprite. The rename changes visible names only. Internal class names, log filenames and the DEB package identifier/version are retained for compatibility. The new single-track action in Spotify's `…` menus was cancelled and is **not** part of this release.

## Downloads

**[Pixie v1 release — Rootless / RootHide DEBs and dylibs](https://github.com/Glongq/EeveeSpotifyReincarnated/releases/tag/pixie-v1)**

- Install the DEB matching your jailbreak. RootHide and Rootless are separate packages.
- Dylibs are the matching unified Eevee + Pixie libraries extracted from those packages, not standalone Spotify apps. Their internal install name remains `EeveeSpotify.dylib`; do not inject them alongside another Eevee/native backend.
- For a sideloaded app, injecting the dylib alone is insufficient: the guarded Spotify executable must be prepared **before installation signing**, as described below.
- This GitHub release does not contain a Spotify IPA. **[IPA announcements — @glongqforks](https://t.me/glongqforks)**.
- GitHub's automatic **Source code (zip/tar.gz)** downloads contain source code, not an installable app.

### Verification scope

The maintainer confirmed the fixed v1 menu works in LiveContainer and reported full jailbreak testing of the pre-rename fixed v1 packages. The Pixie rename preserves their behavior; the renamed IPA/DEBs passed local source, UI, signature and package checks. The jailbreak and iOS versions for the reported jailbreak test were not supplied, so this does not establish compatibility with every jailbreak.

Earlier baseline downloads/offline playback were verified by the maintainer through SideStore and LiveContainer on iPhone 15 Pro Max / iOS 27.0.1. Those remain historical results, not a test of every later build. See the [technical verification report](docs/native-downloads.md).

Native downloads require the exact supported Spotify **9.1.88** ARM64 image, UUID `f51dbd933b8f3a12943196c606e3afc2`, with guarded instruction bytes. Matching version labels alone are insufficient. Minimum iOS is **16.1**; Liquid Glass requires **iOS 26**. Other binaries, iPads, long-term licence renewal and cellular-only downloads have not been independently validated.

## Sources and builds

The sources in this release correspond to the latest fixed IPA and the Pixie v1 packages. See [v1 release notes](RELEASE_NOTES-pixie-v1.md), [source hashes](NativeDownloads/provenance-pixie-v1.json), [native build guide](NativeDownloads/README.md), [jailbreak build guide](NativeDownloads/jailbreak/README.md) and [changelog](CHANGELOG-native-downloads.md).

With the documented macOS/Xcode/Theos toolchain, supply your own unmodified **EeveeSpotify 7.0.0 / Spotify 9.1.88 base IPA**:

```sh
python3 NativeDownloads/tools/test_patchers.py
THEOS_PACKAGE_SCHEME=rootless make -j2 all FINALPACKAGE=1 NATIVE_DOWNLOADS_JAILBREAK=1
python3 NativeDownloads/tools/prepare_ipa.py /absolute/path/to/EeveeSpotify-7.0.0-9.1.88.ipa Spotify-9.1.88-Eevee-Pixie-v1.ipa --core .theos/obj/EeveeSpotify.dylib
```

Select your Theos checkout with `THEOS`. The output is ad-hoc signed for packaging and must be signed by your installation tool. Do not use a RootHide library for sideloading.

The **[Pixie Download Manager — Validate / Build IPA](https://github.com/Glongq/EeveeSpotifyReincarnated/actions/workflows/native-downloads.yml)** workflow validates sources on pushes. Its optional legacy companion-overlay build requires a compatible upstream-only Eevee library and a user-supplied base IPA; unified cores use `prepare_ipa.py` instead. Actions artifacts are temporary and are not a public IPA release.

## Reporting issues and announcements

- **Announcements:** [@glongqforks](https://t.me/glongqforks).
- **Issues for this fork:** [Glongq/EeveeSpotifyReincarnated](https://github.com/Glongq/EeveeSpotifyReincarnated/issues), not upstream. Include installation method, Spotify build, iOS and jailbreak if applicable; redact personal data from logs.
- **Upstream guidance:** [common issues](https://github.com/SideloadLabs/EeveeSpotifyReincarnated/blob/Master/common_issues.md).

## Upstream project and credits

The original EeveeSpotifyReincarnated project is maintained by [jaydenjcpy](https://github.com/jaydenjcpy), [faroukbmiled](https://github.com/faroukbmiled), and [Mod4](https://github.com/M0d-4). Upstream history and contributions also include [estrogencat](https://github.com/estrogencat), [Skye](https://github.com/Meeep1), [whoeevee](https://github.com/whoeevee), and [Spikerko](https://github.com/Spikerko).

The menu and applicable fixes were ported from [Glongq/Vitrine-Pixie](https://github.com/Glongq/Vitrine-Pixie) to Eevee's exact 9.1.88 base. Spotify 9.1.90 offsets were not copied.

**OpenAI Codex** produced the native-download implementation, integration, documentation and local builds under **Glongq's direction**. Glongq performed device testing and supplied feedback. This fork is independent of the upstream maintainers.

[Upstream README](https://github.com/SideloadLabs/EeveeSpotifyReincarnated#readme) · [Contributing](CONTRIBUTING.md) · [Translations](TRANSLATING.md) · [License](LICENSE)

## Disclaimer

This is an unofficial independent modification, not affiliated with, authorized by, or endorsed by Spotify. Use at your own risk. No Spotify application binaries are included in the source repository.
