#!/usr/bin/env python3
"""Offline Gate 3 checklist and human-attested local PR preview; no publication."""
import argparse
import json
from pathlib import Path
import sys

from a2e_collect import canonical, digest
from a2e_entry import run_dir, validate_spec
from a2e_review import report_snapshot


def load(path, default):
    return json.loads(Path(path).read_text(encoding='utf-8')) if path else default


def checklist(root, manifest, base, config, annotations, siblings, audit_findings):
    root = Path(root).resolve()
    spec = run_dir(root) / 'spec.md'
    errors = validate_spec(spec)
    if errors:
        raise ValueError('invalid spec: ' + '; '.join(errors))
    spec_hash = digest(spec.read_bytes())
    snapshot, report_hash = report_snapshot(root, manifest, annotations, siblings, config, base)
    if not isinstance(audit_findings, list):
        raise ValueError('audit findings must be a list')
    findings = []
    ids = set()
    for item in audit_findings:
        if (not isinstance(item, dict) or set(item) != {'id', 'required', 'status', 'description'}
                or not isinstance(item['id'], str) or not item['id'].strip() or item['id'] in ids
                or type(item['required']) is not bool or item['status'] not in ('open', 'resolved')
                or not isinstance(item['description'], str) or not item['description'].strip()):
            raise ValueError('invalid audit finding')
        ids.add(item['id'])
        if item['required'] and item['status'] == 'open':
            findings.append({'id': 'audit:' + item['id'], 'status': 'open'})
    for item in snapshot['metrics']:
        if item['required'] and item['status'] not in ('PASS', 'SKIPPED'):
            findings.append({'id': 'collector:' + item['id'], 'status': item['status']})
    for gap in snapshot['gaps']:
        findings.append({'id': 'visual:' + digest(gap.encode()), 'status': 'GAP'})
    payload = {'version': 1, 'spec_sha256': spec_hash, 'report_sha256': report_hash,
               'audit_findings_sha256': digest(canonical(audit_findings)), 'findings': findings}
    identity = digest(canonical(payload))
    paths = snapshot['state']['paths']
    boundary = ', '.join(json.dumps(path, ensure_ascii=True) for path in paths) if paths else '(no changed paths)'
    return {'snapshot_sha256': identity, **payload,
            'questions': [f'How do changes at {boundary} satisfy the spec invariants?',
                          f'What evidence supports the behavior and limitations of {boundary}?']}


def verify(check, attestation):
    if not isinstance(attestation, dict) or set(attestation) != {
            'snapshot_sha256', 'human', 'spec_sync_confirmed', 'answers', 'waivers'}:
        raise ValueError('invalid attestation fields')
    if attestation['snapshot_sha256'] != check['snapshot_sha256']:
        raise ValueError('stale attestation snapshot')
    if not isinstance(attestation['human'], str) or not attestation['human'].strip():
        raise ValueError('human identification required')
    if attestation['spec_sync_confirmed'] is not True:
        raise ValueError('human spec sync confirmation required')
    answers = attestation['answers']
    if (not isinstance(answers, list) or len(answers) != len(check['questions']) or
            any(not isinstance(a, str) or not a.strip() for a in answers)):
        raise ValueError('human comprehension answers required')
    waivers = attestation['waivers']
    if not isinstance(waivers, list):
        raise ValueError('waivers must be a list')
    expected = {f['id'] for f in check['findings']}
    seen = set()
    for w in waivers:
        if (not isinstance(w, dict) or set(w) != {'snapshot_sha256', 'finding_id', 'reason'}
                or w['snapshot_sha256'] != check['snapshot_sha256']
                or not isinstance(w['finding_id'], str) or w['finding_id'] not in expected
                or w['finding_id'] in seen or not isinstance(w['reason'], str) or not w['reason'].strip()):
            raise ValueError('invalid, stale, duplicate or unscoped waiver')
        seen.add(w['finding_id'])
    if seen != expected:
        raise ValueError('unresolved required findings: ' + ', '.join(sorted(expected - seen)))


def preview(check):
    # Deliberately omit human free text, source locations, local paths and artifact URLs.
    return ('# Decision & Evidence Record — local PR preview\n\n'
            'Human attestation recorded locally; this is not a signature or proof of comprehension.\n\n'
            '- Snapshot SHA-256: ' + check['snapshot_sha256'] + '\n'
            '- Spec SHA-256: ' + check['spec_sha256'] + '\n'
            '- Validated report SHA-256: ' + check['report_sha256'] + '\n'
            '- Required findings waived: ' + str(len(check['findings'])) + '\n\n'
            'No local evidence references, source lines, raw logs, or assets are included. '
            'Review this preview and publish manually if appropriate.\n')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', required=True)
    p.add_argument('--manifest', required=True)
    p.add_argument('--base', required=True)
    p.add_argument('--config', default='.a2e/evidence.yaml')
    p.add_argument('--annotations')
    p.add_argument('--siblings')
    p.add_argument('--findings', required=True, help='local JSON array of auditor findings (may be empty)')
    p.add_argument('--attestation', help='explicit local JSON attestation; omit for checklist')
    p.add_argument('--record', action='store_true', help='emit private decision record JSON instead of public-safe Markdown')
    args = p.parse_args()
    try:
        check = checklist(args.root, args.manifest, args.base, args.config,
                          load(args.annotations, []), load(args.siblings, []), load(args.findings, None))
        if args.attestation:
            attestation = load(args.attestation, None)
            verify(check, attestation)
            if args.record:
                print(json.dumps({'checklist': check, 'human_attestation': attestation,
                                  'notice': 'Human attestation, not a cryptographic signature.'}, indent=2))
            else:
                sys.stdout.write(preview(check))
        else:
            if args.record:
                raise ValueError('--record requires an attestation')
            print(json.dumps(check, indent=2))
        return 0
    except (OSError, ValueError, KeyError, TypeError, UnicodeError) as exc:
        print('signoff denied: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
