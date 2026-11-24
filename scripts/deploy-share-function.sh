#!/usr/bin/env bash
# Idempotent: create share-task-python (if missing) and deploy functions/share-task.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WS="$(cd "$ROOT/.." && pwd)"
if [[ -z "${APPWRITE_API_KEY:-}" && -f "$WS/.env.provision" ]]; then
  # shellcheck disable=SC1091
  source "$WS/.env.provision"
fi
: "${APPWRITE_ENDPOINT:?}"
: "${APPWRITE_PROJECT_ID:?}"
: "${APPWRITE_API_KEY:?}"

FUNCTION_ID="share-task-python"
SRC="$ROOT/functions/share-task"
auth=(-H "X-Appwrite-Project: $APPWRITE_PROJECT_ID" -H "X-Appwrite-Key: $APPWRITE_API_KEY")
json() { python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))"; }

config='{
  "name":"Share task (Python)","runtime":"python-3.9","execute":["users"],
  "entrypoint":"main.py","commands":"pip install -r requirements.txt",
  "scopes":["users.read","rows.read","rows.write"],"timeout":15,"logging":true
}'

existing="$(curl -skS "${auth[@]}" "$APPWRITE_ENDPOINT/functions/$FUNCTION_ID")"

if [[ "${1:-}" == "--check" ]]; then
  [[ "$(json '$id' <<<"$existing")" == "$FUNCTION_ID" ]] || {
    echo "function $FUNCTION_ID not found" >&2
    exit 1
  }
  runtime="$(json 'runtime' <<<"$existing")"
  [[ "$runtime" == "python-3.9" ]] || {
    echo "expected runtime python-3.9 got $runtime" >&2
    exit 1
  }
  echo "deploy-share-function: OK (exists)"
  exit 0
fi

if [[ "$(json '$id' <<<"$existing")" == "$FUNCTION_ID" ]]; then
  echo "function exists — updating config"
  curl -skS -X PUT "${auth[@]}" -H "Content-Type: application/json" \
    "$APPWRITE_ENDPOINT/functions/$FUNCTION_ID" -d "$config" | head -c 200
else
  echo "creating function"
  body="$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); d['functionId']='$FUNCTION_ID'; print(json.dumps(d))" "$config")"
  curl -skS -X POST "${auth[@]}" -H "Content-Type: application/json" \
    "$APPWRITE_ENDPOINT/functions" -d "$body" | head -c 200
fi
echo

ARCHIVE="$(mktemp -t share-task-python.XXXXXX.tar.gz)"
trap 'rm -f "$ARCHIVE"' EXIT
tar -czf "$ARCHIVE" -C "$SRC" --exclude __pycache__ --exclude '.pytest_cache' --exclude 'test_*.py' .

deploy="$(curl -skS -X POST "${auth[@]}" "$APPWRITE_ENDPOINT/functions/$FUNCTION_ID/deployments" \
  -F "activate=true" -F "entrypoint=main.py" -F "commands=pip install -r requirements.txt" \
  -F "code=@$ARCHIVE;type=application/gzip;filename=code.tar.gz")"
DEPLOY_ID="$(json '$id' <<<"$deploy")"
[[ -n "$DEPLOY_ID" ]] || { echo "deployment failed: $deploy" >&2; exit 1; }
echo "deployment=$DEPLOY_ID"

for _ in $(seq 1 60); do
  status="$(curl -skS "${auth[@]}" "$APPWRITE_ENDPOINT/functions/$FUNCTION_ID/deployments/$DEPLOY_ID" | json status)"
  case "$status" in
    ready) echo "deploy-share-function: OK"; exit 0 ;;
    failed) echo "build failed" >&2
      curl -skS "${auth[@]}" "$APPWRITE_ENDPOINT/functions/$FUNCTION_ID/deployments/$DEPLOY_ID" | json buildLogs >&2
      exit 1 ;;
  esac
  sleep 5
done
echo "timeout waiting for $DEPLOY_ID" >&2
exit 1