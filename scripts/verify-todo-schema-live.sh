#!/usr/bin/env bash
# Assert Todo TablesDB schema (tables + title fulltext index).
set -euo pipefail
WS="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1090
source "$WS/.env.provision"
: "${APPWRITE_ENDPOINT:?}"
: "${APPWRITE_PROJECT_ID:?}"
: "${APPWRITE_API_KEY:?}"

SHARE_FUNCTION_ID="${SHARE_FUNCTION_ID:-share-task-python}"

api() {
  curl -skS -H "X-Appwrite-Project: $APPWRITE_PROJECT_ID" \
    -H "X-Appwrite-Key: $APPWRITE_API_KEY" \
    "$@"
}

for table in lists tasks; do
  api "$APPWRITE_ENDPOINT/tablesdb/todo/tables/$table" | grep -q '"$id"' || {
    echo "missing table $table" >&2
    exit 1
  }
done

idx="$(api "$APPWRITE_ENDPOINT/tablesdb/todo/tables/tasks/indexes/title_search")"
echo "$idx" | grep -q '"type":"fulltext"' || {
  echo "missing fulltext index title_search" >&2
  echo "$idx" >&2
  exit 1
}
status="$(echo "$idx" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
[[ "$status" == "available" ]] || echo "warn: index status=$status (may still be processing)"

table="$(api "$APPWRITE_ENDPOINT/tablesdb/todo/tables/tasks")"
python3 - "$table" <<'EOF'
import json, sys
cols = {c["key"]: c for c in json.loads(sys.argv[1])["columns"]}
problems = []
if set(cols.get("status", {}).get("elements") or []) != {"open", "doing", "review", "done"}:
    problems.append("status must be open|doing|review|done")
if set(cols.get("priority", {}).get("elements") or []) != {"high", "mid", "low"}:
    problems.append("priority must be high|mid|low")
for key in ("ownerName", "sharedWith", "sharedNames"):
    if key not in cols:
        problems.append(f"missing column {key}")
for key in ("sharedWith", "sharedNames"):
    if key in cols and not cols[key].get("array"):
        problems.append(f"{key} must be an array")
if problems:
    sys.exit("schema drift: " + "; ".join(problems))
EOF

fn="$(api "$APPWRITE_ENDPOINT/functions/$SHARE_FUNCTION_ID")"
echo "$fn" | grep -q '"execute":\["users"\]' || {
  echo "$SHARE_FUNCTION_ID function missing or not executable by users" >&2
  exit 1
}

echo "verify-todo-schema-live: OK"