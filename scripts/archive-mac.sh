#!/usr/bin/env bash
#
# One command from a clean checkout to a notarized Furlough.dmg that a stranger's Mac will open.
#
#   scripts/archive-mac.sh --check         say what this Mac is missing, and stop
#   scripts/archive-mac.sh                 build, sign, notarize, staple, make the DMG
#   scripts/archive-mac.sh --no-notarize   everything up to Apple, for reading the signature
#   BUILD=202609131900 scripts/archive-mac.sh   pin the build number instead of stamping one
#
# There is no App Store submission for the Mac and there will not be one: FurloughMac is
# unsandboxed, drives browsers through Apple Events, terminates other processes, installs a
# LaunchAgent and carries a system extension, and the Mac App Store requires the sandbox without
# exception. Its road is Developer ID plus notarization, from a page on furloughapp.com. That is
# settled in section 3 of ~/Projects/archive/furlough/testflight-deployment/DEPLOYMENT.md.
#
# WHY THIS IS NOT `xcodebuild -exportArchive`. Xcode 26's Direct Distribution cannot sign an app
# that embeds a system extension (DTS, r.108838909; fixed in the Xcode 27 beta). So the app is
# built the ordinary way and then re-signed by hand, inside out — the extension, the widget, then
# the app — with the Developer ID entitlements beside each target's development ones and the
# Developer ID profiles from the portal. Everything Xcode would have done silently is done here
# in the open, which is the only reason each step below can be checked.
#
# WHAT THIS MAC NEEDS, none of which a script can create for you:
#
#   1. A **Developer ID Application** certificate. Account Holder only, and this is the step
#      nobody else can do: Xcode > Settings > Accounts > (your Apple ID) > Manage Certificates >
#      + > Developer ID Application. `security find-identity -v -p codesigning` should then list
#      one. Keep the private key: losing it means a new certificate and, for anyone already
#      running Furlough, a system extension macOS treats as a different app's.
#
#   2. Two **Developer ID provisioning profiles**, made at developer.apple.com > Certificates,
#      Identifiers & Profiles > Profiles > + > Developer ID (under Distribution), one for
#      com.zachshort.furlough.mac and one for com.zachshort.furlough.mac.filter, each with the
#      Network Extension capability, and the app's also with iCloud (it carries the key-value
#      store the Anchor travels through). Save them as:
#
#          ~/.furlough/signing/FurloughMac.provisionprofile
#          ~/.furlough/signing/FurloughMacFilter.provisionprofile
#
#      Outside the repo, like the App Store Connect key, and overridable with FURLOUGH_SIGNING.
#      A profile is needed even for Developer ID here because both bundles carry restricted
#      entitlements; the App Group alone would not have needed one.
#
#   3. The App Store Connect key already used for TestFlight, which is what notarytool
#      authenticates with: ASC_KEY_ID, ASC_ISSUER_ID and ~/.appstoreconnect/private_keys/.
#
# Run `scripts/archive-mac.sh --check` and it will tell you which of those are missing, in the
# order to do them, rather than failing at signing time with a code.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

MODE="${1:-}"
case "$MODE" in
    ""|--check|--no-notarize) ;;
    *) echo "archive-mac.sh: no option $MODE (try --check or --no-notarize)" >&2; exit 1 ;;
esac

# A UTC timestamp always rises and says when the build was cut. It matters more here than on the
# phone: macOS compares an extension's CFBundleVersion when it is asked to replace one, and this
# project's CURRENT_PROJECT_VERSION sits at 1 in project.yml, so every unstamped build looked to
# macOS like the version it already had. See HANDOFF's note on the filter surviving an update.
BUILD="${BUILD:-$(date -u +%Y%m%d%H%M)}"
VERSION="$(grep -m1 'MARKETING_VERSION:' project.yml | awk '{print $2}' | tr -d '"')"

DERIVED="$ROOT/build/DerivedDataMacRelease"
STAGE="$ROOT/build/mac-release"
APP="$STAGE/Furlough.app"
EXTENSION_ID="com.zachshort.furlough.mac.filter"
SYSEX="$APP/Contents/Library/SystemExtensions/$EXTENSION_ID.systemextension"
WIDGET="$APP/Contents/PlugIns/FurloughMacWidgets.appex"
DMG="$STAGE/Furlough-$VERSION.dmg"

SIGNING="${FURLOUGH_SIGNING:-$HOME/.furlough/signing}"
APP_PROFILE="$SIGNING/FurloughMac.provisionprofile"
FILTER_PROFILE="$SIGNING/FurloughMacFilter.provisionprofile"
ASC_KEY_ID="${ASC_KEY_ID:-L6A2R4SBXQ}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-04f9fe5a-56e5-460f-80ac-c57e788fbdc6}"
NOTARY_KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

# ---------------------------------------------------------------------------------------------
# The preflight. Everything that can be known before a build starts is checked here, and every
# failure is collected rather than thrown, so `--check` prints the whole list of what to do
# instead of one thing at a time across five runs.
# ---------------------------------------------------------------------------------------------

MISSING=()
note()    { printf '    %s\n' "$*"; }
missing() { MISSING+=("$*"); }

echo "==> Checking what this Mac can sign with"

# The certificate. Matched on the name rather than on a hash so a renewed certificate keeps
# working; DEVELOPER_ID overrides it for a Mac with more than one.
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
SIGN_ID="${DEVELOPER_ID:-}"
if [[ -z "$SIGN_ID" ]]; then
    SIGN_ID="$(grep -m1 -o '"Developer ID Application: [^"]*"' <<<"$IDENTITIES" | tr -d '"' || true)"
fi
if [[ -n "$SIGN_ID" ]]; then
    note "certificate: $SIGN_ID"
else
    missing "A Developer ID Application certificate.
    Xcode > Settings > Accounts > your Apple ID > Manage Certificates > + > Developer ID
    Application. Account Holder only, so nobody else can make it for you, and everything
    else here waits on it."
fi

# The profiles. Each is decoded and read rather than trusted by its file name: the two ways this
# goes wrong quietly are a development profile saved under the release name, and a profile made
# before the Network Extension capability was added to the App ID.
check_profile() {
    local path="$1" identifier="$2" label="$3" wants_icloud="$4"
    if [[ ! -f "$path" ]]; then
        missing "The $label Developer ID profile, at
    $path
    Make it at developer.apple.com > Certificates, Identifiers & Profiles > Profiles > + >
    Developer ID, for $identifier, with the Network Extension capability$(
        if [[ "$wants_icloud" == "yes" ]]; then printf ' and iCloud'; fi)."
        return
    fi
    local decoded
    decoded="$(security cms -D -i "$path" 2>/dev/null || true)"
    if [[ -z "$decoded" ]]; then
        missing "$path is not a provisioning profile this Mac can decode."
        return
    fi
    local plist="$STAGE/.profile-check.plist"
    mkdir -p "$STAGE"
    printf '%s' "$decoded" > "$plist"
    local entitlements expires
    entitlements="$(plutil -extract Entitlements xml1 -o - "$plist" 2>/dev/null || true)"
    expires="$(plutil -extract ExpirationDate raw -o - "$plist" 2>/dev/null || echo unknown)"
    if plutil -extract ProvisionedDevices raw -o - "$plist" >/dev/null 2>&1; then
        missing "$(basename "$path") is a *development* profile: it lists provisioned devices.
    A Developer ID build needs the Developer ID kind, which lists none."
    fi
    if ! grep -qF "$identifier" <<<"$entitlements"; then
        missing "$path is not for $identifier."
    fi
    if ! grep -qF "content-filter-provider-systemextension" <<<"$entitlements"; then
        missing "$(basename "$path") does not carry content-filter-provider-systemextension.
    Its App ID needs the Network Extension capability, and the profile has to be made again
    after that is added — an existing profile does not pick it up."
    fi
    if [[ "$wants_icloud" == "yes" ]] && ! grep -qF "ubiquity-kvstore-identifier" <<<"$entitlements"; then
        missing "$(basename "$path") carries no iCloud key-value store. The Anchor crosses
    between devices through it, so a build signed with this profile would come up linked to
    nothing."
    fi
    rm -f "$plist"
    note "$label profile: $(basename "$path"), expires $expires"
}
check_profile "$APP_PROFILE" "com.zachshort.furlough.mac" "app" "yes"
check_profile "$FILTER_PROFILE" "com.zachshort.furlough.mac.filter" "filter" "no"

# The entitlements this script signs with, which are not the ones the project builds with.
for file in FurloughMac/FurloughMac-DeveloperID.entitlements \
            FurloughMacFilter/FurloughMacFilter-DeveloperID.entitlements \
            FurloughMacWidgets/FurloughMacWidgets.entitlements; do
    [[ -f "$ROOT/$file" ]] || missing "$file is gone. It is what codesign is handed below."
done

# Notarization. Checked now rather than after a ten-minute build and a signature.
if [[ "$MODE" != "--no-notarize" ]]; then
    if [[ -f "$NOTARY_KEY" ]]; then
        note "notary key: $NOTARY_KEY"
    else
        missing "The App Store Connect key at
    $NOTARY_KEY
    It is the same one TestFlight uses; ASC_KEY_ID and ASC_ISSUER_ID are in scripts/furlough."
    fi
    xcrun notarytool --help >/dev/null 2>&1 || missing "xcrun notarytool is not available."
fi

if (( ${#MISSING[@]} > 0 )); then
    echo
    echo "Not ready to cut a Mac release. ${#MISSING[@]} thing(s) to do:"
    echo
    for item in "${MISSING[@]}"; do printf '  - %s\n' "$item"; done
    echo
    echo "Everything else in this script is ready and waiting on them."
    exit 1
fi

if [[ "$MODE" == "--check" ]]; then
    echo
    echo "Ready: certificate, profiles, entitlements and the notary key are all in place."
    echo "Cut it with:  scripts/archive-mac.sh"
    exit 0
fi

# ---------------------------------------------------------------------------------------------
# The build, and the same promise check the phone's archive does.
# ---------------------------------------------------------------------------------------------

echo "==> Checking the version against release-notes.json"
if ! scripts/version.sh --check; then
    echo "REFUSING TO SHIP: the version and the release notes do not agree (see above)." >&2
    exit 1
fi

echo "==> Regenerating the project"
xcodegen generate

echo "==> Building Release  (version $VERSION, build $BUILD)"
rm -rf "$DERIVED/Build/Products/Release"
xcodebuild -project Furlough.xcodeproj -scheme FurloughMac -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  -derivedDataPath "$DERIVED" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  build

BUILT="$DERIVED/Build/Products/Release/Furlough.app"
[[ -d "$BUILT" ]] || { echo "REFUSING TO SHIP: no app at $BUILT." >&2; exit 1; }

echo "==> Checking the build is what it says it is"
APP_BINARY="$BUILT/Contents/MacOS/Furlough"
# Read each tool's output into a variable before probing it. `nm ... | grep -q` exits at the
# first match, the tool upstream takes SIGPIPE, and under `set -o pipefail` a probe that FOUND
# something reports "not found" — the fail-open that scripts/archive.sh documents at length.
NM_OUT="$(nm -a "$APP_BINARY" 2>/dev/null || true)"
STRINGS_OUT="$(strings -a "$APP_BINARY" 2>/dev/null || true)"

# The control first. A Debug build splits the binary into a stub and Furlough.debug.dylib, and
# every probe below would then be reading a 60KB stub that contains none of the app — reporting
# whatever the caller hoped for. It is also fatal in its own right: a system extension has to be
# one Mach-O, so a split build cannot install its filter at all.
if ! grep -qF "no unblock button" <<<"$STRINGS_OUT"; then
    echo "REFUSING TO SHIP: the control string is missing from the built binary." >&2
    echo "This is either not a Release build, or it is the debug-dylib stub. The checks here are" >&2
    echo "not measuring what they claim to. Do not trust them." >&2
    exit 1
fi
if [[ -f "$BUILT/Contents/MacOS/Furlough.debug.dylib" ]]; then
    echo "REFUSING TO SHIP: this build carries Furlough.debug.dylib, so its binary is a stub and" >&2
    echo "its extension is not one Mach-O. That is a Debug build; this script builds Release." >&2
    exit 1
fi

for probe in resetEverything clearEverything TestingTools; do
    if grep -q "$probe" <<<"$NM_OUT"; then
        echo "REFUSING TO SHIP: '$probe' is in the built binary." >&2
        echo "Testing-only code has leaked into Release — the Mac's Settings > Testing > Reset" >&2
        echo "everything is behind #if DEBUG || TESTING_TOOLS in FurloughMac/Model/MacModel.swift" >&2
        echo "and Shared/Core/TestingTools.swift. A release for other people must not carry it." >&2
        exit 1
    fi
done
note "clean: no testing-only code, one Mach-O, and the control string is present"

if [[ ! -d "$BUILT/Contents/Library/SystemExtensions/$EXTENSION_ID.systemextension" ]]; then
    echo "REFUSING TO SHIP: the web filter is not embedded in this build. Without it the Mac" >&2
    echo "enforces websites by reading browser tabs alone, which is half the promise." >&2
    exit 1
fi

# ---------------------------------------------------------------------------------------------
# Signing, inside out. Every nested bundle is signed before the thing that contains it, because
# signing a container seals whatever is inside it at that moment.
# ---------------------------------------------------------------------------------------------

echo "==> Staging"
rm -rf "$APP" "$DMG"
mkdir -p "$STAGE"
ditto "$BUILT" "$APP"

echo "==> Putting the Developer ID profiles in"
cp "$APP_PROFILE" "$APP/Contents/embedded.provisionprofile"
cp "$FILTER_PROFILE" "$SYSEX/Contents/embedded.provisionprofile"

# --options runtime is the hardened runtime, which notarization requires; --timestamp is the
# secure timestamp, without which the signature stops verifying the day the certificate expires.
sign() {
    local path="$1" entitlements="$2"
    echo "    signing $(basename "$path")"
    codesign --force --timestamp --options runtime \
        --sign "$SIGN_ID" --entitlements "$ROOT/$entitlements" "$path"
}

echo "==> Signing"
if [[ -d "$APP/Contents/Frameworks" ]]; then
    for framework in "$APP/Contents/Frameworks"/*; do
        [[ -e "$framework" ]] || continue
        echo "    signing $(basename "$framework")"
        codesign --force --timestamp --options runtime --sign "$SIGN_ID" "$framework"
    done
fi
sign "$SYSEX" "FurloughMacFilter/FurloughMacFilter-DeveloperID.entitlements"
if [[ -d "$WIDGET" ]]; then
    sign "$WIDGET" "FurloughMacWidgets/FurloughMacWidgets.entitlements"
fi
sign "$APP" "FurloughMac/FurloughMac-DeveloperID.entitlements"

echo "==> Reading the signature back"
codesign --verify --deep --strict --verbose=2 "$APP"
for bundle in "$SYSEX" "$WIDGET" "$APP"; do
    [[ -d "$bundle" ]] || continue
    authority="$(codesign -dv --verbose=4 "$bundle" 2>&1 | grep -m1 '^Authority=' || true)"
    grep -q "Developer ID Application" <<<"$authority" || {
        echo "REFUSING TO SHIP: $(basename "$bundle") is signed by ${authority:-nothing}." >&2
        exit 1; }
    entitlements="$(codesign -d --entitlements :- "$bundle" 2>/dev/null || true)"
    if grep -qF "get-task-allow" <<<"$entitlements"; then
        echo "REFUSING TO SHIP: $(basename "$bundle") still carries get-task-allow, which is a" >&2
        echo "development signature. Notarization rejects it." >&2
        exit 1
    fi
    note "$(basename "$bundle"): ${authority#Authority=}"
done

# The one entitlement a Developer ID build needs and a development build must not have. Read off
# the signature rather than off the file that was handed to codesign, because what ships is what
# was signed: an entitlement the profile does not grant is dropped here, silently, and the filter
# then refuses to load on somebody else's Mac with nothing in the app to say why.
for bundle in "$APP" "$SYSEX"; do
    entitlements="$(codesign -d --entitlements :- "$bundle" 2>/dev/null || true)"
    grep -qF "content-filter-provider-systemextension" <<<"$entitlements" || {
        echo "REFUSING TO SHIP: $(basename "$bundle") is not signed with" >&2
        echo "content-filter-provider-systemextension. macOS will not load the filter from this" >&2
        echo "build (DTS, developer forums 737894). The profile is the usual reason: it has to" >&2
        echo "carry the Network Extension capability before codesign will keep the entitlement." >&2
        exit 1; }
done
note "both bundles carry content-filter-provider-systemextension"

if [[ "$MODE" == "--no-notarize" ]]; then
    echo "==> Signed, not notarized: $APP"
    echo "    Gatekeeper will refuse it on any Mac but this one until it is."
    exit 0
fi

# ---------------------------------------------------------------------------------------------
# Notarization, then the DMG, then notarization again. The app is stapled before it goes into the
# disk image so that a copy dragged out of the image carries its own ticket and opens on a Mac
# that is offline; the image is stapled too, for the download itself.
# ---------------------------------------------------------------------------------------------

ZIP="$STAGE/Furlough-$VERSION-$BUILD.zip"
echo "==> Notarizing the app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" \
  --key "$NOTARY_KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
  --wait --timeout 30m
xcrun stapler staple "$APP"
rm -f "$ZIP"

echo "==> Building the disk image"
IMAGE="$STAGE/image"
rm -rf "$IMAGE"
mkdir -p "$IMAGE"
ditto "$APP" "$IMAGE/Furlough.app"
ln -s /Applications "$IMAGE/Applications"
hdiutil create -volname "Furlough" -srcfolder "$IMAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$IMAGE"

echo "==> Signing and notarizing the disk image"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
xcrun notarytool submit "$DMG" \
  --key "$NOTARY_KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
  --wait --timeout 30m
xcrun stapler staple "$DMG"

echo "==> What Gatekeeper makes of it"
spctl -a -t open --context context:primary-signature -vv "$DMG" || true
spctl -a -t exec -vv "$APP" || true

echo
echo "==> $DMG"
echo "    version $VERSION, build $BUILD"
echo "    $(du -h "$DMG" | cut -f1), sha256 $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo
echo "    The app inside has to land in /Applications: macOS loads a system extension from"
echo "    nowhere else, and the login item and the watchdog both point there."
