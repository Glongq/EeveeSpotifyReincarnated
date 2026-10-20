"""Verify package contents and Mach-O load dependencies; no device claims."""
from pathlib import Path
import json, plistlib, re, subprocess, sys, tempfile
package=Path(sys.argv[1]).resolve();scheme=sys.argv[2]
assert scheme in ('rootless','roothide')
def run(*args): return subprocess.check_output([str(a) for a in args],text=True)
arch=run('dpkg-deb','-f',package,'Architecture').strip()
assert arch=={'rootless':'iphoneos-arm64','roothide':'iphoneos-arm64e'}[scheme],arch
assert 'firmware (>= 16.1)' in run('dpkg-deb','-f',package,'Depends')
assert 'dev.theos.orion' in run('dpkg-deb','-f',package,'Depends')
with tempfile.TemporaryDirectory(prefix='eevee-v7-deb-') as folder:
    run('dpkg-deb','-x',package,folder)
    root=Path(folder);dylibs=list(root.rglob('EeveeSpotify.dylib'))
    assert len(dylibs)==1
    dylib=dylibs[0]
    relative=str(dylib.relative_to(root))
    assert relative==('var/jb/' if scheme=='rootless' else '')+'Library/MobileSubstrate/DynamicLibraries/EeveeSpotify.dylib',relative
    filter=plistlib.loads(dylib.with_suffix('.plist').read_bytes())
    assert filter['Filter']['Bundles']==['com.spotify.client']
    assert len(list(root.rglob('com.eevee.spotify/COPYING')))==1
    assert len(list(root.rglob('com.eevee.spotify/SwiftProtobuf-LICENSE.txt')))==1
    assert len(list(root.rglob('KaraokeBackgroundShader.metallib')))==1
    assert len(list(root.rglob('EeveeSpotify.bundle/Info.plist')))==1
    frameworks=list(root.rglob('EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf'))
    assert len(frameworks)==1
    text=run('strings',dylib)
    for marker in ('v7 jailbreak adapter','Track downloads','SAPDownloadsSettings', 'offline-quota'):
        assert marker in text,marker
    symbols=run('nm','-g',dylib)
    for symbol in ('_EeveeNativeDownloadsIsReady','_SpotifyAudioProbeInitialize','_AudioUnitSetProperty','_AudioOutputUnitStart'):
        assert re.search(r'\bT '+symbol+r'$',symbols,re.M),symbol
    dependencies=run('otool','-L',dylib)
    assert 'EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf' in dependencies
    assert 'Orion.framework/Orion' in dependencies
    assert 'SpotifyAudioProbe.dylib' not in dependencies
    assert '/Users/' not in dependencies
    assert ('@loader_path/.jbroot/' if scheme=='roothide' else '/var/jb/') in dependencies
    builds=[]
    for binary in (dylib,frameworks[0]):
        build=run('xcrun','vtool','-show-build',binary)
        versions=re.findall(r'\bminos (\d+)\.(\d+)',build)
        assert versions and all(tuple(map(int,v))<=(16,1) for v in versions),build
        run('codesign','--verify',binary)
        builds.append({'binary':str(binary.relative_to(root)),'minimum_ios':versions})
    report={'scheme':scheme,'architecture':arch,'dylib':relative,'macho_builds':builds,
            'device_tested':False,'dependencies':dependencies.splitlines()[1:]}
    package.with_suffix('.verification.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: package layout, filter, downloader symbols, dependencies, minimum iOS and signatures')
