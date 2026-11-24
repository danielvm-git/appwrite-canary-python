#!/usr/bin/env bash
# Production smoke for current VERSION (SPA-aware).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="$(cat "$ROOT/VERSION")"
BASE="${SMOKE_BASE_URL:-https://python.danielvm.net}"
health="$(curl -skS "$BASE/health.json")"
echo "$health" | grep -q '"status"'
echo "$health" | grep -q '"version"'
LIVE_VER="$(printf '%s' "$health" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
[ -n "$LIVE_VER" ] || { echo "no version in health" >&2; exit 1; }
html="$(curl -skS "$BASE/")"
asset="$(echo "$html" | grep -oE '/assets/index-[^"]+\.js' | head -1)"
[ -n "$asset" ] || { echo "no bundle" >&2; exit 1; }
js="$(curl -skS "$BASE$asset")"
grep -q 'Shared with me' <<<"$js"
grep -q "$LIVE_VER" <<<"$js"
echo "smoke OK v$LIVE_VER @ $BASE"