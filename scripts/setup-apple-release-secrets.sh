#!/usr/bin/env bash
# One-shot: upload Developer ID + App Store Connect secrets for release.yml.
# Does not print secret values. Run from anywhere; requires `gh` auth with repo access.
#
# Usage:
#   CERT_PASSWORD='…' ./scripts/setup-apple-release-secrets.sh
# Optional env:
#   P12_PATH          default: ~/Downloads/Toast_AppleKey/Toast_AsitKhanda.p12
#   P8_PATH           default: ~/Downloads/Toast_AppleKey/AuthKey_C9L49B94VB.p8
#   AC_API_KEY_ID     default: derived from AuthKey_*.p8 filename
#   AC_API_ISSUER_ID  set only for Team API keys
set -euo pipefail

REPO="${REPO:-asitkhanda/minidown}"
P12_PATH="${P12_PATH:-$HOME/Downloads/Toast_AppleKey/Toast_AsitKhanda.p12}"
P8_PATH="${P8_PATH:-$HOME/Downloads/Toast_AppleKey/AuthKey_C9L49B94VB.p8}"

if [ -z "${CERT_PASSWORD:-}" ]; then
  echo "Set CERT_PASSWORD to the .p12 export password, then re-run." >&2
  exit 1
fi
if [ ! -f "$P12_PATH" ]; then
  echo "Missing P12 at $P12_PATH" >&2
  exit 1
fi
if [ ! -f "$P8_PATH" ]; then
  echo "Missing AuthKey .p8 at $P8_PATH" >&2
  exit 1
fi

KEY_ID="${AC_API_KEY_ID:-}"
if [ -z "$KEY_ID" ]; then
  base=$(basename "$P8_PATH")
  KEY_ID="${base#AuthKey_}"
  KEY_ID="${KEY_ID%.p8}"
fi

echo "Setting secrets on $REPO …"
base64 -i "$P12_PATH" | gh secret set DEVELOPER_ID_CERT_P12 --repo "$REPO"
printf '%s' "$CERT_PASSWORD" | gh secret set CERT_PASSWORD --repo "$REPO"
gh secret set AC_API_KEY_P8 --repo "$REPO" < "$P8_PATH"
printf '%s' "$KEY_ID" | gh secret set AC_API_KEY_ID --repo "$REPO"

if [ -n "${AC_API_ISSUER_ID:-}" ]; then
  printf '%s' "$AC_API_ISSUER_ID" | gh secret set AC_API_ISSUER_ID --repo "$REPO"
  echo "AC_API_ISSUER_ID set (Team key)."
else
  echo "AC_API_ISSUER_ID skipped (omit for Individual keys; set AC_API_ISSUER_ID=… if Team)."
fi

echo "Done. Current secrets:"
gh secret list --repo "$REPO"
