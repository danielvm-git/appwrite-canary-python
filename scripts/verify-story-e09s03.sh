#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -x "$ROOT/scripts/verify-todo-live.sh"
test -x "$ROOT/scripts/verify-todo-schema-live.sh"
test -x "$ROOT/scripts/observability-check.sh"
grep -q share-task-python "$ROOT/scripts/verify-todo-live.sh"
grep -q share-task-python "$ROOT/scripts/verify-todo-schema-live.sh"
bash "$ROOT/scripts/observability-check.sh"
echo "verify-story-e09s03: OK"