#!/usr/bin/env python3
"""Run focused Godot tests against an already running local mock service."""
import argparse, os, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--godot', required=True)
a = p.parse_args()
env = dict(os.environ, SFXMINT_TEST_ORIGIN='http://127.0.0.1:8797')
for script, marker in [('test_client.gd','SFXMINT TEST RESULT: 37 checks, 0 failures'),('test_credentials.gd','CREDENTIAL PIPE RESULT: PASS')]:
    result = subprocess.run([a.godot,'--headless','--path',str(ROOT),'--script','tests/'+script],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
    print(result.stdout)
    if result.returncode or marker not in result.stdout or 'Parse Error:' in result.stdout or 'SCRIPT ERROR:' in result.stdout:
        raise SystemExit(1)
