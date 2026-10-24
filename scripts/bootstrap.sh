#!/usr/bin/env bash
# bootstrap.sh — install xcodegen if missing, generate the Xcode project, build the SPM packages.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
# Create the "Zones Dev" signing identity only on a developer terminal, never in CI (ADR-0025).
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q '"Zones Dev"'; then
  if [ -t 1 ]; then
    echo "[bootstrap] creating the Zones Dev identity"
    "$root/scripts/dev-cert.sh" || echo "[bootstrap] dev-cert failed; continuing"
  else
    echo "[bootstrap] Zones Dev identity absent and stdout is not a TTY; skipping dev-cert"
  fi
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "[bootstrap] xcodegen missing; installing with brew"
  brew install xcodegen
fi
if [ -f project.yml ]; then
  echo "[bootstrap] xcodegen generate"
  "$root/scripts/q.sh" xcodegen generate
else
  echo "[bootstrap] no project.yml yet; skipping xcodegen"
fi
if [ -f Package.swift ]; then
  echo "[bootstrap] swift build"
  "$root/scripts/q.sh" swift build
else
  echo "[bootstrap] no Package.swift yet; skipping swift build"
fi
echo "[bootstrap] done"
