"""Check a Pixie DEB's layout and dependency chain without claiming device I/O."""
import argparse
import hashlib
import json
import struct
import subprocess
import tempfile
from pathlib import Path

from patch_offline import TARGET, DISABLED
from pixie_target import ROOT

MARKERS = ('AdsSponsoredContextServiceImpl', 'AdsSponsoredContextNPBAttachmentServiceImpl',
    'AdsSponsoredPlaylistHeaderServiceImpl', 'SelfLoadingUpsellBannerUIView',
    'ReferralsUpsellCardElementServiceImpl', 'DownloadUpsellService', 'FreeHostedJamsUpsellServiceImpl',
    'FreeUserSkipUpsellPageService', 'FreeUserShuffleUpsellSheetPageService',
    'premium_gated_start_jam_buttons_enabled', 'playlist_downloading_popup',
    'downloadToggledWithCurrentAvailability:addAction:removeAction:pageIdentifier:pageURI:interactionID:')
EXPORTS = ('SAPCreateDownloadsSettings', 'SAPStartupReport', 'SAPTraceNativeBoundary',
    'SAPObserveExportBoundaryV2', 'AudioUnitSetProperty', 'AudioUnitGetProperty',
    'AudioOutputUnitStart', 'AudioOutputUnitStop', 'AudioComponentInstanceDispose')


def run(*args):
    return subprocess.check_output(list(map(str, args)), text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('--scheme', choices=['rootless', 'roothide'], required=True)
    parser.add_argument('--build-dir', type=Path, required=True)
    args = parser.parse_args()
    package = args.package.resolve()
    build = json.loads((args.build_dir/'build.json').read_text())
    architecture = run('dpkg-deb', '-f', package, 'Architecture').strip()
    assert architecture == {'rootless':'iphoneos-arm64', 'roothide':'iphoneos-arm64e'}[args.scheme]
    assert build['scheme'] == args.scheme and build['matches_ipa_native_patches']
    for name, digest in build['source_sha256_by_file'].items():
        assert hashlib.sha256((ROOT.parent/name).read_bytes()).hexdigest() == digest, 'Source changed: '+name
    with tempfile.TemporaryDirectory(prefix='pixie-deb-check-') as temporary:
        root = Path(temporary)
        subprocess.run(['dpkg-deb', '-x', str(package), str(root)], check=True)
        def one(name):
            matches = list(root.rglob(name))
            assert len(matches) == 1, (name, matches)
            return matches[0]
        eevee, companion = one('EeveeSpotify.dylib'), one('SpotifyAudioProbe.dylib')
        assert eevee.parent == companion.parent
        assert str(eevee.relative_to(root)).startswith('var/jb/' if args.scheme == 'rootless' else 'Library/')
        assert hashlib.sha256(companion.read_bytes()).hexdigest() == build['companion_sha256']
        links = run('otool', '-L', eevee)
        assert '@loader_path/SpotifyAudioProbe.dylib' in links
        # It must be a required dependency, not dependent on tweak discovery order.
        binary, cursor, required = eevee.read_bytes(), 32, False
        assert struct.unpack_from('<I', binary)[0] == 0xfeedfacf
        for _ in range(struct.unpack_from('<I', binary, 16)[0]):
            command, size = struct.unpack_from('<II', binary, cursor)
            if command == 0xc:
                name_offset = struct.unpack_from('<I', binary, cursor+8)[0]
                name = binary[cursor+name_offset:cursor+size].split(b'\0')[0]
                required |= name == b'@loader_path/SpotifyAudioProbe.dylib'
            cursor += size
        assert required, 'Companion is not a required dylib dependency'
        assert '@loader_path/SpotifyAudioProbe.dylib' in run('otool', '-D', companion)
        companion_links = run('otool', '-L', companion)
        assert ('@loader_path/.jbroot/usr/lib/libsubstrate.dylib' if args.scheme == 'roothide'
                else '@rpath/CydiaSubstrate.framework/CydiaSubstrate') in companion_links
        symbols = {line.split()[-1] for line in run('nm', '-gU', companion).splitlines() if line.split()}
        assert all('_'+name in symbols for name in EXPORTS), 'Companion API missing'
        assert all(marker in run('strings', eevee) for marker in MARKERS)
        assert binary.count(TARGET) == 0 and binary.count(DISABLED) == 1
        one('EeveeSpotify.bundle'); one('EeveeSpotify.plist'); one('KaraokeBackgroundShader.metallib')
        framework = one('EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf')
        if args.scheme == 'roothide':
            assert 'libroothide' in links
            assert '@loader_path/.jbroot/Library/Frameworks/EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf' in run('otool', '-D', framework)
        assert one('M4A-NOTICES.md').read_bytes() == (ROOT/'vendor/M4A-NOTICES.md').read_bytes()
        subprocess.run(['codesign', '--verify', '--strict', str(companion)], check=True)
        for item in (eevee, companion, framework):
            run('xcrun', 'dyld_info', '-validate_only', item)
        report = {'package':str(package), 'scheme':args.scheme, 'architecture':architecture,
            'sha256':hashlib.sha256(package.read_bytes()).hexdigest(), 'size_bytes':package.stat().st_size,
            'version':run('dpkg-deb','-f',package,'Version').strip(), 'pixie_bundled':True,
            'required_companion_dependency':True, 'exported_api_checked':list(EXPORTS),
            'eevee_markers_checked':len(MARKERS), 'reminder_patch_applied':True,
            'companion_signature_valid':True, 'notices_bundled':True, 'build':build,
            'device_runtime_tested':False}
    package.with_suffix('.build.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ('scheme','architecture','pixie_bundled','required_companion_dependency','size_bytes')}))


if __name__ == '__main__':
    main()
