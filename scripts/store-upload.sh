#!/usr/bin/env bash
#
# Sends the rendered App Store screenshots to App Store Connect.
#
#   scripts/store-upload.sh          upload build/store-shots/*.jpg as the 6.9-inch iPhone set
#
# The third of the store scripts: store-shots.sh renders the frames, this one uploads them,
# and archive.sh/status.sh handle the build. It touches nothing but the screenshots of the
# version that is being prepared: no metadata, no binary, no submission. Whatever screenshots
# that version already has are replaced, so the set on Apple's side always matches the
# folder here. The 1320x2868 frames land as iPhone 6.9-inch, which Apple accepts in place of
# the 6.5-inch set; deliver reads the device from the pixel size.
#
# Same credentials as status.sh: export ASC_KEY_ID and ASC_ISSUER_ID, with the .p8 at
# ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8, and fastlane installed.

set -euo pipefail

cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?set ASC_KEY_ID (see the header of this script)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (see the header of this script)}"

KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[[ -f "$KEY" ]] || { echo "No key at $KEY — see the header of this script." >&2; exit 1; }
command -v fastlane >/dev/null || { echo "fastlane not installed: brew install fastlane" >&2; exit 1; }

SHOTS="$PWD/build/store-shots"
ls "$SHOTS"/[0-9][0-9].jpg >/dev/null 2>&1 || { echo "No frames in $SHOTS — run scripts/store-shots.sh first." >&2; exit 1; }

BUNDLE_ID="$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER:' project.yml | awk '{print $2}')"
[[ -n "$BUNDLE_ID" ]] || { echo "Could not read PRODUCT_BUNDLE_IDENTIFIER from project.yml" >&2; exit 1; }

# deliver wants one folder per language under the screenshots path, and a Fastfile beside the
# working directory. Both are staged in a temp dir so the repo carries neither.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/fastlane" "$WORK/screenshots/en-US"
cp "$SHOTS"/[0-9][0-9].jpg "$WORK/screenshots/en-US/"
echo "==> Uploading $(ls "$WORK/screenshots/en-US" | wc -l | tr -d ' ') frames for $BUNDLE_ID"

cat > "$WORK/fastlane/Fastfile" <<RUBY
lane :shots do
  app_store_connect_api_key(
    key_id: "${ASC_KEY_ID}",
    issuer_id: "${ASC_ISSUER_ID}",
    key_filepath: "${KEY}",
    in_house: false
  )
  deliver(
    app_identifier: "${BUNDLE_ID}",
    platform: "ios",
    screenshots_path: "${WORK}/screenshots",
    overwrite_screenshots: true,
    skip_binary_upload: true,
    skip_metadata: true,
    skip_app_version_update: true,
    submit_for_review: false,
    run_precheck_before_submit: false,
    precheck_include_in_app_purchases: false,
    force: true
  )
end
RUBY

cd "$WORK"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_OPT_OUT_USAGE=1 FASTLANE_DISABLE_ANIMATION=1 \
  fastlane shots < /dev/null
