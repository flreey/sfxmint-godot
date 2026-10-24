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

def put(z, src, name):
    info = ZipInfo(name, (2026, 10, 23, 0, 0, 0))
    info.compress_type = ZIP_DEFLATED
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    data = src.read_bytes()
    if name == "project.godot":
        data = data.replace(b'"4.7"', b'"4.6"')
    z.writestr(info, data)

# Asset Store downloads must not bundle precompiled programs, even when helpers
# have been built locally. Ship only the addon's source, notices and logo.
files = [(p, p.relative_to(ROOT).as_posix()) for p in sorted((ROOT/'addons/sfxmint').rglob('*')) if p.is_file() and 'bin' not in p.relative_to(ROOT/'addons/sfxmint').parts and p.suffix in ['.gd', '.uid', '.cfg', '.md', '.txt', '.png']]
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
