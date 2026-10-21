# Eevee-Pixie v1

Spotify **9.1.88** · EeveeSpotify **7.0.0** · Pixie Download Manager **v1**


### Menu button fix

Restore interaction and normal selection state when a table cell is reused.
Slot checks can no longer leave unrelated actions disabled after a reload.
The production change is limited to menu-cell configuration.
DEB package revision: `7.0.0+sprite.v1-2`; the manager remains Eevee-Pixie v1.

## Changes

- Pixie-style Download, Download compatibility, Status, Diagnostics and Me sections.
- Download the current track or its album using Spotify's native offline manager.
- One **Send log** JSON containing the report, bounded events and download history.
- Full journal/trace reset, including retained and pending history; stale callbacks cannot restore deleted trace records.
- Compatibility reads and offline-device management with preview, confirmation and verified readback; no automatic removals.
- Optional request/success/failure observation adapted to the exact 9.1.88 binary. Diagnostics default off; key material is not read.
- Keep the v7.3 executable/quota readiness rule and fixed request mode 0. Native queueing and offline storage remain under Spotify.
- Keep the native Add/Download header controls bound through transient updates.
- English-only Pixie manager, Eevee-Pixie v1 footer and new IPA/ZIP/DEB filenames.

## Sources

Eevee/Sprite base: `76f7888c74f68f7b7693b1894a76a2313d7661e9`.
Pixie reference: `Glongq/Vitrine-Pixie`, `0e00970f5ad2decc2aa7ed87286c96f2013785ed`,
plus local journal/trace reset fixes. Source hashes are in
`NativeDownloads/provenance-pixie-v1.json`.

Pixie's 9.1.90 offsets, Vitrine startup patcher and local-cover parser are not
copied into Eevee. Eevee does not contain the affected Vitrine cover parser.
The applicable native observer points and original instructions were checked
against the maintainer's own 9.1.88 base IPA. The tester's IPA was not modified.

Implementation, integration and local builds: **OpenAI Codex**, under Glongq's
direction. Upstream authorship and GPLv3 licensing remain intact.

## Validation scope

Host tests cover native ABI/state preservation, diagnostics-off behavior,
read-request timeouts/fallbacks, album resolution, journal reset, compatibility
and device-request mocks, static binary guards and runtime rollback. The menu
fixture is checked in the iOS simulator, including mini-player clearance.

These checks do not prove downloading on a real iPhone or correct server
responses for every account. The maintainer reports full jailbreak testing of the pre-rename fixed v1 packages and confirms the fixed menu in LiveContainer. The Pixie rename changes display strings only and passed local package/signature/UI checks. The jailbreak and iOS versions of the reported jailbreak test were not supplied. Earlier v4 sideload results remain historical baseline results.

## Rename-only packaging

Only visible Sprite labels became Pixie. All runtime sources match the tested fixed v1 sources after reversing those string edits. In each DEB, only the control display name/description and the re-signed library changed; all other files, archive paths, ownership and permissions were preserved. Package ID `com.eevee.spotify`, internal version `7.0.0+sprite.v1-2`, dependencies and injection filter remain unchanged.

The cancelled `…` menu download action is not included.

## Files

- `Spotify-9.1.88-Eevee-Pixie-v1.ipa` — prepared unified sideload core; sign with the installation tool.
- Local full ZIP — IPA and both DEBs; no Spotify IPA is uploaded in the GitHub release.
- `Spotify-9.1.88-Eevee-Pixie-v1-rootless.deb` — rootless jailbreak package.
- `Spotify-9.1.88-Eevee-Pixie-v1-roothide.deb` — RootHide jailbreak package.

Minimum iOS **16.1**. Liquid Glass requires **iOS 26**. Exact supported Spotify
Mach-O UUID: `f51dbd933b8f3a12943196c606e3afc2`.

GitHub assets include both DEBs, their matching Rootless/RootHide dylibs and checksums. Dylibs are unified cores, require their existing Orion/Protobuf dependencies, and are not a complete sideload installation. Use the Rootless core and `prepare_ipa.py` for the guarded IPA route; do not copy a RootHide core into a sideloaded app.
