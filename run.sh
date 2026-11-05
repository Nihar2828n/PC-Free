#!/usr/bin/env bash
set -e

echo "=== 1. Stopping any old container ==="
docker stop windows 2>/dev/null || true
docker rm -f windows 2>/dev/null || true

echo "=== 2. Freeing system memory ==="
sudo sync || true
echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true

echo "=== 3. Writing optimized windows10.yml ==="
cat > windows10.yml << 'EOF'
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "10"
      USERNAME: "nihar"
      PASSWORD: "ChangeMe123!"
      RAM_SIZE: "2G"
      CPU_CORES: "2"
      DISK_SIZE: "64G"
      RAM_CHECK: "N"
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

echo "=== 4. Starting Windows container ==="
if docker compose version >/dev/null 2>&1; then
  docker compose -f windows10.yml up -d
else
  docker-compose -f windows10.yml up -d
fi

echo "=== 5. Container started! Following boot logs ==="
echo "When you see 'Windows started successfully', open:"
echo "https://${CODESPACE_NAME:-probable-funicular-6jv49qq55pjh5vqp}-8006.app.github.dev"
echo "==============================================="
docker logs -f windows
