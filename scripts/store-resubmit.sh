#!/usr/bin/env bash
#
# Puts a newer build on the version App Review rejected, and resubmits the same submission.
#
#   BUILD=202609090936 scripts/store-resubmit.sh
#   VERSION=1.1 BUILD=202609111514 scripts/store-resubmit.sh   …renaming the record first
#
# The two clicks in the web form after a rejection — swap the build under Version > Build, then
# "Resubmit to App Review" — through the API instead: finds the REJECTED iOS version (or the
# newest one that can still take a build), attaches the build, marks the open submission
# submitted again. Reads before every write; an already-attached build is left alone.
#
# A rejected item can't be resubmitted as-is, so the version goes back in as a fresh item (what
# the web form does underneath) and a just-changed version can take a moment to settle — both
# surface as 409 "not ready to be submitted yet", which this waits out 30s at a time.
#
# Same credentials as the other store scripts: ASC_KEY_ID and ASC_ISSUER_ID, with the .p8 at
# ~/.appstoreconnect/private_keys/. No fastlane: the token is minted here with OpenSSL.

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

# Nothing here exits; `request` below does.
def attempt(token, method, path, body = nil)
  uri = URI('https://api.appstoreconnect.apple.com' + path)
  klass = { 'GET' => Net::HTTP::Get, 'PATCH' => Net::HTTP::Patch, 'POST' => Net::HTTP::Post, 'DELETE' => Net::HTTP::Delete }[method]
  req = klass.new(uri)
  req['Authorization'] = "Bearer #{token}"
  if body
    req['Content-Type'] = 'application/json'
    req.body = body.to_json
  end
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  [res.code.to_i, res.body.to_s.empty? ? {} : JSON.parse(res.body)]
end

def request(token, method, path, body = nil)
  code, json = attempt(token, method, path, body)
  unless code < 300
    warn "#{method} #{path} -> #{code}"
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

# `build` must be named in the sparse fieldset, or the relationship is left out of the answer
# and this re-attaches the same build every run, restarting Apple's checks and making the
# resubmit below fail as "not ready yet" indefinitely. Found out the hard way.
versions = request(token, 'GET', "/v1/apps/#{app_id}/appStoreVersions?filter[platform]=IOS&fields[appStoreVersions]=versionString,appVersionState,build&include=build&fields[builds]=version")
version = versions['data'].find { |v| v['attributes']['appVersionState'] == 'REJECTED' } ||
          versions['data'].find { |v| %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED METADATA_REJECTED INVALID_BINARY].include?(v['attributes']['appVersionState']) }
abort "no iOS version is in a state that takes a build" unless version
attached_id = version.dig('relationships', 'build', 'data', 'id')
attached = (versions['included'] || []).find { |b| b['id'] == attached_id }
puts "version #{version['attributes']['versionString']}: #{version['attributes']['appVersionState']}, build #{attached ? attached['attributes']['version'] : 'none'}"

# App Store Connect refuses a build whose CFBundleShortVersionString differs from the version
# record's, so renaming the record is how a rejected, never-shipped release takes a build cut
# under a later number. Set VERSION to rename; left unset, the record keeps its name.
target_version = ENV['VERSION'].to_s
unless target_version.empty? || target_version == version['attributes']['versionString']
  request(token, 'PATCH', "/v1/appStoreVersions/#{version['id']}",
          { data: { type: 'appStoreVersions', id: version['id'],
                    attributes: { versionString: target_version } } })
  puts "renamed version #{version['attributes']['versionString']} -> #{target_version}"
  version['attributes']['versionString'] = target_version
end

if attached_id == build['id']
  puts "build already attached; nothing to change"
else
  request(token, 'PATCH', "/v1/appStoreVersions/#{version['id']}/relationships/build",
          { data: { type: 'builds', id: build['id'] } })
  check = request(token, 'GET', "/v1/appStoreVersions/#{version['id']}?include=build&fields[builds]=version&fields[appStoreVersions]=versionString,build")
  got = (check['included'] || []).first&.dig('attributes', 'version')
  abort "attach did not stick: version shows build #{got.inspect}" unless got == build_number
  puts "attached build #{build_number} to version #{version['attributes']['versionString']}"
end

subs = request(token, 'GET', "/v1/apps/#{app_id}/reviewSubmissions?filter[platform]=IOS&fields[reviewSubmissions]=state,submittedDate")['data']
open = subs.find { |s| %w[UNRESOLVED_ISSUES READY_FOR_REVIEW].include?(s['attributes']['state']) }
abort "no submission to resubmit (states: #{subs.map { |s| s['attributes']['state'] }.join(', ')}). Use scripts/store-submit.sh --submit to make one." unless open
puts "submission #{open['id']}: #{open['attributes']['state']}"

# The web form's Edit > Add for Review marks the rejected item resolved (API: `resolved: true`),
# moving it and the version to READY_FOR_REVIEW; without this the resubmit below answers "not
# ready to be submitted yet" indefinitely, and a submission with unresolved issues refuses new
# items too. The item's version relationship only appears in the response when asked for by name.
items = request(token, 'GET', "/v1/reviewSubmissions/#{open['id']}/items?fields[reviewSubmissionItems]=state,appStoreVersion&include=appStoreVersion&fields[appStoreVersions]=versionString")['data']
mine = items.select do |i|
  linked = i.dig('relationships', 'appStoreVersion', 'data', 'id')
  linked.nil? || linked == version['id']
end
puts "  items for this version: #{mine.map { |i| i['attributes']['state'] }.join(', ')}" unless mine.empty?
mine.select { |i| i['attributes']['state'] == 'REJECTED' }.each do |item|
  after = request(token, 'PATCH', "/v1/reviewSubmissionItems/#{item['id']}",
                  { data: { type: 'reviewSubmissionItems', id: item['id'], attributes: { resolved: true } } })
  puts "  marked the rejected item resolved: now #{after.dig('data', 'attributes', 'state')}"
end
state = request(token, 'GET', "/v1/appStoreVersions/#{version['id']}?fields[appStoreVersions]=appVersionState")['data']['attributes']['appVersionState']
puts "version is #{state}"

# Up to five minutes of "not ready yet" before giving up.
10.times do |i|
  code, json = attempt(token, 'PATCH', "/v1/reviewSubmissions/#{open['id']}",
                       { data: { type: 'reviewSubmissions', id: open['id'], attributes: { submitted: true } } })
  break if code < 300
  details = (json['errors'] || []).flat_map { |e| [e['detail']] + (e.dig('meta', 'associatedErrors') || {}).values.flatten.map { |a| a['detail'] } }.compact
  not_ready = code == 409 && details.any? { |d| d.include?('not ready to be submitted yet') }
  if !not_ready || i == 9
    warn "PATCH /v1/reviewSubmissions/#{open['id']} -> #{code}"
    warn JSON.pretty_generate(json)
    exit 1
  end
  puts "  not ready yet (#{Time.now.strftime('%H:%M:%S')}); waiting 30s"
  $stdout.flush
  sleep 30
end
after = request(token, 'GET', "/v1/reviewSubmissions/#{open['id']}?fields[reviewSubmissions]=state")['data']['attributes']['state']
puts "resubmitted: #{after}"
RUBY
