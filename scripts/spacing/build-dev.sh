#!/usr/bin/env bash
# Build an isolated, ad-hoc signed development bundle without installing it.
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
sdk="$(xcrun --show-sdk-path)"
app="$root/build/spacing/SquirrelSpacingDev.app"
for file in lib/librime.1.dylib Frameworks/Sparkle.framework/Sparkle librime/src/rime_api_stdbool.h data/plum/default.yaml; do
  [[ -e "$file" ]] || { echo "Missing $file; initialize librime and run action-install.sh first" >&2; exit 1; }
done
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks" "$app/Contents/SharedSupport"
xcrun swiftc -parse-as-library -enable-bare-slash-regex -module-name Squirrel \
  -import-objc-header sources/Squirrel-Bridging-Header.h -I librime/src -I librime/include \
  -I "$sdk/System/Library/Frameworks/Tk.framework/Headers" -F Frameworks \
  lib/librime.1.dylib -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  sources/*.swift -o "$app/Contents/MacOS/Squirrel"
cp resources/rime.pdf "$app/Contents/Resources/"
cp lib/librime.1.dylib "$app/Contents/Frameworks/"
ditto lib/rime-plugins "$app/Contents/Frameworks/rime-plugins"
ditto Frameworks/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"
cp bin/rime_deployer bin/rime_dict_manager "$app/Contents/MacOS/"
cp data/plum/* "$app/Contents/SharedSupport/"
cp data/squirrel.yaml "$app/Contents/SharedSupport/"
ditto data/opencc "$app/Contents/SharedSupport/opencc"
python3 - "$app" <<'PY'
from pathlib import Path
import json,plistlib,sys,subprocess
app=Path(sys.argv[1])
p=plistlib.loads(Path('resources/Info.plist').read_bytes())
old='im.rime.inputmethod.Squirrel';new=old+'.SpacingDev'
def transform(v):
    if isinstance(v,str):return v.replace(old,new)
    if isinstance(v,list):return [transform(x) for x in v]
    if isinstance(v,dict):return {transform(k):transform(val) for k,val in v.items()}
    return v
p=transform(p)
p.update(CFBundleIdentifier=new,CFBundleName='Squirrel Spacing Dev',CFBundleDisplayName='鼠须管空格测试版',
         CFBundleVersion='1.1.2.1',InputMethodConnectionName='Squirrel_SpacingDev_Connection',
         SquirrelSpacingDevelopment=True,SUEnableAutomaticChecks=False)
p.pop('SUFeedURL',None);p.pop('SUPublicEDKey',None)
p['SpacingSourceRevision']=subprocess.check_output(['git','describe','--always','--dirty'],text=True).strip()
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(p))
catalog=json.loads(Path('resources/InfoPlist.xcstrings').read_text())
catalog['strings']={k.replace(old,new):v for k,v in catalog['strings'].items()}
for key,entry in catalog['strings'].items():
    if key in ('CFBundleName','CFBundleDisplayName') or key.startswith(new):
        for language,translation in entry.get('localizations',{}).items():
            suffix={'zh-Hans':'空格测试版','zh-Hant':'空格測試版'}.get(language,' Spacing Dev')
            translation['stringUnit']['value']+=suffix
catalog_path=app.parent/'InfoPlist.xcstrings'
catalog_path.write_text(json.dumps(catalog,ensure_ascii=False))
for source in (catalog_path,Path('resources/Localizable.xcstrings')):
    subprocess.run(['xcrun','xcstringstool','compile',str(source),
                    '--output-directory',str(app/'Contents/Resources')],check=True)
PY
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
printf 'Built (not installed): %s\nUser data: ~/Library/RimeSpacingDev\n' "$app"
