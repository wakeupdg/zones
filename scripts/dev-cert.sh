#!/usr/bin/env bash
# dev-cert.sh — create (once) a stable self-signed code-signing identity "Zones Dev" (ADR-0025).
# Ad-hoc signatures change on every build, so macOS drops the Accessibility grant; a stable identity keeps it.
# The identity lives in its own keychain, zones-dev.keychain-db, added to the user search list.
#
# Hardening (QA-2.1):
#  - The keychain password is random, generated per machine at creation, and stored ONLY in the login
#    keychain (generic password, service zones-dev-keychain). Nothing secret is in the repo.
#  - The keychain auto-locks after 1 hour and on sleep (set-keychain-settings -t 3600 -l). Builds that need
#    the key call `dev-cert.sh --unlock` first (scripts/merge-ticket.sh does); `--lock` locks it again.
#  - The key partition list is `apple-tool:,apple:` (the blanket `codesign:` entry is dropped). Verified on a
#    throwaway keychain: /usr/bin/codesign still signs with no prompt, because -T /usr/bin/codesign stays.
#  - Remaining trade-off: `-T /usr/bin/codesign` means that, while the keychain is unlocked, ANY local
#    process running codesign can sign as "Zones Dev" without a prompt, and the stored password is
#    readable by processes running as this user through `security`. The window is bounded by the 1-hour
#    auto-lock; treat the unlocked hour as trusted. Do not rotate the identity: the Accessibility grant
#    is keyed to the leaf certificate hash.
#
# Usage: scripts/dev-cert.sh             # create if missing; unlock if present; print identity name
#        scripts/dev-cert.sh --unlock    # unlock with the stored password, re-arm auto-lock (no output)
#        scripts/dev-cert.sh --lock      # lock the keychain
#        scripts/dev-cert.sh --harden    # migrate a keychain made by the old script: random password
#                                        # (old one was the repo constant), stored in login keychain,
#                                        # auto-lock on, `codesign:` partition entry dropped. Keeps the identity.
#        scripts/dev-cert.sh --dry-run [mode]  # print the plan, change nothing
#        scripts/dev-cert.sh --remove    # delete the keychain and the stored password
set -euo pipefail
NAME="Zones Dev"
KC="$HOME/Library/Keychains/zones-dev.keychain-db"
SERVICE="zones-dev-keychain"
LEGACY_PASS="zones-dev" # the old committed constant; used only to migrate with --harden
LOCK_SECONDS=3600
DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi
MODE="${1:-create}"

SECRET="" # set to the live keychain password so --dry-run never prints it
run() { # run <cmd...> — print instead of executing under --dry-run
  if [ "$DRY" = 1 ]; then
    local line="$*"
    if [ -n "$SECRET" ]; then line="${line//"$SECRET"/<password>}"; fi
    echo "[dev-cert] dry-run: $line"
  else
    "$@"
  fi
}
stored_pass() { security find-generic-password -s "$SERVICE" -w 2>/dev/null || true; }
store_pass() { # store_pass <password>
  if [ "$DRY" = 1 ]; then echo "[dev-cert] dry-run: security add-generic-password -a zones-dev -s $SERVICE -w <random> -U"; return; fi
  security add-generic-password -a zones-dev -s "$SERVICE" -w "$1" -U
}
new_pass() { openssl rand -hex 24; }
have_identity() { security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NAME\""; }
arm_autolock() { run security set-keychain-settings -t "$LOCK_SECONDS" -l "$KC"; }
unlock() { # unlock using the stored password; quiet no-op when the keychain or password is missing
  local pass; pass="$(stored_pass)"
  [ -f "$KC" ] && [ -n "$pass" ] || return 1
  SECRET="$pass"
  run security unlock-keychain -p "$pass" "$KC"
  arm_autolock
}
add_to_search_list() {
  local existing
  existing="$(security list-keychains -d user | tr -d '" ')"
  # shellcheck disable=SC2086
  run security list-keychains -d user -s $existing "$KC"
}

case "$MODE" in
  --remove)
    run security delete-keychain "$KC" 2>/dev/null || true
    run security delete-generic-password -s "$SERVICE" >/dev/null 2>&1 || true
    echo "[dev-cert] removed $KC"; exit 0 ;;
  --lock)
    run security lock-keychain "$KC"; exit 0 ;;
  --unlock)
    unlock || { echo "[dev-cert] cannot unlock: keychain or stored password missing (run --harden for a legacy keychain)" >&2; exit 1; }
    exit 0 ;;
  --harden)
    [ -f "$KC" ] || { echo "[dev-cert] no keychain at $KC; nothing to harden" >&2; exit 1; }
    pass="$(stored_pass)"
    if [ -n "$pass" ]; then
      echo "[dev-cert] already hardened (password stored in login keychain); re-arming auto-lock"
      unlock || true
      exit 0
    fi
    pass="$(new_pass)"; SECRET="$pass"
    run security unlock-keychain -p "$LEGACY_PASS" "$KC"
    run security set-keychain-password -o "$LEGACY_PASS" -p "$pass" "$KC"
    store_pass "$pass"
    run security unlock-keychain -p "$pass" "$KC"
    arm_autolock
    run security set-key-partition-list -S apple-tool:,apple: -s -k "$pass" "$KC" >/dev/null
    echo "[dev-cert] hardened $KC (identity unchanged)"; exit 0 ;;
  create) ;;
  *) echo "usage: scripts/dev-cert.sh [--dry-run] [--unlock|--lock|--harden|--remove]" >&2; exit 64 ;;
esac

if have_identity; then
  if ! unlock 2>/dev/null && [ -f "$KC" ]; then
    echo "[dev-cert] note: keychain has no stored password (made by the old script); run scripts/dev-cert.sh --harden" >&2
  fi
  echo "$NAME"; exit 0
fi

pass="$(new_pass)"; SECRET="$pass"
if [ "$DRY" = 1 ]; then
  echo "[dev-cert] dry-run: would generate a random password, store it in the login keychain ($SERVICE), create $KC,"
  echo "[dev-cert] dry-run: import a new self-signed '$NAME' identity with -T /usr/bin/codesign, partition list apple-tool:,apple:,"
  echo "[dev-cert] dry-run: set auto-lock (-t $LOCK_SECONDS -l), and trust it for code signing"
  exit 0
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
openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout pass:"$pass" -name "$NAME" >/dev/null 2>&1 \
  || openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout pass:"$pass" -name "$NAME" >/dev/null 2>&1
if [ -f "$KC" ]; then
  # A keychain exists but holds no valid identity. Reuse it only with a stored password.
  pass="$(stored_pass)"; SECRET="$pass"
  [ -n "$pass" ] || { echo "[dev-cert] $KC exists without a stored password; run --harden or --remove first" >&2; exit 1; }
else
  store_pass "$pass"   # store first: a created keychain is never left without its password
  security create-keychain -p "$pass" "$KC"
fi
security unlock-keychain -p "$pass" "$KC"
arm_autolock
add_to_search_list
security import "$tmp/id.p12" -k "$KC" -P "$pass" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$pass" "$KC" >/dev/null
# trust for code signing in the user domain (may show one authorization dialog the first time)
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$tmp/cert.pem" 2>/dev/null || true
if have_identity; then
  echo "$NAME"
else
  echo "[dev-cert] identity created but not yet valid for codesigning; run: security find-identity -p codesigning" >&2
  exit 1
fi
