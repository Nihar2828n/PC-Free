#!/usr/bin/env bash
# Exact one-liner the user posted — polished and runnable as:
#   bash scripts/codespace-one-liner.sh
# or paste the body directly into the Codespace terminal.
set -e

echo "== Machine check =="
nproc; free -h | head -2; df -h | tail -n 20

if [ ! -e /dev/kvm ]; then
  echo "❌ /dev/kvm missing. Windows won't run well here. Stop."
  echo "   Fix: recreate Codespace with 4-core+ machine type (needs nested KVM)"
  exit 1
fi

echo "✅ KVM found"

mkdir -p storage shared
# works at repo root — no need for /workspaces/win indirection, but we support both
BASE_DIR="$(pwd)"
printf ".env\nstorage/\n" > .gitignore

cat > .env <<'EOF'
WINDOWS_USERNAME=nihar
WINDOWS_PASSWORD=ChangeMe123!
EOF

cat > windows10.yml <<'EOF'
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "10"
      USERNAME: ${WINDOWS_USERNAME}
      PASSWORD: ${WINDOWS_PASSWORD}
      RAM_SIZE: "8G"
      CPU_CORES: "4"
      DISK_SIZE: "64G"
    cap_add:
      - NET_ADMIN
    ports:
      - "8006:8006"
      - "3389:3389/tcp"
    volumes:
      - ./storage:/storage
      - ./shared:/shared
    devices:
      - /dev/kvm
      - /dev/net/tun
    stop_grace_period: 2m
    restart: unless-stopped
EOF

if docker compose version >/dev/null 2>&1; then
  docker compose -f windows10.yml up -d
else
  docker-compose -f windows10.yml up -d
fi

echo "== Started. Following logs (Ctrl+C to leave, container keeps running) =="
docker logs -f windows
