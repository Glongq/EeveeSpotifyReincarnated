# Native Downloads v7 — experimental jailbreak packages

> [!WARNING]
> **NOT TESTED ON A REAL JAILBROKEN DEVICE.** These packages passed local tests
> and archive validation only. Installation, native downloading and offline
> playback on a jailbroken iPhone have **not** been verified. Previous
> SideStore/LiveContainer results do not verify this jailbreak adapter.

This is **Glongq's unofficial fork** of
[SideloadLabs/EeveeSpotifyReincarnated](https://github.com/SideloadLabs/EeveeSpotifyReincarnated),
built with **OpenAI Codex under Glongq's direction**.

## Included

- Full EeveeSpotify tweak with the native downloader and UI v7 settings.
- Separate `spotify-v7-rootless.deb` and `spotify-v7-roothide.deb` packages.
- The v7 native-download backend is unchanged. The jailbreak adapter applies the
  existing guarded changes to the mapped Spotify process, once per launch.
- Download controls remain in **EeveeSpotify → Track downloads**.
- Downloads use Spotify's own offline storage. MP3/WAV export is not included;
  WAV capture remains disabled.
- The renamed EeveeSwiftProtobuf framework, resources and licence notices are
  bundled. Package version: `7.0.0+native.v7.1`.

## Requirements and installation

1. Use a **jailbroken device with iOS 16.1 or later**. Liquid Glass requires
   **iOS 26 or later**; disabling glass does not lower the package's iOS minimum.
2. Native downloads require the exact **Spotify 9.1.88 ARM64 binary**, Mach-O UUID
   `f51dbd933b8f3a12943196c606e3afc2`. A matching version string alone does not
   guarantee compatibility. Unsupported binaries are rejected by the adapter.
3. Install **only one** `.deb`, matching your jailbreak: standard rootless or
   RootHide. These files cannot be installed in LiveContainer.
4. Use the jailbreak package manager to resolve **Orion ≥ 1.0.0**. The injection
   engine must provide `MSHookMemory`, such as ElleKit's compatibility API.
5. Restart Spotify after installation. The package keeps identifier
   `com.eevee.spotify` to replace the original tweak rather than inject a second
   copy.

## Local checks completed

- All 11 portable v7 provenance and patcher tests passed.
- Native host tests passed, including audio forwarding, native quota trampoline,
  download state handling, journals and localisation.
- Adapter tests covered exact-image guards, repeated initialization, unsupported
  images and rollback after partial writes, with ASan/UBSan.
- Runtime import rebinding was exercised with a real Apple AudioUnit on macOS.
- Both packages passed layout, injection filter, symbols, dependency paths,
  signatures, minimum deployment target and licence checks.

**These checks are not a substitute for testing on a real jailbroken device.**
This release is intentionally marked **Pre-release**. Report jailbreak-specific
issues in [this fork](https://github.com/Glongq/EeveeSpotifyReincarnated/issues),
including the jailbreak, iOS version, Spotify build and redacted diagnostic logs.

See [the jailbreak build guide](https://github.com/Glongq/EeveeSpotifyReincarnated/blob/native-v7-jailbreak/NativeDownloads/jailbreak/README.md) for source,
build instructions and the outstanding device acceptance test. SHA-256 hashes
for both packages are provided in `SHA256SUMS`.
