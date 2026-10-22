#!/bin/sh
# ASDD installer: one line puts the `asdd` CLI on a developer machine or a CI runner.
#
#   sh -c "$(curl -fsSL https://github.com/OneHillAI/ASDD/releases/latest/download/install.sh)"
#   sh -c "$(curl -fsSL https://github.com/OneHillAI/ASDD/releases/latest/download/install.sh)" sh --version 0.2.0
#   sh install.sh uninstall                   (from a saved copy of this file)
#   sh -c "$(curl -fsSL https://github.com/OneHillAI/ASDD/releases/latest/download/install.sh)" sh uninstall   (without one)
#
# In GitHub Actions, add one step before anything that calls `asdd`; the installer puts its bin dir on
# $GITHUB_PATH for you:
#   - run: sh -c "$(curl -fsSL https://github.com/OneHillAI/ASDD/releases/latest/download/install.sh)" sh --version 0.2.0
#
# What it does: downloads a release archive, verifies its SHA-256, checks the archive holds nothing but one
# `asdd-X.Y.Z/` tree (no absolute paths, no `..`, no links), runs the extracted CLI once to confirm it is the
# version asked for, then installs it under --prefix and links a launcher into --bin-dir.
#
# What it will not do: touch a directory or an `asdd` launcher it did not create, delete anything outside
# <prefix>/versions/X.Y.Z, edit shell profiles, or use sudo. Every deletion goes through remove_owned.
#
# Usage: install.sh [install|uninstall] [--version X.Y.Z] [--prefix DIR] [--bin-dir DIR]
#   --version  a release version, exactly X.Y.Z (default: the latest release)
#   --prefix   where versions are kept          (default: $HOME/.asdd)
#   --bin-dir  where the `asdd` launcher goes   (default: $HOME/.local/bin)
#   ASDD_BASE_URL overrides the release location (https:// or file://); it prints a warning.
#
# The body is wrapped in main() and called on the last line so a truncated download runs nothing.
set -eu

DEFAULT_BASE_URL="https://github.com/OneHillAI/ASDD/releases"
ASSET="asdd-kit.tar.gz"
MARKER=".asdd-install"
LAUNCHER_TAG="# asdd-install launcher"
NL='
'
TMP_WORK=""

die()  { printf 'asdd-install: error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'asdd-install: warning: %s\n' "$*" >&2; }
say()  { printf 'asdd-install: %s\n' "$*"; }
usage() {
  # shellcheck disable=SC2016  # $HOME is shown literally, not expanded
  printf '%s\n' \
    'Usage: install.sh [install|uninstall] [--version X.Y.Z] [--prefix DIR] [--bin-dir DIR]' \
    '  --version  a release version, exactly X.Y.Z (default: the latest release)' \
    '  --prefix   where versions are kept          (default: $HOME/.asdd)' \
    '  --bin-dir  where the `asdd` launcher goes   (default: $HOME/.local/bin)' \
    'ASDD_BASE_URL overrides the release location (https:// or file://); it prints a warning.'
}

# Only the scratch dir this run created (mktemp, always named asdd-install.*) is ever removed on exit.
cleanup() {
  case "$TMP_WORK" in
    */asdd-install.*) [ -d "$TMP_WORK" ] && [ ! -L "$TMP_WORK" ] && rm -rf -- "$TMP_WORK" ;;
  esac
  return 0
}

# Exactly X.Y.Z, digits only. This string ends up in a path that is later removed, so it must be boring.
is_release_version() {
  case "$1" in
    ''|*[!0-9.]*|.*|*.|*..*) return 1 ;;
  esac
  [ "${#1}" -le 32 ] || return 1
  _old_ifs=$IFS; IFS=.
  # shellcheck disable=SC2086  # splitting on the dots is the point
  set -- $1
  IFS=$_old_ifs
  [ $# -eq 3 ]
}

# A directory argument: absolute, no `..` component, nothing the launcher's quoting could not hold, not "/" or $HOME.
check_dir_arg() { # name value
  case "$2" in
    '')  die "$1 needs a directory" ;;
    /*)  ;;
    *)   die "$1 must be an absolute path (got: $2)" ;;
  esac
  # shellcheck disable=SC1003  # the '\' pattern is a literal backslash
  case "$2" in
    *'"'*|*'$'*|*'`'*|*'\'*|*"$NL"*) die "$1 contains a character that is not allowed (quote, \$, backtick, backslash, newline)" ;;
    */..|*/../*|*/.|*/./*|*//*)      die "$1 must be a plain path with no '.', '..' or '//' components (got: $2)" ;;
  esac
  _trim=${2%/}
  [ -n "$_trim" ] || die "$1 must not be the filesystem root"
  [ "$_trim" != "${HOME:-}" ] || die "$1 must not be your home directory itself (use a subdirectory)"
}

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but was not found"; }

fetch() { # url dest
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --proto '=https,file' --retry 2 -o "$2" "$1" || die "download failed: $1"
  elif command -v wget >/dev/null 2>&1; then
    case "$1" in
      https://*) wget -q -O "$2" "$1" || die "download failed: $1" ;;
      *)         die "wget can only fetch https:// URLs; install curl to use $1" ;;
    esac
  else
    die "curl or wget is required"
  fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else die "sha256sum or shasum is required"; fi
}

# A directory this installer made: a real directory (not a link) under <prefix>/versions/X.Y.Z carrying our marker.
owned_dir() { # path
  [ -d "$1" ] || return 1
  [ ! -L "$1" ] || return 1
  [ -f "$1/$MARKER" ] || return 1   # guard:marker
  case "$1" in "$PREFIX"/versions/*) ;; *) return 1 ;; esac
  is_release_version "${1##*/}"
}

# The only place that deletes an installed tree. Re-checks ownership right before removing.
remove_owned() { # path
  owned_dir "$1" || die "refusing to remove $1: not a directory this installer created"
  rm -rf -- "$1"
}

launcher_is_ours() { # path
  [ -f "$1" ] && [ ! -L "$1" ] && grep -qF "$LAUNCHER_TAG" "$1"
}

check_archive() { # archive workdir -> sets ARCHIVE_TOP
  tar -tzf "$1" >"$2/names" 2>/dev/null || die "the download is not a readable .tar.gz archive"
  [ -s "$2/names" ] || die "the archive is empty"
  ! grep -qE '(^/|(^|/)\.\.(/|$))' "$2/names" || die "the archive contains an unsafe path (absolute or '..'); refusing to extract"   # guard:unsafe-path
  ARCHIVE_TOP=$(awk -F/ 'NR==1{print $1; exit}' "$2/names")
  awk -F/ -v t="$ARCHIVE_TOP" '$1!=t{bad=1} END{exit bad}' "$2/names" || die "the archive does not hold a single top-level directory"
  case "$ARCHIVE_TOP" in asdd-*) is_release_version "${ARCHIVE_TOP#asdd-}" || die "the archive's top directory '$ARCHIVE_TOP' is not asdd-X.Y.Z" ;; *) die "the archive's top directory '$ARCHIVE_TOP' is not asdd-X.Y.Z" ;; esac
  tar -tvzf "$1" 2>/dev/null | cut -c1 | grep -q '[lh]' && die "the archive contains links; refusing to extract" || true
}

do_install() {
  need tar; need awk; need grep; need sed; need mktemp; need python3
  python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' || die "python3 3.9 or newer is required"

  if [ -n "${ASDD_BASE_URL:-}" ]; then
    warn "using ASDD_BASE_URL=$ASDD_BASE_URL instead of $DEFAULT_BASE_URL"
    BASE_URL=${ASDD_BASE_URL%/}
  else
    BASE_URL=$DEFAULT_BASE_URL
  fi
  case "$BASE_URL" in https://*|file://*) ;; *) die "ASDD_BASE_URL must start with https:// or file:// (got: $BASE_URL)" ;; esac

  if [ -n "$VERSION" ]; then url_dir="download/v$VERSION"; else url_dir="latest/download"; fi

  # Refuse before changing anything: a foreign launcher, a foreign install dir, a real directory where our symlink goes.
  if [ -e "$BIN_DIR/asdd" ] || [ -L "$BIN_DIR/asdd" ]; then
    launcher_is_ours "$BIN_DIR/asdd" || die "$BIN_DIR/asdd already exists and was not created by asdd-install; not touching it (use --bin-dir for another location)"   # guard:foreign-asdd
  fi
  [ ! -e "$PREFIX/current" ] || [ -L "$PREFIX/current" ] || die "$PREFIX/current exists and is not a link this installer made; not touching it"   # guard:foreign-current

  TMP_WORK=$(mktemp -d "${TMPDIR:-/tmp}/asdd-install.XXXXXX") || die "could not create a scratch directory"
  trap cleanup EXIT INT TERM

  say "downloading $BASE_URL/$url_dir/$ASSET"
  fetch "$BASE_URL/$url_dir/$ASSET" "$TMP_WORK/$ASSET"
  fetch "$BASE_URL/$url_dir/$ASSET.sha256" "$TMP_WORK/$ASSET.sha256"

  expected=$(awk 'NR==1{print $1; exit}' "$TMP_WORK/$ASSET.sha256")
  case "$expected" in
    *[!0-9a-f]*|'') die "the checksum file is not a SHA-256 digest" ;;
  esac
  [ "${#expected}" -eq 64 ] || die "the checksum file is not a SHA-256 digest"
  actual=$(sha256_of "$TMP_WORK/$ASSET")
  [ "$actual" = "$expected" ] || die "checksum mismatch: expected $expected, got $actual; refusing to install"   # guard:checksum

  check_archive "$TMP_WORK/$ASSET" "$TMP_WORK"
  archive_version=${ARCHIVE_TOP#asdd-}
  [ -z "$VERSION" ] || [ "$archive_version" = "$VERSION" ] || die "asked for $VERSION but the archive holds $archive_version"   # guard:archive-version
  VERSION=$archive_version

  mkdir "$TMP_WORK/x"
  nso=""; tar --help 2>&1 | grep -q -- '--no-same-owner' && nso="--no-same-owner"
  # shellcheck disable=SC2086  # $nso is empty or one flag
  tar -xzf "$TMP_WORK/$ASSET" $nso -C "$TMP_WORK/x" || die "could not extract the archive"
  src="$TMP_WORK/x/$ARCHIVE_TOP"
  [ -f "$src/asdd_cli.py" ] || die "the archive does not contain asdd_cli.py"

  got=$(python3 "$src/asdd_cli.py" --version 2>/dev/null || true)
  [ "$got" = "asdd $VERSION" ] || die "the extracted CLI reports '${got:-nothing}', expected 'asdd $VERSION'; refusing to install"   # guard:version-smoke

  dest="$PREFIX/versions/$VERSION"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    owned_dir "$dest" || die "$dest already exists and was not created by asdd-install; not touching it"   # guard:foreign-dir
  fi

  mkdir -p "$PREFIX/versions" "$BIN_DIR"
  if [ -e "$dest" ]; then say "replacing installed $VERSION"; remove_owned "$dest"; fi
  mv "$src" "$dest"
  printf '%s\n' "$VERSION" >"$dest/$MARKER"

  ln -sfn "versions/$VERSION" "$PREFIX/current"
  tmp_launcher="$BIN_DIR/.asdd.$$"
  printf '#!/bin/sh\n%s\nexec python3 "%s/current/asdd_cli.py" "$@"\n' "$LAUNCHER_TAG" "$PREFIX" >"$tmp_launcher"
  chmod 755 "$tmp_launcher"
  mv -f "$tmp_launcher" "$BIN_DIR/asdd"

  out=$("$BIN_DIR/asdd" --version 2>/dev/null || true)
  [ "$out" = "asdd $VERSION" ] || die "the installed launcher reports '${out:-nothing}', expected 'asdd $VERSION'"   # guard:post-smoke

  if [ -n "${GITHUB_PATH:-}" ]; then
    printf '%s\n' "$BIN_DIR" >>"$GITHUB_PATH"
    say "added $BIN_DIR to \$GITHUB_PATH for the steps that follow"
  fi
  say "installed asdd $VERSION -> $BIN_DIR/asdd"
  case ":$PATH:" in *":$BIN_DIR:"*) ;; *) say "note: $BIN_DIR is not on your PATH yet" ;; esac
}

do_uninstall() {
  if [ -e "$BIN_DIR/asdd" ] || [ -L "$BIN_DIR/asdd" ]; then
    if launcher_is_ours "$BIN_DIR/asdd"; then rm -f -- "$BIN_DIR/asdd"; say "removed $BIN_DIR/asdd"
    else warn "leaving $BIN_DIR/asdd: not created by asdd-install"; fi
  fi
  if [ -d "$PREFIX/versions" ] && [ ! -L "$PREFIX/versions" ]; then
    for d in "$PREFIX"/versions/*; do
      [ -e "$d" ] || [ -L "$d" ] || continue
      if owned_dir "$d"; then remove_owned "$d"; say "removed $d"
      else warn "leaving $d: not created by asdd-install"; fi
    done
  fi
  if [ -L "$PREFIX/current" ]; then
    case "$(readlink "$PREFIX/current")" in versions/*) rm -f -- "$PREFIX/current" ;; esac
  fi
  rmdir "$PREFIX/versions" 2>/dev/null || true
  rmdir "$PREFIX" 2>/dev/null || true
}

main() {
  CMD=install; VERSION=""; PREFIX=""; BIN_DIR=""
  if [ $# -gt 0 ]; then
    case "$1" in install|uninstall) CMD=$1; shift ;; esac
  fi
  while [ $# -gt 0 ]; do
    case "$1" in
      --version)  [ $# -ge 2 ] && [ -n "$2" ] || die "--version needs a value (a release version, X.Y.Z)"
                  VERSION=${2#v}
                  [ -n "$VERSION" ] || die "'$2' is not a release version (expected X.Y.Z, for example 0.2.0)"
                  shift 2 ;;
      --prefix)   [ $# -ge 2 ] && [ -n "$2" ] || die "--prefix needs a directory"; PREFIX=$2; shift 2 ;;
      --bin-dir)  [ $# -ge 2 ] && [ -n "$2" ] || die "--bin-dir needs a directory"; BIN_DIR=$2; shift 2 ;;
      -h|--help)  usage; exit 0 ;;
      *)          die "unknown option: $1" ;;
    esac
  done

  if [ -n "$VERSION" ]; then
    is_release_version "$VERSION" || die "'$VERSION' is not a release version (expected X.Y.Z, for example 0.2.0)"   # guard:version
  fi
  [ -n "$PREFIX" ]  || { [ -n "${HOME:-}" ] || die "HOME is not set; pass --prefix"; PREFIX="$HOME/.asdd"; }
  [ -n "$BIN_DIR" ] || { [ -n "${HOME:-}" ] || die "HOME is not set; pass --bin-dir"; BIN_DIR="$HOME/.local/bin"; }
  PREFIX=${PREFIX%/}; BIN_DIR=${BIN_DIR%/}
  check_dir_arg --prefix "$PREFIX"
  check_dir_arg --bin-dir "$BIN_DIR"

  case "$CMD" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
  esac
}

main "$@"
