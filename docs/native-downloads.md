# Native downloads: architecture and verification

## Scope

This fork adds the experimental native-download implementation from
`spotify-ui-v4` to EeveeSpotifyReincarnated. It has been tested on the exact
Spotify 9.1.88 ARM64 binary documented in `NativeDownloads/provenance.json`.
Support for other Spotify binaries must be established separately.

## Installation verification

- **LiveContainer:** installation, native downloads and offline playback were
  confirmed by the maintainer on iPhone 15 Pro Max running iOS 27.0.1.
- **SideStore:** installation, native downloads and offline playback were also
  confirmed by the maintainer on the same test device.

The detailed diagnostic snapshots described below were collected during the
LiveContainer verification. The subsequent SideStore test is user-confirmed,
rather than a separately published native diagnostic capture.

## Request lifecycle

1. iOS loads `SpotifyAudioProbe.dylib` through the added Mach-O dependency.
   Its constructor installs the offline configuration, manager, transport and
   settings integrations once per process.
2. Spotify's own album/playlist action reaches
   `SPTOfflineManagerImplementation.makeEntityAvailableOfflineWithURL:trackURLs:`
   or its URL-only variant. The observer records the request and calls the original.
   The custom single-track action reads `SPTEsperantoPlayer.state.track.URI`.
3. Native manager preparation executes on the manager's scheduler and checks the
   supported image before using version-specific offsets. The v4 quota guard
   uses minimum music limits of 1,000,000 tracks and 2,147,483,647 seconds of total
   music duration. These are local content quotas, not licence validity periods.
   Native negative/sentinel updates remain unchanged.
4. The single-track action probes `GetItems` using existing Esperanto transports,
   then sends `AddDownload` to `spotify.offline_esperanto.proto.Offline` if required.
   Existing queued/downloaded tasks are monitored without adding a duplicate.
5. The guarded offline key-request call passes mode 0 instead of mode 1. The
   original provider, audio-file identifier, callbacks, native handles and storage
   path remain in use. Keys are issued through Spotify's infrastructure. The full
   server-side semantics of every numeric mode have not been established.
6. Spotify's original downloader retrieves and persists the content. Network
   ordering and scheduling are controlled by Spotify. Automatic Play/PreparePlay
   commands are not part of the download implementation.
7. The single-track action requires two consecutive `GetItems` downloaded states
   before announcing completion. Optional diagnostics additionally compare native
   key/completion events, item states, collection progress and displayed icons.
8. Completion, error or timeout releases the action's observers and timers. A
   verification timeout does not itself prove that native downloading stopped.

The supplied Eevee reminder handler is disabled by a guarded, one-byte target-name
change so Spotify's original offlining handler can run. The extension is a
companion library; ordinary upstream .deb builds do not acquire it automatically.

## Diagnostics and performance

Diagnostics have their own persisted switch and are off by default. When enabled,
active single-track checks poll about once a second; journal sessions refresh
tracked items about every 5 seconds, collections/total progress about every 10
seconds, and manager/licence snapshots about every 30 seconds. Sessions have idle
and maximum-duration bounds. Read requests can use bounded bridge fallbacks;
unacknowledged AddDownload mutations are not blindly replayed.

v4 disables the recorder, WAV UI, writer timer and capture ring in release builds.
The audio diagnostics and manual mute API remain. It also caches settings icons,
reduces redundant transport/configuration work, and formats TXT/JSON from a shared
immutable journal snapshot off the UI thread. No whole-app battery-saving or
zero-overhead claim is made.

## Verified results

The local v4 device verification recorded:

- An album at 8/8 tracks, 100%, with downloaded bytes equal to total bytes and no
  remaining queued tracks.
- Fresh native key-received and download-completed events for seven new downloads.
- User-confirmed audible playback and seeking into the middle of two tested tracks
  after disabling Wi-Fi and cellular data.
- Diagnostics activation without the previously reproduced page-protocol crash.
- English/Russian UI and access to the final settings row above the mini-player
  in the UIKit fixture.

These observations describe the tested device/build and selected tracks. They
are not a guarantee for every account, encoding, operating system or future date.
The exported diagnostic snapshot still contained 19 unanswered and 16 outstanding
read requests. Ten recorded local-track errors were outside the tested album.
Long-term licence renewal and cellular-only downloading have not been
verified separately.

Private device exports, account data and raw playback histories are not included
in this repository. `NativeDownloads/provenance.json` records source and reference
artifact hashes; packaged application binaries are not committed.

## Maintaining the snapshot

The runtime source files match the recorded v4 hashes. Packaging/tests are adapted
for portable repository paths. Before changing runtime code, review the change,
update the matching source hashes in `provenance.json`, and document the new tested
scope. A changed build should receive a new release identifier. Never remove the
UUID/instruction guards merely to accept a different Spotify binary.

Upstream project: https://github.com/SideloadLabs/EeveeSpotifyReincarnated
Upstream base commit: `c211189324145d20a032eabc83f886ff8b38798d`.

## Credits

Native-download development, fork integration, documentation and local builds were
produced with OpenAI Codex under Glongq's direction. Glongq performed device testing
and supplied feedback. The upstream EeveeSpotify project retains its original
authorship, history and GPLv3 licence.
