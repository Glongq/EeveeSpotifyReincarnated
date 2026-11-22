# EeveeSpotify 7.0.0 / Spotify 9.1.92 / Pixie Manager 1.4

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

See `BUILD-pixie-v1.4.md` for build commands. All new outputs belong in a fresh
directory under `outputs/`.

## Pixie 1.4 export sites

Pixie 1.4 adds nine observation points for audio export plus code-window guards.
They were located by matching the verified Spotify 9.1.90 functions against the
9.1.92 executable (normalised instruction windows with relocation fields
masked) and then verified by original prologue bytes and instruction-by-instruction
comparison. Addresses and bytes live in `targets/spotify-9.1.92.json` (`export`).

| Boundary | 9.1.90 | 9.1.92 |
| --- | --- | --- |
| CacheKey | `0x101daf0d0` | `0x102f2cfd8` |
| StreamKey | `0x1012e2658` | `0x107ec7698` |
| CacheCipher | `0x1046ff01c` | `0x1043c1394` |
| CacheCipherApple | `0x1003dfb38` | `0x10498c258` |
| MediaKeyPath | `0x103594d70` | `0x103183f50` |
| MediaKeyBlob | `0x1020fd560` | `0x104d10e74` |
| MediaContext | `0x107970fe8` | `0x103032f54` |
| MediaRecord | `0x1020fd5f0` | `0x104d10f04` |
| UnsealedMediaKey | `0x103cc61f8` | `0x105230dac` |

Differences that matter: the offline-success callback reads the key owner's file
descriptor at offset `0x120` in 9.1.92 (`0xc8` in 9.1.90); the generated
`ExportSites.h` carries this and the other derived offsets so no 9.1.90 offset is
left in the runtime. The cache-key mapping, storage owner, unseal caller and
share-creation windows are otherwise instruction-identical.

Device check (maintainer's iPhone, LiveContainer, 2026-11-07): with build002 and later the trace shows the
unseal, media-record and cache-envelope boundaries firing and 55 of 56 export requests producing a file
(the failures were tracks downloaded by the earlier broken build001, which captured no keys). build001
exported nothing because the export observer compared the image with the 9.1.90 UUID. Final build006
(logs of the same device): 11 of 11 export requests produced a file, the media-key-path, unseal, media-record and
native-cache boundaries all fired, and the trace, action and journal logs contain no errors. M4A conversion of the
produced files, the share sheet and the download-quality row were used by the maintainer but are not separately
asserted in the logs.

Still unverified: a direct AltStore/ldid install (the dead bytes in front of the signature are removed, but this was
not tried), the raw download-quality enum on 9.1.92, Spotify Connect (it depends on LiveContainer's Local Network
permission), and the full builder from a clean EeveeSpotify 7.0.0 IPA (none was available).

## Download-quality hint

The "Download quality is Normal" row at the top of the Pixie menu no longer depends on Vitrine's
`SGSpotifyPreferences` / `SGOpenSpotifyURI` (neither exists in EeveeSpotify, so the row never appeared).
Pixie captures Spotify's own preferences object (`initWithScheduler:` and the `audioSyncBitrate` /
`playbackSpeed` getters) and link dispatcher (`setMainUILoaded:` and `navigateToURI:...`) and routes
`spotify:settings:quality` through the dispatcher. The row is a real first table section, shown only while
the quality is Normal and has never been High; tapping it, or any observed High, hides it permanently.
All selectors were checked to exist in the 9.1.92 executable. The raw quality enum (1 Low, 2 Normal, 3 High,
4 Very high, 5 Lossless) was proven on 9.1.90 and is assumed unchanged on 9.1.92; this is not device-verified.
