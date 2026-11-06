#!/usr/bin/env python3
"""Check committed backports, including newly added files, without Git mutations."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
manifest = json.loads(Path(__file__).with_name('backports.json').read_text())
subprocess.run(['git', 'merge-base', '--is-ancestor', manifest['base_commit'], 'HEAD'], cwd=root, check=True)
for name, expected in manifest['source_files_sha256'].items():
    actual = hashlib.sha256((root / name).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit('Backport source mismatch: ' + name)
subprocess.run(['git', 'diff', '--check', manifest['base_commit']], cwd=root, check=True)
print(f"PASS: {len(manifest['patches'])} backports, {len(manifest['source_files_sha256'])} exact source files")
