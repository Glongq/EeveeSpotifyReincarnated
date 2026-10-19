"""Native settings fixture with both of Spotify's page protocol names.

Uses an already booted iPhone simulator. No Spotify installation is simulated:
this verifies UIKit integration, language selection, menu rows and geometry.
"""
from pathlib import Path
import json
import plistlib
import shutil
import subprocess
import time

root=Path(__file__).resolve().parents[1]
out=root/'build/ui-v4'
app=out/'SpotifySettingsPreview.app'
app.mkdir(parents=True,exist_ok=True)
def run(*args,check=True):
 p=subprocess.run([str(x) for x in args],cwd=root,check=check,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=45)
 return p.stdout.strip()
devices=json.loads(run('xcrun','simctl','list','devices','--json'))['devices']
booted=[d for ds in devices.values() for d in ds if d['state']=='Booted' and d.get('isAvailable') and 'iPhone' in d['name']]
assert booted,'Boot an iPhone simulator first'
udid=booted[0]['udid']
sdk=run('xcrun','--sdk','iphonesimulator','--show-sdk-path')
objects=[]
for src in ['src/DownloadSettingsUI.m','src/Diagnostics.m','src/Localization.m','tests/SettingsFixtureActions.m']:
 obj=out/(Path(src).stem+'.o');objects.append(obj)
 run('xcrun','clang','-c','-target','arm64-apple-ios27.0-simulator','-isysroot',sdk,'-fobjc-arc','-std=gnu11','-Isrc','-DSAP_UI_FIXTURE',src,'-o',obj)
run('xcrun','swiftc','-swift-version','5','-parse-as-library','-target','arm64-apple-ios27.0-simulator','-sdk',sdk,'-import-objc-header','src/AudioProbeUI.h','tests/SettingsFixture.swift',*objects,'-framework','UIKit','-framework','SwiftUI','-o',app/'SpotifySettingsPreview')
bundle='local.spotify.settingspreview.v4'
info={'CFBundleIdentifier':bundle,'CFBundleExecutable':'SpotifySettingsPreview','CFBundleName':'Settings Preview','CFBundleVersion':'24','CFBundleShortVersionString':'24','CFBundlePackageType':'APPL','CFBundleLocalizations':['ru','en'],'CFBundleDevelopmentRegion':'en','LSRequiresIPhoneOS':True,'UIDeviceFamily':[1],'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default','UISceneDelegateClassName':'SAPFixtureSceneDelegate'}]}},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait']}
(app/'Info.plist').write_bytes(plistlib.dumps(info))
run('codesign','--force','--sign','-','--timestamp=none',app)
run('xcrun','simctl','install',udid,app)
for language in ['ru','en']:
 run('xcrun','simctl','terminate',udid,bundle,check=False)
 container=Path(run('xcrun','simctl','get_app_container',udid,bundle,'data'))
 result=container/'Documents/result.log';result.unlink(missing_ok=True)
 print(run('xcrun','simctl','launch',udid,bundle,'-AppleLanguages','('+language+')'),flush=True)
 deadline=time.monotonic()+20
 while time.monotonic()<deadline:
  text=result.read_text() if result.exists() else ''
  if 'PASS: entry spacing, mini-player clearance, navigation and native pages rendered' in text:break
  time.sleep(.3)
 else:raise RuntimeError('Fixture did not complete: '+text)
 assert 'PASS: legacy and module-qualified native page protocols;' in text
 target=out/language;target.mkdir(exist_ok=True)
 for file in (container/'Documents').iterdir():
  if file.suffix in ['.log','.png']:shutil.copy2(file,target/file.name)
 print(language+': '+text,flush=True)
print('PASS: RU/EN native settings UI; modern/legacy page protocol assertion; no WAV; switch; navigation; mini-player clearance')
