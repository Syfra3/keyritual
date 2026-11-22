#!/usr/bin/env python3
"""Validate the current branch's Tier 2 entry spec; does not activate the cage."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys


REQUIRED = (
    'Problem', 'Minimum change', 'Cross-service view',
    'Internal state / module view', 'Affected contracts', 'Negative invariants',
    'Approved implementation scope', 'Frozen checks and human approval',
    'Resume context',
)
PLACEHOLDER = re.compile(
    r'\b(?:todo|tbd|fixme|placeholder|pending|undecided|lorem ipsum|'
    r'fill\s+(?:this|in)|not\s+(?:yet\s+)?(?:specified|provided|determined)|'
    r'to\s+be\s+(?:determined|filled|provided))\b|<[^>]+>|\[\s*(?:\.\.\.|x?\s*)\]|\.{3,}',
    re.IGNORECASE,
)


def git(root, *args):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0', GIT_NO_LAZY_FETCH='1',
               GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)
    return subprocess.run(['git', '-C', str(root), '-c', 'core.fsmonitor=false',
                           '-c', 'core.hooksPath=/dev/null', *args],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, env=env, check=False)


def run_dir(root):
    """Return the absolute run directory for root's current branch or detached HEAD.

    Branch identities include a digest of the full ref, avoiding slug collisions.
    Detached identities include the full commit digest. No files are created.
    """
    root = Path(root).resolve()
    top = git(root, 'rev-parse', '--show-toplevel')
    if top.returncode or Path(top.stdout.strip()).resolve() != root:
        raise ValueError('--root must be the Git working-tree root')
    ref = git(root, 'symbolic-ref', '--quiet', 'HEAD')
    if ref.returncode == 0:
        identity = ref.stdout.strip()
        name = identity.removeprefix('refs/heads/')
        slug = re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')[:40].strip('-') or 'branch'
        safe = slug + '-' + hashlib.sha256(identity.encode()).hexdigest()[:16]
    else:
        head = git(root, 'rev-parse', '--verify', 'HEAD')
        if head.returncode:
            raise ValueError('cannot identify branch or detached HEAD')
        safe = 'detached-' + head.stdout.strip()
    return root / '.a2e' / 'runs' / safe


def validate_spec(path):
    """Return validation errors for the required Markdown sections in path."""
    try:
        text = path.read_text(encoding='utf-8')
    except (OSError, UnicodeError) as exc:
        return [f'cannot read spec: {exc}']
    sections = {}
    current = None
    fenced = False
    for line in text.splitlines():
        if line.lstrip().startswith('```'):
            fenced = not fenced
        match = re.fullmatch(r'##\s+(.+?)\s*#*\s*', line) if not fenced else None
        if match:
            current = match.group(1).strip()
            sections.setdefault(current, []).append([])
        elif current is not None:
            sections[current][-1].append(line)
    errors = []
    for heading in REQUIRED:
        occurrences = sections.get(heading, [])
        if len(occurrences) != 1:
            errors.append(f'{heading}: expected exactly one section')
            continue
        body = '\n'.join(occurrences[0]).strip()
        meaningful = re.sub(r'```[^\n]*|<!--.*?-->|[\s\-*:|#`]', '', body, flags=re.DOTALL)
        if (not meaningful or PLACEHOLDER.search(body)
                or re.fullmatch(r'\s*(?:n/?a|none|unknown|-)\s*', body, re.IGNORECASE)):
            errors.append(f'{heading}: missing content or placeholder')
        elif heading in ('Cross-service view', 'Internal state / module view'):
            if not re.search(r'```mermaid\s*\n[\s\S]*?\n```', body, re.IGNORECASE):
                errors.append(f'{heading}: requires a Mermaid diagram')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, help='Git working-tree root')
    args = parser.parse_args()
    try:
        spec = run_dir(args.root) / 'spec.md'
    except (ValueError, OSError) as exc:
        print(f'Tier 2 entry denied: {exc}', file=sys.stderr)
        return 1
    errors = validate_spec(spec)
    if errors:
        print(f'Tier 2 entry denied: {spec}', file=sys.stderr)
        for error in errors:
            print(f'- {error}', file=sys.stderr)
        return 1
    print(f'Tier 2 spec valid: {spec}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
