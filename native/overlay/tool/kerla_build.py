#!/usr/bin/env python3
"""Check and build a VPNkerla pilot on the target platform's own toolchain."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.parse

parser = argparse.ArgumentParser()
parser.add_argument('--platform', choices=['android', 'windows', 'linux', 'macos'], required=True)
parser.add_argument('--api-url', default='')
parser.add_argument('--check-only', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
os.chdir(root)
env = dict(os.environ, CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', TAR_OPTIONS='--no-same-owner')
origin = urllib.parse.urlsplit(args.api_url)
if args.api_url and (origin.scheme != 'https' or not origin.hostname or origin.username or origin.password or origin.query or origin.fragment or origin.path not in ['', '/']):
    raise SystemExit('API origin must be an HTTPS URL without credentials, query or fragment.')
if not args.check_only and args.platform != 'android':
    required_host = {'windows': 'win32', 'linux': 'linux', 'macos': 'darwin'}[args.platform]
    if sys.platform != required_host:
        raise SystemExit('Build this desktop target on its own operating system.')

def run(*command):
    executable = shutil.which(command[0])
    if not executable:
        raise SystemExit('Required tool is missing: ' + command[0])
    subprocess.run([executable, *command[1:]], env=env, check=True)

run('flutter', '--suppress-analytics', 'pub', 'get')
pubspec = root / 'pubspec.yaml'
original = pubspec.read_text()
if original.count('build_assets: true') != 2:
    raise SystemExit('Native build hooks must both be enabled in the source.')
try:
    pubspec.write_text(original.replace('build_assets: true', 'build_assets: false'))
    run('dart', 'run', 'intl_utils:generate')
    run('flutter', 'analyze', '--no-fatal-infos')
    run('flutter', 'test', 'test/kerla/', '--reporter', 'expanded')
finally:
    pubspec.write_text(original)
if args.check_only:
    raise SystemExit(0)

flags = ['--dart-define=KERLA_API_URL=' + args.api_url]
if args.platform == 'android':
    run('flutter', 'build', 'apk', '--debug', '--target-platform', 'android-arm64', *flags)
    source = root / 'build/app/outputs/flutter-apk/app-debug.apk'
else:
    run('flutter', 'build', args.platform, '--release', *flags)
    candidates = {
        'windows': list(root.glob('build/windows/*/runner/Release')),
        'linux': list(root.glob('build/linux/*/release/bundle')),
        'macos': list(root.glob('build/macos/Build/Products/Release/*.app')),
    }[args.platform]
    if len(candidates) != 1:
        raise SystemExit('Expected exactly one complete platform bundle.')
    source = candidates[0]

output = root / 'kerla-dist'
output.mkdir(exist_ok=True)
stem = 'VPNkerla-' + args.platform + '-pilot'
if source.is_dir():
    artifact = Path(shutil.make_archive(str(output / stem), 'zip', source.parent, source.name))
else:
    artifact = output / (stem + source.suffix)
    shutil.copy2(source, artifact)
digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
(output / (artifact.name + '.sha256')).write_text(digest + '  ' + artifact.name + '\n')
(output / 'BUILD-STATUS.json').write_text(json.dumps({
    'product': 'VPNkerla', 'channel': 'pilot', 'platform': args.platform,
    'apiConfigured': bool(args.api_url), 'deviceTested': False,
    'storeSigned': False, 'sha256': digest,
}, indent=2) + '\n')
print('Pilot artifact:', artifact)
