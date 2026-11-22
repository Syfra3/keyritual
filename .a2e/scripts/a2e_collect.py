#!/usr/bin/env python3
"""Offline diff collector. Config is JSON (a YAML subset); see evidence.example.yaml.

Collectors receive matching repository-relative paths as literal argv, and A2E_OUTPUT_DIR
as an absolute private output directory. They must write result.json containing a numeric
metric and optional relative artifact paths. No command is run without --execute.
"""
import argparse
import fnmatch
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys

from a2e_entry import git, run_dir


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(',', ':')).encode()


def git_bytes(root, *args):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0', GIT_NO_LAZY_FETCH='1',
               GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)
    p = subprocess.run(['git', '-C', str(root), '-c', 'core.fsmonitor=false',
                        '-c', 'core.hooksPath=/dev/null', *args],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    if p.returncode:
        raise ValueError('git ' + args[0] + ' failed: ' + p.stderr.decode(errors='replace').strip())
    return p.stdout


def state(root, base):
    """Return the local merge base, changed names and a content-bound snapshot."""
    root = Path(root).resolve()
    merge = git_bytes(root, 'merge-base', 'HEAD', base).decode().strip()
    names = set()
    # --no-renames preserves both sides and makes deletes and renames explicit.
    for args in [('diff', '--name-only', '-z', '--no-renames', merge),
                 ('diff', '--cached', '--name-only', '-z', '--no-renames'),
                 ('ls-files', '--others', '--exclude-standard', '-z')]:
        names.update(os.fsdecode(x) for x in git_bytes(root, *args).split(b'\0') if x)
    paths = sorted(names, key=os.fsencode)
    entries = []
    for name in paths:
        path = root / name
        if path.is_symlink():
            value = ['symlink', os.readlink(path)]
        elif path.is_file():
            value = ['file', digest(path.read_bytes()), bool(path.stat().st_mode & 0o111)]
        elif path.exists():
            value = ['other']
        else:
            value = ['deleted']
        entries.append([name, value])
    # Include index identity as well as the working tree, so staged-only changes bind.
    index = digest(git_bytes(root, 'diff', '--cached', '--binary', '--no-ext-diff', 'HEAD'))
    head = git_bytes(root, 'rev-parse', 'HEAD').decode().strip()
    return {'base': merge, 'head': head, 'paths': paths,
            'snapshot': digest(canonical([merge, head, entries, index]))}


def load_config(root, config):
    path = Path(config)
    if not path.is_absolute():
        path = root / path
    data = path.read_bytes()
    obj = json.loads(data)
    if set(obj) != {'version', 'collectors'} or obj['version'] != 1 or not isinstance(obj['collectors'], list):
        raise ValueError('invalid config')
    ids = set()
    for c in obj['collectors']:
        if set(c) - {'id', 'patterns', 'script', 'required', 'category', 'boundary', 'budget'} or not all(k in c for k in ('id', 'patterns', 'required', 'category', 'boundary')):
            raise ValueError('invalid collector fields')
        if not isinstance(c['id'], str) or not c['id'] or not all(ch.isalnum() or ch in '-_' for ch in c['id']) or c['id'] in ids:
            raise ValueError('invalid or duplicate collector id')
        ids.add(c['id'])
        if not isinstance(c['patterns'], list) or not c['patterns'] or not all(isinstance(p, str) and p for p in c['patterns']) or type(c['required']) is not bool or not all(isinstance(c[k], str) and c[k] for k in ('category', 'boundary')):
            raise ValueError('invalid collector definition')
        if 'budget' in c and (type(c['budget']) not in (int, float) or not math.isfinite(c['budget'])):
            raise ValueError('invalid budget')
        if 'script' in c and (not isinstance(c['script'], str) or not c['script']):
            raise ValueError('invalid script')
    return obj, digest(data)


def relative_file(directory, name):
    if not isinstance(name, str) or not name or Path(name).is_absolute() or '..' in Path(name).parts:
        raise ValueError('artifact must be a relative path')
    path = directory / name
    if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(directory.resolve()):
        raise ValueError('artifact missing or outside output directory')
    return path


def script_hashes(root, cfg):
    hashes = {}
    for c in cfg['collectors']:
        if c.get('script'):
            try:
                hashes[c['id']] = digest(relative_file(root, c['script']).read_bytes())
            except (OSError, ValueError):
                hashes[c['id']] = None
    return hashes


def read_manifest(path):
    obj = json.loads(Path(path).read_text(encoding='utf-8'))
    if not isinstance(obj, dict) or obj.get('version') != 1:
        raise ValueError('invalid manifest')
    return obj


def _validate_manifest(root, manifest_path, cfg, config_hash, current, historical=False):
    directory = run_dir(root)
    path = Path(manifest_path).resolve()
    if not path.is_relative_to(directory.resolve()):
        raise ValueError('manifest outside current run directory')
    obj = read_manifest(path)
    recorded = obj.get('state')
    if (obj.get('config_sha256') != config_hash or obj.get('scripts') != script_hashes(root, cfg)
            or not isinstance(recorded, dict) or set(recorded) != {'base', 'head', 'paths', 'snapshot'}
            or not isinstance(recorded['paths'], list) or not all(isinstance(p, str) for p in recorded['paths'])
            or recorded['paths'] != sorted(set(recorded['paths']), key=os.fsencode)
            or not isinstance(recorded['snapshot'], str) or len(recorded['snapshot']) != 64
            or recorded['base'] != current['base'] or recorded['head'] != current['head']
            or (not historical and recorded != current)):
        raise ValueError('stale config or change state')
    if historical and obj.get('phase') != 'before':
        raise ValueError('invalid historical phase')
    if obj.get('run') != str(directory.relative_to(root)):
        raise ValueError('wrong run')
    if obj.get('phase') not in ('before', 'after') or path != directory / obj['phase'] / 'manifest.json':
        raise ValueError('invalid manifest location or phase')
    items = obj.get('collectors')
    if not isinstance(items, list) or len(items) != len(cfg['collectors']):
        raise ValueError('invalid collector list')
    for item, definition in zip(items, cfg['collectors']):
        if not isinstance(item, dict):
            raise ValueError('invalid collector entry')
        matched = [p for p in obj['state']['paths'] if any(fnmatch.fnmatchcase(p, pat) for pat in definition['patterns'])]
        if (item.get('id') != definition['id'] or item.get('category') != definition['category'] or
                item.get('boundary') != definition['boundary'] or item.get('required') is not definition['required'] or
                item.get('paths') != matched or item.get('status') not in ('PASS', 'FAIL', 'REGRESSION', 'SKIPPED', 'GAP', 'NOT_CONFIGURED') or
                (not matched and item.get('status') != 'SKIPPED') or (matched and item.get('status') == 'SKIPPED')):
            raise ValueError('invalid collector entry')
        if item['status'] in ('PASS', 'REGRESSION'):
            metric = item.get('metric')
            if (type(metric) not in (int, float) or not math.isfinite(metric) or
                    item.get('exit_code') != 0 or item.get('argv') != [definition.get('script'), *matched]):
                raise ValueError('invalid successful collector result')
            if not definition.get('script') or obj['scripts'].get(definition['id']) is None:
                raise ValueError('invalid successful collector script')
            if obj['phase'] == 'before' and item['status'] != 'PASS':
                raise ValueError('invalid before verdict')
            if obj['phase'] == 'after' and 'budget' in definition:
                baseline_path = directory / 'before' / 'manifest.json'
                if obj.get('baseline_sha256') != digest(baseline_path.read_bytes()):
                    raise ValueError('baseline manifest hash mismatch')
                baseline = _validate_manifest(root, baseline_path, cfg, config_hash, current, historical=True)
                prior = next((x for x in baseline['collectors'] if x['id'] == item['id']), None)
                if (not prior or prior['status'] != 'PASS' or item.get('baseline_metric') != prior.get('metric')
                        or item.get('budget') != definition['budget']):
                    raise ValueError('invalid baseline metric or budget')
                expected = 'REGRESSION' if metric - prior['metric'] > definition['budget'] else 'PASS'
                if item['status'] != expected:
                    raise ValueError('invalid budget verdict')
            elif item['status'] == 'REGRESSION':
                raise ValueError('invalid regression verdict')
        artifacts = item.get('artifacts')
        if not isinstance(artifacts, list) or not all(isinstance(a, dict) for a in artifacts):
            raise ValueError('invalid artifacts')
        if 'metric' in item:
            result_path = relative_file(path.parent / item['id'], 'result.json')
            data = result_path.read_bytes()
            result = json.loads(data)
            if (item.get('result_sha256') != digest(data) or not isinstance(result, dict)
                    or result.get('metric') != item['metric']
                    or not isinstance(result.get('artifacts', []), list)
                    or [a.get('path') for a in item.get('artifacts', [])] !=
                       [str(Path(item['id']) / n) for n in result.get('artifacts', []) if isinstance(n, str)]
                    or not all(isinstance(n, str) for n in result.get('artifacts', []))):
                raise ValueError('collector result mismatch')
        for artifact in artifacts:
            if not isinstance(artifact, dict) or set(artifact) != {'path', 'sha256'}:
                raise ValueError('invalid artifact')
            p = relative_file(path.parent, artifact['path'])
            if not p.resolve().is_relative_to((path.parent / item['id']).resolve()) or digest(p.read_bytes()) != artifact['sha256']:
                raise ValueError('artifact hash mismatch')
    return obj


def validate_consumer(root, manifest_path, config='.a2e/evidence.yaml', base='HEAD'):
    """Validate current evidence; statuses still require consumer policy enforcement.

    Historical before snapshots need not equal today's worktree, but must retain
    the same base, HEAD, config and scripts. Hashes detect changes, not forgery.
    """
    root = Path(root).resolve()
    cfg, config_hash = load_config(root, config)
    return _validate_manifest(root, manifest_path, cfg, config_hash, state(root, base))


def validate_historical_before(root, manifest_path, config='.a2e/evidence.yaml', base='HEAD'):
    """Validate a before manifest against today's base, HEAD, config and scripts.

    The historical worktree snapshot may differ. This verifies artifact hashes, not
    the origin or truth of the collector's measurements.
    """
    root = Path(root).resolve()
    cfg, config_hash = load_config(root, config)
    return _validate_manifest(root, manifest_path, cfg, config_hash, state(root, base), historical=True)


def collect(root, config, base, phase, execute):
    root = Path(root).resolve()
    run = run_dir(root)
    cfg, config_hash = load_config(root, config)
    current = state(root, base)
    scripts = script_hashes(root, cfg)
    out = run / phase
    out.mkdir(parents=True, exist_ok=True)
    baseline = None
    baseline_hash = None
    if phase == 'after':
        try:
            baseline_path = run / 'before' / 'manifest.json'
            baseline = _validate_manifest(root, baseline_path, cfg, config_hash, current, historical=True)
            baseline_hash = digest(baseline_path.read_bytes())
        except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
            baseline = None
    results = []
    for c in cfg['collectors']:
        matched = [p for p in current['paths'] if any(fnmatch.fnmatchcase(p, pat) for pat in c['patterns'])]
        item = {'id': c['id'], 'category': c['category'], 'boundary': c['boundary'],
                'required': c['required'], 'paths': matched, 'artifacts': [], 'diagnostic': ''}
        if not matched:
            item['status'] = 'SKIPPED'
        elif not c.get('script'):
            item['status'] = 'GAP' if c['required'] else 'NOT_CONFIGURED'
            item['diagnostic'] = 'collector not configured'
        elif not execute:
            item['status'] = 'GAP' if c['required'] else 'NOT_CONFIGURED'
            item['diagnostic'] = 'execution not requested'
        else:
            try:
                script = relative_file(root, c['script'])
                output = out / c['id']
                output.mkdir(exist_ok=True)
                result_path = output / 'result.json'
                if result_path.exists():
                    result_path.unlink()
                argv = [str(script), *matched]
                p = subprocess.run(argv, cwd=root, env=dict(os.environ, A2E_OUTPUT_DIR=str(output)),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                item['argv'] = [c['script'], *matched]
                item['exit_code'] = p.returncode
                if p.returncode:
                    item['status'], item['diagnostic'] = 'FAIL', 'collector exited nonzero'
                else:
                    result_data = result_path.read_bytes()
                    result = json.loads(result_data)
                    if not isinstance(result, dict) or set(result) - {'metric', 'artifacts'} or type(result.get('metric')) not in (int, float) or not math.isfinite(result['metric']) or not isinstance(result.get('artifacts', []), list):
                        raise ValueError('invalid collector result')
                    item['metric'] = result['metric']
                    item['result_sha256'] = digest(result_data)
                    for name in result.get('artifacts', []):
                        artifact = relative_file(output, name)
                        item['artifacts'].append({'path': str(artifact.relative_to(out)), 'sha256': digest(artifact.read_bytes())})
                    item['status'] = 'PASS'
                    if phase == 'after' and 'budget' in c:
                        prior = next((x for x in (baseline or {}).get('collectors', []) if x.get('id') == c['id'] and x.get('status') == 'PASS'), None)
                        if not prior or 'metric' not in prior:
                            item['status'], item['diagnostic'] = 'GAP', 'missing or stale baseline'
                        else:
                            item['baseline_metric'] = prior['metric']
                            item['budget'] = c['budget']
                            if item['metric'] - prior['metric'] > c['budget']:
                                item['status'], item['diagnostic'] = 'REGRESSION', 'metric exceeds budget'
            except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
                item.pop('metric', None)
                item.pop('result_sha256', None)
                item['artifacts'] = []
                item['status'], item['diagnostic'] = 'GAP', str(exc)
        results.append(item)
    manifest = {'version': 1, 'run': str(run.relative_to(root)), 'phase': phase,
                'config_sha256': config_hash, 'scripts': scripts, 'state': current, 'collectors': results}
    if baseline_hash is not None:
        manifest['baseline_sha256'] = baseline_hash
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + '\n', encoding='utf-8')
    return out / 'manifest.json'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True)
    parser.add_argument('--config', default='.a2e/evidence.yaml')
    parser.add_argument('--base', required=True, help='local Git revision; no fetch')
    parser.add_argument('--phase', choices=('before', 'after'), required=True)
    parser.add_argument('--execute', action='store_true', help='run explicitly configured reviewed local scripts')
    args = parser.parse_args()
    try:
        print(collect(args.root, args.config, args.base, args.phase, args.execute))
        return 0
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print('collector error: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
