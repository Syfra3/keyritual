#!/usr/bin/env python3
"""Offline local evidence review. No collectors or publication are invoked."""
import argparse
import html
import json
from pathlib import Path
import sys

from a2e_collect import canonical, digest, validate_consumer, validate_historical_before
from a2e_entry import run_dir

IMAGE_SUFFIXES = {'.png', '.jpg', '.jpeg', '.gif', '.webp'}


def visual_pairs(root, after_path, config='.a2e/evidence.yaml', base='HEAD'):
    """Return validated visual references and gaps; hashes do not prove origin."""
    root = Path(root).resolve()
    after = validate_consumer(root, after_path, config, base)
    if after['phase'] != 'after':
        raise ValueError('current manifest must be after phase')
    run = run_dir(root)
    try:
        before = validate_historical_before(root, run / 'before' / 'manifest.json', config, base)
    except (OSError, ValueError, KeyError, TypeError):
        before = None
    previous = {item['id']: item for item in before['collectors']} if before else {}
    pairs, gaps = [], []
    for item in after['collectors']:
        if item['category'].lower() != 'visual' or item['status'] == 'SKIPPED':
            continue
        prior = previous.get(item['id'])
        if item['status'] != 'PASS' or not prior or prior['status'] != 'PASS':
            gaps.append(item['id'] + ': missing validated passing visual before/after')
            continue
        def images(entry):
            return {a['path'].split('/', 1)[-1]: a for a in entry['artifacts']
                    if Path(a['path']).suffix.lower() in IMAGE_SUFFIXES}
        old, new = images(prior), images(item)
        names = sorted(set(old) | set(new))
        if not names:
            gaps.append(item['id'] + ': no listed visual artifacts')
        for name in names:
            if name not in old or name not in new:
                gaps.append(item['id'] + ': missing visual pair for ' + name)
            else:
                pairs.append({'collector': item['id'], 'name': name,
                              'before': str((run / 'before' / old[name]['path']).relative_to(root)),
                              'after': str((run / 'after' / new[name]['path']).relative_to(root)),
                              'before_sha256': old[name]['sha256'],
                              'after_sha256': new[name]['sha256']})
    return pairs, gaps


def sibling_candidates(root, requests):
    """Search explicitly listed repository files, bounded; results are candidates only."""
    if not isinstance(requests, list) or len(requests) > 20:
        raise ValueError('siblings must be a list of at most 20 file/symbol requests')
    found, sources = [], []
    for request in requests:
        if not isinstance(request, dict) or set(request) != {'file', 'symbol'}:
            raise ValueError('invalid sibling request')
        name, symbol = request['file'], request['symbol']
        if not isinstance(name, str) or not isinstance(symbol, str) or not symbol or len(symbol) > 200:
            raise ValueError('invalid sibling file or symbol')
        path = Path(name)
        if path.is_absolute() or '..' in path.parts or not path.parts:
            raise ValueError('sibling file must be repository-relative')
        file = root / path
        if not file.resolve().is_relative_to(root) or not file.is_file() or file.stat().st_size > 262144:
            raise ValueError('invalid or oversized sibling file')
        data = file.read_bytes()
        sources.append({'file': name, 'sha256': digest(data)})
        for number, line in enumerate(data.decode('utf-8').splitlines(), 1):
            if symbol in line and len(found) < 100:
                found.append({'file': name, 'line': number, 'symbol': symbol})
    return found, sources


def report_snapshot(root, after_path, annotations, siblings, config='.a2e/evidence.yaml', base='HEAD'):
    """Build private snapshot and digest for a future signoff consumer, not an attestation."""
    root = Path(root).resolve()
    after = validate_consumer(root, after_path, config, base)
    if after['phase'] != 'after':
        raise ValueError('current manifest must be after phase')
    if not isinstance(annotations, list) or len(annotations) > 100:
        raise ValueError('annotations must be a list of at most 100 entries')
    for item in annotations:
        if (not isinstance(item, dict) or set(item) != {'classification', 'expected', 'observed', 'reason'}
                or item['classification'] not in ('new', 'modified', 'unexpected', 'unknown')
                or not all(isinstance(item[k], str) and item[k] for k in ('expected', 'observed', 'reason'))):
            raise ValueError('invalid architecture annotation; use unknown for missing values')
    pairs, gaps = visual_pairs(root, after_path, config, base)
    try:
        before = validate_historical_before(root, run_dir(root) / 'before/manifest.json', config, base)
    except (OSError, ValueError, KeyError, TypeError):
        before = None
    prior = {x['id']: x for x in before['collectors']} if before else {}
    metrics = []
    for item in after['collectors']:
        old = prior.get(item['id'], {})
        comparable = item['status'] in ('PASS', 'REGRESSION') and old.get('status') == 'PASS'
        metrics.append({'id': item['id'], 'status': item['status'], 'required': item['required'],
                        'before': old.get('metric') if comparable else None,
                        'after': item.get('metric'),
                        'delta': item['metric'] - old['metric'] if comparable else None})
    candidates, sources = sibling_candidates(root, siblings)
    snapshot = {'version': 1, 'state': after['state'], 'config_sha256': after['config_sha256'],
                'scripts': after['scripts'], 'current_manifest_sha256': digest(Path(after_path).read_bytes()),
                'before_manifest_sha256': digest((run_dir(root) / 'before/manifest.json').read_bytes()) if before else None,
                'metrics': metrics, 'visual_pairs': pairs, 'gaps': gaps,
                'annotations': annotations, 'sibling_requests': siblings,
                'sibling_candidates': candidates, 'sibling_sources': sources}
    return snapshot, digest(canonical(snapshot))


def render(snapshot, output_format):
    # Escape all dynamic text as HTML entities and Markdown punctuation. No links are
    # activated: local artifact paths are references, not published asset URLs.
    def esc(value):
        text = html.escape(str(value), quote=True)
        return ''.join(' ' if ord(c) < 32 else ('\\' + c if c in r'\\`*_{}[]()#!|>~' else c) for c in text)
    lines = ['# Local PR evidence preview', '', 'Evidence hashes detect changes, not origin or truth.',
             '', '## Metrics (before, after, delta)']
    for m in snapshot['metrics']:
        lines.append('- ' + esc(m['id']) + ': ' + esc(m['status']) + '; ' +
                     ', '.join(esc(m[k] if m[k] is not None else 'unknown') for k in ('before', 'after', 'delta')))
    lines += ['', '## Visual references']
    for p in snapshot['visual_pairs']:
        lines.append('- ' + esc(p['collector']) + ' / ' + esc(p['name']) + ': before ' + esc(p['before']) + ' (SHA-256 ' + esc(p['before_sha256']) + '); after ' + esc(p['after']) + ' (SHA-256 ' + esc(p['after_sha256']) + ')')
    for gap in snapshot['gaps']:
        lines.append('- Gap: ' + esc(gap))
    lines += ['', '## Defensive architecture (human annotations; unverified)']
    if not snapshot['annotations']:
        lines.append('- Unknown: no annotations supplied.')
    for a in snapshot['annotations']:
        lines.append('- ' + '; '.join(esc(k) + ': ' + esc(a[k]) for k in ('classification', 'expected', 'observed', 'reason')))
    lines += ['', '## Sibling candidates (not verified compatibility)']
    if not snapshot['sibling_candidates']:
        lines.append('- Unknown: no candidates found.')
    for c in snapshot['sibling_candidates']:
        lines.append('- ' + esc(c['file']) + ':' + str(c['line']) + ' — ' + esc(c['symbol']))
    text = '\n'.join(lines) + '\n'
    return text if output_format == 'markdown' else '<!doctype html><html><body><pre>' + html.escape(text) + '</pre></body></html>\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True)
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--base', required=True)
    parser.add_argument('--config', default='.a2e/evidence.yaml')
    parser.add_argument('--annotations', help='local JSON array of human annotations')
    parser.add_argument('--siblings', help='local JSON array of file/symbol requests')
    parser.add_argument('--format', choices=('markdown', 'html'), default='markdown')
    args = parser.parse_args()
    try:
        annotations = json.loads(Path(args.annotations).read_text()) if args.annotations else []
        siblings = json.loads(Path(args.siblings).read_text()) if args.siblings else []
        snapshot, _ = report_snapshot(args.root, args.manifest, annotations, siblings, args.config, args.base)
        sys.stdout.write(render(snapshot, args.format))
        return 0
    except (OSError, ValueError, KeyError, TypeError, UnicodeError) as exc:
        print('review error: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
