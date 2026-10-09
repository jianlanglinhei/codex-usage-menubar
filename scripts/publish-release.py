#!/usr/bin/env python3
"""Verify a notarized archive, prepare checksums; publish only with an explicit flag."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--version', required=True)
parser.add_argument('--notes', type=Path)
parser.add_argument('--target', help='Reviewed Git commit or branch for the release tag')
parser.add_argument('--publish', action='store_true', help='Public GitHub release; obtain release approval first')
parser.add_argument('--latest', action='store_true')
args = parser.parse_args()
if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
    parser.error('Expected a semantic version such as 1.0.7')
root = Path(__file__).resolve().parent.parent
folder = root / 'build/releases' / args.version
archive = folder / f'CodexUsage-{args.version}-macos-arm64.zip'
with tempfile.TemporaryDirectory(prefix='codex-cub-release-') as temporary:
    subprocess.run(['ditto', '-x', '-k', str(archive), temporary], check=True)
    app = Path(temporary) / 'CodexUsage.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'local.alsc.codex-usage' or info.get('CFBundleShortVersionString') != args.version:
        raise SystemExit('Archive identity/version mismatch')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    details = subprocess.run(['codesign', '-dv', '--verbose=4', str(app)], capture_output=True, text=True, check=True).stderr
    if 'TeamIdentifier=8UPDG7X2WM' not in details or 'Authority=Developer ID Application:' not in details:
        raise SystemExit('Archive is not signed by the expected Developer ID')
    subprocess.run(['xcrun', 'stapler', 'validate', str(app)], check=True)
    subprocess.run(['spctl', '--assess', '--type', 'execute', str(app)], check=True)
checksum = hashlib.sha256(archive.read_bytes()).hexdigest() + '  ' + archive.name + '\n'
for name in ['SHA256SUMS', archive.name + '.sha256']:
    (folder / name).write_text(checksum)
print(json.dumps({'version': args.version, 'archive': str(archive), 'sha256': checksum.split()[0], 'verified': True}))
if args.publish:
    if not args.target or not args.notes or not args.notes.is_file():
        parser.error('--publish requires --target and an existing --notes file')
    # Do not overwrite an existing release or asset; gh create fails for duplicate tags/releases.
    subprocess.run(['gh', 'release', 'create', 'v' + args.version, '--repo', 'jianlanglinhei/codex-usage-menubar',
                    '--target', args.target, '--title', 'Codex Cub v' + args.version,
                    '--notes-file', str(args.notes), '--latest=' + str(args.latest).lower(),
                    str(archive), str(folder / 'SHA256SUMS'), str(folder / (archive.name + '.sha256'))], check=True)
else:
    print('Prepared locally. Nothing was published. Use --publish after release approval.')
