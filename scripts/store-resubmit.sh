#!/usr/bin/env bash
#
# Puts a newer build on the version App Review rejected, and resubmits the same submission.
#
#   BUILD=202609090936 scripts/store-resubmit.sh
#
# The two clicks in the web form after a rejection — swap the build under Version > Build,
# then "Resubmit to App Review" — through the API instead. It finds the iOS version whose
# state is REJECTED (or, failing that, the newest one that can still take a build), attaches
# the build, and marks the open submission submitted again. Reads before every write and says
# what it found; a build that is already attached is left alone.
#
# Written 2026-09-09, when 1.0 (202609090423) was rejected under 2.5.1 and the fix went up as
# 202609090936 while nobody was at the Mac. Same credentials as the other store scripts:
# ASC_KEY_ID and ASC_ISSUER_ID, with the .p8 at ~/.appstoreconnect/private_keys/. No fastlane:
# the token is minted here with OpenSSL.

set -euo pipefail
cd "$(dirname "$0")/.."

: "${BUILD:?set BUILD to the build number to attach, e.g. BUILD=202609090936}"
: "${ASC_KEY_ID:?set ASC_KEY_ID (see the header of this script)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (see the header of this script)}"
KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[[ -f "$KEY" ]] || { echo "no key at $KEY" >&2; exit 1; }
BUNDLE_ID="$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER:' project.yml | awk '{print $2}')"

exec ruby - "$BUILD" "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$KEY" "$BUNDLE_ID" <<'RUBY'
require 'openssl'; require 'base64'; require 'json'; require 'net/http'; require 'uri'
build_number, key_id, issuer, key_path, bundle_id = ARGV

pk = OpenSSL::PKey::EC.new(File.read(key_path))
b64 = ->(s) { Base64.urlsafe_encode64(s, padding: false) }
now = Time.now.to_i
input = b64.({ alg: 'ES256', kid: key_id, typ: 'JWT' }.to_json) + '.' +
        b64.({ iss: issuer, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' }.to_json)
der = pk.sign(OpenSSL::Digest::SHA256.new, input)
r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\0") }
token = input + '.' + b64.(r + s)

def request(token, method, path, body = nil)
  uri = URI('https://api.appstoreconnect.apple.com' + path)
  klass = { 'GET' => Net::HTTP::Get, 'PATCH' => Net::HTTP::Patch, 'POST' => Net::HTTP::Post }[method]
  req = klass.new(uri)
  req['Authorization'] = "Bearer #{token}"
  if body
    req['Content-Type'] = 'application/json'
    req.body = body.to_json
  end
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  json = res.body.to_s.empty? ? {} : JSON.parse(res.body)
  unless res.code.to_i < 300
    warn "#{method} #{path} -> #{res.code}"
    warn JSON.pretty_generate(json)
    exit 1
  end
  json
end

apps = request(token, 'GET', "/v1/apps?filter[bundleId]=#{bundle_id}")['data']
abort "no app with bundle id #{bundle_id}" if apps.empty?
app_id = apps.first['id']

builds = request(token, 'GET', "/v1/builds?filter[app]=#{app_id}&filter[version]=#{build_number}&fields[builds]=version,processingState")['data']
abort "build #{build_number} is not on App Store Connect" if builds.empty?
build = builds.first
abort "build #{build_number} is #{build['attributes']['processingState']}, not VALID yet; wait for processing" unless build['attributes']['processingState'] == 'VALID'
puts "build #{build_number}: #{build['id']} (VALID)"

versions = request(token, 'GET', "/v1/apps/#{app_id}/appStoreVersions?filter[platform]=IOS&fields[appStoreVersions]=versionString,appVersionState&include=build&fields[builds]=version")
version = versions['data'].find { |v| v['attributes']['appVersionState'] == 'REJECTED' } ||
          versions['data'].find { |v| %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED METADATA_REJECTED INVALID_BINARY].include?(v['attributes']['appVersionState']) }
abort "no iOS version is in a state that takes a build" unless version
attached = (versions['included'] || []).find { |b| b['id'] == version.dig('relationships', 'build', 'data', 'id') }
puts "version #{version['attributes']['versionString']}: #{version['attributes']['appVersionState']}, build #{attached ? attached['attributes']['version'] : 'none'}"

if attached && attached['id'] == build['id']
  puts "build already attached; nothing to change"
else
  request(token, 'PATCH', "/v1/appStoreVersions/#{version['id']}/relationships/build",
          { data: { type: 'builds', id: build['id'] } })
  check = request(token, 'GET', "/v1/appStoreVersions/#{version['id']}?include=build&fields[builds]=version&fields[appStoreVersions]=versionString")
  got = (check['included'] || []).first&.dig('attributes', 'version')
  abort "attach did not stick: version shows build #{got.inspect}" unless got == build_number
  puts "attached build #{build_number} to version #{version['attributes']['versionString']}"
end

subs = request(token, 'GET', "/v1/apps/#{app_id}/reviewSubmissions?filter[platform]=IOS&fields[reviewSubmissions]=state,submittedDate")['data']
open = subs.find { |s| %w[UNRESOLVED_ISSUES READY_FOR_REVIEW].include?(s['attributes']['state']) }
abort "no submission to resubmit (states: #{subs.map { |s| s['attributes']['state'] }.join(', ')}). Use scripts/store-submit.sh --submit to make one." unless open
puts "submission #{open['id']}: #{open['attributes']['state']}"

request(token, 'PATCH', "/v1/reviewSubmissions/#{open['id']}",
        { data: { type: 'reviewSubmissions', id: open['id'], attributes: { submitted: true } } })
after = request(token, 'GET', "/v1/reviewSubmissions/#{open['id']}?fields[reviewSubmissions]=state")['data']['attributes']['state']
puts "resubmitted: #{after}"
RUBY
