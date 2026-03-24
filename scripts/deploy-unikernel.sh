#!/usr/bin/env bash
# deploy-unikernel.sh
#
# Creates a Hetzner Ubuntu server that:
#   1. Downloads a unikernel image from object storage
#   2. Writes it directly to /dev/sda with dd
#   3. Reboots — the unikernel boots in place of Ubuntu
#
# Usage:
#   ./scripts/deploy-unikernel.sh <image-url> [server-name] [server-type] [location]
#
# Example:
#   ./scripts/deploy-unikernel.sh \
#     https://unikernels.hel1.your-objectstorage.com/nginx_qemu-x86_64 \
#     nginx-unikernel \
#     cpx22 \
#     hel1
#
# Requirements:
#   - HCLOUD_TOKEN env var set (or loaded from sops)
#   - hcloud CLI installed

set -euo pipefail

IMAGE_URL="${1:-}"
SERVER_NAME="${2:-unikernel-$(date +%s)}"
SERVER_TYPE="${3:-cpx22}"
LOCATION="${4:-hel1}"
BASE_IMAGE="ubuntu-24.04"

if [[ -z "$IMAGE_URL" ]]; then
  echo "Usage: $0 <image-url> [server-name] [server-type] [location]"
  exit 1
fi

# Load HCLOUD_TOKEN from SOPS if not set
if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
  SECRETS="$HOME/.openclaw/workspace/secrets/password-store.yaml"
  if [[ -f "$SECRETS" ]]; then
    echo "🔐 Loading HCLOUD_TOKEN from SOPS..."
    HCLOUD_TOKEN=$(sops --decrypt "$SECRETS" | python3 -c "
import sys, yaml
d = yaml.safe_load(sys.stdin)
print(d.get('accounts', {}).get('hetzner', {}).get('api_token', ''))
" 2>/dev/null || true)
  fi
  if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
    echo "❌ HCLOUD_TOKEN is not set."
    exit 1
  fi
fi

export HCLOUD_TOKEN

# Cloud-init: download image, dd to /dev/sda, reboot
USER_DATA=$(cat <<EOF
#cloud-config
write_files:
  - path: /tmp/write-unikernel.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -euo pipefail
      IMAGE_URL="${IMAGE_URL}"
      IMAGE_PATH="/dev/shm/unikernel.img"
      TARGET="/dev/sda"

      echo "[*] Downloading unikernel from \$IMAGE_URL..."
      curl --fail --location --progress-bar -o "\$IMAGE_PATH" "\$IMAGE_URL"

      echo "[*] Writing to \$TARGET..."
      cp /usr/bin/dd /dev/shm/dd
      blkdiscard "\$TARGET" -f || true
      /dev/shm/dd if="\$IMAGE_PATH" of="\$TARGET" bs=4M conv=sync

      echo "[*] Syncing and rebooting..."
      sync
      echo b > /proc/sysrq-trigger
runcmd:
  - /tmp/write-unikernel.sh
EOF
)

echo "🚀 Creating server: $SERVER_NAME ($SERVER_TYPE @ $LOCATION)"
echo "   Base image : $BASE_IMAGE"
echo "   Unikernel  : $IMAGE_URL"
echo ""

USERDATA_FILE=$(mktemp)
echo "$USER_DATA" > "$USERDATA_FILE"

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $HCLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  https://api.hetzner.cloud/v1/servers \
  -d "{
    \"name\": \"$SERVER_NAME\",
    \"server_type\": \"$SERVER_TYPE\",
    \"image\": \"$BASE_IMAGE\",
    \"location\": \"$LOCATION\",
    \"user_data\": $(python3 -c "import json,sys; print(json.dumps(open('$USERDATA_FILE').read()))")
  }")
rm -f "$USERDATA_FILE"

SERVER_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['server']['id'])")
echo "✅ Server created (id: $SERVER_ID)"
echo ""

# Poll until the server comes back up after reboot
echo "⏳ Waiting for unikernel to boot (polling every 10s)..."
for i in $(seq 1 60); do
  INFO=$(curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" \
    "https://api.hetzner.cloud/v1/servers/$SERVER_ID")
  STATUS=$(echo "$INFO" | python3 -c "import sys,json; print(json.load(sys.stdin)['server']['status'])")
  IP=$(echo "$INFO" | python3 -c "import sys,json; print(json.load(sys.stdin)['server']['public_net']['ipv4']['ip'])")
  echo "  [$i/60] status=$STATUS ip=$IP"
  if [[ "$STATUS" == "running" && $i -gt 3 ]]; then
    echo ""
    echo "✅ Server is running: $SERVER_NAME ($IP)"
    echo "   Test: curl http://$IP"
    break
  fi
  sleep 10
done
