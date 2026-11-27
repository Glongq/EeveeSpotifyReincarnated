#!/usr/bin/env python3
"""Build and validate both Pixie DEBs using this project's prepared toolchains."""
import argparse
import io
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]


def validate_shader(package):
    data = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(package)])
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        matches = [m for m in archive.getmembers() if m.name.endswith('/KaraokeBackgroundShader.metallib')]
        assert len(matches) == 1, 'Metal shader missing or duplicated'
        shader = archive.extractfile(matches[0]).read()
        assert shader.startswith(b'MTLB') and all(name in shader for name in
            (b'karaoke_bg_vertex', b'karaoke_bg_fragment')), 'Metal library has no karaoke functions'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa', type=Path, required=True)
    parser.add_argument('--version', help='Package version (default: control Version + "+pixie.<Spotify version>")')
    parser.add_argument('--swift-no-nested-sandbox', action='store_true',
                        help='Run Xcode macro subprocesses inside the existing outer sandbox')
    args = parser.parse_args()
    ipa = args.ipa.resolve(strict=True)
    with ZipFile(ipa) as archive:
        spotify = plistlib.loads(archive.read('Payload/Spotify.app/Info.plist'))['CFBundleShortVersionString']
    target = f'targets/spotify-{spotify}.json'
    if not (ROOT/'NativeDownloads'/target).is_file():
        raise SystemExit(f'No Pixie target for Spotify {spotify}: NativeDownloads/{target}')
    if not args.version:
        control = (ROOT/'control').read_text()
        eevee = next(line.split(':', 1)[1].strip() for line in control.splitlines() if line.startswith('Version:'))
        args.version = f'{eevee}+pixie.{spotify}'
    output = ROOT/'Outputs/DEBS'/args.version
    output.mkdir(parents=True, exist_ok=True)
    for scheme, label in [('rootless', 'rootless'), ('roothide', 'RootHide')]:
        theos = ROOT/'Outputs/BuildTools'/('theos-'+scheme)
        framework = theos/'lib/iphone'/scheme/'EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf'
        if not framework.is_file():
            raise SystemExit(f'Prepare Theos and EeveeSwiftProtobuf 1.29.0 first: {framework}')
        env = dict(os.environ, THEOS=str(theos), THEOS_PACKAGE_SCHEME=scheme,
                   PIXIE_JAILBREAK='1', PIXIE_SOURCE_IPA=str(ipa), PIXIE_TARGET=target,
                   REPO_SLUG='Glongq/EeveeSpotifyReincarnated', PACKAGE_VERSION=args.version)
        if args.swift_no_nested_sandbox:
            env['ADDITIONAL_SWIFTFLAGS'] = '-Xfrontend -disable-sandbox'
        with (output/(scheme+'.log')).open('w') as log:
            for command in (['/opt/homebrew/bin/gmake', 'clean'],
                            ['/opt/homebrew/bin/gmake', 'package', 'FINALPACKAGE=1']):
                print(f'{label}: {" ".join(command)}', flush=True)
                subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        built = ROOT/'packages'/f'com.eevee.spotify_{args.version}_{"iphoneos-arm64" if scheme == "rootless" else "iphoneos-arm64e"}.deb'
        package = output/f'EeveeSpotify-{args.version}-{label}.deb'
        shutil.copy2(built, package)
        build_dir = ROOT/'.theos'/('pixie-'+scheme)
        subprocess.run([sys.executable, 'NativeDownloads/tools/validate_jailbreak_deb.py', str(package),
                        '--scheme', scheme, '--build-dir', str(build_dir)], cwd=ROOT, check=True)
        validate_shader(package)
        retained = output/(label+'-companion')
        retained.mkdir(exist_ok=True)
        for name in ('JailbreakPlan.h', 'build.json'):
            shutil.copy2(build_dir/name, retained/name)
        print(f'{label}: validated {package}', flush=True)


if __name__ == '__main__':
    main()
