# DEB branch instructions

- This branch builds EeveeSpotify with Pixie for rootless and RootHide.
- Keep the upstream Theos build: theos/theos for rootless and roothide/theos for RootHide; build EeveeSwiftProtobuf 1.29.0 per scheme.
- Do not commit IPA, DEB, toolchains or build output. The prepared native patch plan contains only verified offsets and patch/guard bytes, never the complete Spotify executable.
- Regenerate the prepared plan from a matching clean decrypted IPA after changing any recorded generator input. Keep exact executable UUID and guarded-byte checks before runtime writes.
- Preserve the single self-contained Send log export. Runtime success must be established on the jailbroken device.
- Commit completed changes locally; only push when the user requests it. Do not change existing PR branches or publish releases without an explicit request.
- Keep generated packages, source provenance and validation reports together under Outputs/DEBS.
