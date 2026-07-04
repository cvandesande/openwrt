#!/usr/bin/env bash
set -euo pipefail

if [ -z "${GITHUB_APP_ID:-}" ]; then
	printf '::error::GITHUB_APP_ID is required\n' >&2
	exit 1
fi

if [ -z "${GITHUB_APP_PRIVATE_KEY:-}" ]; then
	printf '::error::GITHUB_APP_PRIVATE_KEY is required\n' >&2
	exit 1
fi

if [ -z "${GITHUB_REPOSITORY:-}" ]; then
	printf '::error::GITHUB_REPOSITORY is required\n' >&2
	exit 1
fi

if [ -z "${GITHUB_OUTPUT:-}" ]; then
	printf '::error::GITHUB_OUTPUT is required\n' >&2
	exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

key_file="${tmpdir}/app-private-key.pem"
printf '%s\n' "$GITHUB_APP_PRIVATE_KEY" > "$key_file"
chmod 0600 "$key_file"

b64url() {
	openssl base64 -A | tr '+/' '-_' | tr -d '='
}

now="$(date +%s)"
iat="$((now - 60))"
exp="$((now + 540))"

header='{"alg":"RS256","typ":"JWT"}'
payload="$(printf '{"iat":%s,"exp":%s,"iss":"%s"}' "$iat" "$exp" "$GITHUB_APP_ID")"
unsigned="$(printf '%s' "$header" | b64url).$(printf '%s' "$payload" | b64url)"
signature="$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$key_file" -binary | b64url)"
jwt="${unsigned}.${signature}"

api_root="${GITHUB_API_URL:-https://api.github.com}"
installation_json="${tmpdir}/installation.json"
http_code="$(curl -sS -w '%{http_code}' -o "$installation_json" \
	-H "Authorization: Bearer ${jwt}" \
	-H 'Accept: application/vnd.github+json' \
	-H 'X-GitHub-Api-Version: 2022-11-28' \
	"${api_root}/repos/${GITHUB_REPOSITORY}/installation")"

if [ "$http_code" != 200 ]; then
	printf '::error::Failed to get GitHub App installation for %s (HTTP %s)\n' "$GITHUB_REPOSITORY" "$http_code" >&2
	cat "$installation_json" >&2 || true
	exit 1
fi

installation_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$installation_json")"
body='{"permissions":{"contents":"write","workflows":"write"}}'
token_json="${tmpdir}/token.json"
http_code="$(curl -sS -w '%{http_code}' -o "$token_json" \
	-X POST \
	-H "Authorization: Bearer ${jwt}" \
	-H 'Accept: application/vnd.github+json' \
	-H 'X-GitHub-Api-Version: 2022-11-28' \
	-d "$body" \
	"${api_root}/app/installations/${installation_id}/access_tokens")"

if [ "$http_code" != 201 ]; then
	printf '::error::Failed to create GitHub App installation token (HTTP %s)\n' "$http_code" >&2
	cat "$token_json" >&2 || true
	exit 1
fi

token="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$token_json")"
printf '::add-mask::%s\n' "$token"
printf 'token=%s\n' "$token" >> "$GITHUB_OUTPUT"
