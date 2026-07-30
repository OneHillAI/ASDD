"""Locate the openspec CLI beyond PATH.

An adopter who runs `npm install -g @fission-ai/openspec` gets the binary in npm's global bin, which is
frequently NOT on a non-login shell's PATH (a common default is `~/.npm-global/bin`). A bare PATH lookup
(`shutil.which`) then reports "not installed" when the tool is merely unreachable - the exact trap this
avoids. We search PATH first, then npm's own reported global bin, then the common global-bin locations,
so a caller can tell three states apart: reachable, installed-but-off-PATH, and genuinely absent.

Zero-dependency (stdlib). Shared by cli/openspec-gate.py (the gate) and cli/doctor.py (the preflight).
"""
import os
import shutil
import subprocess


def _npm_global_bin():
    """npm's own reported global bin dir, or None if npm is unavailable."""
    try:
        p = subprocess.run(["npm", "prefix", "-g"], capture_output=True, text=True, timeout=8)
    except Exception:
        return None
    pref = (p.stdout or "").strip()
    return os.path.join(pref, "bin") if pref else None


def _candidate_dirs():
    """Directories to search after PATH, most authoritative first, de-duplicated."""
    dirs = []
    # A colon-separated override, mainly a test hook but also an explicit escape hatch.
    env = os.environ.get("ASDD_OPENSPEC_SEARCH")
    if env:
        dirs += [d for d in env.split(os.pathsep) if d]
    g = _npm_global_bin()
    if g:
        dirs.append(g)
    home = os.path.expanduser("~")
    dirs += [
        os.path.join(home, ".npm-global", "bin"),
        os.path.join(home, ".npm", "bin"),
        os.path.join(home, ".local", "bin"),
        "/usr/local/bin",
        "/opt/homebrew/bin",
    ]
    seen, out = set(), []
    for d in dirs:
        if d and d not in seen:
            seen.add(d)
            out.append(d)
    return out


def locate(binary="openspec"):
    """Return (path, on_path).

    path is the executable's absolute path, or None if it is not found anywhere. on_path is True when
    PATH alone resolves it, so a caller can distinguish "reachable" from "installed but PATH must be
    fixed" from "absent" (path is None).
    """
    on_path = shutil.which(binary)
    if on_path:
        return on_path, True
    for d in _candidate_dirs():
        cand = os.path.join(d, binary)
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand, False
    return None, False
