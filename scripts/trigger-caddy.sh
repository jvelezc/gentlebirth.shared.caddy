#!/usr/bin/env bash
# Called by app repositories after a successful deploy to the shared Contabo host.
# Sends an app-deployed event to jvelezc/gentlebirth.shared.caddy and waits for the
# resulting Caddy run, failing if routes could not be applied or a route regressed.
#
# Requires: gh CLI, GH_TOKEN with access to the Caddy repository (repo scope, or a
# fine-grained token with Actions read/write + Contents read on that repository).
# Uses GITHUB_REPOSITORY, GITHUB_SHA, GITHUB_SERVER_URL, GITHUB_RUN_ID from Actions.
set -euo pipefail

caddy_repo="${SHARED_CADDY_REPOSITORY:-jvelezc/gentlebirth.shared.caddy}"
[[ -n "${GH_TOKEN:-}" ]] || { echo '::error::SHARED_CADDY_DISPATCH_TOKEN is not configured'; exit 1; }

run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

gh api "repos/${caddy_repo}/dispatches" --silent \
  -f event_type=app-deployed \
  -f "client_payload[repository]=${GITHUB_REPOSITORY}" \
  -f "client_payload[sha]=${GITHUB_SHA}" \
  -f "client_payload[run_url]=${run_url}"
echo "Sent app-deployed to ${caddy_repo} for ${GITHUB_REPOSITORY}@${GITHUB_SHA:0:12}"

run_id=''
for _ in $(seq 1 30); do
  run_id="$(gh run list -R "$caddy_repo" --event repository_dispatch --limit 20 \
    --json databaseId,displayTitle,createdAt \
    --jq "[.[] | select(.createdAt >= \"${started}\" and (.displayTitle | contains(\"${GITHUB_SHA}\")))] | .[0].databaseId // empty")"
  [[ -n "$run_id" ]] && break
  sleep 5
done
[[ -n "$run_id" ]] || { echo "::error::No Caddy run started for ${GITHUB_SHA}"; exit 1; }

echo "Caddy run: ${GITHUB_SERVER_URL}/${caddy_repo}/actions/runs/${run_id}"
if ! gh run watch "$run_id" -R "$caddy_repo" --exit-status --interval 10 >/dev/null; then
  echo "::error::Shared Caddy run failed: ${GITHUB_SERVER_URL}/${caddy_repo}/actions/runs/${run_id}"
  exit 1
fi
echo 'Shared Caddy applied and every public route check held.'
{
  echo '### Shared Caddy'
  echo "- Routes re-applied and verified: ${GITHUB_SERVER_URL}/${caddy_repo}/actions/runs/${run_id}"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
