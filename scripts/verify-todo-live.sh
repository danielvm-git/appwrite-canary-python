#!/usr/bin/env bash
# Live Todo slice: two users; user B cannot read user A's task row.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WS="$(cd "$ROOT/.." && pwd)"
PROVISION="$WS/.env.provision"
[[ -f "$PROVISION" ]] || {
  echo "missing $PROVISION" >&2
  exit 1
}
# shellcheck disable=SC1090
source "$PROVISION"
: "${APPWRITE_ENDPOINT:?}"
: "${APPWRITE_PROJECT_ID:?}"
: "${APPWRITE_API_KEY:?}"

SHARE_FUNCTION_ID="${SHARE_FUNCTION_ID:-share-task-python}"

rand="$(openssl rand -hex 4)"
U1="todo-a-${rand}@example.com"
U2="todo-b-${rand}@example.com"
PW="TodoVerify9x${rand}"

curl_json() {
  local method="$1"
  local url="$2"
  shift 2
  curl -skS -X "$method" \
    -H "X-Appwrite-Project: $APPWRITE_PROJECT_ID" \
    -H "Content-Type: application/json" \
    "$url" "$@"
}

curl_key() {
  local method="$1"
  local url="$2"
  shift 2
  curl -skS -X "$method" \
    -H "X-Appwrite-Project: $APPWRITE_PROJECT_ID" \
    -H "X-Appwrite-Key: $APPWRITE_API_KEY" \
    -H "Content-Type: application/json" \
    "$url" "$@"
}

curl_session() {
  local method="$1"
  local url="$2"
  local session="$3"
  shift 3
  curl -skS -X "$method" \
    -H "X-Appwrite-Project: $APPWRITE_PROJECT_ID" \
    -H "X-Appwrite-Session: $session" \
    -H "Content-Type: application/json" \
    "$url" "$@"
}

echo "== users =="
UID_A="todoA${rand}"
UID_B="todoB${rand}"
curl_key POST "$APPWRITE_ENDPOINT/users" \
  -d "{\"userId\":\"$UID_A\",\"email\":\"$U1\",\"password\":\"$PW\",\"name\":\"A\"}" >/dev/null
curl_key POST "$APPWRITE_ENDPOINT/users" \
  -d "{\"userId\":\"$UID_B\",\"email\":\"$U2\",\"password\":\"$PW\",\"name\":\"B\"}" >/dev/null

secret_for() {
  curl_key POST "$APPWRITE_ENDPOINT/users/$1/sessions" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["secret"])'
}

S1="$(secret_for "$UID_A")"
S2="$(secret_for "$UID_B")"
[[ -n "$S1" && -n "$S2" ]] || { echo "session secrets missing" >&2; exit 1; }
UID1="$UID_A"

echo "== create task row as user A =="
ROW_JSON="$(curl_session POST "$APPWRITE_ENDPOINT/tablesdb/todo/tables/tasks/rows" "$S1" \
  -d "{\"rowId\":\"task${rand}\",\"data\":{\"title\":\"secret-${rand}\",\"userId\":\"$UID1\",\"status\":\"open\"}}")"
ROW_ID="$(echo "$ROW_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("$id",""))')"
[[ -n "$ROW_ID" ]] || {
  echo "row create failed: $ROW_JSON" >&2
  exit 1
}
echo "row=$ROW_ID"
echo "$ROW_JSON" | grep -q "user:$UID1" || {
  echo "FAIL: row has no owner permissions (request ran as guest?): $ROW_JSON" >&2
  exit 1
}

echo "== user B read must fail =="
code="$(curl_session GET "$APPWRITE_ENDPOINT/tablesdb/todo/tables/tasks/rows/$ROW_ID" "$S2" \
  -o /tmp/todo-verify-body.json -w '%{http_code}')"
if [[ "$code" == "200" ]]; then
  echo "FAIL: cross-user read allowed" >&2
  cat /tmp/todo-verify-body.json >&2
  exit 1
fi
echo "blocked HTTP $code"

share_as() {
  local session="$1"
  local email="$2"
  local payload
  payload="$(python3 -c 'import json,sys; print(json.dumps({"async":False,"method":"POST","headers":{"content-type":"application/json"},"body":json.dumps({"taskId":sys.argv[1],"email":sys.argv[2]})}))' "$ROW_ID" "$email")"
  curl_session POST "$APPWRITE_ENDPOINT/functions/$SHARE_FUNCTION_ID/executions" "$session" -d "$payload" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("responseBody") or json.dumps(d))'
}

expect_share() {
  local label="$1"
  local want="$2"
  local body="$3"
  echo "$body" | grep -q "$want" || {
    echo "FAIL: $label expected $want got $body" >&2
    exit 1
  }
  echo "$label: $want"
}

echo "== share-task function ($SHARE_FUNCTION_ID) =="
expect_share "A shares with B" '"ok":true' "$(share_as "$S1" "$U2")"
expect_share "A shares twice" '"code":"already"' "$(share_as "$S1" "$U2")"
expect_share "A shares with self" '"code":"self"' "$(share_as "$S1" "$U1")"
expect_share "B re-shares" '"code":"forbidden"' "$(share_as "$S2" "$U1")"

code="$(curl_session GET "$APPWRITE_ENDPOINT/tablesdb/todo/tables/tasks/rows/$ROW_ID" "$S2" -o /dev/null -w '%{http_code}')"
[[ "$code" == "200" ]] || { echo "FAIL: shared read HTTP $code" >&2; exit 1; }
echo "B reads shared row: 200"

code="$(curl_session PATCH "$APPWRITE_ENDPOINT/tablesdb/todo/tables/tasks/rows/$ROW_ID" "$S2" \
  -d '{"data":{"status":"review"}}' -o /dev/null -w '%{http_code}')"
[[ "$code" == "200" ]] || { echo "FAIL: shared status update HTTP $code" >&2; exit 1; }
echo "B moves status to review: 200"

code="$(curl_session DELETE "$APPWRITE_ENDPOINT/tablesdb/todo/tables/tasks/rows/$ROW_ID" "$S2" -o /dev/null -w '%{http_code}')"
[[ "$code" != "204" && "$code" != "200" ]] || { echo "FAIL: shared user deleted row" >&2; exit 1; }
echo "B delete blocked: HTTP $code"

curl_session DELETE "$APPWRITE_ENDPOINT/tablesdb/todo/tables/tasks/rows/$ROW_ID" "$S1" -o /dev/null
curl_key DELETE "$APPWRITE_ENDPOINT/users/$UID_A" -o /dev/null
curl_key DELETE "$APPWRITE_ENDPOINT/users/$UID_B" -o /dev/null
echo "verify-todo-live: OK"