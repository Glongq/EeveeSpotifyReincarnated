# Native Downloads changelog

## Installation verification update — 2026-10-19

- Maintainer confirmed v4 installation, native downloads and offline playback
  through both SideStore and LiveContainer on iPhone 15 Pro Max / iOS 27.0.1.
- LiveContainer remains the source of the detailed native diagnostic results.
- Added installation compatibility and build/distribution instructions.
- Clarified Sideloadly as not tested, without claiming extra installation targets.
- Updated the fork FAQ to distinguish Spotify 9.1.88 from older upstream guidance.

## Source release v4 — 2026-10-19

- Publish the exact runtime source snapshot from `spotify-ui-v4`.
- Preserve native album/playlist downloads and the guarded key-request mode change.
- Integrate track actions and diagnostics into EeveeSpotify settings; no floating PCM button.
- Support English/Russian and account for the mini-player when scrolling settings.
- Disable WAV recording and its capture buffer in release builds.
- Include diagnostic/export optimisations and bounded request lifetimes.
- Add source provenance, guarded IPA packaging, local tests and a dedicated Actions workflow.

Tested native-download configuration: Spotify 9.1.88 with the recorded Mach-O UUID,
EeveeSpotify 7.0.0, SideStore and LiveContainer, iPhone 15 Pro Max / iOS 27.0.1.
Detailed device diagnostics are from LiveContainer; see the
[verification scope](docs/native-downloads.md#verified-results) for remaining limits.
