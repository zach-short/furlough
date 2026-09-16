#!/usr/bin/env bash
#
# puck.sh — render the anchor puck and package it for whoever is printing it.
#
#   scripts/puck.sh                  both variants, zipped, into build/puck/
#   scripts/puck.sh --bead 0.40      the same, with a tighter snap bead
#   scripts/puck.sh --stl-only       just the four STLs, no zip
#   scripts/puck.sh -o ~/Desktop     put the zip somewhere else
#
# The puck goes to people who are not in this repo, so what they get has to stand on its own:
# four STLs named in the order they print, a plain-language READ ME, and the .scad sources so
# they can change the fit without asking. design/anchor-puck/print-instructions.txt is that
# README — it is checked in rather than written fresh each time, because the last copy was
# assembled by hand in a temp folder and could not be sent twice.
#
# --bead exists because that is the one number a tester is ever told to change. The snap bead
# holds the press cap on (design/anchor-puck/README.md, "The fit"); if a printer runs lean the
# answer is 0.40 and if it cracks the body it is 0.20, and either way both halves have to be
# re-exported together or they no longer match. Passing it here does both at once and names the
# zip after the value, so two test packages can sit in the same folder without a guessing game.
#
# It does not commit, tag, or upload. Zach commits.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
SRC="$ROOT/design/anchor-puck"
NOTES="$SRC/print-instructions.txt"

if [[ -t 1 ]]; then B=$'\033[1m'; D=$'\033[2m'; O=$'\033[0m'; else B=''; D=''; O=''; fi
say() { printf '%s==>%s %s\n' "$B" "$O" "$*"; }
die() { printf 'puck: %s\n' "$*" >&2; exit 1; }

BEAD=""
OUT="$ROOT/build/puck"
ZIP=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bead)     shift; BEAD="${1:-}"; [[ -n "$BEAD" ]] || die "--bead needs a number"; shift ;;
    --stl-only) ZIP=0; shift ;;
    -o|--out)   shift; OUT="${1:-}"; [[ -n "$OUT" ]] || die "-o needs a directory"; shift ;;
    -h|--help)  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          die "no option $1" ;;
  esac
done

command -v openscad >/dev/null 2>&1 || die "openscad is not on the PATH — brew install --cask openscad"
[[ -f "$NOTES" ]] || die "missing $NOTES, which is the README the package is built around"

# OpenSCAD exits nonzero on a failed assert, but it also prints ERROR: and carries on for some
# geometry faults, and an -o that never got written leaves a stale file from the last run
# looking like a success. So take four things, not one: the status, the log, a file that
# actually exists, and the manifold report openscad makes about the solid it just wrote — a
# non-manifold STL slices into nonsense rather than failing, which is exactly the kind of green
# gate this repo has been bitten by before. The report is only matched when it is present, so a
# later openscad that words it differently loosens the gate instead of breaking the script.
render() {
  local variant="$1" part="$2" dest="$3" log status
  rm -f "$dest"
  log="$(openscad --export-format=binstl \
                  -D "variant=\"$variant\"" -D "part=\"$part\"" \
                  ${BEAD:+-D "bead=$BEAD"} \
                  -o "$dest" "$SRC/anchor-puck.scad" 2>&1)" && status=0 || status=$?
  if (( status != 0 )) || grep -qE 'ERROR|ASSERT' <<<"$log"; then
    printf '\n%spuck: %s %s failed to render.%s\n\n' "$B" "$variant" "$part" "$O" >&2
    grep -E 'ERROR|ASSERT|WARNING' <<<"$log" >&2 || printf '%s\n' "$log" >&2
    exit 1
  fi
  [[ -s "$dest" ]] || die "$variant $part rendered nothing"
  if grep -q 'Status:' <<<"$log" && ! grep -qE 'Status:[[:space:]]+NoError' <<<"$log"; then
    grep -E 'Status:|manifold' <<<"$log" >&2
    die "$variant $part is not a closed solid — do not send it to a slicer"
  fi
  # The line the .scad echoes about the joint — the only place the bead and bore diameters are
  # stated back. Only the press variant prints one, so keep the first and let the rest miss.
  [[ -n "$SNAP" ]] || SNAP="$(sed -n 's/^ECHO: "\(snap: .*\)"$/\1/p' <<<"$log" | head -1)"
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/Furlough puck"
mkdir -p "$PKG/twist version (backup)" "$PKG/source"

say "rendering${BEAD:+ with bead=$BEAD}"
SNAP=""
render press body "$PKG/1 - body.stl"
render press lid  "$PKG/2 - lid.stl"
render twist body "$PKG/twist version (backup)/1 - cup.stl"
render twist lid  "$PKG/twist version (backup)/2 - cap.stl"
[[ -n "$SNAP" ]] && printf '    %s%s%s\n' "$D" "$SNAP" "$O"

cp "$NOTES" "$PKG/READ ME.txt"
cp "$SRC/anchor-puck.scad" "$SRC/anchor-mark.scad" "$PKG/source/"

# The READ ME tells the tester to edit `bead` and re-export. If this run already moved it, the
# sources they get should say so too, or they will read 0.30 in a package that is not 0.30.
if [[ -n "$BEAD" ]]; then
  perl -i -pe "s/^bead = [0-9.]+;/bead = $BEAD;/" "$PKG/source/anchor-puck.scad"
  grep -q "^bead = $BEAD;" "$PKG/source/anchor-puck.scad" || die "could not set bead in the packaged source"
fi

mkdir -p "$OUT"
if (( ZIP )); then
  name="furlough-puck${BEAD:+-bead$BEAD}.zip"
  rm -f "$OUT/$name"
  ( cd "$STAGE" && zip -r -X -q "$OUT/$name" "Furlough puck" -x ".*" "__MACOSX*" )
  say "$OUT/$name"
  printf '    %s%s%s\n' "$D" "$(unzip -l "$OUT/$name" | tail -1 | awk '{print $2, "files,", $1, "bytes uncompressed"}')" "$O"
else
  rm -rf "$OUT/Furlough puck"
  cp -R "$PKG" "$OUT/"
  say "$OUT/Furlough puck"
fi
