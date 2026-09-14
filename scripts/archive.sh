#!/usr/bin/env bash
#
# One command from a clean checkout to an .ipa ready for App Store Connect.
#
#   scripts/archive.sh              archive and export
#   scripts/archive.sh --upload     …and send it to App Store Connect
#   BUILD=1234 scripts/archive.sh   pin the build number instead of stamping one
#   TESTING_TOOLS=1 scripts/archive.sh   build one that carries Settings > Testing
#
# TESTING_TOOLS=1 compiles the reset button into a Release build, hidden behind five taps on
# Version (Settings > About; see Shared/Core/TestingTools.swift). TestFlight and the App Store
# share a binary, so a build made this way must never be promoted for review.
#
# Uploading needs an App Store Connect API key (App Store Connect > Users and Access >
# Integrations). Export ASC_KEY_ID and ASC_ISSUER_ID, and put the .p8 where altool looks:
# ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8. Keep the .p8 out of this repo.
#
# Needs the Family Controls distribution entitlement granted and an Apple Distribution
# certificate on this Mac first (DEPLOYMENT.md sections 1-2), or it fails at signing.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

# App Store Connect refuses a second upload that reuses a build number under the same version.
BUILD="${BUILD:-$(date -u +%Y%m%d%H%M)}"
ARCHIVE="$ROOT/build/Furlough-$BUILD.xcarchive"
EXPORT="$ROOT/build/export"

# Single-quoted so $(inherited) reaches xcodebuild literally, and stays one argument despite
# the space in it.
TESTING_TOOLS="${TESTING_TOOLS:-0}"
TOOLS_SETTINGS=()
if [[ "$TESTING_TOOLS" == "1" ]]; then
    TOOLS_SETTINGS=(SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) TESTING_TOOLS')
    echo "==> TESTING_TOOLS=1: this build will carry Settings > Testing"
fi

echo "==> Checking the version against release-notes.json"
if ! scripts/version.sh --check; then
    echo "REFUSING TO SHIP: the version and the release notes do not agree (see above)." >&2
    exit 1
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

# The promise check, on the built archive rather than the source (DEPLOYMENT.md section 6 has
# the full audit).
echo "==> Checking the archive is what this build says it is"
APP_BINARY="$ARCHIVE/Products/Applications/Furlough.app/Furlough"

# Assign each tool's output to a variable before grepping — piping straight into `grep -q` lets
# grep exit at its first match, SIGPIPE the upstream tool, and turn a FOUND match into "not
# found" under `set -o pipefail`. Measured here 2026-09-08: the same probe against the same
# binary passed at 13:25 and failed that evening, purely from where the match fell relative to
# the 64KB pipe buffer — a ship gate that depends on string layout is not a gate. `|| true`
# because grep's exit 1 on no-match is not itself a script failure.
NM_OUT="$(nm -a "$APP_BINARY" 2>/dev/null || true)"
STRINGS_OUT="$(strings -a "$APP_BINARY" 2>/dev/null || true)"

# Control check first — if this string is missing, the probes below are reading a binary they
# can't trust (see the debug-dylib trap in DEPLOYMENT.md). This is also the probe that caught
# the SIGPIPE bug above, since it fails closed.
if ! grep -qF "no unblock button" <<<"$STRINGS_OUT"; then
    echo "REFUSING TO SHIP: the control string is missing from the archived binary." >&2
    echo "The checks here are not measuring what they claim to. Do not trust them." >&2
    exit 1
fi

if [[ "$TESTING_TOOLS" == "1" ]]; then
    # Absence is the failure here — a flag that silently did nothing would ship a build that
    # looks like a tester's and behaves like a customer's.
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

# App Review's automated scan (guideline 2.5.1) rejected build 202609090423 on 2026-09-09: every
# bundle linking FamilyControls/ManagedSettings/DeviceActivity needs the family-controls
# entitlement, and the widget linked ManagedSettings via Shared/Core without carrying it. Checks
# every bundle in the archive so the next such slip fails here, not in review.
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
