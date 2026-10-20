# Native Downloads v7.2 — jailbreak startup update

> [!WARNING]
> **NOT VERIFIED ON A REAL JAILBROKEN DEVICE.** v7.1 received reports of launch
> failures. v7.2 changes the initialization path, but resolution of those failures
> on the affected device has **not** been confirmed. This remains a **Pre-release**.

This is **Glongq's unofficial fork** of
[SideloadLabs/EeveeSpotifyReincarnated](https://github.com/SideloadLabs/EeveeSpotifyReincarnated),
built with **OpenAI Codex under Glongq's direction**.

## Changes since v7.1

- Library initialization now performs read-only validation and registers a native
  offline-manager initializer hook. It no longer writes executable memory or
  rebinds AudioToolbox imports during this early loading phase.
- On the first native offline-manager construction, guarded patches are applied
  once before the original initializer runs. Its arguments, ownership convention
  and return value are preserved.
- An app-bundled executable patching engine is rejected: exporting `MSHookMemory`
  alone does not establish permission to modify signed executable pages.
- Startup readiness is tracked separately from the registered lifecycle hook.
- The v7 download backend and settings interface are unchanged. No diagnostic
  loader, additional screens or permanent polling were added.

## Downloads and requirements

**Jailbreak packages only — no IPA is included in this release.**

- `spotify-v7.2-rootless.deb`: standard rootless jailbreak.
- `spotify-v7.2-roothide.deb`: RootHide jailbreak.
- `SHA256SUMS`: SHA-256 checksums for these two packages.

Install **one** matching DEB through your jailbreak package manager and restart
Spotify. Package version: `7.0.0+native.v7.2`; identifier: `com.eevee.spotify`.

Minimum iOS: **16.1**. Liquid Glass requires **iOS 26 or later**. Native downloads
require the exact **Spotify 9.1.88 ARM64 binary**, UUID
`f51dbd933b8f3a12943196c606e3afc2`; matching version numbers alone are insufficient.
Orion **1.0.0 or later** and a supported injection engine providing `MSHookMemory`
are required. These DEBs are not intended for LiveContainer or direct IPA injection.

## Local verification

- All 11 existing v7 provenance and patcher tests passed.
- ASan/UBSan tests verified zero executable writes during startup preflight,
  one-time patching at manager initialization, initializer forwarding, exact-image
  guards and partial-write rollback.
- Runtime AudioToolbox import rebinding and audio forwarding passed on a real
  Apple AudioUnit on macOS.
- Both DEBs passed package layout, filter, required symbols, dependency paths,
  signatures, minimum deployment target and licence checks.

**These checks do not verify device launch, downloads or offline playback on a
jailbroken iPhone.** Please report results in
[this fork's issues](https://github.com/Glongq/EeveeSpotifyReincarnated/issues).

[Source and build guide](https://github.com/Glongq/EeveeSpotifyReincarnated/blob/native-v7.2-jailbreak/NativeDownloads/jailbreak/README.md)
