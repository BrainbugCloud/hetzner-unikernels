#!/usr/bin/env bash
# Build and deploy a unikernel image to Hetzner using ops.
# Credentials are loaded from the SOPS-encrypted password store.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS="$HOME/.openclaw/workspace/secrets/password-store.yaml"
EXAMPLE="${1:-hello-http}"
EXAMPLE_DIR="$REPO_DIR/examples/$EXAMPLE"

if [[ ! -f "$EXAMPLE_DIR/main.go" ]]; then
  echo "❌ Example not found: $EXAMPLE_DIR"
  exit 1
fi

if [[ ! -f "$EXAMPLE_DIR/config.json" ]]; then
  echo "❌ config.json not found in $EXAMPLE_DIR — copy config.json.example and fill it in."
  exit 1
fi

echo "🔐 Loading credentials from SOPS..."
OBJECT_STORAGE_DOMAIN=$(sops --decrypt "$SECRETS" | python3 -c "import sys,yaml; d=yaml.safe_load(sys.stdin); print(d['object_storage']['hetzner']['unikernels']['endpoint'].split('.',1)[1])")
OBJECT_STORAGE_KEY=$(sops --decrypt "$SECRETS" | python3 -c "import sys,yaml; d=yaml.safe_load(sys.stdin); print(d['object_storage']['hetzner']['unikernels']['access_key_id'])")
OBJECT_STORAGE_SECRET=$(sops --decrypt "$SECRETS" | python3 -c "import sys,yaml; d=yaml.safe_load(sys.stdin); print(d['object_storage']['hetzner']['unikernels']['secret_access_key'])")

export OBJECT_STORAGE_DOMAIN
export OBJECT_STORAGE_KEY
export OBJECT_STORAGE_SECRET

if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
  echo "❌ HCLOUD_TOKEN is not set."
  exit 1
fi

echo "✅ Credentials loaded."
echo "   OBJECT_STORAGE_DOMAIN: $OBJECT_STORAGE_DOMAIN"
echo "   OBJECT_STORAGE_KEY:    ${OBJECT_STORAGE_KEY:0:6}..."

cd "$EXAMPLE_DIR"
echo ""
echo "🔨 Building ops image for example: $EXAMPLE"
ops image create -t hetzner -c config.json main.go

echo ""
echo "✅ Image created. To list images:"
echo "   ops image list -t hetzner"
echo ""
echo "To create an instance:"
echo "   ops instance create -t hetzner -c config.json main -p 8080"
