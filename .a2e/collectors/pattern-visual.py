#!/usr/bin/env python3
"""Copy the five owner-selected, previously captured UI images as after evidence."""
import json
import os
from pathlib import Path
import shutil

source = Path('/tmp/opencode/keyritual-captures')
output = Path(os.environ['A2E_OUTPUT_DIR'])
names = [
    'current-collection-disabled.png',
    'current-targeted-fallback.png',
    'current-targeted-with-data.png',
    'current-clear-success.png',
    'clear-error-reloaded.png',
]
for name in names:
    image = source / name
    if image.is_symlink() or not image.is_file():
        raise SystemExit(f'Missing reviewed image: {name}')
    shutil.copyfile(image, output / name)
(output / 'result.json').write_text(json.dumps({'metric': len(names), 'artifacts': names}) + '\n')
