#!/usr/bin/env bash
#
# Finishes the App Store record for the version being prepared and, on request, submits it.
#
#   REVIEW_FIRST=Zach REVIEW_LAST=Short REVIEW_EMAIL=you@example.com REVIEW_PHONE='+1 555 555 5555' \
#   PRICE=free scripts/store-submit.sh            set everything, stop short of submitting
#   … scripts/store-submit.sh --submit            the same, then submit 1.0 for review
#
# The last of the store scripts. archive.sh --upload sends the build, store-upload.sh the
# screenshots; this one does the rest of what App Store Connect wants before the Submit button
# works, all through the API and none of it in the web form:
#
#   - attaches the newest VALID build to the version (or BUILD=202609090423 to pin one)
#   - sets the marketing URL (MARKETING_URL, default https://furloughapp.com)
#   - creates the availability, worldwide except the EU, if the app has none yet
#   - creates the price schedule if the app has none yet: PRICE=free, or a USD customer price
#     such as PRICE=2.99, matched against Apple's price points for the USA
#   - writes the App Review contact and the notes block from design/store/LISTING.md
#   - with --submit, creates the review submission for the version and submits it
#
# Each step reads before it writes and says what it found, so a re-run is safe: a record that
# already exists is left alone, a value that already matches is not rewritten. What it cannot
# do is the App Privacy questionnaire, which has no API; if that is unanswered, the submission
# is refused with a message saying so, and it is one screen in the web form.
#
# Same credentials as the other scripts: export ASC_KEY_ID and ASC_ISSUER_ID, with the .p8 at
# ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8, and fastlane installed.

set -euo pipefail

cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?set ASC_KEY_ID (see the header of this script)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (see the header of this script)}"
: "${REVIEW_FIRST:?set REVIEW_FIRST, the App Review contact's first name}"
: "${REVIEW_LAST:?set REVIEW_LAST, the App Review contact's last name}"
: "${REVIEW_EMAIL:?set REVIEW_EMAIL, the App Review contact's email}"
: "${REVIEW_PHONE:?set REVIEW_PHONE, the App Review contact's phone, with + and a country code}"
: "${PRICE:?set PRICE=free or a USD customer price such as PRICE=2.99}"

KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[[ -f "$KEY" ]] || { echo "No key at $KEY — see the header of this script." >&2; exit 1; }
command -v fastlane >/dev/null || { echo "fastlane not installed: brew install fastlane" >&2; exit 1; }

BUNDLE_ID="$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER:' project.yml | awk '{print $2}')"
[[ -n "$BUNDLE_ID" ]] || { echo "Could not read PRODUCT_BUNDLE_IDENTIFIER from project.yml" >&2; exit 1; }

# The review notes are the fenced block under "## App Review notes" in the listing, taken from
# the file rather than pasted here so there is one copy of them.
NOTES_FILE="$(mktemp)"
awk '/^## App Review notes/{s=1} s && /^```/{f++; next} s && f==1{print} s && f==2{exit}' design/store/LISTING.md > "$NOTES_FILE"
[[ -s "$NOTES_FILE" ]] || { echo "Could not find the App Review notes block in design/store/LISTING.md" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" "$NOTES_FILE"' EXIT
mkdir -p "$WORK/fastlane"
cat > "$WORK/fastlane/Fastfile" <<'RUBY'
require 'json'; require 'net/http'; require 'uri'

lane :submit do
  app_store_connect_api_key(key_id: ENV['ASC_KEY_ID'], issuer_id: ENV['ASC_ISSUER_ID'],
    key_filepath: ENV['KEY'], in_house: false)
  token = Spaceship::ConnectAPI.token.text
  call = ->(method, path, body = nil) do
    uri = URI("https://api.appstoreconnect.apple.com#{path}")
    req = { get: Net::HTTP::Get, patch: Net::HTTP::Patch, post: Net::HTTP::Post }[method].new(uri)
    req['Authorization'] = "Bearer #{token}"; req['Content-Type'] = 'application/json'
    req.body = JSON.generate(body) if body
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
    [res.code.to_i, (JSON.parse(res.body) rescue {})]
  end
  fail_on = ->(step, code, r) do
    return unless r["errors"]
    UI.user_error!("#{step}: HTTP #{code}: " + r["errors"].map { |e| "#{e['title']} — #{e['detail']}" }.join(" | "))
  end

  app = Spaceship::ConnectAPI::App.find(ENV['BUNDLE_ID'])
  version = app.get_edit_app_store_version(platform: Spaceship::ConnectAPI::Platform::IOS)
  UI.user_error!("No version in preparation for #{ENV['BUNDLE_ID']}") unless version
  UI.message("#{app.name} #{app.id} — version #{version.version_string} (#{version.app_store_state})")
  loc = version.get_app_store_version_localizations.find { |l| l.locale == app.primary_locale }

  # 1. The build.
  code, r = call.(:get, "/v1/builds?filter[app]=#{app.id}&filter[processingState]=VALID&sort=-uploadedDate&limit=20&fields[builds]=version,processingState")
  fail_on.("builds", code, r)
  builds = r["data"] || []
  build = ENV['BUILD'].to_s.empty? ? builds.first : builds.find { |b| b.dig('attributes', 'version') == ENV['BUILD'] }
  UI.user_error!("No VALID build #{ENV['BUILD']} found") unless build
  code, r = call.(:get, "/v1/appStoreVersions/#{version.id}?include=build")
  current = (r["included"] || []).map { |i| i.dig("attributes", "version") }.compact.first
  if current == build.dig("attributes", "version")
    UI.message("build #{current} already attached")
  else
    code, r = call.(:patch, "/v1/appStoreVersions/#{version.id}/relationships/build", { data: { type: "builds", id: build["id"] } })
    fail_on.("attach build", code, r)
    UI.success("attached build #{build.dig('attributes', 'version')} (was #{current || 'none'})")
  end

  # 2. The marketing URL.
  want = ENV['MARKETING_URL']
  if loc && loc.marketing_url != want
    code, r = call.(:patch, "/v1/appStoreVersionLocalizations/#{loc.id}", { data: { type: "appStoreVersionLocalizations", id: loc.id, attributes: { marketingUrl: want } } })
    fail_on.("marketing url", code, r)
    UI.success("marketing URL #{loc.marketing_url.inspect} -> #{want}")
  else
    UI.message("marketing URL already #{want}")
  end

  # 3. Availability: worldwide except the EU (design/store/LISTING.md, Territories).
  eu = %w[AUT BEL BGR HRV CYP CZE DNK EST FIN FRA DEU GRC HUN IRL ITA LVA LTU LUX MLT NLD POL PRT ROU SVK SVN ESP SWE]
  code, r = call.(:get, "/v1/apps/#{app.id}/appAvailabilityV2")
  if code == 404
    terrs = []; path = "/v1/territories?limit=200"
    while path
      c, t = call.(:get, path); fail_on.("territories", c, t)
      terrs += (t["data"] || []).map { |x| x["id"] }
      nxt = t.dig("links", "next"); path = nxt && nxt.sub("https://api.appstoreconnect.apple.com", "")
    end
    body = {
      data: { type: "appAvailabilities", attributes: { availableInNewTerritories: false },
              relationships: { app: { data: { type: "apps", id: app.id } },
                               territoryAvailabilities: { data: terrs.map { |t| { type: "territoryAvailabilities", id: "${#{t}}" } } } } },
      included: terrs.map { |t| { type: "territoryAvailabilities", id: "${#{t}}", attributes: { available: !eu.include?(t) },
                                  relationships: { territory: { data: { type: "territories", id: t } } } } }
    }
    code, r = call.(:post, "/v2/appAvailabilities", body)
    fail_on.("availability", code, r)
    UI.success("availability created: #{terrs.count - eu.count} territories on, the #{eu.count} EU members off")
  else
    fail_on.("availability", code, r)
    UI.message("availability already set; left alone")
  end

  # 4. Price.
  code, r = call.(:get, "/v1/appPriceSchedules/#{app.id}")
  if code == 404
    code, r = call.(:get, "/v1/apps/#{app.id}/appPricePoints?filter[territory]=USA&limit=200&fields[appPricePoints]=customerPrice")
    fail_on.("price points", code, r)
    want_price = ENV['PRICE'].downcase == 'free' ? 0.0 : Float(ENV['PRICE'])
    point = (r["data"] || []).find { |p| p.dig("attributes", "customerPrice").to_f == want_price }
    UI.user_error!("No USA price point at #{want_price}; Apple's USD points start #{(r['data'] || []).map { |p| p.dig('attributes', 'customerPrice') }.first(12).join(', ')} …") unless point
    body = {
      data: { type: "appPriceSchedules",
              relationships: { app: { data: { type: "apps", id: app.id } },
                               baseTerritory: { data: { type: "territories", id: "USA" } },
                               manualPrices: { data: [{ type: "appPrices", id: "${price}" }] } } },
      included: [{ type: "appPrices", id: "${price}", attributes: { startDate: nil },
                   relationships: { appPricePoint: { data: { type: "appPricePoints", id: point["id"] } } } }]
    }
    code, r = call.(:post, "/v1/appPriceSchedules", body)
    fail_on.("price schedule", code, r)
    UI.success("price schedule created: USD #{want_price} in the USA, Apple's equivalents elsewhere")
  else
    fail_on.("price schedule", code, r)
    UI.message("price schedule already set; left alone")
  end

  # 5. App Review contact and notes. The block validates as a unit, so every field goes each time.
  detail = version.fetch_app_store_review_detail
  attrs = { contactFirstName: ENV['REVIEW_FIRST'], contactLastName: ENV['REVIEW_LAST'],
            contactEmail: ENV['REVIEW_EMAIL'], contactPhone: ENV['REVIEW_PHONE'],
            demoAccountRequired: false, notes: File.read(ENV['NOTES_FILE']).strip }
  UI.user_error!("Review notes are #{attrs[:notes].length} chars; Apple's limit is 4000") if attrs[:notes].length > 4000
  if detail
    code, r = call.(:patch, "/v1/appStoreReviewDetails/#{detail.id}", { data: { type: "appStoreReviewDetails", id: detail.id, attributes: attrs } })
  else
    code, r = call.(:post, "/v1/appStoreReviewDetails", { data: { type: "appStoreReviewDetails", attributes: attrs, relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version.id } } } } })
  end
  fail_on.("review details", code, r)
  UI.success("review contact #{attrs[:contactFirstName]} #{attrs[:contactLastName]} written, notes #{attrs[:notes].length} chars")

  # 6. Submit, only when asked.
  unless ENV['DO_SUBMIT'] == '1'
    UI.important("Not submitting: run again with --submit when the record reads right.")
    next
  end
  code, r = call.(:get, "/v1/apps/#{app.id}/reviewSubmissions?filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES")
  fail_on.("review submissions", code, r)
  open_sub = (r["data"] || []).first
  if open_sub
    UI.important("A review submission already exists in state #{open_sub.dig('attributes', 'state')}; not creating another.")
    next
  end
  code, r = call.(:post, "/v1/reviewSubmissions", { data: { type: "reviewSubmissions", attributes: { platform: "IOS" }, relationships: { app: { data: { type: "apps", id: app.id } } } } })
  fail_on.("create submission", code, r)
  sub = r.dig("data", "id")
  code, r = call.(:post, "/v1/reviewSubmissionItems", { data: { type: "reviewSubmissionItems", relationships: { reviewSubmission: { data: { type: "reviewSubmissions", id: sub } }, appStoreVersion: { data: { type: "appStoreVersions", id: version.id } } } } })
  fail_on.("add version to submission", code, r)
  code, r = call.(:patch, "/v1/reviewSubmissions/#{sub}", { data: { type: "reviewSubmissions", id: sub, attributes: { submitted: true } } })
  fail_on.("submit", code, r)
  UI.success("Submitted for review: submission #{sub} is #{r.dig('data', 'attributes', 'state')}")
end
RUBY

DO_SUBMIT=0
[[ "${1:-}" == "--submit" ]] && DO_SUBMIT=1

cd "$WORK"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
KEY="$KEY" BUNDLE_ID="$BUNDLE_ID" NOTES_FILE="$NOTES_FILE" DO_SUBMIT="$DO_SUBMIT" \
MARKETING_URL="${MARKETING_URL:-https://furloughapp.com}" \
FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_OPT_OUT_USAGE=1 FASTLANE_DISABLE_ANIMATION=1 \
  fastlane submit < /dev/null
