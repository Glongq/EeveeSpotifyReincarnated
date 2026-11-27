# Pixie DEB builds

EeveeSpotify with Pixie as rootless and RootHide packages, for every Spotify version
that has a target profile in `NativeDownloads/targets`. Device runtime testing remains
required.

## GitHub Actions

`.github/workflows/pixie-debs.yml` runs on push to a branch whose name contains
`debs`, or by hand. It is upstream's `builddeb.yml` (Xcode 26.3, theos/theos for
rootless, roothide/theos for RootHide, EeveeSwiftProtobuf 1.29.0, the same tests and
package checks, `make package FINALPACKAGE=1`) with `PIXIE_JAILBREAK=1` and these
additions:

- One build per target in `NativeDownloads/targets` whose clean decrypted IPA,
  `com.spotify.client-<version>-*.ipa`, is attached to the draft release named by the
  repository variable `PIXIE_IPA_RELEASE`. Versions without one are skipped with a
  warning.
- The IPA is read on the runner only to generate the guarded patch plan with the
  same IPA patchers; it is never uploaded.
- The guarded runtime helpers are tested, and each package is checked by
  `tools/validate_jailbreak_deb.py` and for the compiled karaoke shader.
- Artifacts: the DEB, its SHA-256 and the companion's `build.json`. No release is created.

A new Spotify version needs no workflow change: once its target profile exists,
attach its clean IPA to the draft release.

## Makefile

`PIXIE_JAILBREAK=1` requires `PIXIE_TARGET=targets/spotify-<version>.json`. The plan
comes from `PIXIE_SOURCE_IPA` (a clean IPA), or else from a prepared plan in
`jailbreak/plans/spotify-<version>`, which can be exported without committing the IPA:

```sh
PIXIE_TARGET=targets/spotify-<version>.json python3 NativeDownloads/tools/build_jailbreak.py \
  --ipa /path/to/clean-Spotify.ipa --export-plan NativeDownloads/jailbreak/plans/spotify-<version>
```

A prepared plan is refused once any generator input changes.

## Runtime changes

- Bundle Pixie as a required dependency of Eevee in the existing Theos package.
- Apply the IPA native patches in memory through the Substrate-compatible
  `MSHookMemory` API, with exact UUID and original-byte validation before writes.
- Install payloads before entry branches, then audio import slots; verify writes
  and roll back in reverse phase order on failure. Preserve previous audio hooks.
- Select the unique loaded `MH_EXECUTE` image. Record bundle build metadata as
  informational; matching UUID and every guarded byte remain mandatory.
- Include expected/observed identities, executable index/path, memory backend,
  native guards, import failures and write-verification failures in the existing
  self-contained Send log and startup summary.

## Local build

`Scripts/build-pixie-debs-local.py --ipa /path/to/clean-Spotify.ipa` picks the target
from the IPA's version. Prepare each scheme's Theos and EeveeSwiftProtobuf framework first.
