#!/usr/bin/env python3
"""Build one native/cross helper and copy it into the addon. Never contacts SFXMint."""
import argparse
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
TARGETS = {
    'aarch64-apple-darwin': 'macos-arm64',
    'x86_64-apple-darwin': 'macos-x86_64',
    'x86_64-pc-windows-gnu': 'windows-x86_64.exe',
    'x86_64-pc-windows-msvc': 'windows-x86_64.exe',
    'x86_64-unknown-linux-gnu': 'linux-x86_64',
    'aarch64-unknown-linux-gnu': 'linux-arm64',
}
p = argparse.ArgumentParser()
p.add_argument('target', choices=TARGETS)
p.add_argument('--zig', action='store_true', help='Use cargo-zigbuild (cross builds; Zig must be on PATH).')
a = p.parse_args()
triple = a.target + ('.2.28' if a.zig and 'linux' in a.target else '')
subprocess.run(['cargo', 'zigbuild' if a.zig else 'build', '--release', '--locked', '--manifest-path', str(ROOT/'credential-helper/Cargo.toml'), '--target', triple], check=True)
source = ROOT/'credential-helper/target'/a.target/'release'/('sfxmint-credentials.exe' if 'windows' in a.target else 'sfxmint-credentials')
dest = ROOT/'addons/sfxmint/bin'/('sfxmint-credentials-'+TARGETS[a.target])
shutil.copy2(source, dest)
dest.chmod(0o755)
print(dest)
