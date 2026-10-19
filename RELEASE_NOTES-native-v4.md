# EeveeSpotify Native Downloads v4 — Experimental

**EeveeSpotify:** 7.0.0  
**Spotify:** 9.1.88  
**Source release tag:** `native-v4`

This is an independent, experimental fork of [EeveeSpotifyReincarnated](https://github.com/SideloadLabs/EeveeSpotifyReincarnated) with native offline-download support.

## What's included

- Native downloads for tracks, albums and playlists within Spotify.
- **EeveeSpotify → Track downloads** settings entry for individual tracks and optional diagnostics.
- Offline playback through Spotify's existing offline storage.
- English and Russian interface.
- WAV capture disabled; no MP3/WAV export.

## Tested compatibility

- **SideStore:** installation, downloads and offline playback confirmed by the maintainer.
- **LiveContainer:** installation, downloads and offline playback confirmed by the maintainer.
- **Tested device:** iPhone 15 Pro Max, iOS 27.0.1.
- **Supported base:** Spotify 9.1.88 with the exact guarded ARM64 Mach-O binary and EeveeSpotify 7.0.0.

Other Spotify binary versions, long-term license renewal and cellular-only downloading have not been verified. Some diagnostic read requests may time out. This build is experimental and may have bugs.

## Download and source code

- **Published IPA post:** https://t.me/glongqforks/2
- **Updates and announcements:** https://t.me/glongqforks
- **Source code, build instructions and tests:** this GitHub repository. GitHub generates the source archives attached to this release automatically.

The complete modified Spotify IPA is distributed separately on Telegram and **is not attached to this GitHub source release**. The source build workflow requires a compatible unmodified EeveeSpotify base IPA supplied by the builder.

## Credits

Native-download implementation, integration and builds: **OpenAI Codex under Glongq's direction**; device testing and feedback: **Glongq**.

Based on **SideloadLabs/EeveeSpotifyReincarnated** and its upstream contributors. Original attribution and GPLv3 license are preserved.

**Disclaimer:** Unofficial fork. Not affiliated with, endorsed by, or authorized by Spotify or the original EeveeSpotify maintainers.
