# Spec: a one-line install for the asdd CLI

Lane: feature. One command puts the `asdd` CLI on a developer machine or a CI runner, at a pinned version,
without anyone cloning the repository or knowing which Python packaging route to use.

## Problem

Getting `asdd` today means `pip install git+https://github.com/OneHillAI/ASDD`, which tracks `main` rather
than a release, needs pip and a build step, and cannot be pinned in a CI file the way an adopter pins every
other tool. An adopter who wants ASDD in their pipeline has no single line to paste, and no checksum to rely
on.

## Outcomes

- `sh -c "$(curl -fsSL <release>/install.sh)"` installs the latest release; adding `sh --version X.Y.Z` after
  it installs exactly that release. Both work in a GitHub Actions step, and the installer adds its bin directory to
  `$GITHUB_PATH` there.
- The installer downloads a release archive and its SHA-256, and installs nothing if the checksum does not
  match, the archive holds anything but one `asdd-X.Y.Z/` tree, a path is absolute or contains `..`, the
  archive contains links, or the extracted CLI does not report the version that was asked for.
- A release is published by pushing a `vX.Y.Z` tag. The release workflow checks the tag against the version
  in `asdd_cli.py` and `pyproject.toml`, installs from the archive it just built, and only then publishes.
- `install.sh uninstall` removes what the installer put there and nothing else.

## Scope

- `install.sh` (POSIX `sh`), its test `install.test.sh`, and a mutation check `install.mutation.sh`.
- `.github/workflows/release.yml` and `.github/workflows/install-test.yml`.
- The README quick start and a changelog entry.

## Out of scope

- Signing releases or verifying who published one. The checksum and the archive come from the same release,
  so the installer catches a corrupted or swapped download, not a compromised release. Pin a version.
- Windows. Installing under WSL or Git Bash works; a native PowerShell installer is a separate change.
- Changing how `asdd` finds its tools, or the existing `pip install` route.

## Constraints

- The installer deletes directories, so it may delete only `<prefix>/versions/X.Y.Z` trees that carry its own
  marker file, through one function that re-checks ownership. It never overwrites an `asdd` launcher or a
  directory it did not create, edits shell profiles, or uses `sudo`.
- The version string is part of a path that is later removed, so it must be exactly `X.Y.Z` digits; anything
  else is refused before any download or removal.
- `--prefix` and `--bin-dir` must be absolute, free of `..`, `.` and `//` components, and neither `/` nor the
  user's home directory itself.
- The body of `install.sh` runs from a function called on the last line, so a truncated download runs
  nothing.
- Tests run the installer confined to one temp root: a fake `HOME`, an `rm` shim that refuses operands outside
  it, and on macOS an OS sandbox denying writes elsewhere. No test deletes anything by an unchecked variable.

## Verification

- `bash install.test.sh` passes (pinned and latest installs, upgrade, re-install, defaults, `$GITHUB_PATH`,
  uninstall, and a refusal for each bad archive, foreign launcher, foreign directory, bad version and bad
  directory argument), and records no `rm` attempt outside the sandbox.
- `bash install.mutation.sh` removes each `# guard:` line in `install.sh` in turn and the test fails for every
  one except those listed as exempt with a reason.
- Installing from an archive built by `git archive` from this repository succeeds, and the installed CLI runs.

## Acceptance criteria

- A user can paste the one line into a terminal or a workflow step and get a working `asdd` at a version they
  chose, or the installer says why it refused and leaves the machine unchanged.
- No test or mutant can write or delete outside its temp root.
