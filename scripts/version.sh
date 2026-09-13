#!/usr/bin/env bash
#
# version.sh — the marketing version, and the one rule about changing it.
#
#   scripts/version.sh                 what the version is, and whether the notes agree
#   scripts/version.sh --check         say nothing and exit 0 if they agree; explain and fail if not
#   scripts/version.sh patch           1.1.0 -> 1.1.1
#   scripts/version.sh minor           1.1.0 -> 1.2.0
#   scripts/version.sh major           1.1.0 -> 2.0.0
#   scripts/version.sh 1.4.2           straight to a number, for the rare case the words miss
#
# MARKETING_VERSION lives once, in project.yml's base settings, and every target's Info.plist
# reads it through $(MARKETING_VERSION). What each of the three numbers means, and what forces
# which, is README's Versioning section — this file enforces the mechanical half of it:
#
#   * three components, always, so 1.1 and 1.1.0 can never both be written down;
#   * the new number is greater than the old one, because App Store Connect will not take a
#     version that is not and finding that out at upload time wastes an archive;
#   * release-notes.json already has an entry for it, written before the bump rather than after.
#     The last one is the point of the whole script. Notes written afterwards are written from
#     the git log by whoever has forgotten what the changes were for, and `scripts/archive.sh`
#     calls --check so a build cannot be cut without them.
#
# It does not commit, tag, or push. Zach commits.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
PROJECT="$ROOT/project.yml"
NOTES="$ROOT/release-notes.json"

if [[ -t 1 ]]; then B=$'\033[1m'; D=$'\033[2m'; O=$'\033[0m'; else B=''; D=''; O=''; fi
die() { printf 'version: %s\n' "$*" >&2; exit 1; }

current() { grep -m1 '^    MARKETING_VERSION:' "$PROJECT" | awk '{print $2}' | tr -d '"'; }

# Every version release-notes.json has an entry for, newest first, as the file has them.
noted() {
  python3 - "$NOTES" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    for release in json.load(f)["versions"]:
        print(release["version"])
PY
}

# Three components, each a number. The one spelling the repo accepts.
well_formed() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# Sort -V puts versions in order; a version is greater than another when it is not the one that
# sorts first, and is not equal to it.
greater_than() { [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$2" ]]; }

check() {
    local version="$1" quiet="${2:-}"
    well_formed "$version" || die "MARKETING_VERSION is \"$version\", which is not MAJOR.MINOR.PATCH.
  Every version is three numbers — 1.2.0, never 1.2 — so that two spellings of one version
  cannot both exist. README's Versioning section says why."
    if ! noted | grep -qx "$version"; then
        die "release-notes.json has no entry for $version.
  Write it before the bump, not after: notes written afterwards are reconstructed from the git
  log by someone who has forgotten what the changes were for. The newest entry in the file is
  $(noted | head -1).
  The file is at release-notes.json; both apps bundle it and the site imports it."
    fi
    [[ -n "$quiet" ]] || printf '%s%s%s is in release-notes.json.\n' "$B" "$version" "$O"
}

report() {
    local version; version="$(current)"
    printf '%sMARKETING_VERSION%s  %s   %s(project.yml)%s\n' "$B" "$O" "$version" "$D" "$O"
    printf '%srelease-notes.json%s %s\n' "$B" "$O" "$(noted | head -5 | tr '\n' ' ')"
    printf '\n'
    if well_formed "$version" && noted | grep -qx "$version"; then
        printf '  The notes cover this version.\n'
    else
        printf '  %sThey do not agree — scripts/archive.sh will refuse to cut a build.%s\n' "$B" "$O"
        printf '  Run scripts/version.sh --check for what is wrong.\n'
    fi
    printf '\n  %sBuild numbers are not versions%s: CURRENT_PROJECT_VERSION is a UTC timestamp\n' "$D" "$O"
    printf '  %sarchive.sh stamps on each build, always rising, never reused.%s\n' "$D" "$O"
    printf '\n  %spatch%s a fix nobody has to learn   %sminor%s something new to find   %smajor%s something to be told\n' "$B" "$O" "$B" "$O" "$B" "$O"
}

bump() {
    local from="$1" part="$2" major minor patch
    IFS=. read -r major minor patch <<<"$from"
    case "$part" in
        major) printf '%d.0.0\n' "$((major + 1))" ;;
        minor) printf '%d.%d.0\n' "$major" "$((minor + 1))" ;;
        patch) printf '%d.%d.%d\n' "$major" "$minor" "$((patch + 1))" ;;
    esac
}

set_version() {
    local from="$1" to="$2"
    well_formed "$to" || die "\"$to\" is not MAJOR.MINOR.PATCH."
    greater_than "$to" "$from" || die "$to is not greater than $from.
  App Store Connect refuses a version that does not rise, and finding that out at upload time
  wastes an archive."
    check "$to" quiet
    # The one line, matched on its own indentation so a target's $(MARKETING_VERSION) is safe.
    python3 - "$PROJECT" "$from" "$to" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
line_old = f'    MARKETING_VERSION: "{old}"\n'
line_new = f'    MARKETING_VERSION: "{new}"\n'
with open(path) as f:
    text = f.read()
if text.count(line_old) != 1:
    raise SystemExit(f"version: expected one {line_old.strip()} in project.yml, found {text.count(line_old)}")
with open(path, "w") as f:
    f.write(text.replace(line_old, line_new))
PY
    printf '%s%s -> %s%s in project.yml.\n\n' "$B" "$from" "$to" "$O"
    printf '  Next: %sxcodegen generate%s, then %sfurlough beta%s when the build is ready.\n' "$B" "$O" "$B" "$O"
    printf '  %sNothing has been committed — that is Zach'"'"'s.%s\n' "$D" "$O"
}

case "${1:-report}" in
    report)               report ;;
    --check|-c)           check "$(current)" quiet ;;
    major|minor|patch)    set_version "$(current)" "$(bump "$(current)" "$1")" ;;
    -h|--help)            sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)                    set_version "$(current)" "$1" ;;
esac
