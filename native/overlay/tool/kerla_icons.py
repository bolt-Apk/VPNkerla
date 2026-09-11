#!/usr/bin/env python3
"""Render the existing VPNkerla SVG mark into platform icon formats."""
from io import BytesIO
from pathlib import Path
import cairosvg
from PIL import Image

root = Path(__file__).resolve().parents[1]
svg = (root / 'assets_source/images/vpnkerla.svg').read_bytes()

def render(size):
    return Image.open(BytesIO(cairosvg.svg2png(bytestring=svg, output_width=size, output_height=size))).convert('RGBA')

targets = [root / 'assets/images/icon.png', root / 'android/app/src/main/ic_launcher-playstore.png']
targets += list((root / 'android/app/src/main/res').glob('mipmap-*/ic_launcher*.webp'))
targets += list((root / 'macos/Runner/Assets.xcassets/AppIcon.appiconset').glob('*.png'))
for target in targets:
    if not target.exists():
        continue
    with Image.open(target) as original:
        size = original.size
    if size[0] != size[1]:
        raise SystemExit('Unexpected non-square icon: ' + str(target))
    render(size[0]).save(target)
render(256).save(root / 'windows/runner/resources/app_icon.ico', sizes=[(s, s) for s in [16, 24, 32, 48, 64, 128, 256]])
vector = '''<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <group android:translateX="22" android:translateY="22">
        <path android:pathData="M37,12L17,35H32L27,52L48,25H34Z" android:fillColor="#192310"/>
    </group>
</vector>
'''
res = root / 'android/app/src/main/res'
for name in ['ic_launcher_foreground.xml', 'ic_launcher_foreground_tv.xml']:
    (res / 'drawable' / name).write_text(vector)
(res / 'values/ic_launcher_background.xml').write_text('<resources><color name="ic_launcher_background">#C8F76B</color></resources>\n')
