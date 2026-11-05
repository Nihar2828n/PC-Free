#!/usr/bin/env bash
# PC-Free — One-click Windows 10 on GitHub Codespaces
# Tested on GitHub Codespaces (Ubuntu 22.04/24.04) with Docker
# Usage:  bash start.sh
# Then:   open the Ports tab → 8006 → globe icon (Public) → Windows in browser
set -e

# ---------- helpers ----------
info()  { echo -e "\033[1;34m== $*\033[0m"; }
ok()    { echo -e "\033[1;32m✅ $*\033[0m"; }
warn()  { echo -e "\033[1;33m⚠️  $*\033[0m"; }
err()   { echo -e "\033[1;31m❌ $*\033[0m"; }

compose_cmd=""
if docker compose version >/dev/null 2>&1; then
  compose_cmd="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  compose_cmd="docker-compose"
else
  err "Docker Compose not found. Install Docker Engine 20.10+ and try again."
  exit 1
fi

# ---------- 1. machine check ----------
info "Machine check"
echo "--- CPUs / Memory / Disk ---"
nproc || true
free -h | head -n 2 || true
echo
df -h || true
echo

# Show best partitions (helps user pick Codespace machine type)
if df -h | grep -E "/workspaces|/tmp" >/dev/null 2>&1; then
  echo "Largest partitions:"
  df -h | sort -k4 -hr | head -n 5
  echo
fi

if [ ! -e /dev/kvm ]; then
  err "/dev/kvm missing. Windows won't run well here."
  echo "   Fix: In Codespace, recreate it with a larger machine type:"
  echo "        Code → Codespaces → ⋯ → Change machine type → 4-core (or higher)"
  echo "   KVM needs nested virtualization — 2-core Codespaces often lack it."
  echo "   Locally: enable VT-x/AMD-V in BIOS and ensure kvm module is loaded:"
  echo "        sudo modprobe kvm_intel  # or kvm_amd"
  echo "        ls -la /dev/kvm"
  exit 1
fi
ok "KVM found at /dev/kvm"

# Ensure /dev/net/tun exists (required by dockurr/windows for network)
if [ ! -e /dev/net/tun ]; then
  warn "/dev/net/tun missing — creating it"
  sudo mkdir -p /dev/net || true
  sudo mknod /dev/net/tun c 10 200 2>/dev/null || true
  sudo chmod 600 /dev/net/tun 2>/dev/null || true
fi

# ---------- 2. workspace layout ----------
# Works both at repo root and in /workspaces/win (legacy path from early guide)
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
# If user ran the old guide path /workspaces/win, honor it; otherwise use repo root
if [ -d "/workspaces/win" ] && [ "$REPO_ROOT" = "/workspaces/win" ]; then
  BASE_DIR="/workspaces/win"
else
  BASE_DIR="$REPO_ROOT"
fi

info "Using base dir: $BASE_DIR"
mkdir -p "$BASE_DIR/storage" "$BASE_DIR/shared"
cd "$BASE_DIR"

# ---------- 3. .gitignore (never commit secrets or disk images) ----------
if [ ! -f "$BASE_DIR/.gitignore" ]; then
  cat > "$BASE_DIR/.gitignore" <<'GI'
.env
storage/
shared/
*.qcow2
*.img
GI
  ok "Created .gitignore"
else
  # ensure required entries exist
  grep -q "^\.env" "$BASE_DIR/.gitignore" || echo ".env" >> "$BASE_DIR/.gitignore"
  grep -q "^storage/" "$BASE_DIR/.gitignore" || echo "storage/" >> "$BASE_DIR/.gitignore"
fi

# ---------- 4. .env (Windows credentials) ----------
if [ ! -f "$BASE_DIR/.env" ]; then
  if [ -f "$BASE_DIR/.env.example" ]; then
    cp "$BASE_DIR/.env.example" "$BASE_DIR/.env"
    warn "Created .env from .env.example — edit it to change username/password (default: nihar / ChangeMe123!)"
  else
    cat > "$BASE_DIR/.env" <<'ENV'
WINDOWS_USERNAME=nihar
WINDOWS_PASSWORD=ChangeMe123!
ENV
    ok "Created .env with default credentials (edit to personalize)"
  fi
else
  ok ".env already exists — keeping your credentials"
fi

# Warn about weak password
if grep -q "ChangeMe123" "$BASE_DIR/.env" 2>/dev/null; then
  warn "You are using the default password ChangeMe123! — change it in .env before sharing your Codespace"
fi

# ---------- 5. windows10.yml ----------
if [ ! -f "$BASE_DIR/windows10.yml" ]; then
  cat > "$BASE_DIR/windows10.yml" <<'YML'
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
YML
  ok "Created windows10.yml"
else
  ok "windows10.yml already exists — keeping it"
fi

# ---------- 6. (optional) move Docker data-root for low-disk Codespaces ----------
# Uncomment if you hit "no space left" on /var/lib/docker.
# This moves Docker storage to /tmp/docker-data (ephemeral but larger on some runners).
# Requires a docker daemon restart and uses extra time — so we do NOT enable by default.
# To enable manually:
#   sudo mkdir -p /tmp/docker-data
#   echo '{ "data-root": "/tmp/docker-data" }' | sudo tee /etc/docker/daemon.json
#   sudo systemctl restart docker || sudo service docker restart
#   docker info | grep "Docker Root Dir"
#
# We print the current docker root for diagnostics:
if command -v docker >/dev/null 2>&1; then
  echo "Docker Root Dir: $(docker info 2>/dev/null | grep -i "Docker Root Dir" || echo "unknown")"
fi

# ---------- 7. pull and start ----------
info "Starting Windows 10 container (first boot downloads ~4GB — takes 5-10 min)..."
echo "   If this is the first run, be patient — subsequent starts take ~2-3 min."
echo

# Load env for compose (compose does this automatically, but we also export for logging)
set -a
# shellcheck disable=SC1091
[ -f "$BASE_DIR/.env" ] && . "$BASE_DIR/.env"
set +a

# Prefer docker compose -f windows10.yml up -d (detached) so logs can follow
$compose_cmd -f "$BASE_DIR/windows10.yml" up -d

ok "Container started (detached)"
echo
echo "=== How to open Windows ==="
if [ -n "$CODESPACE_NAME" ]; then
  echo "🌐 Direct Browser Link: https://${CODESPACE_NAME}-8006.app.github.dev"
  echo "   (Make sure port 8006 is set to Public in the Ports tab!)"
else
  echo "🌐 Browser Link: http://localhost:8006 (or check forwarded address in Ports tab)"
fi
echo
echo " 1) In Codespaces, open the PORTS tab (bottom panel beside Terminal)"
echo " 2) Find port 8006 → right-click → Port Visibility → Public"
echo " 3) Click the 🌐 globe icon to open Windows in your browser"
echo " 4) RDP also available on localhost:3389 (user: $WINDOWS_USERNAME / pass: from .env)"
echo
echo "=== Useful commands ==="
echo "  docker logs -f windows          # follow boot logs (Ctrl+C to exit, container keeps running)"
echo "  docker stop windows             # graceful shutdown (data persists in ./storage)"
echo "  docker restart windows          # if frozen / black screen"
echo "  $compose_cmd -f windows10.yml down -v   # ⚠️  deletes ALL Windows data"
echo
echo "=== Following logs (Ctrl+C to leave, container keeps running) ==="
docker logs -f windows
