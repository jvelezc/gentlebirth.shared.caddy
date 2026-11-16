#!/usr/bin/env bash
# Exercise the real installer only inside a fresh disposable container.
set -euo pipefail
[[ -f /run/.containerenv || -f /.dockerenv ]] || { echo 'Disposable container required.' >&2; exit 1; }
[[ ! -e /etc/caddy ]] || { echo 'Expected an empty disposable filesystem.' >&2; exit 1; }
mkdir -p /etc/caddy/sites /tmp/caddy-fixture/bin /tmp/caddy-stage/sites
printf 'old-main\n' > /etc/caddy/Caddyfile
printf 'old-api\n' > /etc/caddy/sites/api.caddy
printf 'private-fixture-sentinel\n' > /etc/caddy/sites/legacy-private.caddy
chmod 0600 /etc/caddy/sites/legacy-private.caddy
cp -p /etc/caddy/sites/legacy-private.caddy /tmp/caddy-fixture/private-original
cat > /tmp/caddy-fixture/bin/caddy <<'CADDY'
#!/usr/bin/env bash
if [[ -f /tmp/reject-candidate ]] && grep -q bad-candidate /etc/caddy/Caddyfile; then exit 1; fi
CADDY
cat > /tmp/caddy-fixture/bin/systemctl <<'SYSTEMCTL'
#!/usr/bin/env bash
exit 0
SYSTEMCTL
chmod +x /tmp/caddy-fixture/bin/*
export PATH="/tmp/caddy-fixture/bin:$PATH"
installer=/workspace/scripts/apply-caddy.sh

test_apply_preserves_unmanaged_secret_site() {
  printf 'new-main\n' > /tmp/caddy-stage/Caddyfile
  printf 'new-api\n' > /tmp/caddy-stage/sites/api.caddy
  printf 'new-appointments\n' > /tmp/caddy-stage/sites/appointments.caddy
  bash "$installer" /tmp/caddy-stage > /tmp/caddy-fixture/apply.log 2>&1
  cmp /tmp/caddy-stage/Caddyfile /etc/caddy/Caddyfile
  cmp /tmp/caddy-stage/sites/api.caddy /etc/caddy/sites/api.caddy
  cmp /tmp/caddy-stage/sites/appointments.caddy /etc/caddy/sites/appointments.caddy
  cmp /tmp/caddy-fixture/private-original /etc/caddy/sites/legacy-private.caddy
  [[ "$(stat -c '%a' /etc/caddy/sites/legacy-private.caddy)" == 600 ]]
  ! grep -q private-fixture-sentinel /tmp/caddy-fixture/apply.log
  echo 'PASS test_apply_preserves_unmanaged_secret_site'
}

test_failed_validation_restores_owned_and_unmanaged_sites() {
  cp /etc/caddy/Caddyfile /tmp/caddy-fixture/previous-main
  cp /etc/caddy/sites/api.caddy /tmp/caddy-fixture/previous-api
  printf 'bad-candidate\n' > /tmp/caddy-stage/Caddyfile
  printf 'broken-api\n' > /tmp/caddy-stage/sites/api.caddy
  touch /tmp/reject-candidate
  if bash "$installer" /tmp/caddy-stage > /tmp/caddy-fixture/failure.log 2>&1; then
    echo 'Invalid candidate unexpectedly succeeded.' >&2; exit 1
  fi
  cmp /tmp/caddy-fixture/previous-main /etc/caddy/Caddyfile
  cmp /tmp/caddy-fixture/previous-api /etc/caddy/sites/api.caddy
  cmp /tmp/caddy-fixture/private-original /etc/caddy/sites/legacy-private.caddy
  [[ "$(stat -c '%a' /etc/caddy/sites/legacy-private.caddy)" == 600 ]]
  ! grep -q private-fixture-sentinel /tmp/caddy-fixture/failure.log
  echo 'PASS test_failed_validation_restores_owned_and_unmanaged_sites'
}

test_apply_preserves_unmanaged_secret_site
test_failed_validation_restores_owned_and_unmanaged_sites
