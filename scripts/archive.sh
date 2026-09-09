#!/usr/bin/env bash
#
# One command from a clean checkout to an .ipa ready for App Store Connect.
#
#   scripts/archive.sh              archive and export
#   scripts/archive.sh --upload     …and send it to App Store Connect
#   BUILD=1234 scripts/archive.sh   pin the build number instead of stamping one
#   TESTING_TOOLS=1 scripts/archive.sh   build one that carries Settings > Testing
#
# TESTING_TOOLS=1 compiles the reset button into a Release build, for a TestFlight round where
# wiping the setup on the phone is the point. It is hidden in the app until it is asked for —
# five taps on Version, under Settings > About; see Shared/Core/TestingTools.swift — but
# TestFlight and the App Store are the same binary, so a build made this way must never be the
# one promoted for review. The check below knows about the flag and says so, loudly, either way.
#
# Uploading needs an App Store Connect API key (App Store Connect > Users and Access >
# Integrations). Export ASC_KEY_ID and ASC_ISSUER_ID, and put the .p8 where altool looks:
# ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8. Keep the .p8 out of this repo.
#
# None of this can succeed before the Family Controls distribution entitlement is granted and
# an Apple Distribution certificate exists on this Mac; see sections 1 and 2 of
# ~/Projects/archive/furlough/testflight-deployment/DEPLOYMENT.md.
# It will fail at signing, loudly, rather than producing something unsigned and misleading.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

# A UTC timestamp always rises and never collides, and says when the build was cut. App Store
# Connect refuses a second upload that reuses a build number under the same marketing version.
BUILD="${BUILD:-$(date -u +%Y%m%d%H%M)}"
ARCHIVE="$ROOT/build/Furlough-$BUILD.xcarchive"
EXPORT="$ROOT/build/export"

# Off unless asked for. Single-quoted so $(inherited) reaches xcodebuild as those nine
# characters, and so the whole setting stays one argument despite the space in it.
TESTING_TOOLS="${TESTING_TOOLS:-0}"
TOOLS_SETTINGS=()
if [[ "$TESTING_TOOLS" == "1" ]]; then
    TOOLS_SETTINGS=(SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) TESTING_TOOLS')
    echo "==> TESTING_TOOLS=1: this build will carry Settings > Testing"
fi

echo "==> Regenerating the project"
xcodegen generate

echo "==> Archiving  (version $(grep -m1 'MARKETING_VERSION:' project.yml | awk '{print $2}' | tr -d '\"'), build $BUILD)"
xcodebuild -project Furlough.xcodeproj -scheme Furlough -configuration Release \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  ${TOOLS_SETTINGS[@]+"${TOOLS_SETTINGS[@]}"} \
  archive

# The promise check, on the thing that actually ships rather than on the source. Debug-only code
# is one misplaced #endif from surviving into a release, and the app tells the person in
# onboarding and in Settings that a release build has no unblock button. The archived
# DEPLOYMENT.md section 6
# has the full audit and why the Debug side of the comparison matters; this is the cheap guard.
echo "==> Checking the archive is what this build says it is"
APP_BINARY="$ARCHIVE/Products/Applications/Furlough.app/Furlough"

# Read each tool's output once, into a variable, and probe the variable. The probes below used to
# pipe straight into `grep -q`, and that was silently broken in the worst available direction.
#
# `grep -q` exits at its first match. The tool upstream is then writing into a closed pipe, takes
# SIGPIPE, and dies with status 141 — and under the `set -o pipefail` at the top of this script,
# 141 becomes the pipeline's status. So a debug probe that FOUND something reported "not found":
#
#     if nm -a "$APP_BINARY" | grep -q resetEverything; then   # match -> SIGPIPE -> 141
#                                                              # -> `if` is false -> ships it
#
# The one check standing between a leaked unblock button and the App Store failed OPEN. Measured
# 2026-09-08 against this archive: probing for `AppIntents`, which is on line 1 of nm's output and
# appears 57 times, the idiom above printed "not detected".
#
# It only bites when the tool's output exceeds the 64KB pipe buffer — nm is ~115KB here, strings
# ~170KB — and only when the match lands early enough that there is still output left to write.
# That is why it passed on 2026-09-08 at 13:25 and failed the same evening: nothing about the
# promise changed, only where the matching bytes fell in the binary. A ship gate whose answer
# depends on string layout is not a gate.
#
# Assigning the output first means there is no pipe to break, no early exit, and no dependence on
# where a match falls. `|| true` because grep exits 1 on no-match, which `set -e` would take as a
# failure of the script rather than the answer it is.
NM_OUT="$(nm -a "$APP_BINARY" 2>/dev/null || true)"
STRINGS_OUT="$(strings -a "$APP_BINARY" 2>/dev/null || true)"

# The control first, then the probes. If this copy is missing, no probe below proves anything:
# they would report whatever the caller hoped for against a binary they cannot actually read.
# See the debug-dylib trap in the archived doc. This is also the probe that caught the SIGPIPE
# bug described above — it fails CLOSED, which is the only reason the fail-open was ever noticed.
if ! grep -qF "no unblock button" <<<"$STRINGS_OUT"; then
    echo "REFUSING TO SHIP: the control string is missing from the archived binary." >&2
    echo "The checks here are not measuring what they claim to. Do not trust them." >&2
    exit 1
fi

if [[ "$TESTING_TOOLS" == "1" ]]; then
    # Asked for the testing tools, so their absence is the failure. A flag that silently did
    # nothing would hand over a build that looks like a tester's and behaves like a customer's.
    for probe in resetEverything TestingTools; do
        if ! grep -q "$probe" <<<"$NM_OUT"; then
            echo "REFUSING TO SHIP: TESTING_TOOLS=1 was asked for, but '$probe' is not in the" >&2
            echo "archived binary. The compilation condition did not reach the Swift files that" >&2
            echo "carry it; check the #if DEBUG || TESTING_TOOLS blocks and xcodegen output." >&2
            exit 1
        fi
    done
    echo "    carries Settings > Testing, hidden behind five taps on Version"
    echo "    DO NOT submit this build for review: TestFlight and the App Store share a binary."
else
    for probe in resetEverything clearEverything TestingTools; do
        if grep -q "$probe" <<<"$NM_OUT"; then
            echo "REFUSING TO SHIP: '$probe' is in the archived binary." >&2
            echo "Testing-only code has leaked into Release. Either TESTING_TOOLS is set in the" >&2
            echo "project rather than passed to this script, or an #if DEBUG || TESTING_TOOLS" >&2
            echo "block is misplaced — Furlough/Model/AppModel.swift," >&2
            echo "Furlough/Views/SettingsView.swift, Shared/Core/TestingTools.swift." >&2
            exit 1
        fi
    done
    echo "    clean: no testing-only code, and the control string is present"
fi

# Apple's Screen Time scan, run here first. App Review's automated pass rejected build
# 202609090423 on 2026-09-09 (guideline 2.5.1): every bundle that links FamilyControls,
# ManagedSettings or DeviceActivity must carry com.apple.developer.family-controls, and the
# widget linked ManagedSettings through Shared/Core while carrying nothing. It no longer links
# it (NO_SCREEN_TIME on the FurloughWidgets target in project.yml); this checks every bundle in
# the archive against that rule, so the next such slip fails here rather than in review.
# Same shape as above: each tool's output lands in a variable before anything probes it.
echo "==> Checking that every bundle linking a Screen Time framework is entitled for it"
APP_DIR="$ARCHIVE/Products/Applications/Furlough.app"
for bundle in "$APP_DIR" "$APP_DIR"/PlugIns/*.appex "$APP_DIR"/Extensions/*.appex; do
    [[ -d "$bundle" ]] || continue
    executable="$bundle/$(plutil -extract CFBundleExecutable raw "$bundle/Info.plist")"
    LINKED="$(otool -L "$executable" 2>/dev/null || true)"
    LINKED="$(grep -oE '(FamilyControls|ManagedSettings|DeviceActivity)\.framework' <<<"$LINKED" | sort -u | tr '\n' ' ' || true)"
    ENTITLEMENTS="$(codesign -d --entitlements :- "$bundle" 2>/dev/null || true)"
    if [[ -n "$LINKED" ]] && ! grep -qF "com.apple.developer.family-controls" <<<"$ENTITLEMENTS"; then
        echo "REFUSING TO SHIP: $(basename "$bundle") links ${LINKED}but carries no family-controls entitlement." >&2
        echo "App Review's automated scan rejects this (2.5.1). Either a file this bundle compiles" >&2
        echo "imports the framework and should not — see Shared/Core/ScreenTimeStandIns.swift — or the" >&2
        echo "bundle needs the entitlement and its own Family Controls distribution grant." >&2
        exit 1
    fi
    if [[ -n "$LINKED" ]]; then
        echo "    $(basename "$bundle"): links ${LINKED}and is entitled"
    else
        echo "    $(basename "$bundle"): links no Screen Time framework"
    fi
done

echo "==> Exporting"
rm -rf "$EXPORT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$EXPORT" -allowProvisioningUpdates

IPA="$EXPORT/Furlough.ipa"
echo "==> Built $IPA"

if [[ "${1:-}" == "--upload" ]]; then
    : "${ASC_KEY_ID:?set ASC_KEY_ID (see the header of this script)}"
    : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (see the header of this script)}"
    echo "==> Uploading to App Store Connect"
    xcrun altool --upload-app -f "$IPA" -t ios \
      --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
    echo "==> Uploaded build $BUILD. It appears in TestFlight once processing finishes."
else
    echo "    Upload it with:  scripts/archive.sh --upload"
fi
