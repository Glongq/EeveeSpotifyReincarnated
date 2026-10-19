# Common Issues — Glongq's Native Downloads Fork

> [!IMPORTANT]
> This FAQ covers the **unofficial Glongq fork**. For the original project,
> see the [upstream FAQ](https://github.com/SideloadLabs/EeveeSpotifyReincarnated/blob/Master/common_issues.md).
> Upstream installation and version instructions are not compatibility claims for this fork.

## Versions and sideloading installation

**Native Downloads v4** targets **Spotify 9.1.88 / EeveeSpotify 7.0.0**
with the guarded ARM64 binary documented in [the compatibility guide](NativeDownloads/README.md).

| Method | Install | Native downloads | Offline playback |
| --- | --- | --- | --- |
| **SideStore** | Verified | Verified | Verified |
| **LiveContainer** | Verified | Verified | Verified |

Tests were performed by the maintainer on iPhone 15 Pro Max / iOS 27.0.1.
Detailed native diagnostics were collected during the LiveContainer tests.
A matching Spotify version label alone does not guarantee the same binary.

This source repository has no public modified Spotify IPA release.
To make a local build, follow [NativeDownloads/README.md](NativeDownloads/README.md)
or run the [native-download workflow](.github/workflows/native-downloads.yml)
with a compatible user-supplied base IPA. The workflow uploads temporary artifacts
and does not automatically publish a GitHub Release.

# Feature Requests

For requests concerning this fork's native-download extension, open an issue
or a pull request in **Glongq/EeveeSpotifyReincarnated**. For features maintained
by upstream, consult the original project's contribution policy.

Other Premium features such as very high audio quality and AI DJ remain outside this fork's download implementation. Cellular-only downloading has not been independently validated; do not infer support from successful Wi-Fi tests.

# Troubleshooting & Issues

## Accessing Settings

EeveeSpotify settings can be accessed from within the Spotify app:
1. Open Spotify
2. Tap your profile icon (top right)
3. Scroll down to find "EeveeSpotify" in the settings list
4. Tap to access all tweak settings

## Something Went Wrong

If you're unable to sign in and see an error, try these solutions:
1. Clear Spotify app data
2. Reinstall the app
3. Check your internet connection
4. If using a VPN, try disconnecting/reconnecting

## Lyrics Not Showing Up

If you see the "Couldn't load the lyrics for this song" message and no lyrics load:
1. Open EeveeSpotify settings
2. Go to the Lyrics section
3. Try changing the lyrics source
4. If that doesn't help, go to the Patching section and enable "Overwrite Configuration"
5. Reset data within the EeveeSpotify settings

## Premium Not Working

If all tracks are skipped, a song stops as soon as you play it, songs play in a random order, you see the "You discovered a Premium feature" popup when trying to play a song, or you encounter other restrictions:

**Region Issue**: You can only use Spotify abroad for 14 days. The solution:
1. Connect to a VPN server in any country
2. Change your region at accounts.spotify.com
3. Sign out of Spotify
4. Log back into Spotify with the VPN still enabled

This issue is solely related to your account region. Do not enable "Overwrite Configuration" unless you've also tried the region fix. If your region is already correct, still try connecting to a VPN, changing your region to somewhere else, signing out, and then logging back into the Spotify app.

## Downloading

This fork includes **experimental native downloads**, based on the verified v4
runtime. Use Spotify's regular album/playlist Download button, or open
**EeveeSpotify → Track downloads** for the current-track action and diagnostics.

- The checked target is Spotify 9.1.88 / EeveeSpotify 7.0.0 with the exact
  Mach-O UUID in [the compatibility guide](NativeDownloads/README.md).
  The maintainer confirmed native downloads and offline playback with both
  **SideStore and LiveContainer** on the tested device.
- Content is stored by Spotify for offline playback. Separate MP3/WAV export is
  not part of this release; WAV capture is disabled.
- A request being accepted or a green icon alone is not an independent playback
  test. Use the native state check and, when appropriate, verify with networking off.
- Historical errors can remain after a later successful download. Diagnostic
  read requests can still time out; this is a documented remaining limitation.
- Automatic per-track playback is not required by the download implementation.
- Long-term licence renewal and cellular-only downloads have not been verified.

For problems, enable diagnostics, reproduce the issue, and submit the relevant
redacted observations to **Glongq/EeveeSpotifyReincarnated** using the Native
Download issue form. This implementation is independent of upstream's download
policy; do not send its support issues to upstream.

The upstream "Download local playlist" action refers to local files from a PC
on the same Wi-Fi network. It is a separate feature.

## Spotify Connect

When using Spotify Connect, you may encounter ads, be unable to skip tracks, and experience other limitations. The music is streamed directly from Spotify's cloud to the connected device, while your phone acts only as a remote control. This is beyond EeveeSpotify's control. If you want to avoid these limitations, use Bluetooth instead.

## Ads on Homescreen

You may see ads on the home screen. This is a known issue and will not be fixed, as it is a real challenge to patch these server-sided ads.

## Ads in Podcasts

You may see ads in podcasts. This is Spotify's default behavior, even on Premium accounts. This won't be fixed - just skip the ads manually.

