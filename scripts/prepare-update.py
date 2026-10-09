#!/usr/bin/env python3
"""Prepare an appcast locally. Never uploads or changes the live update channel."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from urllib.parse import urlparse

parser = argparse.ArgumentParser()
parser.add_argument('--archive', type=Path, required=True)
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--base-url', default='https://codex-cub.edgewavelabs.ai/downloads/')
parser.add_argument('--notes', default='新增检查更新入口，支持下载、校验、安装并重启。 / Adds secure in-app updates.')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
sparkle = Path(subprocess.check_output([str(root / 'scripts/sparkle.sh')], text=True).strip())
parsed = urlparse(args.base_url)
if parsed.scheme != 'https' and not (parsed.scheme == 'http' and parsed.hostname in ('127.0.0.1', 'localhost')):
    raise SystemExit('Update downloads must use HTTPS (except loopback tests)')
info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
if info['CFBundleIdentifier'] != 'local.alsc.codex-usage':
    raise SystemExit('Refusing to prepare an update for a different app')
with zipfile.ZipFile(args.archive) as archive:
    packaged = plistlib.loads(archive.read('CodexUsage.app/Contents/Info.plist'))
for field in ('CFBundleIdentifier', 'CFBundleVersion', 'CFBundleShortVersionString', 'SUPublicEDKey'):
    if packaged.get(field) != info.get(field):
        raise SystemExit('Archive/app metadata mismatch: ' + field)
public_key = subprocess.check_output([str(sparkle / 'bin/generate_keys'), '--account', 'codex-usage-menubar', '-p'], text=True).strip()
if info.get('SUPublicEDKey') != public_key:
    raise SystemExit('Embedded update key does not match the signing account')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(args.app)], check=True)
result = subprocess.check_output([str(sparkle / 'bin/sign_update'), '--account', 'codex-usage-menubar', str(args.archive)], text=True)
signature = re.search(r'sparkle:edSignature="([A-Za-z0-9+/=]+)"', result)
if not signature:
    raise SystemExit('No EdDSA signature returned')
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
rss = ET.Element('rss', {'version': '2.0'})
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = 'Codex Cub Updates'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = 'Codex Cub ' + info['CFBundleShortVersionString']
ET.SubElement(item, f'{{{ns}}}version').text = info['CFBundleVersion']
ET.SubElement(item, f'{{{ns}}}shortVersionString').text = info['CFBundleShortVersionString']
ET.SubElement(item, f'{{{ns}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
ET.SubElement(item, 'description').text = args.notes
ET.SubElement(item, 'enclosure', {
    'url': args.base_url.rstrip('/') + '/' + args.archive.name,
    'length': str(args.archive.stat().st_size),
    'type': 'application/octet-stream',
    f'{{{ns}}}edSignature': signature.group(1),
})
ET.indent(rss)
args.output.parent.mkdir(parents=True, exist_ok=True)
ET.ElementTree(rss).write(args.output, encoding='utf-8', xml_declaration=True)
subprocess.run([str(sparkle / 'bin/sign_update'), '--account', 'codex-usage-menubar', str(args.output)], check=True)
args.archive.with_suffix(args.archive.suffix + '.sha256').write_text(hashlib.sha256(args.archive.read_bytes()).hexdigest() + '  ' + args.archive.name + '\n')
print('Prepared:', args.output)
