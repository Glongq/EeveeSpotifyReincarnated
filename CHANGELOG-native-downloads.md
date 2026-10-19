# Native Downloads changelog

## Source release v4 — 2026-10-19

- Publish the exact runtime source snapshot from `spotify-ui-v4`.
- Preserve native album/playlist downloads and the guarded key-request mode change.
- Integrate track actions and diagnostics into EeveeSpotify settings; no floating PCM button.
- Support English/Russian and account for the mini-player when scrolling settings.
- Disable WAV recording and its capture buffer in release builds.
- Include diagnostic/export optimisations and bounded request lifetimes.
- Add source provenance, guarded IPA packaging, local tests and a dedicated Actions workflow.

Tested native-download configuration: Spotify 9.1.88 with the recorded Mach-O UUID,
EeveeSpotify 7.0.0, LiveContainer, iPhone 15 Pro Max / iOS 27.0.1. See
[verification scope](docs/native-downloads.md#verified-results) for remaining limits.
