#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
test -d functions/share-task
python3 -m pip install -q -r functions/share-task/requirements.txt pytest
python3 -m pytest functions/share-task/test_share.py -q
echo "verify-story-e09s02: OK"