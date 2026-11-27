# Pixie DEB builds

EeveeSpotify with Pixie as rootless and RootHide packages, for every Spotify version
that has a target profile in `NativeDownloads/targets`. Device runtime testing remains
required.

## GitHub Actions

Upstream's `.github/workflows/builddeb.yml`, run by hand, unchanged when its `pixie`
field is empty. With `pixie` set to a Spotify version such as `9.2.2`, it also:

- requires `NativeDownloads/targets/spotify-<version>.json` and the clean decrypted IPA
  `com.spotify.client-<version>-*.ipa` in the draft release named by the repository
  variable `PIXIE_IPA_RELEASE`;
- reads that IPA on the runner only to generate the guarded patch plan, with the same
  patchers as the IPA build; it is never uploaded;
- builds both packages with `PIXIE_JAILBREAK=1` as version `<control Version>+pixie.<version>`;
- tests the guarded runtime helpers and checks each package with
  `tools/validate_jailbreak_deb.py` and for the compiled karaoke shader.

A new Spotify version needs no workflow change: once its target profile exists,
attach its clean IPA to the draft release and enter the version.

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
