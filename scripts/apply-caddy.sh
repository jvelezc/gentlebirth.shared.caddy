#!/usr/bin/env bash
# Install a staged Caddy configuration on the host, validate it, reload Caddy,
# and restore the previous configuration if anything fails.
# Usage (as root): apply-caddy.sh <staged directory containing Caddyfile and sites/>
set -Eeuo pipefail
umask 022

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || fail 'Run as root.'
stage="${1:-}"
[[ -f "$stage/Caddyfile" && -d "$stage/sites" ]] || fail "Stage must contain Caddyfile and sites/: $stage"
command -v caddy >/dev/null || fail 'Caddy is not installed.'

target=/etc/caddy
backup=/etc/caddy.previous

exec 9>/run/lock/shared-caddy-deploy.lock
flock -n 9 || fail 'Another Caddy deployment is active.'

echo '--- Changes against the live configuration'
diff -ruN --exclude='*.mancebo-previous' --exclude=apply-caddy.sh "$target" "$stage" || true

rm -rf "$backup"
cp -a "$target" "$backup"

restore() {
  local code=$?
  trap - EXIT
  set +e
  echo 'Restoring previous Caddy configuration.' >&2
  rm -rf "$target" && cp -a "$backup" "$target"
  caddy validate --config "$target/Caddyfile" --adapter caddyfile >/dev/null 2>&1 && systemctl reload caddy
  exit "$code"
}
trap restore EXIT

rm -rf "$target/sites"
install -o root -g root -m 0644 "$stage/Caddyfile" "$target/Caddyfile"
install -d -o root -g root -m 0755 "$target/sites"
install -o root -g root -m 0644 "$stage"/sites/*.caddy "$target/sites/"

caddy validate --config "$target/Caddyfile" --adapter caddyfile || fail 'Candidate configuration is invalid.'
systemctl reload caddy || fail 'Caddy rejected the reload.'
systemctl is-active --quiet caddy || fail 'Caddy is not active after reload.'

trap - EXIT
echo 'Caddy configuration applied and reloaded.'
