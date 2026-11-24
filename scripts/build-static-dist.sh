#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VER="$(cat VERSION 2>/dev/null || echo 0.1.0)"
rm -rf dist
mkdir -p dist
sed "s/{{ version }}/$VER/g" templates/index.html > dist/index.html
printf '%s\n' "{\"status\":\"ok\",\"version\":\"$VER\"}" > dist/health.json