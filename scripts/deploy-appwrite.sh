#!/usr/bin/env bash
set -euo pipefail
: "${APPWRITE_ENDPOINT:?}"
: "${APPWRITE_PROJECT_ID:?}"
: "${APPWRITE_API_KEY:?}"
: "${APPWRITE_SITE_ID:?}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${ROOT}/dist"
if [ ! -d "$DIST" ]; then
  echo "dist/ missing — run scripts/build-dist.sh" >&2
  exit 1
fi
ARCHIVE="$(mktemp -t canary-deploy.XXXXXX.tar.gz)"
trap 'rm -f "$ARCHIVE"' EXIT
tar -czf "$ARCHIVE" -C "$DIST" .
auth=(-H "X-Appwrite-Project: ${APPWRITE_PROJECT_ID}" -H "X-Appwrite-Key: ${APPWRITE_API_KEY}")
DEPLOY_JSON="$(curl -skS -X POST "${APPWRITE_ENDPOINT%/}/sites/${APPWRITE_SITE_ID}/deployments" "${auth[@]}" -F "entrypoint=" -F "activate=true" -F "code=@${ARCHIVE};type=application/gzip;filename=code.tar.gz")"
DEPLOY_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("$id",""))' <<<"$DEPLOY_JSON")"
[ -n "$DEPLOY_ID" ] || { echo "create deployment failed: $DEPLOY_JSON" >&2; exit 1; }
for _ in $(seq 1 60); do
  STATUS="$(curl -skS "${APPWRITE_ENDPOINT%/}/sites/${APPWRITE_SITE_ID}/deployments/${DEPLOY_ID}" "${auth[@]}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
  [ "$STATUS" = "ready" ] && { echo deployment ready; exit 0; }
  [ "$STATUS" = "failed" ] && exit 1
  sleep 5
done
exit 1