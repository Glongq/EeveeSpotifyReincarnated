"""Build the existing Pixie companion plus its guarded jailbreak bootstrap."""
import argparse
import hashlib
import json
import plistlib
import subprocess
from pathlib import Path
from zipfile import ZipFile

from companion_build import build_companion
from jailbreak_plan import make_plan, header
from pixie_target import ROOT, PROFILE, PROFILE_PATH, validate_sources
from export_release_materials import notices


def stage_eevee(path, stage_root):
    # Eevee itself is staged unchanged, as in build_eevee_9192.py; only the notices are added.
    destination = stage_root/'usr/share/doc/com.eevee.spotify/Pixie'
    destination.mkdir(parents=True, exist_ok=True)
    for name, data in notices().items():
        (destination/Path(name).name).write_bytes(data)


def plan_inputs():
    names = ['build_jailbreak.py', 'jailbreak_plan.py', 'patch_imports.py',
             'patch_native_restrictions.py', 'patch_key_request_mode.py',
             'patch_native_trace.py', 'patch_export.py', 'pixie_target.py']
    paths = [ROOT/'tools'/name for name in names] + [PROFILE_PATH]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def prepared_plan(directory):
    metadata = json.loads((directory/'plan.json').read_text())
    for key in ('spotify_version', 'spotify_build', 'uuid'):
        if metadata[key] != PROFILE[key]:
            raise ValueError('Prepared plan target differs: '+key)
    if metadata['generator_inputs_sha256'] != plan_inputs():
        raise ValueError('Prepared plan is stale; regenerate from the clean IPA')
    generated = (directory/'JailbreakPlan.h').read_text()
    if hashlib.sha256(generated.encode()).hexdigest() != metadata['header_sha256']:
        raise ValueError('Prepared plan header checksum differs')
    if not metadata['matches_ipa_native_patches']:
        raise ValueError('Prepared plan was not verified against the IPA patchers')
    return generated, metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument('--ipa', type=Path)
    source.add_argument('--plan-dir', type=Path)
    parser.add_argument('--export-plan', type=Path)
    parser.add_argument('--theos', type=Path)
    parser.add_argument('--scheme', choices=['rootless', 'roothide'])
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--stage-eevee', type=Path)
    parser.add_argument('--stage-root', type=Path)
    args = parser.parse_args()
    if args.stage_eevee:
        if not args.stage_root:
            parser.error('--stage-eevee requires --stage-root')
        stage_eevee(args.stage_eevee, args.stage_root)
        return
    if not (args.ipa or args.plan_dir):
        parser.error('Supply --ipa or --plan-dir')
    validate_sources()
    if args.ipa:
        with ZipFile(args.ipa) as archive:
            info = plistlib.loads(archive.read('Payload/Spotify.app/Info.plist'))
            if (info.get('CFBundleShortVersionString'), info.get('CFBundleVersion')) != (PROFILE['spotify_version'], PROFILE['spotify_build']):
                raise ValueError('Input IPA does not match the active Spotify profile')
            if any(name.endswith(('EeveeSpotify.dylib', 'SpotifyAudioProbe.dylib')) for name in archive.namelist()):
                raise ValueError('Supply the clean decrypted IPA, not an already patched IPA')
            executable = archive.read('Payload/Spotify.app/Spotify')
        plan, imports = make_plan(executable)
        generated = '#define SAP_JB_SPOTIFY_BUILD "' + PROFILE['spotify_build'] + '"\n' + header(plan, imports)
        metadata = {'spotify_version': PROFILE['spotify_version'], 'spotify_build': PROFILE['spotify_build'],
            'uuid': PROFILE['uuid'], 'native_ranges': len(plan), 'audio_import_slots': len(imports),
            'matches_ipa_native_patches': True,
            'source_ipa_sha256': hashlib.sha256(args.ipa.read_bytes()).hexdigest(),
            'header_sha256': hashlib.sha256(generated.encode()).hexdigest(),
            'generator_inputs_sha256': plan_inputs()}
    else:
        generated, metadata = prepared_plan(args.plan_dir)
    if args.export_plan:
        args.export_plan.mkdir(parents=True, exist_ok=True)
        (args.export_plan/'JailbreakPlan.h').write_text(generated)
        (args.export_plan/'plan.json').write_text(json.dumps(metadata, indent=2)+'\n')
        print('Exported verified native plan (no Spotify executable): '+str(args.export_plan))
        return
    if not all((args.theos, args.scheme, args.output_dir)):
        parser.error('Supply --theos, --scheme and --output-dir')
    work = args.output_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    (work/'JailbreakPlan.h').write_text(generated)
    jailbreak = ROOT/'jailbreak'
    theos = args.theos.resolve()
    library = work/'SpotifyAudioProbe.dylib'
    build_companion(library, work,
        extra_sources=[jailbreak/'JailbreakSupport.m'],
        extra_flags=['-DSAP_JAILBREAK=1', '-I'+str(jailbreak), '-I'+str(work)],
        link_flags=['-L'+str(theos/'vendor/lib/iphone'/args.scheme), '-weak-lsubstrate',
                    '-Wl,-rpath,@loader_path/../../Frameworks'],
        install_name='@loader_path/SpotifyAudioProbe.dylib')
    # Keep the same verified ad-hoc companion signature as the IPA builder.
    report = {'spotify_version': PROFILE['spotify_version'], 'spotify_build': PROFILE['spotify_build'],
        'uuid': PROFILE['uuid'], 'scheme': args.scheme, 'native_ranges': metadata['native_ranges'],
        'audio_import_slots': metadata['audio_import_slots'], 'matches_ipa_native_patches': True,
        'source_ipa_sha256': metadata['source_ipa_sha256'],
        'plan_input': 'clean_ipa' if args.ipa else 'prepared_verified_plan',
        'plan_header_sha256': metadata['header_sha256'],
        'companion_sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT.parent, text=True).strip(),
        'source_tree_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT.parent, text=True)),
        'theos_commit': subprocess.check_output(['git', '-C', str(theos), 'rev-parse', 'HEAD'], text=True).strip(),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
        'device_runtime_tested': False}
    paths = [ROOT.parent/'Makefile', *ROOT.rglob('*.h'), *ROOT.rglob('*.c'), *ROOT.rglob('*.m'),
             *ROOT.rglob('*.swift'), *ROOT.glob('tools/*.py'), *ROOT.glob('targets/*.json')]
    report['source_sha256_by_file'] = {str(p.relative_to(ROOT.parent)):hashlib.sha256(p.read_bytes()).hexdigest()
                                     for p in sorted(set(paths))}
    (work/'build.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
