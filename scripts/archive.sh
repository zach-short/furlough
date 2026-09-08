#!/usr/bin/env bash
#
# One command from a clean checkout to an .ipa ready for App Store Connect.
#
#   scripts/archive.sh              archive and export
#   scripts/archive.sh --upload     …and send it to App Store Connect
#   BUILD=1234 scripts/archive.sh   pin the build number instead of stamping one
#
# Uploading needs an App Store Connect API key (App Store Connect > Users and Access >
# Integrations). Export ASC_KEY_ID and ASC_ISSUER_ID, and put the .p8 where altool looks:
# ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8. Keep the .p8 out of this repo.
#
# None of this can succeed before the Family Controls distribution entitlement is granted and
# an Apple Distribution certificate exists on this Mac; see DEPLOYMENT.md sections 1 and 2.
# It will fail at signing, loudly, rather than producing something unsigned and misleading.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

# A UTC timestamp always rises and never collides, and says when the build was cut. App Store
# Connect refuses a second upload that reuses a build number under the same marketing version.
BUILD="${BUILD:-$(date -u +%Y%m%d%H%M)}"
ARCHIVE="$ROOT/build/Furlough-$BUILD.xcarchive"
EXPORT="$ROOT/build/export"

echo "==> Regenerating the project"
xcodegen generate

echo "==> Archiving  (version $(grep -m1 'MARKETING_VERSION:' project.yml | awk '{print $2}' | tr -d '\"'), build $BUILD)"
xcodebuild -project Furlough.xcodeproj -scheme Furlough -configuration Release \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  archive

# The promise check, on the thing that actually ships rather than on the source. Debug-only code
# is one misplaced #endif from surviving into a release, and the app tells the person in
# onboarding and in Settings that a release build has no unblock button. DEPLOYMENT.md section 6
# has the full audit and why the Debug side of the comparison matters; this is the cheap guard.
echo "==> Checking the release keeps its promise"
APP_BINARY="$ARCHIVE/Products/Applications/Furlough.app/Furlough"
for probe in resetEverything clearEverything; do
    if nm -a "$APP_BINARY" 2>/dev/null | grep -q "$probe"; then
        echo "REFUSING TO SHIP: '$probe' is in the archived binary." >&2
        echo "Debug-only code has leaked into Release. Check the #if DEBUG blocks in" >&2
        echo "Furlough/Model/AppModel.swift and Furlough/Views/SettingsView.swift." >&2
        exit 1
    fi
done
if ! strings -a "$APP_BINARY" | grep -qF "no unblock button"; then
    # If this copy is missing, the probes above proved nothing: they would report a clean pass
    # against a binary they cannot actually read. See the debug-dylib trap in DEPLOYMENT.md.
    echo "REFUSING TO SHIP: the control string is missing from the archived binary." >&2
    echo "The check above is not measuring what it claims to. Do not trust it." >&2
    exit 1
fi
echo "    clean: no debug-only code, and the control string is present"

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
