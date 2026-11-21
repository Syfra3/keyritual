"""Host-neutral edit cage policy. This is not a sandbox."""
from pathlib import Path
import stat


def protected_path(parts):
    lower = [p.lower() for p in parts]
    base = lower[-1]
    protected = {'package.json', 'package-lock.json', 'npm-shrinkwrap.json', 'pnpm-lock.yaml', 'yarn.lock', 'bun.lock', 'bun.lockb', 'go.mod', 'go.sum', 'cargo.toml', 'cargo.lock', 'pyproject.toml', 'poetry.lock', 'pdm.lock', 'uv.lock', 'requirements.txt', 'pipfile', 'pipfile.lock', 'gemfile', 'gemfile.lock', 'composer.json', 'composer.lock', 'podfile', 'podfile.lock', 'gradlew', 'gradlew.bat', 'gradle.properties', 'gradle-wrapper.properties', 'gradle-wrapper.jar', 'gradle.lockfile', 'libs.versions.toml', '.cage-active', '.cage-scope', 'agents.md'}
    controls = {('scripts', name) for name in ('aaed.py', 'a2e_entry.py', 'a2e_collect.py', 'a2e_review.py', 'a2e_signoff.py', 'a2e_cage.py', 'a2e_install.py')}
    return (tuple(lower) in controls
            or any(p in ('tests', 'test', '__tests__', '.claude', '.a2e', '.maestro', 'gradle') for p in lower)
            or base in protected or base.endswith(('.gradle', '.gradle.kts', '.podspec')) or '.test.' in base or '.spec.' in base
            or '_test.' in base or base.startswith('test_') or base.endswith('_test.py')
            or base.startswith('requirements') and base.endswith('.txt'))


def check_edit(root, active, raw):
    """Return (allowed, reason); root and target are supplied by the host."""
    if not active:
        return True, ''
    try:
        root = Path(root)
        if not root.is_absolute():
            return False, 'invalid root'
        root = root.resolve()
        if not isinstance(raw, str) or not raw or '\x00' in raw or any(p == '..' for p in Path(raw).parts):
            return False, 'ambiguous path'
        target = Path(raw)
        if not target.is_absolute():
            return False, 'edit target must be absolute'
        parts = target.relative_to(root).parts
        if not parts or protected_path(parts):
            return False, 'protected path'
        component = root
        for part in parts:
            component = component / part
            try:
                mode = component.lstat().st_mode
            except FileNotFoundError:
                continue
            if stat.S_ISLNK(mode):
                return False, 'symlink edit target component'
        target = target.resolve()
        canonical_parts = target.relative_to(root).parts
        if not canonical_parts or protected_path(canonical_parts):
            return False, 'protected path'
        scope = root / '.cage-scope'
        if scope.exists():
            lines = [x.strip() for x in scope.read_text().splitlines() if x.strip() and not x.lstrip().startswith('#')]
            allowed = []
            for line in lines:
                p = Path(line)
                if p.is_absolute() or '..' in p.parts or not p.parts:
                    return False, 'invalid scope'
                candidate = (root / p).resolve()
                candidate.relative_to(root)
                allowed.append(candidate)
            if not any(target == p or p in target.parents for p in allowed):
                return False, 'outside scope'
        return True, ''
    except (ValueError, KeyError, TypeError, OSError, RuntimeError):
        return False, 'malformed target or outside root'
