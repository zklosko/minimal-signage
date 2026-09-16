#!/usr/bin/env bash
#
# setup.sh — bootstrap a Cog/WPE WebKit kiosk on Raspberry Pi OS Lite (Bookworm).
#
# Run as root (or with sudo) on a freshly booted Pi.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="${SCRIPT_DIR}/files"

# --- Config ---
KIOSK_USER="${SUDO_USER:-pi}"
KIOSK_UID="$(id -u "${KIOSK_USER}")"

SIGNAGE_DIR="/home/${KIOSK_USER}/signage"
NODE_MAJOR=22

BOOT_CONFIG="/boot/firmware/config.txt"
# ADMIN_REPO_URL="https://github.com/zklosko/minimal-signage.git"

REBOOT_NEEDED=0

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash setup.sh" >&2
  exit 1
fi

if ! id "${KIOSK_USER}" >/dev/null 2>&1; then 
  echo "Kiosk user '${KIOSK_USER}' does not exist." >&2 
  exit 1 
fi

echo "==> Target user: ${KIOSK_USER}"
echo "==> Kiosk UID: ${KIOSK_UID}"
echo "==> Signage dir: ${SIGNAGE_DIR}"

# --- Template renderer ---------------------------------------------------
# Renders a {{TOKEN}} template file to a destination path using sed.
# Usage: render_template <template-file> <dest-path> TOKEN=value [TOKEN=value ...]
render_template() {
  local src="$1" dest="$2"
  shift 2
  local sed_args=()
  for pair in "$@"; do
    local key="${pair%%=*}"
    local val="${pair#*=}"
    sed_args+=(-e "s#{{${key}}}#${val}#g")
  done
  sed "${sed_args[@]}" "$src" > "$dest"
}

# --- System update ---
echo "==> Updating system packages..."
apt-get update -y
apt-get full-upgrade -y

# --- Enable KMS driver (idempotent check) -----------------------------
echo "==> Checking KMS display driver in ${BOOT_CONFIG}..."
if [[ -f "$BOOT_CONFIG" ]] && ! grep -q "^dtoverlay=vc4-kms-v3d" "$BOOT_CONFIG"; then
  echo "dtoverlay=vc4-kms-v3d" >> "$BOOT_CONFIG"
  echo "    Added vc4-kms-v3d overlay. A reboot will be required."
  REBOOT_NEEDED=1
else
  echo "    KMS overlay already present or config.txt not found at expected path."
fi

# --- Install kiosk stack ---
echo "==> Installing kiosk packages..."
apt-get install -y cage cog wpewebkit-driver seatd curl ca-certificates

# --- Install Node.js ---
echo ""
echo "==> Checking for Node.js..."
INSTALL_NODE=1

if command -v node >/dev/null 2>&1; then
  CURRENT_MAJOR="$(node -v | sed 's/^v//' | cut -d. -f1)"
  if [[ "$CURRENT_MAJOR" -ge "$NODE_MAJOR" ]]; then
    echo "    Node $(node -v) already installed, skipping."
    INSTALL_NODE=0
  fi
fi
if [[ "$INSTALL_NODE" -eq 1 ]]; then
  echo "    Installing Node.js ${NODE_MAJOR}.x..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
fi

# --- Group membership for GPU/display access ---
echo ""
echo "==> Configuring display permissions..."

if ! getent group seat >/dev/null 2>&1; then
  groupadd --system seat
fi

usermod -aG video,render,input,seat "${KIOSK_USER}"

# --- Enable seatd ---
echo ""
echo "==> Enabling seatd..."

systemctl enable seatd.service
systemctl start seatd.service

# --- Signage config directory + default config ---
echo "==> Creating application directories..."
mkdir -p "${SIGNAGE_DIR}"

chown -R "${KIOSK_USER}:${KIOSK_USER}" "${SIGNAGE_DIR}"

# --- Deploy Fastify ---
echo ""
echo "==> Deploying Fastify backend..."

if [[ ! -f "${SIGNAGE_DIR}/package.json" ]]; then 
  echo "" 
  echo "ERROR: ${SIGNAGE_DIR}/package.json was not found." 
  echo "" 
  echo "Place the Node/Fastify application in:" 
  echo " ${SIGNAGE_DIR}" 
  echo "" 
  exit 1 
fi

sudo -u "${KIOSK_USER}" env \
  HOME="/home/${KIOSK_USER}" \
  npm ci --prefix "${SIGNAGE_DIR}"

sudo -u "${KIOSK_USER}" env \
  npm run build --prefix "${SIGNAGE_DIR}"

sudo -u "${KIOSK_USER}" env \
  npm run db:init --prefix "${SIGNAGE_DIR}"

# --- Install Cog startup script
echo ""
echo "==> Installing /usr/local/bin/start-cog.sh..."

install -m 755 "${SCRIPT_DIR}/installer/start-cog.sh" /usr/local/bin/start-cog.sh

# --- Install Node backend systemd service
echo ""
echo "===> Installing signage.service..."

render_template \
  "${FILES_DIR}/installer/signage.service" \
  /etc/systemd/system/signage.service \
  "KIOSK_USER=${KIOSK_USER}" \
  "SIGNAGE_DIR=${SIGNAGE_DIR}"

# --- Install Cage/Cog kiosk systemd service
echo "" 
echo "==> Rendering signage-kiosk.service..." 

render_template \
  "${FILES_DIR}/installer/signage-kiosk.service" \
  /etc/systemd/system/signage-kiosk.service \
  "KIOSK_USER=${KIOSK_USER}" \
  "KIOSK_UID=${KIOSK_UID}"

# --- Reload systemd and enable services ---
echo ""
echo "==> Reloading systemd and enabling services..."

systemctl daemon-reload
systemctl enable seatd.service
systemctl enable signage.service
systemctl enable signage-kiosk.service

# --- Clean up
echo ""
echo "==> Fixing ownership..."

chown -R \
  "${KIOSK_USER}:${KIOSK_USER}" \
  "${SIGNAGE_DIR}" \
  "${ADMIN_DIR}"

echo "" 
echo "============================================================" 
echo " Installation complete" 
echo "============================================================" 
echo "" 
echo "Kiosk user: ${KIOSK_USER}" 
echo "Kiosk UID: ${KIOSK_UID}" 
echo "" 
echo "Node application: ${SIGNAGE_DIR}" 
echo "Player: http://127.0.0.1:3000/player" 
echo "Admin: http://127.0.0.1:3000/" 
echo ""

if [[ "${REBOOT_NEEDED}" -eq 1 ]]; then 
  echo "A reboot is required because the KMS configuration changed." 
  echo "" 
  echo "Run:" 
  echo " sudo reboot" 
else 
  echo "A reboot is recommended to verify clean boot behavior." 
  echo "" 
  echo "Run:" 
  echo " sudo reboot" 
fi
