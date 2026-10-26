# EeveeSpotify 7.0.0 / Spotify 9.1.92 / Pixie Manager 1.3

This isolated project copies the working Eevee/Pixie 1.3 sources from
`2026-10-19/eevee-source-publish`, excluding old outputs, build directories,
packages and repository history. Pixie stays at version 1.3.

The supplied IPA is `Spotify 9.1.92 (EeveeSpotify 7.0.0) [@ipavault].ipa`,
Spotify build `919203058`, ARM64 UUID `2acd33ee445b326d8b75b3e32403790a`.

| Native boundary | Spotify 9.1.90 | Spotify 9.1.92 |
| --- | --- | --- |
| Restriction setter | `0x101d1debc` | `0x107fcf9fc` |
| Offline manager vtable | `0x10ca326c8` | `0x10d3b0be0` |
| Request argument instruction | `0x103594f60` | `0x103184140` |
| Native provider | `0x1083de7b0` | `0x1011c5544` |
| Provider argument mapping | `0x1083de894` | `0x1011c5628` |
| Success callback | `0x106231e70` | `0x107ef6ed4` |
| Failure callback | `0x100893730` | `0x108d72d20` |
| Imported dlsym stub | `0x109b65b68` | `0x10a2f8938` |

The setter remains manager-vtable slot 65. Its music/episode fields remain at
the same offsets. The manager destructor publishes the relocated vtable with
the same secondary-table offsets. Native hook class/selector names are still
present. The request site still constructs the same two native callbacks.

The failure observer uses verified zero-filled space after the final declared
section of executable `__TEXT`. The larger 9.1.92 image puts that callback
outside a direct ARM64 branch's reach from the old header cave. This preserves
the existing direct-branch trampoline and original callback ABI. No live code
patching, extra polling or callback replacement is introduced.

The diagnostic render-source callback was separately matched from the original
9.1.88 callback to `0x107fa0da4`; the owner/source fields are unchanged.

## Verification

- Eevee UI and Pixie companion compiled successfully.
- Native ARM64 fixtures passed for the quota setter and all observation
  trampolines, including register/vector/FP state and diagnostics-off behavior.
- The exact input UUID, bytes, dlsym binding, manager vtable and native hook
  names passed; altered entries, occupied caves and repeated patches reject.
- Packaging changes only the Spotify executable and Eevee library and adds
  the Pixie companion. Input resources and five extensions are retained.
- This 9.1.92 IPA has not been launched or tested on an iPhone. No jailbreak
  package is produced or claimed compatible by this port.

See `BUILD-pixie-v1.3.md` for build commands. All new outputs belong in a fresh
directory under `outputs/`.
