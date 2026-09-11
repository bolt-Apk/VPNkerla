#!/usr/bin/env python3
"""Reconstruct the pinned GPL client. No credentials or release signing keys."""
import json
import hashlib
import pathlib
import shutil
import subprocess
import sys

base = pathlib.Path(__file__).resolve().parent
pin = json.loads((base / 'upstream.json').read_text())
target = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'vpnkerla-client').resolve()
if target.exists():
    raise SystemExit('Choose a new, empty destination path.')

def git(*args):
    subprocess.run(['git', '-C', str(target), *args], check=True)

subprocess.run(['git', 'clone', '--no-checkout', pin['url'], str(target)], check=True)
git('checkout', '--detach', pin['commit'])
git('config', 'submodule.core/Clash.Meta.url', 'https://github.com/chen08209/Clash.Meta.git')
git('submodule', 'update', '--init', '--recursive')
actual = subprocess.check_output(['git', '-C', str(target / 'core/Clash.Meta'), 'rev-parse', 'HEAD'], text=True).strip()
if actual != pin['coreCommit']:
    raise SystemExit('Core commit mismatch: do not build.')
git('apply', '--check', str(base / 'upstream.patch'))
git('apply', str(base / 'upstream.patch'))
(target / '.github/workflows/build.yaml').unlink(missing_ok=True)
shutil.copytree(base / 'overlay', target, dirs_exist_ok=True)
if hashlib.sha256((target / 'pubspec.lock').read_bytes()).hexdigest() != pin['pubspecLockSha256']:
    raise SystemExit('Dependency lock mismatch: do not build.')
print('VPNkerla source prepared:', target)
