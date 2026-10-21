#!/usr/bin/env bash
# Test for install.sh. Exit 0 iff every expectation holds.
#
# SAFETY. install.sh deletes directories, so this test never lets it near real files:
#   1. Everything happens under one fresh temp root ($T). HOME, TMPDIR, --prefix and --bin-dir all point inside it.
#   2. Every `rm` the installer runs goes through a shim that refuses any operand outside $T and records the attempt.
#   3. On macOS the installer runs under sandbox-exec with file-write* denied outside $T, checked by a probe first.
#      Set ASDD_REQUIRE_OS_SANDBOX=1 to refuse to run without it (install.mutation.sh does).
#   4. The only recursive delete here removes $T itself, and only after proving it is the sentinel-marked temp root
#      this run created. There is no `rm -rf "$VAR"` on an unchecked variable anywhere in this file.
# ASDD_INSTALL_SH points the test at another copy of the installer (install.mutation.sh uses this).
set -u
DIR=$(cd "$(dirname "$0")" && pwd -P)
INSTALL=${ASDD_INSTALL_SH:-$DIR/install.sh}
SENTINEL=.asdd-install-test-root

[ -f "$INSTALL" ] || { echo "install.test.sh: no installer at $INSTALL"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "install.test.sh: python3 is required"; exit 2; }

realpath_py() { python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

# ---- the sandbox root -------------------------------------------------------------------------------------------
MADE=$(mktemp -d "${TMPDIR:-/tmp}/asdd-install-test.XXXXXX") || { echo "install.test.sh: cannot create a temp dir"; exit 2; }
[ -n "$MADE" ] && [ -d "$MADE" ] && [ ! -L "$MADE" ] || { echo "install.test.sh: temp dir is not usable: '$MADE'"; exit 2; }
T=$(realpath_py "$MADE")
case "$T" in /*/asdd-install-test.??????) ;; *) echo "install.test.sh: unexpected temp root '$T'"; exit 2 ;; esac
: >"$T/$SENTINEL" || { echo "install.test.sh: cannot write the sentinel"; exit 2; }
mkdir "$T/home" "$T/tmp" "$T/shim" "$T/h" "$T/rel"

# shellcheck disable=SC2329  # runs from the EXIT trap
cleanup_root() {
  # Remove $T only if it is still exactly the directory this run made.
  [ -n "${T:-}" ] && [ -d "$T" ] && [ ! -L "$T" ] && [ -f "$T/$SENTINEL" ] || return 0
  case "$T" in /*/asdd-install-test.??????) ;; *) return 0 ;; esac
  [ "$T" != "/" ] && [ "$T" != "${HOME:-/}" ] || return 0
  rm -rf -- "$T"
}
trap cleanup_root EXIT

cat >"$T/shim/rm" <<'SHIM'
#!/bin/sh
# Test shim: refuse any rm operand that resolves outside the sandbox root, and record the attempt.
for a in "$@"; do
  case "$a" in -*) continue ;; esac
  r=$(/usr/bin/python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$a" 2>/dev/null || echo "?")
  case "$r" in
    "$ASDD_TEST_ROOT"/*) ;;
    *) echo "rm $a -> $r" >>"$ASDD_TEST_ROOT/violations"; echo "rm: blocked, outside the test sandbox: $r" >&2; exit 99 ;;
  esac
done
exec /bin/rm "$@"
SHIM
chmod 755 "$T/shim/rm"

# ---- OS-level sandbox (macOS) -----------------------------------------------------------------------------------
SBX=()
if [ "$(uname -s)" = Darwin ] && command -v sandbox-exec >/dev/null 2>&1; then
  PROFILE="(version 1)(allow default)(deny file-write* (require-not (require-any (subpath \"$T\") (subpath \"/dev\"))))"
  probe="$(dirname "$T")/asdd-sandbox-probe.$$"
  sandbox-exec -p "$PROFILE" /bin/sh -c "echo x > '$probe'" >/dev/null 2>&1
  if [ -e "$probe" ]; then
    rm -f -- "$probe"; echo "install.test.sh: the OS sandbox did not block a write outside the root; refusing to run"; exit 2
  fi
  SBX=(sandbox-exec -p "$PROFILE")
fi
if [ "${ASDD_REQUIRE_OS_SANDBOX:-0}" = 1 ] && [ ${#SBX[@]} -eq 0 ]; then
  echo "install.test.sh: ASDD_REQUIRE_OS_SANDBOX=1 but no OS sandbox is available here"; exit 2
fi

EXTRA_ENV=()
BASE_URL_FOR_RUN=""
# inst ARGS... : run the installer isolated. Sets OUT (stdout+stderr) and RC.
inst() {
  OUT=$("${SBX[@]+"${SBX[@]}"}" env -i HOME="$T/home" PATH="$T/shim:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$T/tmp" \
        ASDD_TEST_ROOT="$T" ASDD_BASE_URL="${BASE_URL_FOR_RUN:-file://$T/rel}" "${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"}" \
        /bin/sh "$INSTALL" "$@" 2>&1)
  RC=$?
}
# sbxrun CMD... : run something else (a launcher) with the same isolation.
sbxrun() {
  "${SBX[@]+"${SBX[@]}"}" env -i HOME="$T/home" PATH="$T/shim:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$T/tmp" ASDD_TEST_ROOT="$T" "$@" 2>&1
}

# mkrel RELDIR VERSION [MODE] : publish a fake release under $T/rel/RELDIR.
mkrel() {
  python3 -I - "$T/rel/$1" "$2" "${3:-good}" <<'PY'
import hashlib, io, os, sys, tarfile
d, v, mode = sys.argv[1:4]
os.makedirs(d, exist_ok=True)
shown = "9.9.9" if mode == "wrongcli" else v
cli = ('__version__ = "%s"\nimport sys\nif len(sys.argv) > 1 and sys.argv[1] in ("-V", "--version"):\n'
       '    print("asdd %s")\n' % (v, shown)).encode()
def add(tf, name, data=b"", mode_=0o644, typ=tarfile.REGTYPE, link=""):
    ti = tarfile.TarInfo(name); ti.size = len(data) if typ == tarfile.REGTYPE else 0
    ti.mode = mode_; ti.type = typ; ti.linkname = link
    tf.addfile(ti, io.BytesIO(data) if typ == tarfile.REGTYPE else None)
path = os.path.join(d, "asdd-kit.tar.gz")
with tarfile.open(path, "w:gz") as tf:
    top = "asdd-" + v
    add(tf, top + "/asdd_cli.py", cli, 0o755)
    add(tf, top + "/README", b"fake kit\n")
    if mode == "dotdot":   add(tf, top + "/../../escaped", b"x")
    if mode == "absolute": add(tf, "/escaped", b"x")
    if mode == "symlink":  add(tf, top + "/link", typ=tarfile.SYMTYPE, link="/etc/passwd")
    if mode == "twotops":  add(tf, "other/file", b"x")
digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
if mode == "badsum": digest = "0" * 64
if mode == "nosum":
    if os.path.exists(path + ".sha256"): os.unlink(path + ".sha256")
else:
    open(path + ".sha256", "w").write(digest + "  asdd-kit.tar.gz\n")
PY
}

# snap DIR : a fingerprint of everything under DIR (names and contents).
snap() { ( cd "$1" 2>/dev/null && { find . -print | LC_ALL=C sort; find . -type f -exec cksum {} + | LC_ALL=C sort; } ) 2>/dev/null; }

fail=0; n=0
ok()  { n=$((n + 1)); printf '  ok   %s\n' "$*"; }
bad() { n=$((n + 1)); fail=1; printf '  FAIL %s\n' "$*"; }
newhome() { H="$T/h/$1"; mkdir -p "$H"; }
refused_untouched() { # label before-snapshot : RC!=0, H unchanged, optional message regex in $3
  local label=$1 before=$2 msg=${3:-}
  if [ "$RC" = 0 ]; then bad "$label was accepted (rc=0): $OUT"; return; fi
  if [ "$(snap "$H")" != "$before" ]; then bad "$label changed files before refusing: $OUT"; return; fi
  if [ -n "$msg" ] && ! printf '%s' "$OUT" | grep -qE "$msg"; then bad "$label was refused without the expected message /$msg/: $OUT"; return; fi
  ok "$label"
}

echo "install.sh tests (sandbox root: $T; OS sandbox: $([ ${#SBX[@]} -gt 0 ] && echo on || echo 'off, rm shim only'))"

# 1. pinned install
newhome pin; mkrel download/v1.2.3 1.2.3
inst install --version 1.2.3 --prefix "$H/p" --bin-dir "$H/bin"
if [ "$RC" = 0 ] && [ "$(sbxrun "$H/bin/asdd" --version)" = "asdd 1.2.3" ] \
   && [ -L "$H/p/current" ] && [ "$(readlink "$H/p/current")" = "versions/1.2.3" ] && [ -f "$H/p/versions/1.2.3/.asdd-install" ]; then
  ok "a pinned version installs, links, and runs"
else bad "pinned install failed (rc=$RC): $OUT"; fi
left=0; for d in "$T"/tmp/asdd-install.*; do [ -e "$d" ] && left=1; done
if [ "$left" = 1 ]; then bad "the installer left its scratch directory behind"; else ok "scratch directory is cleaned up"; fi

# 2. latest, upgrade, idempotence
mkrel latest/download 1.2.5
inst install --prefix "$H/p" --bin-dir "$H/bin"
if [ "$RC" = 0 ] && [ "$(sbxrun "$H/bin/asdd" --version)" = "asdd 1.2.5" ] && [ -d "$H/p/versions/1.2.3" ] && [ -d "$H/p/versions/1.2.5" ]; then
  ok "no --version installs the latest, keeps the older version, and moves 'current'"
else bad "latest install failed (rc=$RC): $OUT"; fi
inst install --version 1.2.3 --prefix "$H/p" --bin-dir "$H/bin"
if [ "$RC" = 0 ] && [ "$(sbxrun "$H/bin/asdd" --version)" = "asdd 1.2.3" ]; then ok "re-installing an installed version replaces it cleanly"; else bad "re-install failed (rc=$RC): $OUT"; fi

# 3. defaults live under HOME
newhome defaults
inst install --version 1.2.3
if [ "$RC" = 0 ] && [ -x "$T/home/.local/bin/asdd" ] && [ -d "$T/home/.asdd/versions/1.2.3" ]; then ok "defaults are \$HOME/.asdd and \$HOME/.local/bin"; else bad "default locations wrong (rc=$RC): $OUT"; fi
inst uninstall
if [ "$RC" = 0 ] && [ ! -e "$T/home/.asdd" ] && [ ! -e "$T/home/.local/bin/asdd" ]; then ok "uninstall removes what install made, including the empty prefix"; else bad "uninstall left files (rc=$RC): $OUT"; fi

# 4. GitHub Actions PATH
newhome gha
EXTRA_ENV=("GITHUB_PATH=$H/ghpath"); inst install --version 1.2.3 --prefix "$H/p" --bin-dir "$H/bin"; EXTRA_ENV=()
if [ "$RC" = 0 ] && grep -qxF "$H/bin" "$H/ghpath"; then ok "the bin dir is appended to \$GITHUB_PATH"; else bad "GITHUB_PATH not updated (rc=$RC): $OUT"; fi

# 5. archive and checksum refusals leave everything untouched
#    Each case must be refused by the installer's own check (its message), not merely by tar failing later.
for spec in "badsum:checksum mismatch" "nosum:download failed" "dotdot:unsafe path" "absolute:unsafe path" \
            "symlink:contains links" "twotops:single top-level" "wrongcli:refusing to install"; do
  mode=${spec%%:*}; msg=${spec#*:}
  newhome "mode-$mode"; mkrel download/v2.0.0 2.0.0 "$mode"; before=$(snap "$H")
  inst install --version 2.0.0 --prefix "$H/p" --bin-dir "$H/bin"
  refused_untouched "a '$mode' release is refused ($msg)" "$before" "$msg"
done
newhome mismatch; mkrel download/v2.0.1 2.0.0; before=$(snap "$H")
inst install --version 2.0.1 --prefix "$H/p" --bin-dir "$H/bin"
refused_untouched "a release holding a different version than asked is refused" "$before" "asked for 2.0.1"
if [ ! -e "$T/escaped" ] && [ ! -e "$T/rel/escaped" ]; then ok "nothing was extracted outside the scratch directory"; else bad "an unsafe archive wrote outside its directory"; fi

# 6. things the installer does not own
newhome foreign-bin; mkdir -p "$H/bin"; printf '#!/bin/sh\necho mine\n' >"$H/bin/asdd"; chmod 755 "$H/bin/asdd"; before=$(snap "$H")
inst install --version 1.2.3 --prefix "$H/p" --bin-dir "$H/bin"
refused_untouched "an existing foreign 'asdd' is not overwritten" "$before" "not created by asdd-install"
newhome foreign-dir; mkdir -p "$H/p/versions/1.2.3"; echo precious >"$H/p/versions/1.2.3/keep"; before=$(snap "$H")
inst install --version 1.2.3 --prefix "$H/p" --bin-dir "$H/bin"
refused_untouched "an existing unmarked version directory is not replaced" "$before" "not created by asdd-install"
newhome foreign-current; mkdir -p "$H/p/current"; echo precious >"$H/p/current/keep"; before=$(snap "$H")
inst install --version 1.2.3 --prefix "$H/p" --bin-dir "$H/bin"
refused_untouched "a real directory named 'current' is not replaced" "$before" "not a link"
newhome uninstall-foreign
inst install --version 1.2.3 --prefix "$H/p" --bin-dir "$H/bin"
mkdir -p "$H/p/versions/9.9.9"; echo precious >"$H/p/versions/9.9.9/keep"; mkdir -p "$H/p/versions/not-a-version"; echo precious >"$H/p/versions/not-a-version/keep"
inst uninstall --prefix "$H/p" --bin-dir "$H/bin"
if [ "$RC" = 0 ] && [ -f "$H/p/versions/9.9.9/keep" ] && [ -f "$H/p/versions/not-a-version/keep" ] && [ ! -e "$H/p/versions/1.2.3" ] && [ ! -e "$H/bin/asdd" ]; then
  ok "uninstall removes only what it installed"
else bad "uninstall touched something it does not own (rc=$RC): $OUT"; fi

# 7. version validation. The version is part of a path that is later removed, so the validator itself must refuse these.
badv=0
for v in "1.2" "1.2.3.4" "../x" "../../.." "1.2.3-rc1" "1.2.3/../9.9.9" "1..2" ".1.2" "1.2." "v" "x.y.z" "1.2.3 " " 1.2.3" ""; do
  newhome version; before=$(snap "$H")
  inst install --version "$v" --prefix "$H/p" --bin-dir "$H/bin"
  if [ "$RC" = 0 ] || [ "$(snap "$H")" != "$before" ] || ! printf '%s' "$OUT" | grep -qE 'not a release version|needs a value'; then
    bad "version '$v' was not refused by the validator (rc=$RC): $OUT"; badv=1
  fi
done
[ "$badv" = 0 ] && ok "versions that are not exactly X.Y.Z are refused by the validator before any download or removal"

# 8. directory arguments
newhome dirs; before=$(snap "$H")
# shellcheck disable=SC2016  # '$b' is meant literally: a dollar sign must be refused, not expanded
dirtests=("--prefix:relative/path" "--prefix:/" "--prefix:$T/home" "--prefix:$H/../x" "--prefix:$H/p/../../x"
          "--prefix:$H//p" '--prefix:/tmp/a$b' "--prefix:" "--bin-dir:bin" "--bin-dir:")
for spec in "${dirtests[@]}"; do
  flag=${spec%%:*}; val=${spec#*:}
  inst install --version 1.2.3 "$flag" "$val"
  if [ "$RC" = 0 ] || [ "$(snap "$H")" != "$before" ]; then bad "$flag '$val' was accepted (rc=$RC): $OUT"; else ok "$flag '$val' is refused"; fi
done
inst install --version 1.2.3 --prefix
if [ "$RC" != 0 ]; then ok "an option with no value is refused"; else bad "a bare --prefix was accepted"; fi

# 9. where it downloads from
newhome url; before=$(snap "$H")
BASE_URL_FOR_RUN="http://example.invalid/releases"; inst install --version 1.2.3 --prefix "$H/p" --bin-dir "$H/bin"; BASE_URL_FOR_RUN=""
refused_untouched "a plain-http base URL is refused" "$before" "https:// or file://"
inst install --version 1.2.3 --prefix "$H/p" --bin-dir "$H/bin"
if printf '%s' "$OUT" | grep -q 'warning: using ASDD_BASE_URL='; then ok "overriding the base URL prints a warning"; else bad "no warning when ASDD_BASE_URL is overridden"; fi

# 10. the guardrails themselves held
if [ -s "$T/violations" ]; then bad "the installer tried to delete outside the sandbox: $(cat "$T/violations")"; else ok "no deletion was attempted outside the sandbox"; fi
stray=""
for f in "$T"/home/* "$T"/home/.[!.]*; do
  [ -e "$f" ] || continue
  case "${f##*/}" in .asdd|.local|Library) ;; *) stray="$stray ${f##*/}" ;; esac
done
if [ -n "$stray" ]; then bad "unexpected files appeared in the test HOME: $stray"; else ok "nothing stray appeared in HOME"; fi

if [ "$fail" = 0 ]; then echo "install self-test: PASS ($n checks)"; else echo "install self-test: FAIL"; fi
exit "$fail"
