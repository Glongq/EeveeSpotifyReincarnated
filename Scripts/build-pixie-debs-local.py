#!/usr/bin/env python3
"""Build and validate both Pixie DEBs using this project's prepared toolchains."""
import argparse
import io
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tarfile

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
    parser.add_argument('--version', default='7.5.0+pixie.deb2')
    parser.add_argument('--swift-no-nested-sandbox', action='store_true',
                        help='Run Xcode macro subprocesses inside the existing outer sandbox')
    parser.add_argument('--metal-toolchain', type=Path,
                        help='Use an installed Metal.xctoolchain directly when Xcode discovery is unavailable')
    args = parser.parse_args()
    ipa = args.ipa.resolve(strict=True)
    output = ROOT/'Outputs/DEBS'/args.version
    output.mkdir(parents=True, exist_ok=True)
    for scheme, label in [('rootless', 'rootless'), ('roothide', 'RootHide')]:
        theos = ROOT/'Outputs/BuildTools'/('theos-'+scheme)
        framework = theos/'lib/iphone'/scheme/'EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf'
        if not framework.is_file():
            raise SystemExit(f'Prepare Theos and EeveeSwiftProtobuf 1.29.0 first: {framework}')
        env = dict(os.environ, THEOS=str(theos), THEOS_PACKAGE_SCHEME=scheme,
                   PIXIE_JAILBREAK='1', PIXIE_SOURCE_IPA=str(ipa),
                   REPO_SLUG='Glongq/EeveeSpotifyReincarnated', PACKAGE_VERSION=args.version)
        if args.swift_no_nested_sandbox:
            env['ADDITIONAL_SWIFTFLAGS'] = '-Xfrontend -disable-sandbox'
        if args.metal_toolchain:
            for variable, tool in [('METAL', 'metal'), ('METALLIB', 'metallib')]:
                # Preserve the executable's alias: resolving metallib to air-lld
                # changes its default link mode and can emit an empty library.
                path = args.metal_toolchain.absolute()/'usr/bin'/tool
                if not path.is_file():
                    raise SystemExit(f'Metal tool unavailable: {path}')
                env[variable] = shlex.join(['xcrun', '-sdk', 'iphoneos', str(path)])
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
