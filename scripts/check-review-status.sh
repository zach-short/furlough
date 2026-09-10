#!/usr/bin/env bash
#
# Polls App Store Connect for Furlough's App Store review state and fires a macOS
# notification only when it changes from the last-seen state. Read-only (get_app_store_versions),
# never writes anything to App Store Connect. Meant to run from the LaunchAgent
# com.zachshort.furlough.reviewstatus, not by hand, though running it by hand is safe.
#
# State lives outside the repo (~/Library/Application Support/Furlough) so it is not
# something a git session ever sees or touches.

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH"

ASC_KEY_ID="L6A2R4SBXQ"
ASC_ISSUER_ID="04f9fe5a-56e5-460f-80ac-c57e788fbdc6"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
BUNDLE_ID="com.zachshort.furlough"

STATE_DIR="$HOME/Library/Application Support/Furlough"
STATE_FILE="$STATE_DIR/review-status.state"
LOG_DIR="$HOME/Library/Logs/Furlough"
LOG_FILE="$LOG_DIR/review-status.log"
mkdir -p "$STATE_DIR" "$LOG_DIR"

ts() { date '+%Y-%m-%d %H:%M:%S %z'; }

[[ -f "$KEY_PATH" ]] || { echo "[$(ts)] no key at $KEY_PATH, skipping" >> "$LOG_FILE"; exit 0; }
command -v fastlane >/dev/null || { echo "[$(ts)] fastlane not found" >> "$LOG_FILE"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/fastlane"
cat > "$WORK/fastlane/Fastfile" <<RUBY
lane :appstate do
  app_store_connect_api_key(
    key_id: "${ASC_KEY_ID}",
    issuer_id: "${ASC_ISSUER_ID}",
    key_filepath: "${KEY_PATH}",
    in_house: false
  )
  app = Spaceship::ConnectAPI::App.find("${BUNDLE_ID}")
  v = app.get_app_store_versions.first
  if v
    puts "STATE:#{v.app_store_state}"
    puts "VERSION:#{v.version_string}"
  else
    puts "STATE:NONE"
  end
end
RUBY

cd "$WORK"
if ! OUTPUT="$(FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_OPT_OUT_USAGE=1 FASTLANE_DISABLE_ANIMATION=1 \
    fastlane appstate < /dev/null 2>&1)"; then
  echo "[$(ts)] check failed:" >> "$LOG_FILE"
  echo "$OUTPUT" >> "$LOG_FILE"
  exit 1
fi

CURRENT_STATE="$(grep -o 'STATE:[A-Z_]*' <<<"$OUTPUT" | head -1 | cut -d: -f2)"
VERSION="$(grep -o 'VERSION:[0-9.]*' <<<"$OUTPUT" | head -1 | cut -d: -f2)"

if [[ -z "$CURRENT_STATE" ]]; then
  echo "[$(ts)] could not parse state, raw output:" >> "$LOG_FILE"
  echo "$OUTPUT" >> "$LOG_FILE"
  exit 1
fi

LAST_STATE=""
[[ -f "$STATE_FILE" ]] && LAST_STATE="$(cat "$STATE_FILE")"

echo "[$(ts)] version=$VERSION state=$CURRENT_STATE (last=$LAST_STATE)" >> "$LOG_FILE"

if [[ "$CURRENT_STATE" != "$LAST_STATE" ]]; then
  echo "$CURRENT_STATE" > "$STATE_FILE"
  if [[ -n "$LAST_STATE" ]]; then
    osascript -e "display notification \"Furlough $VERSION: $LAST_STATE → $CURRENT_STATE\" with title \"App Store review status changed\" sound name \"Glass\"" || true
  fi
fi
