"""Prepare an injected native Eevee IPA BEFORE the installation tool signs it.

Copying a jailbreak DEB's libraries into an IPA is not enough on stock iOS.
This step applies/verifies the guarded main-executable patches without runtime
executable writes. It never overwrites the input. No diagnostic UI is added.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import plistlib
import subprocess
import tempfile
import zipfile
from prepare_executable import prepare


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('input', type=Path)
    p.add_argument('output', type=Path, nargs='?', default=Path('Spotify-9.1.88-Eevee+Sprite.ipa'))
    p.add_argument('--core', type=Path, help='Replace EeveeSpotify.dylib with a newly built rootless native core')
    p.add_argument('--if-native', action='store_true', help='Pass upstream non-native builds through unchanged')
    a = p.parse_args()
    if a.input.resolve() == a.output.resolve():
        p.error('Output must differ from the input IPA')
    with zipfile.ZipFile(a.input) as z, tempfile.TemporaryDirectory(prefix='eevee-native-ipa-') as tmp:
        infos = [n for n in z.namelist() if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
        if len(infos) != 1:
            raise ValueError('Expected one main app')
        info_name = infos[0]
        app = info_name.rsplit('/', 1)[0]
        core_name = f'{app}/Frameworks/EeveeSpotify.dylib'
        core = a.core.read_bytes() if a.core else z.read(core_name)
        native = b'EeveeNativeDownloadsWillHandleDownloads' in core
        if not native and not a.if_native:
            raise ValueError('Use a unified native-download core, not an upstream-only Eevee library')
        replacements = {}
        report = {'native_core': native, 'diagnostic_ui': False, 'device_tested': False,
                  'input': a.input.name, 'input_sha256': hashlib.sha256(a.input.read_bytes()).hexdigest()}
        if native:
            if b'Sprite Download Manager' in core:
                report.update({'manager_name': 'Sprite Download Manager', 'manager_version': '7.3', 'manager_language': 'en'})
            if b'@loader_path/.jbroot/usr/lib/libroothide.dylib' in core:
                raise ValueError('RootHide is not a sideload core; use rootless')
            if any(n.endswith('/SpotifyAudioProbe.dylib') for n in z.namelist()):
                raise ValueError('Do not combine two native backends')
            for dependency in ('Orion.framework/Orion', 'EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf'):
                if f'{app}/Frameworks/{dependency}' not in z.namelist():
                    raise ValueError(f'Missing dependency: {dependency}')
            info = plistlib.loads(z.read(info_name))
            if info.get('CFBundleShortVersionString') != '9.1.88':
                raise ValueError('Native downloads require the guarded Spotify 9.1.88 image')
            exe = f'{app}/{info["CFBundleExecutable"]}'
            binary, patches = prepare(z.read(exe))
            info['MinimumOSVersion'] = '16.1'
            replacements[info_name] = plistlib.dumps(info, fmt=plistlib.FMT_BINARY)
            for name, data in ((exe, binary), (core_name, core)):
                staged = Path(tmp) / name.rsplit('/', 1)[1]
                staged.write_bytes(data)
                subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(staged)], check=True)
                subprocess.run(['codesign', '--verify', '--strict', str(staged)], check=True)
                subprocess.run(['xcrun', 'dyld_info', '-validate_only', str(staged)], check=True)
                replacements[name] = staged.read_bytes()
            report.update({'static_patches': patches, 'minimum_ios': '16.1',
                           'core_sha256': hashlib.sha256(replacements[core_name]).hexdigest(),
                           'requires_user_signing': True})
        a.output.parent.mkdir(parents=True, exist_ok=True)
        # Finish and verify in a temporary file before exposing a build artifact.
        pending = Path(tmp) / 'prepared.ipa'
        with zipfile.ZipFile(pending, 'w', allowZip64=True) as out:
            for item in z.infolist():
                out.writestr(copy.copy(item), replacements.get(item.filename, z.read(item.filename)), compresslevel=1)
        with zipfile.ZipFile(pending) as result:
            if result.testzip() is not None:
                raise ValueError('Archive integrity check failed')
            if native:
                checked = result.read(exe)
                if prepare(checked)[0] != checked:
                    raise ValueError('Final archive is missing executable patches')
            changed = {n for n in z.namelist() if z.read(n) != result.read(n)}
            if not changed <= replacements.keys():
                raise ValueError(f'Unexpected archive changes: {changed}')
        import shutil
        shutil.copyfile(pending, a.output)
    report['output_sha256'] = hashlib.sha256(a.output.read_bytes()).hexdigest()
    report['changed_entries'] = sorted(changed)
    a.output.with_suffix('.build.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: verified static native patches; no runtime executable writes required' if native else 'Upstream-only core: no native-download changes applied')


if __name__ == '__main__':
    main()
