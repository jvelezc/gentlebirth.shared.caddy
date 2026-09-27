#!/usr/bin/env bash
# Probe every route in checks.txt. Writes "URL STATUS PASS|FAIL" lines to stdout.
# Usage: check-routes.sh [checks file]
set -uo pipefail
file="${1:-checks.txt}"
while read -r method url expected; do
  [[ -z "${method:-}" || "$method" == \#* ]] && continue
  status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -X "$method" "$url")"
  [[ "$status" == "$expected" ]] && result=PASS || result=FAIL
  printf '%s %s %s %s\n' "$method" "$url" "$status" "$result"
done < "$file"
