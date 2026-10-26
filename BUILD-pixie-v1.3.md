# Build EeveeSpotify 7.0.0 / Spotify 9.1.90 + Pixie Manager v1.3

Requires macOS, full Xcode, Python 3, Theos with Orion and EeveeSwiftProtobuf, and GNU make. Use an iOS 26+ SDK for the Liquid Glass controls. Supply your own compatible, decrypted EeveeSpotify 7.0.0 / Spotify 9.1.90 IPA.

From the repository root, with `THEOS` set:

```sh
python3 NativeDownloads/tools/validate_eevee_9190.py
THEOS_PACKAGE_SCHEME=rootless gmake -j4 all FINALPACKAGE=1
cp .theos/obj/EeveeSpotify.dylib /tmp/EeveeSpotify-Pixie.dylib
codesign --force --sign - --timestamp=none /tmp/EeveeSpotify-Pixie.dylib
python3 NativeDownloads/tools/build_eevee_9190.py /path/to/EeveeSpotify-7.0.0-9.1.90.ipa \
  --eevee-dylib /tmp/EeveeSpotify-Pixie.dylib \
  --output NativeDownloads/outputs/new-build/Spotify-9.1.90-EeveeSpotify-Pixie-v1.3.ipa
```

Choose a fresh output directory for each build. The builder preserves the input resources and extensions, updates the guarded Spotify executable and Eevee library, and adds the Pixie companion. It signs the changed binaries ad hoc for packaging; installation requires your signing tool. No certificate or account credentials are supplied by this repository.

Current IPA builds keep the Eevee UI and Pixie companion separate. Do not enable `NATIVE_DOWNLOADS_JAILBREAK=1` for this command or inject an old unified Pixie v1 library alongside it.

The source snapshot includes artist identity and layout integration, release/playlist queues, native completion recovery, diagnostics and offline-device management. Eevee's existing `SpriteAuthentication.headersWithCompletion:` supplies authenticated headers. No Vitrine runtime is required.

Local device-management tests cover source agreement, reviewed device/cache identities, one-shot commands, failed/malformed responses, readback and the real Swift Eevee header-provider bridge. Their HTTP requests are intercepted by `NSURLProtocol`; they do not authenticate to Spotify or change real devices.

Old `build.py`, `prepare_ipa.py`, jailbreak tooling and v1 provenance describe the previous 9.1.88 release. Use tag `pixie-v1` to reproduce those artifacts. The current source publication does not rebuild or validate jailbreak packages.
