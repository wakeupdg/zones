#!/usr/bin/env bash
# dev-cert.sh — create (once) a stable self-signed code-signing identity "Zones Dev" (ADR-0025).
# Ad-hoc signatures change on every build, so macOS drops the Accessibility grant; a stable identity keeps it.
# The identity lives in its own keychain, zones-dev.keychain-db, added to the user search list.
# Usage: scripts/dev-cert.sh            # create if missing, print identity name
#        scripts/dev-cert.sh --remove   # delete the keychain
set -euo pipefail
NAME="Zones Dev"
KC="$HOME/Library/Keychains/zones-dev.keychain-db"
PASS="zones-dev"
if [ "${1:-}" = "--remove" ]; then
  security delete-keychain "$KC" 2>/dev/null || true
  echo "[dev-cert] removed $KC"; exit 0
fi
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "$NAME"; exit 0
fi
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/ext.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=$NAME
[v3]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/ext.cnf" >/dev/null 2>&1
openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout pass:"$PASS" -name "$NAME" >/dev/null 2>&1 \
  || openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout pass:"$PASS" -name "$NAME" >/dev/null 2>&1
if [ ! -f "$KC" ]; then
  security create-keychain -p "$PASS" "$KC"
  security set-keychain-settings "$KC"            # no auto-lock
fi
security unlock-keychain -p "$PASS" "$KC"
# add to the search list (keep existing entries)
existing="$(security list-keychains -d user | tr -d '" ' )"
# shellcheck disable=SC2086
security list-keychains -d user -s $existing "$KC"
security import "$tmp/id.p12" -k "$KC" -P "$PASS" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null
# trust for code signing in the user domain (may show one authorization dialog the first time)
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$tmp/cert.pem" 2>/dev/null || true
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "$NAME"
else
  echo "[dev-cert] identity created but not yet valid for codesigning; run: security find-identity -p codesigning" >&2
  exit 1
fi
