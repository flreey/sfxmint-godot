#!/usr/bin/env python3
"""Native editor/import/export checks in a disposable project, with a running mock Worker."""
import argparse, os, pathlib, shutil, subprocess, tempfile, zipfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--godot', required=True)
p.add_argument('--archive', type=pathlib.Path, help='Test the delivered plugin ZIP instead of local addon files.')
a = p.parse_args()
ART = ROOT/'tests/artifacts'
ART.mkdir(exist_ok=True)
env = dict(os.environ, SFXMINT_TEST_ORIGIN='http://127.0.0.1:8797')
with tempfile.TemporaryDirectory(prefix='sfxmint-editor-') as folder:
    target = pathlib.Path(folder)
    if a.archive:
        with zipfile.ZipFile(a.archive) as archive:
            archive.extractall(target)
    else:
        shutil.copytree(ROOT/'addons', target/'addons')
    shutil.copytree(ROOT/'example', target/'example', ignore=shutil.ignore_patterns('.godot','addons','audio'))
    project = (ROOT/'project.godot').read_text().replace('"4.7"', '"4.6"').replace('"res://addons/sfxmint/plugin.cfg")','"res://addons/sfxmint/plugin.cfg", "res://addons/smoke/plugin.cfg")')
    (target/'project.godot').write_text(project)
    smoke = target/'addons/smoke'
    smoke.mkdir()
    shutil.copy2(ROOT/'tests/editor_smoke.gd',smoke/'smoke.gd')
    (smoke/'plugin.cfg').write_text('[plugin]\nname="Local smoke"\ndescription="Disposable native test"\nauthor="SFXMint"\nversion="1"\nscript="smoke.gd"\n')
    def run(args, log, marker=None):
        try:
            r = subprocess.run([a.godot,'--headless','--path',str(target),*args],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
        except subprocess.TimeoutExpired as error:
            output = error.stdout or b''
            if isinstance(output, bytes): output = output.decode(errors='replace')
            (ART/log).write_text(output)
            print(output, flush=True)
            raise SystemExit(f'Timed out: {log}')
        (ART/log).write_text(r.stdout)
        print(r.stdout)
        if r.returncode or (marker and marker not in r.stdout) or 'Parse Error:' in r.stdout or 'SCRIPT ERROR:' in r.stdout:
            raise SystemExit(f'Failed: {log}')
    run(['--editor'], 'editor-smoke.log', 'EDITOR SMOKE RESULT: 0 failures')
    (target/'.runtime_test.gd').write_text('extends SceneTree\nfunc _initialize():\n\trun.call_deferred()\nfunc run():\n\tvar scene = load("res://example/demo.tscn").instantiate()\n\troot.add_child(scene)\n\tawait process_frame\n\tscene._pickup()\n\tvar ok = scene.coins == 1 and scene.player.playing\n\tprint("DEMO RUNTIME RESULT: " + ("PASS" if ok else "FAIL"))\n\tscene.queue_free()\n\tawait process_frame\n\tquit(0 if ok else 1)\n')
    run(['--script','.runtime_test.gd'], 'demo-runtime.log', 'DEMO RUNTIME RESULT: PASS')
    (target/'export_presets.cfg').write_text('[preset.0]\nname="Verification"\nplatform="Linux"\nrunnable=true\nexport_filter="all_resources"\ninclude_filter="*.json,*.md"\nexclude_filter="addons/smoke/*"\nexport_path=""\nscript_export_mode=1\n[preset.0.options]\nbinary_format/architecture="x86_64"\n')
    for bad in (target/'audio/sfxmint').glob('invalid-wav*'):
        bad.unlink()
    pack = ART/'verified-game-export.zip'
    run(['--editor','--export-pack','Verification',str(pack)], 'export-smoke.log')
    with zipfile.ZipFile(pack) as z:
        names = z.namelist()
        assert not any('sfxmint-credentials-' in n or n.startswith('addons/sfxmint/bin/') or 'tasks-' in n for n in names), names
        assert any('fixture-coin' in n for n in names), 'missing game audio'
        assert any(n == 'audio/sfxmint/sounds.json' for n in names), 'missing demo manifest'
        assert not any(b'sfx_live_'+b'1'*40 in z.read(n) for n in names)
    print('EXPORT RESULT: helpers/cache absent; local audio and manifest present; fixture key absent')
