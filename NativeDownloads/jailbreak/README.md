# Pixie Download Manager — Eevee-Pixie v1 jailbreak packages

Port of the Pixie menu and applicable fixes onto the Eevee/Sprite 7.3 base
(`76f7888c74f68f7b7693b1894a76a2313d7661e9`). Built with OpenAI Codex under
Glongq's direction. This is an unofficial fork of EeveeSpotifyReincarnated.
See [v1 release notes](../../RELEASE_NOTES-pixie-v1.md).

> The maintainer reports full jailbreak testing of the pre-rename fixed v1 packages.
> Pixie v1 changes their visible branding only. The renamed packages passed local
> validation; the jailbreak and iOS versions of the reported test were not supplied.

## Compatibility

- Package minimum: iOS 16.1. Liquid Glass activates only on iOS 26 or later.
- Native downloads require **Spotify 9.1.88**, ARM64 Mach-O UUID
  `f51dbd933b8f3a12943196c606e3afc2`. A matching app version string alone is
  insufficient: App Store variants can have different UUIDs/code.
- `rootless` and `roothide` packages are separate alternatives; install only the
  one matching the jailbreak. The package identifier remains `com.eevee.spotify`
  so package managers replace the original tweak instead of injecting two copies.
- The injection engine must export `MSHookMemory` (including ElleKit's Substrate
  compatibility API). If unavailable or a guard fails, the adapter stays inactive.
- These are jailbreak packages, not LiveContainer IPA files. Our original v7
  LiveContainer device results do not verify this new runtime adapter.

## What changes from the IPA build

The native queue, transport, callbacks, UI, cache and persistence retain their v7
implementations. The shared preparation check now requires both verified code
patches and the target quotas. Quotas alone no longer produce `ready=true`.
The read-only sampler uses the same rule. WAV capture stays disabled.

The IPA applies guarded executable patches and passive diagnostic boundaries before signing. Jailbreak loading
applies the same bytes to the **mapped process image** through `MSHookMemory`:

1. During library loading, validate the exact UUID, instructions, writer capability
   (unless already statically prepared), and initializer signature, then register
   one offline-manager initializer hook. No executable
   memory or AudioToolbox import writes occur during this preflight.
2. On the first native offline-manager construction, before forwarding its init,
   install the quota trampoline/entry branch and fixed-mode request/callback observers. Arguments
   and the retained initializer result are forwarded unchanged.
3. Check each write and attempt rollback if any write is partial or rejected.
4. Rebind only Spotify's five AudioToolbox imports for audio diagnostics. Original
   AudioToolbox implementations remain available to the probe, avoiding recursion.
5. Skip Eevee's download reminder when a validated native initializer hook owns
   download handling. Readiness is reported separately after patch application.

No executable file in the Spotify app is rewritten. Patching is once per process,
without a periodic code writer. Existing v7 download scheduling remains unchanged.
An executable writer bundled inside the app is rejected; exporting the symbol
alone does not prove a sideloaded app can modify executable pages.

## Build locally

Requires Xcode with the iPhoneOS SDK and Metal toolchain, GNU make, dpkg, ldid,
a standard recursive Theos checkout and a recursive `roothide/theos` checkout.

```sh
THEOS_ROOTLESS=/absolute/path/to/theos \
THEOS_ROOTHIDE=/absolute/path/to/roothide-theos \
NativeDownloads/jailbreak/build-debs.sh
```

The script builds the renamed EeveeSwiftProtobuf dependency if absent, verifies
v1 provenance, tests runtime guards/rollback, builds both packages, then checks
package paths, injection filter, native symbols, dependencies, signatures and
minimum deployment targets. It does not push, tag, or create a release.
Outputs are in `NativeDownloads/outputs/pixie-v1/`.

## Device checks for other configurations

Install the matching package using the jailbreak package manager, with Spotify
9.1.88 already installed, and restart Spotify. Open EeveeSpotify → Pixie Download Manager.
Verify the runtime reports the supported image and key mode 0. Download a fresh
album, wait for native completion, restart offline, then play and seek within
previously unplayed tracks. Also verify normal playback, pause/resume, relaunch,
and the downloads menu on a pre-iOS-26 device with glass disabled.

Do not infer support for another jailbreak/iOS combination from the reported test. An unsupported Spotify image should remain unchanged and log
an inactive adapter rather than trying nearby offsets.

## Device validation status

The DEBs are separate from the prepared sideload IPA. Install through the jailbreak package
manager; copying its libraries into an IPA alone does not prepare native downloads. For
sideloading, use the documented `NativeDownloads/tools/prepare_ipa.py` build step
before installation signing; this is separate from installing the DEB on jailbreak.

The startup path was changed after reported v7.1 launch failures. The remote
crash has not been reproduced locally or confirmed resolved on the affected
device. The maintainer subsequently reported that the fixed v1 packages work on jailbreak; the original reporter's device configuration remains unverified.

## v7.3 readiness correction

The shared report exposes `quota_ready`, `executable_patches_ready`, and `ready`.
`ready` requires all three: supported live manager, both verified code patches,
and target quotas. The earlier combination of elevated quotas + untouched key
mode 1 now reports false. Missing/unknown key mode is also false. The manual
button returns a specific missing-patches error without sending `AddDownload`.
No new timers, scanning, background writers or key retries were added.

The adapter does not take over the download reminder when required patches are
missing and no external jailbreak writer is available. A fully prepared IPA
requires no executable writer and causes zero executable-memory writes.
