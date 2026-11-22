#!/usr/bin/env python3
"""Local, explicit evidence runs. See docs/evidence-run.md; never publishes evidence."""
import argparse
import html
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from a2e_collect import canonical, digest, git_bytes, relative_file, state


def save(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(json.dumps(obj, indent=2, ensure_ascii=True) + '\n')
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def managed(root, path):
    """Reject symlinked managed paths, including ancestors within .a2e."""
    path = Path(path)
    base = root / '.a2e'
    if '..' in path.parts or not path.is_relative_to(base):
        raise ValueError('managed path must be beneath .a2e')
    current = root
    for part in path.relative_to(root).parts:
        current = current / part
        if current.is_symlink():
            raise ValueError('symlink in managed path: ' + str(current.relative_to(root)))
    return path


def directory(root, name):
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}', name):
        raise ValueError('invalid run id')
    parent = root / '.a2e' / 'runs' / 'stable'
    path = parent / name
    return managed(root, path)


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def feature(root, name):
    if not isinstance(name, str) or not name.startswith('.a2e/specs/') or not name.endswith('.feature'):
        raise ValueError('feature must be a .a2e/specs/*.feature path')
    path = managed(root, root / name)
    data = path.read_bytes()
    text = data.decode('utf-8')
    scenarios, tag, current, steps, seen_feature = {}, None, None, [], False
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('Feature:') and not seen_feature and not scenarios and tag is None:
            seen_feature = bool(line[8:].strip())
            if not seen_feature:
                raise ValueError('empty Feature')
        elif re.fullmatch(r'@[A-Za-z0-9_-]+', line) and seen_feature and tag is None:
            if current and not all(x in steps for x in ('Given', 'When', 'Then')):
                raise ValueError('scenario requires Given, When and Then')
            tag, current, steps = line[1:], None, []
            if tag in scenarios:
                raise ValueError('duplicate scenario id: ' + tag)
        elif line.startswith('Scenario:') and tag and line[9:].strip():
            current = tag
            scenarios[current] = {'title': line[9:].strip(), 'steps': []}
            tag = None
        elif current and re.match(r'^(Given|When|Then|And|But)\s+\S', line):
            keyword = line.split(None, 1)[0]
            if keyword in ('And', 'But') and not steps:
                raise ValueError('And/But requires a preceding step')
            steps.append(keyword)
            scenarios[current]['steps'].append(line)
        else:
            raise ValueError('unsupported Gherkin at line ' + str(number) + ': ' + line)
    if not seen_feature or not scenarios or tag or not all(x in steps for x in ('Given', 'When', 'Then')):
        raise ValueError('feature requires tagged scenarios with Given, When and Then')
    return digest(data), scenarios


def packet(root, path):
    obj = load(path)
    if not isinstance(obj, dict):
        raise ValueError('invalid packet')
    if 'version' in obj:
        return packet_v2(root, obj)
    if set(obj) != {'scope', 'expectations', 'checks'}:
        raise ValueError('packet requires scope, expectations and checks')
    if not all(isinstance(obj[k], str) and obj[k].strip() for k in ('scope', 'expectations')) or not isinstance(obj['checks'], list) or not obj['checks']:
        raise ValueError('invalid packet')
    ids = set()
    for c in obj['checks']:
        if not isinstance(c, dict) or set(c) != {'id', 'boundary', 'scenario', 'runner'} or not all(isinstance(v, str) and v.strip() for v in c.values()):
            raise ValueError('invalid check')
        if not re.fullmatch(r'[A-Za-z0-9_-]+', c['id']) or c['id'] in ids:
            raise ValueError('invalid check id')
        ids.add(c['id'])
        relative_file(root, c['runner'])
    return obj


def packet_v2(root, obj):
    if set(obj) != {'version', 'scope', 'expectations', 'feature', 'architecture', 'checks'} or type(obj['version']) is not int or obj['version'] != 2:
        raise ValueError('invalid v2 packet fields or version')
    if not all(isinstance(obj[k], str) and obj[k].strip() for k in ('scope', 'expectations')):
        raise ValueError('invalid scope or expectations')
    _, scenarios = feature(root, obj['feature'])
    arch = obj['architecture']
    if not isinstance(arch, dict) or set(arch) != {'components', 'connections'} or not all(isinstance(arch[k], list) for k in arch) or not arch['components']:
        raise ValueError('invalid architecture')
    ids, components = set(), set()
    def identifier(value):
        return isinstance(value, str) and bool(re.fullmatch(r'[A-Za-z0-9_-]+', value))
    for kind in ('components', 'connections'):
        for node in arch[kind]:
            keys = {'id', 'label'} if kind == 'components' else {'id', 'label', 'from', 'to'}
            if not isinstance(node, dict) or set(node) != keys or not identifier(node['id']) or node['id'] in ids or not isinstance(node['label'], str) or not node['label'].strip():
                raise ValueError('invalid or duplicate architecture id/label')
            if kind == 'connections' and (node['from'] not in components or node['to'] not in components):
                raise ValueError('unknown connection endpoint')
            ids.add(node['id'])
            if kind == 'components':
                components.add(node['id'])
    if not isinstance(obj['checks'], list) or not obj['checks']:
        raise ValueError('checks must be nonempty')
    checks = set()
    for c in obj['checks']:
        if not isinstance(c, dict) or set(c) != {'id', 'scenario_ids', 'architecture_ids', 'runner'} or not identifier(c['id']) or c['id'] in checks:
            raise ValueError('invalid or duplicate check id')
        checks.add(c['id'])
        for key, known in (('scenario_ids', scenarios), ('architecture_ids', ids)):
            values = c[key]
            if not isinstance(values, list) or not values or not all(identifier(x) for x in values) or len(set(values)) != len(values) or not set(values) <= set(known):
                raise ValueError('invalid or unknown ' + key)
        relative_file(root, c['runner'])
    return obj


def feature_hash(root, run):
    if run['packet'].get('version') == 2:
        return feature(root, run['packet']['feature'])[0]
    return None


def identity(run):
    parts = [run['base'], run['packet'], run['runners']]
    if run['packet'].get('version') == 2:
        parts.extend([run['feature_sha256'], run['packet_source'], run['packet_file_sha256']])
    return digest(canonical(parts))


def current_inputs(root, run):
    try:
        packet_ok = (run['packet'].get('version') != 2 or
                     digest(Path(run['packet_source']).read_bytes()) == run['packet_file_sha256'])
        return packet_ok and preflight(root, run['packet']) == run['runners'] and feature_hash(root, run) == run.get('feature_sha256')
    except (OSError, ValueError, UnicodeError):
        return False


def preflight(root, obj):
    rows = []
    for c in obj['checks']:
        try:
            p = relative_file(root, c['runner'])
            rows.append({'id': c['id'], 'runner': c['runner'], 'sha256': digest(p.read_bytes()), 'executable': os.access(p, os.X_OK)})
        except (ValueError, OSError):
            rows.append({'id': c['id'], 'runner': c['runner'], 'sha256': None, 'executable': False})
    return rows


def current(root, run):
    return state(root, run['base'])


def collect(root, folder, run, phase):
    now = current(root, run)
    if phase == 'baseline' and (now['head'] != run['base'] or now['paths']):
        raise ValueError('baseline requires clean pinned base at HEAD')
    if not current_inputs(root, run):
        raise ValueError('packet, feature or runner changed since plan')
    results = []
    for check in run['packet']['checks']:
        parent = managed(root, folder / phase / check['id'])
        parent.mkdir(parents=True, exist_ok=True)
        output = Path(tempfile.mkdtemp(prefix='attempt-', dir=parent))
        result_file = output / 'result.json'
        item = {'id': check['id'], 'status': 'failed', 'artifacts': []}
        try:
            p = subprocess.run([str(relative_file(root, check['runner']))], cwd=root,
                               env=dict(os.environ, A2E_OUTPUT_DIR=str(output)), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
            item['exit_code'] = p.returncode
            if p.returncode == 0:
                data = managed(root, relative_file(output, 'result.json')).read_bytes()
                result = json.loads(data)
                if not isinstance(result, dict) or set(result) - {'metric', 'artifacts'} or not isinstance(result.get('artifacts', []), list):
                    raise ValueError('invalid result')
                metric = result.get('metric')
                if metric is not None and (type(metric) not in (int, float) or not math.isfinite(metric)):
                    raise ValueError('invalid metric')
                item.update(status='passed', metric=metric, result_sha256=digest(data), attempt=output.name)
                for name in result.get('artifacts', []):
                    artifact = relative_file(output, name)
                    managed(root, artifact)
                    item['artifacts'].append({'path': name, 'sha256': digest(artifact.read_bytes())})
        except (OSError, ValueError, TypeError, subprocess.TimeoutExpired) as exc:
            item = {'id': check['id'], 'status': 'failed', 'artifacts': [], 'diagnostic': str(exc)}
        results.append(item)
    if current(root, run) != now or not current_inputs(root, run):
        raise ValueError('workspace, feature or runners changed during collection')
    manifest = {'version': 1, 'phase': phase, 'run_id': run['id'], 'packet_sha256': run['packet_sha256'], 'state': now, 'results': results}
    save(managed(root, folder / phase / 'manifest.json'), manifest)


def evidence(root, folder, run, phase):
    path = managed(root, folder / phase / 'manifest.json')
    if not path.exists():
        return None, 'missing'
    try:
        obj = load(path)
        if (obj['version'] != 1 or obj['phase'] != phase or obj['run_id'] != run['id'] or obj['packet_sha256'] != run['packet_sha256'] or not current_inputs(root, run) or [x['id'] for x in obj['results']] != [x['id'] for x in run['packet']['checks']]):
            raise ValueError('identity mismatch')
        now = current(root, run)
        if (phase == 'candidate' and obj['state'] != now) or (phase == 'baseline' and (obj['state']['head'] != run['base'] or obj['state']['base'] != run['base'] or obj['state']['paths'])):
            raise ValueError('state changed')
        for item in obj['results']:
            if item['status'] not in ('passed', 'failed'):
                raise ValueError('invalid status')
            if item['status'] == 'passed':
                if not re.fullmatch(r'attempt-[a-z0-9_]+', item['attempt']):
                    raise ValueError('invalid attempt directory')
                out = managed(root, folder / phase / item['id'] / item['attempt'])
                data = relative_file(out, 'result.json').read_bytes()
                result = json.loads(data)
                if digest(data) != item['result_sha256'] or result.get('metric') != item.get('metric') or result.get('artifacts', []) != [a['path'] for a in item['artifacts']]:
                    raise ValueError('result changed')
                for a in item['artifacts']:
                    if digest(managed(root, relative_file(out, a['path'])).read_bytes()) != a['sha256']:
                        raise ValueError('artifact changed')
        return obj, 'valid'
    except (OSError, ValueError, KeyError, TypeError):
        return None, 'stale'


def render(root, folder, run, plan=False):
    base, bs = evidence(root, folder, run, 'baseline')
    candidate, cs = evidence(root, folder, run, 'candidate')
    old = {x['id']: x for x in base['results']} if base else {}
    new = {x['id']: x for x in candidate['results']} if candidate else {}
    def esc(value):
        return html.escape(str(value), quote=True).replace('|', '&#124;').replace('\n', ' ')
    v2 = run['packet'].get('version') == 2
    lines = ['# Evidence run ' + esc(run['id']), '', ('Declared architecture (not discovered or verified).' if v2 else 'Legacy/unlinked: scenario and architecture coverage is not established.'), '', 'Goal and scope: ' + esc(run['packet']['scope']),
             'Expectations: ' + esc(run['packet']['expectations']), 'Base revision: `' + run['base'] + '`',
             'Gate 1 packet: `' + run['packet_sha256'] + '` (' + ('stale' if not current_inputs(root, run) else 'recorded' if run.get('approval') == run['packet_sha256'] else 'pending') + ')',
             '', 'Raw artifacts are private. Hashes do not establish origin or truth.', '', '```mermaid', 'graph LR']
    rows = []
    artifact_refs = []
    if v2:
        arch = run['packet']['architecture']
        nodes = {x['id']: 'a' + str(i) for i, x in enumerate(arch['components'])}
        for component in arch['components']:
            lines.append('  ' + nodes[component['id']] + '["' + esc(component['id'] + ': ' + component['label']).replace('`', '&#96;') + '"]')
        for i, connection in enumerate(arch['connections']):
            lines.append('  ' + nodes[connection['from']] + ' --> aconn' + str(i) + '["' + esc(connection['id'] + ': ' + connection['label']).replace('`', '&#96;') + '"] --> ' + nodes[connection['to']])
            nodes[connection['id']] = 'aconn' + str(i)
        try:
            _, scenarios = feature(root, run['packet']['feature'])
        except (OSError, ValueError, UnicodeError):
            scenarios = {}
    else:
        scenarios = {}
    for i, c in enumerate(run['packet']['checks']):
        b, n = old.get(c['id'], {}), new.get(c['id'], {})
        status = 'planned' if plan else n.get('status', cs)
        label = lambda s: esc(s).replace('"', '&quot;').replace('`', '&#96;')
        if v2:
            for architecture_id in c['architecture_ids']:
                for scenario_id in c['scenario_ids']:
                    lines.append(f'  {nodes[architecture_id]} --> s{i}_{scenario_id}["{label(scenario_id)}"] --> c{i}["{label(c["id"])}: {label(c["runner"])}"] --> r{i}["{label(status)}"]')
        else:
            lines += [f'  b{i}["{label(c["boundary"])}"] --> s{i}["{label(c["scenario"])}"] --> c{i}["{label(c["id"])}"] --> r{i}["{label(status)}"]']
        before, after = b.get('metric'), n.get('metric')
        delta = after - before if b.get('status') == n.get('status') == 'passed' and before is not None and after is not None else None
        artifacts = ', '.join(a['path'] for a in n.get('artifacts', [])) or 'none'
        for phase, entry in (('baseline', b), ('candidate', n)):
            for j, a in enumerate(entry.get('artifacts', [])):
                key = f'e{i}_{phase}{j}'
                lines.append(f'  r{i} --> {key}["{phase}: {label(a["path"])}"]')
                artifact_refs.append((phase, c['id'], entry['attempt'], a))
        rows.append([', '.join(c['architecture_ids']) if v2 else c['boundary'], ', '.join(c['scenario_ids']) if v2 else c['scenario'], c['id'] + (' (' + c['runner'] + ')' if v2 else ''), status, artifacts, before, after, delta])
    lines += ['```', '', '| Boundary | Scenario | Check | Result / gap | Artifacts (private) | Baseline | Candidate | Delta |', '| --- | --- | --- | --- | --- | --- | --- | --- |']
    lines += ['| ' + ' | '.join(esc(x if x is not None else '—') for x in row) + ' |' for row in rows]
    if v2:
        lines += ['', '## Readable scenarios']
        if not current_inputs(root, run):
            lines.append('Packet, feature or runner changed; approval and evidence are stale.')
        for scenario_id, scenario in scenarios.items():
            lines += ['', '### ' + esc(scenario_id) + ': ' + esc(scenario['title'])]
            lines += ['- ' + esc(step) for step in scenario['steps']]
    if artifact_refs:
        lines += ['', '## Validated private artifact references']
        for phase, check_id, attempt, a in artifact_refs:
            ref = folder.relative_to(root) / phase / check_id / attempt / a['path']
            lines.append('- ' + esc(ref) + ' · SHA-256 `' + a['sha256'] + '`')
    lines += ['', 'Baseline: ' + bs + '; candidate: ' + cs, '', '## Review attempts']
    candidate_digest = digest(canonical(candidate)) if candidate else None
    lines += ['- ' + esc(x['verdict']) + ': ' + esc(x['finding']) +
              (' (prior snapshot)' if x.get('candidate_sha256') != candidate_digest else '')
              for x in run['reviews']] or ['- None']
    lines += ['', 'Offline draft only: no Gate 3 approval or publication is implied.']
    return '\n'.join(lines) + '\n'


def starter(root, name):
    paths = [managed(root, root / '.a2e' / folder / (name + suffix)) for folder, suffix in
             (('specs', '.feature'), ('packets', '.json'), ('tests', '.py'))]
    if any(p.exists() or p.is_symlink() for p in paths):
        raise ValueError('starter file already exists; refusing overwrite')
    obj = {'version': 2, 'scope': 'Describe the intended behavior', 'expectations': 'Replace the scaffold with real assertions',
           'feature': '.a2e/specs/' + name + '.feature',
           'architecture': {'components': [{'id': 'client', 'label': 'Client'}, {'id': 'service', 'label': 'Service'}],
                            'connections': [{'id': 'request', 'from': 'client', 'to': 'service', 'label': 'request'}]},
           'checks': [{'id': 'check1', 'scenario_ids': ['S1'], 'architecture_ids': ['client', 'request'], 'runner': '.a2e/tests/' + name + '.py'}]}
    contents = ['Feature: Describe behavior\n\n  @S1\n  Scenario: Replace this example\n    Given a meaningful starting state\n    When the behavior is exercised\n    Then assert the expected outcome\n',
                json.dumps(obj, indent=2) + '\n',
                '#!/usr/bin/env python3\nraise SystemExit("Unimplemented: replace with real assertions and write result.json")\n']
    for path, content in zip(paths, contents):
        managed(root, path.parent).mkdir(parents=True, exist_ok=True)
        managed(root, path)
        with path.open('x', encoding='utf-8') as stream:
            stream.write(content)
    paths[2].chmod(0o755)
    for path in paths:
        print(path.relative_to(root))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True)
    parser.add_argument('--id', required=True)
    sub = parser.add_subparsers(dest='command', required=True)
    plan = sub.add_parser('plan'); plan.add_argument('--packet', required=True); plan.add_argument('--base', required=True)
    sub.add_parser('init')
    sub.add_parser('preflight')
    approve = sub.add_parser('approve'); approve.add_argument('--packet-sha256', required=True)
    sub.add_parser('baseline')
    sub.add_parser('candidate')
    sub.add_parser('status')
    sub.add_parser('draft')
    review = sub.add_parser('review'); review.add_argument('--verdict', choices=('pass', 'blocker'), required=True); review.add_argument('--finding', required=True)
    args = parser.parse_args()
    try:
        root = Path(args.root).resolve()
        if Path(git_bytes(root, 'rev-parse', '--show-toplevel').decode().strip()).resolve() != root:
            raise ValueError('root must be repository root')
        folder = directory(root, args.id)
        path = managed(root, folder / 'run.json')
        if args.command == 'init':
            starter(root, args.id)
            return 0
        if args.command == 'plan':
            if path.exists():
                raise ValueError('run already exists')
            packet_path = Path(args.packet).resolve()
            obj = packet(root, packet_path)
            base = git_bytes(root, 'rev-parse', '--verify', args.base + '^{commit}').decode().strip()
            run = {'version': 1, 'id': args.id, 'base': base, 'packet': obj, 'runners': preflight(root, obj), 'reviews': []}
            if obj.get('version') == 2:
                run['feature_sha256'] = feature(root, obj['feature'])[0]
                run['packet_source'] = str(packet_path)
                run['packet_file_sha256'] = digest(packet_path.read_bytes())
            run['packet_sha256'] = identity(run)
            save(path, run)
            print(render(root, folder, run, True), end='')
            return 0
        run = load(path)
        if run['id'] != args.id or identity(run) != run['packet_sha256']:
            raise ValueError('invalid run identity')
        if args.command == 'preflight':
            print(json.dumps(preflight(root, run['packet']), indent=2))
        elif args.command == 'approve':
            if args.packet_sha256 != run['packet_sha256'] or not current_inputs(root, run):
                raise ValueError('approval does not match the current packet and runners')
            run['approval'] = args.packet_sha256
            save(path, run)
            print('Gate 1 owner decision recorded locally (not a signature)')
        elif args.command in ('baseline', 'candidate'):
            if run.get('approval') != run['packet_sha256']:
                raise ValueError('Gate 1 owner approval required before collection')
            collect(root, folder, run, args.command)
            print(folder / args.command / 'manifest.json')
        elif args.command == 'review':
            if len(run['reviews']) >= 3 or (run['reviews'] and run['reviews'][-1]['verdict'] == 'pass'):
                raise ValueError('automatic review budget exhausted or review already passed')
            candidate, _ = evidence(root, folder, run, 'candidate')
            if not candidate:
                raise ValueError('review requires current candidate evidence')
            if args.verdict == 'pass' and any(x['status'] != 'passed' for x in candidate['results']):
                raise ValueError('review cannot pass failed candidate checks')
            run['reviews'].append({'verdict': args.verdict, 'finding': args.finding,
                                   'candidate_sha256': digest(canonical(candidate))})
            save(path, run)
            print('review recorded')
        else:
            print(render(root, folder, run), end='')
        return 0
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print('run error: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
