#!/usr/bin/env python3
"""Check the actual delivered archives in a clean project, without production access."""
import argparse
import configparser
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--godot', required=True)
a = p.parse_args()
env = dict(os.environ, SFXMINT_TEST_ORIGIN='http://127.0.0.1:8797')
config = configparser.ConfigParser()
config.read(ROOT/'addons/sfxmint/plugin.cfg')
version = config['plugin']['version'].strip('"')
with zipfile.ZipFile(ROOT/f'dist/sfxmint-godot-{version}-plugin.zip') as z:
    assert 'addons/sfxmint/plugin.cfg' in z.namelist()
    assert 'addons/sfxmint/README.md' in z.namelist()
    assert all(n.startswith('addons/sfxmint/') for n in z.namelist()), 'plugin must not install files over a project root'
    assert len([n for n in z.namelist() if '/bin/sfxmint-credentials-' in n]) == 5
    assert z.read('addons/sfxmint/panel.gd') == (ROOT/'addons/sfxmint/panel.gd').read_bytes()
with tempfile.TemporaryDirectory(prefix='sfxmint-plugin-install-') as folder:
    target = Path(folder)
    with zipfile.ZipFile(ROOT/f'dist/sfxmint-godot-{version}-plugin.zip') as z:
        z.extractall(target)
    (target/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Clean plugin install"\nconfig/features=PackedStringArray("4.6", "GL Compatibility")\n[editor_plugins]\nenabled=PackedStringArray("res://addons/sfxmint/plugin.cfg")\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    r = subprocess.run([a.godot,'--headless','--path',folder,'--editor','--import','--quit'],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
    print(r.stdout)
    assert r.returncode == 0 and 'SCRIPT ERROR:' not in r.stdout and 'Parse Error:' not in r.stdout
with tempfile.TemporaryDirectory(prefix='sfxmint-zip-install-') as folder:
    target = Path(folder)
    with zipfile.ZipFile(ROOT/f'dist/sfxmint-godot-{version}-example.zip') as z:
        z.extractall(target)
    assert '"4.6"' in (target/'project.godot').read_text()
    for args in [['--editor','--import','--quit'], ['--script','.verify.gd']]:
        if args[0] == '--script':
            # Remove the addon entirely: demo playback must not depend on it.
            import shutil
            shutil.rmtree(target/'addons')
            (target/'.verify.gd').write_text('extends SceneTree\nfunc _initialize():\n\trun.call_deferred()\nfunc run():\n\tvar scene = load("res://example/demo.tscn").instantiate()\n\troot.add_child(scene)\n\tawait process_frame\n\tscene._pickup()\n\tvar ok = scene.coins == 1 and scene.player.playing\n\tprint("PACKAGED OFFLINE DEMO: " + ("PASS" if ok else "FAIL"))\n\tscene.queue_free()\n\tawait process_frame\n\tquit(0 if ok else 1)\n')
        r = subprocess.run([a.godot,'--headless','--path',folder,*args],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
        print(r.stdout)
        assert r.returncode == 0 and 'SCRIPT ERROR:' not in r.stdout and 'Parse Error:' not in r.stdout
        if args[0] == '--script': assert 'PACKAGED OFFLINE DEMO: PASS' in r.stdout
print('PACKAGE INSTALL RESULT: PASS; five helpers included; clean import; demo plays after addon removal')
