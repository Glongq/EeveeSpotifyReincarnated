# Native downloads v7 — jailbreak packages

Local development port of `spotify-ui-v7`, based on fork source commit
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

The existing `NativeDownloads/src` files remain byte-for-byte v7. The downloader,
UI, native queue, callbacks, cache and persistence use the same implementations.
WAV capture stays disabled, as in the v7 release.

The IPA applied two guarded executable patches before signing. Jailbreak loading
applies the same bytes to the **mapped process image** through `MSHookMemory`:

1. Check the exact Mach-O UUID, executable text, reserved header padding, quota
   setter, key caller, provider and mode-mapping instructions.
2. Install the existing quota trampoline, then its entry branch, then change
   the existing offline caller's key-request mode from 1 to 0.
3. Check each write and attempt rollback if any write is partial or rejected.
4. Rebind only Spotify's five AudioToolbox imports for audio diagnostics. Original
   AudioToolbox implementations remain available to the probe, avoiding recursion.
5. Skip Eevee's download reminder only when the native adapter initialized.

No executable file in the Spotify app is rewritten. Patching is once per process,
without a periodic code writer. Existing v7 download scheduling remains unchanged.

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
Outputs are in `NativeDownloads/outputs/jailbreak-v7/`.

## Device acceptance test still required

Install the matching package using the jailbreak package manager, with Spotify
9.1.88 already installed, and restart Spotify. Open EeveeSpotify → Track downloads.
Verify the runtime reports the supported image and key mode 0. Download a fresh
album, wait for native completion, restart offline, then play and seek within
previously unplayed tracks. Also verify normal playback, pause/resume, relaunch,
and the downloads menu on a pre-iOS-26 device with glass disabled.

Do not label this port device-verified until those checks pass on a real
jailbroken device. An unsupported Spotify image should remain unchanged and log
an inactive adapter rather than trying nearby offsets.
