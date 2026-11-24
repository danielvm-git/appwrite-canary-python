#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
grep -qxF v2.0.0 public/shell/SHELL_PIN
! test -f templates/index.html
! test -f scripts/build-dist.sh
bash "$ROOT/scripts/preflight.sh"
export VITE_APPWRITE_ENDPOINT="${VITE_APPWRITE_ENDPOINT:-https://appwrite.danielvm.net/v1}"
export VITE_APPWRITE_PROJECT_ID="${VITE_APPWRITE_PROJECT_ID:-local}"
export VITE_SHARE_FUNCTION_ID=share-task-python
export VITE_CANARY_NAME=Python
export VITE_REPO_URL=https://github.com/danielvm-git/appwrite-canary-python
export VITE_PRODUCT_LABEL=Todo API
npm run build
bundle="$(ls dist/assets/index-*.js | head -1)"
grep -q 'Shared with me' "$bundle"
grep -q share-task-python "$bundle"
grep -q Python "$bundle"
grep -q danielvm-git/appwrite-canary-python "$bundle"
echo "verify-story-e09s01: OK"