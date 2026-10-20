# Sprite Download Manager 7.3

Unofficial EeveeSpotifyReincarnated fork; implementation and builds by OpenAI
Codex under Glongq's direction. Base Eevee 7 / guarded Spotify 9.1.88, iOS 16.1+.

- Rename the manager to Sprite Download Manager, make its UI/status/error text
  English-only, and show Version 7.3 in the settings footer.
- Name IPA outputs `Spotify-9.1.88-Eevee+Sprite.ipa`.
- Fix false readiness when quotas are raised but the quota guard or key-mode
  patch is absent. Preparation and read-only reports share the same checks.
- Stop the manual download action with a clear error before submitting requests
  from an incompletely patched build.
- Check executable-writer capability before the jailbreak adapter takes over.
  Keep one-time initialization and support already statically prepared images.
- Select the Spotify image by its exact Mach-O UUID instead of assuming dyld
  index 0, which can refer to the LiveContainer host.
- Add a checked IPA preparation step to ordinary IPA packaging and DEB-to-IPA
  packaging, before installation signing. Copying a DEB alone is insufficient.
- Preserve native queueing, transport, persistence, UI and download scheduling.

Local readiness, guard, rollback, import and packaging checks are recorded with
build outputs. This revision has NOT been verified on a real iPhone or jailbreak.
Prior launch failures are not claimed fixed on the reporting tester's device.
No third-party tester IPA was modified or used as the build input for v7.3.
