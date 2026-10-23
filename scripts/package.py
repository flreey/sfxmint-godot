#!/usr/bin/env python3
"""Create reproducible local installation ZIPs from an explicit allowlist."""
import hashlib
import json
import configparser
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'dist'
config = configparser.ConfigParser()
config.read(ROOT/'addons/sfxmint/plugin.cfg')
VERSION = config['plugin']['version'].strip('"')
REQUIRED = ['macos-arm64', 'macos-x86_64', 'windows-x86_64.exe', 'linux-x86_64', 'linux-arm64']

def put(z, src, name):
    info = ZipInfo(name, (2026, 10, 23, 0, 0, 0))
    info.compress_type = ZIP_DEFLATED
    info.create_system = 3
    mode = 0o755 if src.name.startswith('sfxmint-credentials-') else 0o644
    info.external_attr = (0o100000 | mode) << 16
    data = src.read_bytes()
    if name == "project.godot":
        data = data.replace(b'"4.7"', b'"4.6"')
    z.writestr(info, data)

files = [(p, p.relative_to(ROOT).as_posix()) for p in sorted((ROOT/'addons/sfxmint').rglob('*')) if p.is_file() and (p.suffix in ['.gd', '.uid', '.cfg', '.md', '.txt', '.png'] or p.name == '.gdignore' or p.name.startswith('sfxmint-credentials-'))]
for suffix in REQUIRED:
    binary = ROOT/'addons/sfxmint/bin'/('sfxmint-credentials-'+suffix)
    if not binary.is_file():
        raise SystemExit(f'Missing required binary: {binary.name}. Build it before packaging.')
for name in ['README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.txt', 'addons/sfxmint/README.md']:
    if not (ROOT/name).is_file():
        raise SystemExit(f'Missing documentation: {name}')
OUT.mkdir(exist_ok=True)
outputs = []
for kind in ['plugin', 'example']:
    path = OUT/f'sfxmint-godot-{VERSION}-{kind}.zip'
    with ZipFile(path, 'w') as z:
        for source, name in files:
            put(z, source, name)
        if kind == 'example':
            for name in ['README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.txt']:
                put(z, ROOT/name, name)
            put(z, ROOT/'project.godot', 'project.godot')
            put(z, ROOT/'export_presets.cfg', 'export_presets.cfg')
            for source in sorted((ROOT/'example').glob('*')):
                if source.suffix in ['.gd', '.tscn', '.uid']:
                    put(z, source, 'example/'+source.name)
            # Only the documented, redistributable demo sound; never arbitrary lab imports.
            for source in sorted((ROOT/'example/audio').glob('*')):
                if source.suffix in ['.wav', '.json', '.md']:
                    put(z, source, 'audio/sfxmint/'+source.name)
    with ZipFile(path) as z:
        names = z.namelist()
        assert not any('/.godot/' in n or '.env' in n or 'tasks-' in n for n in names)
        assert not any(b'sfx_live_' + b'1'*40 in z.read(n) for n in names)
    outputs.append({'file':path.name,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(OUT/'SHA256SUMS').write_text(''.join(f'{v["sha256"]}  {v["file"]}\n' for v in outputs))
print(json.dumps(outputs, indent=2))
