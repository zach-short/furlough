#!/usr/bin/env bash
#
# Sends a build to TestFlight external beta review.
#
#   BUILD=202609091529 scripts/beta-submit.sh
#   BUILD=202609091529 WHATS_NEW="..." scripts/beta-submit.sh
#
# The TestFlight tab's "Submit for Review" through the API. Beta App Review (this script) and
# App Review (store-submit.sh/store-resubmit.sh) are separate queues that don't touch each
# other — submitting here does not disturb a version already waiting in App Review.
#
# Gates checked before anything is written: the build must be VALID, and its "What to Test"
# must be non-empty (Apple refuses an external build without one, with an unhelpful error).
#
# Submission is external-group membership: adding a build to a non-internal group is what puts
# it in front of Beta App Review. The explicit betaAppReviewSubmissions POST is tried first
# since it says what it did; group-add is the fallback the web form uses underneath. Both are
# idempotent — an already-submitted build is reported and left alone.
#
# Same credentials as the other store scripts: ASC_KEY_ID and ASC_ISSUER_ID, with the .p8 at
# ~/.appstoreconnect/private_keys/. No fastlane; the token is minted here.

set -euo pipefail
cd "$(dirname "$0")/.."

: "${BUILD:?set BUILD to the build number to submit, e.g. BUILD=202609091529}"
: "${ASC_KEY_ID:?set ASC_KEY_ID (see the header of this script)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (see the header of this script)}"
KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[[ -f "$KEY" ]] || { echo "no key at $KEY" >&2; exit 1; }
BUNDLE_ID="$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER:' project.yml | awk '{print $2}')"

exec ruby - "$BUILD" "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$KEY" "$BUNDLE_ID" "${WHATS_NEW:-}" <<'RUBY'
# encoding: utf-8
# Needed because this runs from stdin: ruby otherwise assumes US-ASCII and the em-dashes below
# are a syntax error.
require 'openssl'; require 'base64'; require 'json'; require 'net/http'; require 'uri'
build_number, key_id, issuer, key_path, bundle_id, whats_new = ARGV

pk = OpenSSL::PKey::EC.new(File.read(key_path))
b64 = ->(s) { Base64.urlsafe_encode64(s, padding: false) }
now = Time.now.to_i
input = b64.({ alg: 'ES256', kid: key_id, typ: 'JWT' }.to_json) + '.' +
        b64.({ iss: issuer, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' }.to_json)
der = pk.sign(OpenSSL::Digest::SHA256.new, input)
r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\0") }
TOKEN = input + '.' + b64.(r + s)

def attempt(method, path, body = nil)
  uri = URI('https://api.appstoreconnect.apple.com' + path)
  klass = { 'GET' => Net::HTTP::Get, 'PATCH' => Net::HTTP::Patch,
            'POST' => Net::HTTP::Post, 'DELETE' => Net::HTTP::Delete }[method]
  req = klass.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  if body
    req['Content-Type'] = 'application/json'
    req.body = body.to_json
  end
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  [res.code.to_i, (JSON.parse(res.body) rescue {})]
end

def request(method, path, body = nil)
  status, parsed = attempt(method, path, body)
  unless (200..299).include?(status)
    detail = (parsed['errors'] || []).map { |e| "#{e['title']}: #{e['detail']}" }.join("\n  ")
    abort "#{method} #{path} -> #{status}\n  #{detail}"
  end
  parsed
end

# --- the build ------------------------------------------------------------------------
app = request('GET', "/v1/apps?filter[bundleId]=#{bundle_id}")['data'].first
abort "no app for #{bundle_id}" unless app
app_id = app['id']

builds = request('GET', "/v1/builds?filter[app]=#{app_id}&filter[version]=#{build_number}")['data']
build = builds.first
abort "no build #{build_number} on #{bundle_id}" unless build
bid = build['id']
state = build.dig('attributes', 'processingState')
abort "build #{build_number} is #{state}, not VALID — nothing to submit yet" unless state == 'VALID'
puts "build #{build_number} (#{bid}) is VALID"

# --- already in review? ---------------------------------------------------------------
existing = request('GET', "/v1/builds/#{bid}/betaAppReviewSubmission")['data']
if existing
  s = existing.dig('attributes', 'betaReviewState')
  puts "already submitted for beta review: #{s} (#{existing.dig('attributes', 'submittedDate')})"
  exit 0 unless s == 'REJECTED'
  puts "previous beta review was REJECTED — submitting again"
end

# --- What to Test ---------------------------------------------------------------------
# Apple's error for an empty "What to Test" names neither the field nor the build — fill it
# before submitting, never after.
locs = request('GET', "/v1/betaBuildLocalizations?filter[build]=#{bid}")['data']
loc = locs.find { |l| l.dig('attributes', 'locale') == 'en-US' } || locs.first
current = loc && loc.dig('attributes', 'whatsNew')
if current.nil? || current.strip.empty?
  abort "build #{build_number} has no What to Test and none was given — set WHATS_NEW=..." if whats_new.empty?
  if loc
    request('PATCH', "/v1/betaBuildLocalizations/#{loc['id']}",
            { data: { type: 'betaBuildLocalizations', id: loc['id'],
                      attributes: { whatsNew: whats_new } } })
  else
    request('POST', '/v1/betaBuildLocalizations',
            { data: { type: 'betaBuildLocalizations',
                      attributes: { locale: 'en-US', whatsNew: whats_new },
                      relationships: { build: { data: { type: 'builds', id: bid } } } } })
  end
  puts "set What to Test (#{whats_new.length} chars)"
else
  puts "What to Test already set, left alone"
end

# --- submit ---------------------------------------------------------------------------
status, parsed = attempt('POST', '/v1/betaAppReviewSubmissions',
                         { data: { type: 'betaAppReviewSubmissions',
                                   relationships: { build: { data: { type: 'builds', id: bid } } } } })
if (200..299).include?(status)
  puts "submitted: #{parsed.dig('data', 'attributes', 'betaReviewState')}"
else
  # The explicit endpoint refuses in some account states; fall back to the group-add the web
  # form uses underneath.
  detail = (parsed['errors'] || []).map { |e| e['detail'] }.join('; ')
  puts "betaAppReviewSubmissions -> #{status} (#{detail})"
  puts "falling back to external-group membership, which is what the web form does"
  groups = request('GET', "/v1/betaGroups?filter[app]=#{app_id}&limit=50")['data']
  ext = groups.reject { |g| g.dig('attributes', 'isInternalGroup') }
  abort 'no external beta group on this app — make one in TestFlight first' if ext.empty?
  group = ext.first
  request('POST', "/v1/betaGroups/#{group['id']}/relationships/builds",
          { data: [{ type: 'builds', id: bid }] })
  puts "added to \"#{group.dig('attributes', 'name')}\" (#{group['id']})"
end

# --- what Apple thinks now ------------------------------------------------------------
sub = request('GET', "/v1/builds/#{bid}/betaAppReviewSubmission")['data']
det = request('GET', "/v1/builds/#{bid}/buildBetaDetail")['data']
puts "beta review state:   #{sub ? sub.dig('attributes', 'betaReviewState') : 'none'}"
puts "external build state: #{det.dig('attributes', 'externalBuildState')}"
RUBY
