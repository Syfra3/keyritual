#!/usr/bin/env python3
"""Offline evidence collector and renderer. See README for trust boundaries."""
import argparse
import hashlib
import html
import json
import os
import re
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

# The checkout retains its historical layout; installed bundles stay under .a2e.
BUNDLE_ROOT = '.a2e/legacy-runs' if Path(__file__).resolve().parent.parent.name == '.a2e' else '_specs'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *args):
    try:
        env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        env.update(GIT_OPTIONAL_LOCKS='0', GIT_TERMINAL_PROMPT='0', GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull, GIT_NO_LAZY_FETCH='1')
        p = subprocess.run(['git', '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null', '-C', str(root), *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15, env=env)
        return p.returncode, p.stdout.decode('utf-8', 'replace')
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, str(e)


def owned(root, rel):
    p = Path(rel)
    if p.is_absolute() or '..' in p.parts or not p.parts:
        raise ValueError('artifact path must be relative')
    current = root
    for part in p.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError('symlink in artifact path')
    dest = (root / p).resolve()
    if not dest.is_relative_to(root) or dest == root:
        raise ValueError('artifact escapes project')
    return dest


def validate_invariants(invariants, checks):
    if not isinstance(invariants, list):
        raise ValueError('invariants must be a list')
    ids = set()
    for inv in invariants:
        if not isinstance(inv, dict) or set(inv) != {'id', 'description', 'checks'}:
            raise ValueError('invariant requires id, description, checks')
        if any(not isinstance(inv[k], str) or not inv[k].strip() for k in ('id', 'description')) or inv['id'] in ids:
            raise ValueError('invalid or duplicate invariant id/description')
        ids.add(inv['id'])
        indexes = inv['checks']
        if not isinstance(indexes, list) or len(indexes) != len(set(indexes)) or any(type(i) is not int or i < 0 or i >= len(checks) for i in indexes):
            raise ValueError('invalid invariant check indexes')


def collect(a):
    root = Path(a.root).resolve(strict=True)
    code, top = git(root, 'rev-parse', '--show-toplevel')
    if code != 0 or Path(top.strip()).resolve() != root:
        raise ValueError('primary must be a Git root')
    if not a.feature or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_' for c in a.feature):
        raise ValueError('feature must be a simple name')
    invariants = [json.loads(value) for value in a.invariant]
    validate_invariants(invariants, a.check)
    bundle = owned(root, BUNDLE_ROOT + '/' + a.feature)
    artifacts = owned(root, BUNDLE_ROOT + '/' + a.feature + '/artifacts')
    artifacts.mkdir(parents=True, exist_ok=False)
    if (bundle / 'manifest.json').exists():
        raise ValueError('manifest already exists; use a fresh feature')
    manifest = {'version': 1, 'created_utc': datetime.now(timezone.utc).isoformat(), 'repositories': [], 'checks': [], 'artifacts': [], 'invariants': invariants}
    def save(name, text):
        path = owned(root, str((artifacts / name).relative_to(root)))
        data = text.encode('utf-8')
        path.write_bytes(data)
        ref = str(path.relative_to(root))
        manifest['artifacts'].append({'path': ref, 'sha256': digest(data)})
        return ref
    for i, raw in enumerate([str(root)] + a.sibling):
        repo = Path(raw).resolve()
        item = {'root': str(repo), 'role': 'primary' if i == 0 else 'sibling'}
        rc, top = git(repo, 'rev-parse', '--show-toplevel')
        if rc != 0 or Path(top.strip()).resolve() != repo:
            item.update(status='unavailable', gap='not an accessible Git root')
        else:
            rc_head, head = git(repo, 'rev-parse', '--verify', 'HEAD')
            status_args = ['status', '--short', '--untracked-files=all']
            if i == 0:
                status_args += ['--', '.', ':(exclude)' + BUNDLE_ROOT + '/' + a.feature + '/**']
            rc_status, status = git(repo, *status_args)
            rc_diff, diff = git(repo, 'diff', '--no-ext-diff', '--no-textconv', '--stat', 'HEAD') if rc_head == 0 else git(repo, 'diff', '--no-ext-diff', '--no-textconv', '--stat', '--cached')
            if rc_head != 0:
                rc_work, work = git(repo, 'diff', '--no-ext-diff', '--no-textconv', '--stat')
                diff += '\nIndex to worktree:\n' + work
                if rc_work != 0:
                    rc_diff = rc_work
            item.update(status='ok' if rc_status == 0 and rc_diff == 0 else 'gap', baseline=head.strip() if rc_head == 0 else 'unborn HEAD', evidence=save(f'repo-{i}.txt', 'Baseline: ' + (head.strip() if rc_head == 0 else 'unborn HEAD') + '\nStatus:\n' + status + '\nDiff stat:\n' + diff), gap='Git query failed' if rc_status != 0 or rc_diff != 0 else None)
        manifest['repositories'].append(item)
    for i, command in enumerate(a.check):
        # Explicit JSON argv, not shell and not repository-discovered commands.
        argv = json.loads(command)
        if not isinstance(argv, list) or not argv or any(not isinstance(x, str) or not x for x in argv):
            raise ValueError('check must be a JSON array of nonempty strings')
        try:
            result = subprocess.run(argv, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=a.timeout)
            text = result.stdout.decode('utf-8', 'replace')
            status = 'passed' if result.returncode == 0 else 'failed'
            rc = result.returncode
        except subprocess.TimeoutExpired as e:
            text = (e.stdout or b'').decode('utf-8', 'replace') + '\nTIMEOUT\n'
            status, rc = 'timeout', None
        except OSError as e:
            text, status, rc = str(e), 'unavailable', None
        ref = save(f'check-{i}.txt', text)
        manifest['checks'].append({'argv': argv, 'status': status, 'exit_code': rc, 'counts': None, 'evidence': ref})
    (bundle / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(bundle / 'manifest.json')


def render(a):
    root = Path(a.root).resolve(strict=True)
    manifest_path = owned(root, a.manifest)
    rel = manifest_path.relative_to(root)
    if len(rel.parts) != len(Path(BUNDLE_ROOT).parts) + 2 or rel.parts[:-2] != Path(BUNDLE_ROOT).parts or rel.name != 'manifest.json':
        raise ValueError('manifest must be ' + BUNDLE_ROOT + '/<feature>/manifest.json')
    m = json.loads(manifest_path.read_text())
    if m.get('version') != 1 or not isinstance(m.get('artifacts'), list):
        raise ValueError('unsupported manifest')
    if not isinstance(m.get('repositories'), list) or not isinstance(m.get('checks'), list):
        raise ValueError('invalid manifest collections')
    validate_invariants(m.get('invariants', []), m['checks'])
    for check in m['checks']:
        if not isinstance(check, dict) or not isinstance(check.get('argv'), list) or not check['argv'] or any(not isinstance(x, str) or not x for x in check['argv']):
            raise ValueError('invalid check argv')
        status, code = check.get('status'), check.get('exit_code')
        if not ((status == 'passed' and type(code) is int and code == 0) or (status == 'failed' and type(code) is int and code != 0) or (status in ('timeout', 'unavailable') and code is None)):
            raise ValueError('inconsistent check outcome')
    refs = {}
    for art in m['artifacts']:
        path = owned(root, art['path'])
        if path.parent != manifest_path.parent / 'artifacts':
            raise ValueError('artifact outside bundle')
        if art['path'] in refs or digest(path.read_bytes()) != art['sha256']:
            raise ValueError('duplicate or tampered artifact: ' + art['path'])
        refs[art['path']] = art['sha256']
    for obj in m['repositories'] + m['checks']:
        if obj.get('evidence') and obj['evidence'] not in refs:
            raise ValueError('unlisted evidence')
        if obj in m['checks'] and not obj.get('evidence'):
            raise ValueError('missing check evidence')
        if obj in m['repositories'] and obj.get('status') == 'ok' and not obj.get('evidence'):
            raise ValueError('missing repository evidence')
    def safe(x):
        return str(x).replace('\\', '\\\\').replace('|', '\\|').replace('\n', ' ').replace('\r', ' ').replace('<', '&lt;').replace('>', '&gt;')
    diagram = ['flowchart LR', '  Unknown[Relationships unknown - human review required]']
    for i, repo in enumerate(m['repositories']):
        if not repo.get('evidence'):
            continue
        content = owned(root, repo['evidence']).read_text(errors='replace')
        status = content.partition('\nStatus:\n')[2].partition('\nDiff stat:\n')[0]
        diagram.append(f'  R{i}[Repository {i}] -.-> Unknown')
        for j, line in enumerate(status.splitlines()):
            label = re.sub(r'[^a-zA-Z0-9_./ -]', ' ', line[3:])[:120].strip() or 'unknown path'
            diagram.append(f'  R{i} --> R{i}C{j}[{label}]')
    lines = ['# Evidence review', '', 'Local artifacts may contain secrets. Review before sharing.', '', '## Observed change / reverse diagram', '', '```mermaid', *diagram, '```', '', 'Repository numbers follow the table below. Nodes derive from listed Git status evidence; Git summaries do not establish runtime relationships or downstream compatibility.', '', '## Repository impact', '', '| Root | Status | Evidence / gap |', '|---|---|---|']
    for repo in m['repositories']:
        lines.append('| ' + ' | '.join(safe(repo.get(k, '')) for k in ('root', 'status')) + ' | ' + safe(repo.get('evidence') or repo.get('gap') or 'GAP') + ' |')
    lines += ['', '## Invariant / check traceability', '', '| Invariant | Check | Outcome | Evidence |', '|---|---|---|---|']
    mapped = set()
    findings = []
    for inv in m.get('invariants', []):
        label = safe(inv['id'] + ': ' + inv['description'])
        if not inv['checks']:
            lines.append('| ' + label + ' | none | GAP | none |')
            findings.append('- GAP: ' + label + ' has no mapped checks; evidence: none; impact: unverified behavior. Disposition: pending human review. Remediation: map an appropriate check.')
        for index in inv['checks']:
            mapped.add(index)
            check = m['checks'][index]
            lines.append('| ' + label + ' | ' + safe(json.dumps(check['argv'])) + ' | ' + safe(check['status']) + ' (counts unavailable) | ' + safe(check['evidence']) + ' |')
            if check['status'] != 'passed':
                findings.append('- ' + safe(check['status'].upper()) + ': ' + label + '; evidence: ' + safe(check['evidence']) + '; impact: invariant not verified. Disposition: pending human review. Remediation: investigate the check and rerun.')
    for index, check in enumerate(m['checks']):
        if index not in mapped:
            lines.append('| GAP: invariant mapping not supplied | ' + safe(json.dumps(check['argv'])) + ' | ' + safe(check['status']) + ' (counts unavailable) | ' + safe(check['evidence']) + ' |')
            findings.append('- GAP: check has no invariant mapping; evidence: ' + safe(check['evidence']) + '; outcome: ' + safe(check['status']) + '. Disposition: pending human review. Remediation: map or explain this check.')
    if not m.get('invariants'):
        findings.append('- GAP: no invariants supplied; evidence: none; impact: coverage unverified. Disposition: pending human review. Remediation: define invariants and map checks.')
    check_refs = ', '.join(safe(c['evidence']) for c in m['checks']) or 'none available'
    repo_refs = ', '.join(safe(r['evidence']) for r in m['repositories'] if r.get('evidence')) or 'none available'
    lines += ['', '## Defensive findings and human disposition', '', *findings, '- GAP: Relationships and sibling consumer impact are unknown; evidence: ' + repo_refs + '; impact: compatibility is unverified. Disposition: pending human review. Remediation: inspect repository evidence and relevant contracts.', '']
    text = '\n'.join(lines)
    out = manifest_path.parent
    owned(root, str((out / 'evidence.md').relative_to(root))).write_text(text)
    page = '<!doctype html><html><head><meta charset="utf-8"><title>Evidence review</title></head><body><pre>' + html.escape(text) + '</pre></body></html>\n'
    owned(root, str((out / 'evidence.html').relative_to(root))).write_text(page)
    print(out / 'evidence.md'); print(out / 'evidence.html')


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest='action', required=True)
    c = sub.add_parser('collect'); c.add_argument('--root', required=True); c.add_argument('--feature', required=True); c.add_argument('--sibling', action='append', default=[]); c.add_argument('--check', action='append', default=[]); c.add_argument('--invariant', action='append', default=[]); c.add_argument('--timeout', type=float, default=30); c.set_defaults(func=collect)
    r = sub.add_parser('render'); r.add_argument('--root', required=True); r.add_argument('--manifest', required=True); r.set_defaults(func=render)
    args = p.parse_args()
    try:
        args.func(args)
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as e:
        print('aaed: ' + str(e), file=sys.stderr); return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
