# Pixie DEB builds

Build EeveeSpotify with Pixie for Spotify 9.2.0 (build 920002054), executable UUID
`b49e75781d8635d38bb57daf68fed8a8`. Device runtime testing remains required.

## GitHub Actions

The `pixie-debs` branch runs `.github/workflows/builddeb.yml` on push. The workflow
keeps the upstream Theos process: Xcode 26.3, theos/theos for rootless,
roothide/theos for RootHide, EeveeSwiftProtobuf 1.29.0, then `make clean` and
`make package FINALPACKAGE=1`. Both schemes enable `PIXIE_JAILBREAK=1`.

The verified prepared plan under `plans/spotify-9.2.0` contains only native patch
and guard bytes, import offsets, target identity and provenance hashes. It was
produced from the matching clean decrypted IPA by the same IPA patchers. No full
Spotify executable or IPA is committed or uploaded to the runner. CI refuses a
stale generator input or changed plan header before compiling the companion.

To regenerate after changing a recorded generator input:

```sh
python3 NativeDownloads/tools/build_jailbreak.py --ipa /path/to/clean-Spotify.ipa \
  --export-plan NativeDownloads/jailbreak/plans/spotify-9.2.0
```

CI artifacts contain the DEB, source archive, generated plan, build provenance,
package validation, SHA-256 and focused runtime-helper results. Package checks
cover architecture, required companion dependency, API, signatures, framework,
Eevee reminder patch, decoder notices and compiled karaoke shader functions.
No release is created by this workflow.

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

The earlier combined identity error did not identify its failed subcondition.
Matching runtime UUID and code samples were observed, but successful host builds
or package checks do not establish jailbreak startup or download success.

## Local build

The clean-IPA path remains supported via `PIXIE_SOURCE_IPA`, or omit it to use the
prepared plan. Prepare each scheme's Theos and EeveeSwiftProtobuf framework first.
Local helper: `Scripts/build-pixie-debs-local.py --ipa /path/to/clean-Spotify.ipa`.
On hosts with restricted Xcode discovery, its optional `--metal-toolchain` argument
must preserve the `metallib` executable alias rather than resolving it to air-lld.
