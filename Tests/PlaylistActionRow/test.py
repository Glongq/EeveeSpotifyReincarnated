from pathlib import Path
import argparse,json,plistlib,shutil,subprocess,time
from datetime import datetime
parser=argparse.ArgumentParser(description="Compile the action-row fixture; runtime launch is explicit opt-in")
mode=parser.add_mutually_exclusive_group()
mode.add_argument("--compile-only",action="store_true")
mode.add_argument("--run",action="store_true")
parser.add_argument("--output-dir",type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
out=(args.output_dir or root/'outputs'/datetime.now().strftime('action-row-compile-%Y%m%d-%H%M%S-%f')).resolve()
if out.exists() and any(out.iterdir()):raise SystemExit('Choose a fresh output directory')
app=out/'ActionRowFixture.app';app.mkdir(parents=True,exist_ok=True)
def run(*args,check=True):
 p=subprocess.run([str(a) for a in args],cwd=root,capture_output=True,text=True,timeout=60)
 if check and p.returncode:raise RuntimeError(p.stdout+p.stderr)
 return p.stdout.strip()
sdk=run('xcrun','--sdk','iphonesimulator','--show-sdk-path')
version=run('xcrun','--sdk','iphonesimulator','--show-sdk-version')
target=f'arm64-apple-ios{version}-simulator'
run('xcrun','clang','-c','-target',target,'-isysroot',sdk,'-fobjc-arc','-ISources/EeveeSpotifyC/include','Sources/EeveeSpotifyC/EncoreBridge.m','-o',out/'bridge.o')
objects=[out/'bridge.o']
for source in ['Sources/EeveeSpotifyC/PixieArtistDownloads.m','Tests/PlaylistActionRow/FollowFixtureBridge.m']:
 obj=out/(Path(source).stem+'.o');objects.append(obj)
 run('xcrun','clang','-c','-target',target,'-isysroot',sdk,'-fobjc-arc','-ISources/EeveeSpotifyC/include',source,'-o',obj)
run('xcrun','swiftc','-swift-version','5','-parse-as-library','-target',target,'-sdk',sdk,'-ISources/EeveeSpotifyC/include','Sources/EeveeSpotify/LiquidGlass/GlassKit.swift','Sources/EeveeSpotify/Pages/PageLookup.swift','Sources/EeveeSpotify/Pages/PlaylistDownloadControl.swift','Sources/EeveeSpotify/Pages/PlaylistActionRow.swift','Sources/EeveeSpotify/Pages/PixieArtistIdentity.swift','Tests/PlaylistActionRow/Fixture.swift',*objects,'-framework','UIKit','-o',app/'ActionRowFixture')
bundle='local.spotify.actionrow.v7';(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':bundle,'CFBundleExecutable':'ActionRowFixture','CFBundleName':'Action Row','CFBundlePackageType':'APPL','CFBundleVersion':'7','CFBundleShortVersionString':'7','LSRequiresIPhoneOS':True,'UIDeviceFamily':[1],'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default','UISceneDelegateClassName':'ActionRowSceneDelegate'}]}}}))
run('codesign','--force','--sign','-','--timestamp=none',app)
if not args.run:
 print('PASS: action-row fixture compile/link; no simctl query, install or launch; runtime not tested')
 (out/'results.json').write_text(json.dumps({'compiled':True,'runtime_tested':False,'follow_provider':'fixture-unavailable','app':str(app)},indent=2)+'\n')
 raise SystemExit(0)
devices=json.loads(run('xcrun','simctl','list','devices','--json'))['devices'];udid=next(d['udid'] for ds in devices.values() for d in ds if d['state']=='Booted' and 'iPhone' in d['name'])
run('xcrun','simctl','terminate',udid,bundle,check=False);run('xcrun','simctl','install',udid,app)
container=Path(run('xcrun','simctl','get_app_container',udid,bundle,'data'));log=container/'Documents/result.log';log.unlink(missing_ok=True)
print(run('xcrun','simctl','launch',udid,bundle),flush=True)
for i in range(60):
 text=log.read_text() if log.exists() else ''
 if 'PASS: production PlaylistActionRow UI fixture complete' in text:break
 time.sleep(.3)
else:raise RuntimeError('UI fixture failed: '+text)
print(text);shutil.copy2(log,out/'result.log');shutil.copy2(container/'Documents/action-row.png',out/'action-row.png')
