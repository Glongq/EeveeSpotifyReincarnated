# Sprite Download Manager 7.3 — jailbreak packages

Preparation revision v7.3 of `spotify-ui-v7`, based on fork source commit
`1e93d081d49cd0273c9493665b30b69994aea156`. Built with OpenAI Codex under
Glongq's direction. This is an unofficial fork of EeveeSpotifyReincarnated.

> **NOT TESTED ON A REAL JAILBROKEN DEVICE.** This is an experimental pre-release.
> Local tests passed; installation, downloading and offline playback on a
> jailbroken iPhone have not been verified.

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

The IPA applied two guarded executable patches before signing. Jailbreak loading
applies the same bytes to the **mapped process image** through `MSHookMemory`:

1. During library loading, validate the exact UUID, instructions, writer capability
   (unless already statically prepared), and initializer signature, then register
   one offline-manager initializer hook. No executable
   memory or AudioToolbox import writes occur during this preflight.
2. On the first native offline-manager construction, before forwarding its init,
   install the existing quota trampoline/entry branch and key mode 0. Arguments
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
v7 provenance, tests runtime guards/rollback, builds both packages, then checks
package paths, injection filter, native symbols, dependencies, signatures and
minimum deployment targets. It does not push, tag, or create a release.
Outputs are in `NativeDownloads/outputs/jailbreak-v7.3/`.

## Device acceptance test still required

Install the matching package using the jailbreak package manager, with Spotify
9.1.88 already installed, and restart Spotify. Open EeveeSpotify → Sprite Download Manager.
Verify the runtime reports the supported image and key mode 0. Download a fresh
album, wait for native completion, restart offline, then play and seek within
previously unplayed tracks. Also verify normal playback, pause/resume, relaunch,
and the downloads menu on a pre-iOS-26 device with glass disabled.

Do not label this port device-verified until those checks pass on a real
jailbroken device. An unsupported Spotify image should remain unchanged and log
an inactive adapter rather than trying nearby offsets.

## v7.3 validation status

This release contains jailbreak DEBs only. Install through the jailbreak package
manager; copying its libraries into an IPA alone does not prepare native downloads. For
sideloading, use the documented `NativeDownloads/tools/prepare_ipa.py` build step
before installation signing; this is separate from installing the DEB on jailbreak.

The startup path was changed after reported v7.1 launch failures. The remote
crash has not been reproduced locally or confirmed resolved on the affected
device. v7.3 remains an unverified pre-release.

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
