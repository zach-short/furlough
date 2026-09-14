#!/usr/bin/env bash
#
# What App Store Connect thinks of the builds that have been uploaded.
#
#   scripts/status.sh          the last 6 builds, newest first
#   scripts/status.sh 20       the last 20
#
# The companion to archive.sh: that one sends a build, this one says what became of it. An
# upload is only half an answer — altool reports "UPLOAD SUCCEEDED" the moment the bytes land,
# but Apple then processes for a minute to an hour and can still reject for a missing
# entitlement, a bad icon, or export compliance. The build can't be installed until VALID.
#
# Same credentials as `archive.sh --upload`, read from ~/.appstoreconnect/private_keys/ by
# fastlane's `app_store_connect_api_key` action rather than `--api_key_path`, which wants the
# private key pasted into a JSON file instead of read from its path.
#
# Needs fastlane (`brew install fastlane`) for the App Store Connect API, instead of hand-rolling
# an ES256 JWT in bash.

set -euo pipefail

cd "$(dirname "$0")/.."

LIMIT="${1:-6}"
: "${ASC_KEY_ID:?set ASC_KEY_ID (see the header of this script)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (see the header of this script)}"

KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[[ -f "$KEY" ]] || { echo "No key at $KEY — see the header of this script." >&2; exit 1; }
command -v fastlane >/dev/null || { echo "fastlane not installed: brew install fastlane" >&2; exit 1; }

# The app target is first in project.yml; its extensions carry the same prefix with a suffix.
BUNDLE_ID="$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER:' project.yml | awk '{print $2}')"
[[ -n "$BUNDLE_ID" ]] || { echo "Could not read PRODUCT_BUNDLE_IDENTIFIER from project.yml" >&2; exit 1; }

# fastlane insists on a fastlane/Fastfile beside the working directory; a temp dir keeps that
# scaffolding out of the repo.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/fastlane"
cat > "$WORK/fastlane/Fastfile" <<RUBY
lane :status do
  app_store_connect_api_key(
    key_id: "${ASC_KEY_ID}",
    issuer_id: "${ASC_ISSUER_ID}",
    key_filepath: "${KEY}",
    in_house: false
  )
  app = Spaceship::ConnectAPI::App.find("${BUNDLE_ID}")
  UI.success("#{app.name} — Apple ID #{app.id}")
  builds = app.get_builds(includes: "preReleaseVersion,buildBetaDetail").first(${LIMIT})
  UI.important("No builds uploaded yet.") if builds.empty?
  builds.each do |b|
    d = b.build_beta_detail
    # The two beta states below only mean anything once processing_state reads VALID.
    UI.message(format("%-8s %-16s %-12s internal=%-24s external=%s",
                      b.pre_release_version&.version || "?",
                      "(#{b.version})",
                      b.processing_state,
                      d&.internal_build_state || "-",
                      d&.external_build_state || "-"))
  end
end
RUBY

cd "$WORK"
FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_OPT_OUT_USAGE=1 FASTLANE_DISABLE_ANIMATION=1 \
  fastlane status < /dev/null
