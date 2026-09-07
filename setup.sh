#!/usr/bin/env bash
#
# setup.sh — bootstrap a Cog/WPE WebKit kiosk on Raspberry Pi OS Lite (Bookworm).
#
# Run as root (or with sudo) on a freshly booted Pi. Requires your admin
# panel's git repo URL:
#   sudo ADMIN_REPO_URL=git@github.com:you/signage-admin.git bash setup.sh
#
# Idempotent: safe to re-run. Installs packages, enables the KMS driver,
# renders systemd units + support files from files/ (see render_template),
# and clones (or pulls, on rerun) your admin panel repo.
#
# NOTE: this is a straight extraction of the previous single-file script.
# Logic is unchanged, including two known open issues (graphical.target
# may never be reached on a Lite install, and XDG_RUNTIME_DIR for
# cog-kiosk.service isn't guaranteed to exist) — those are queued for the
# architecture rewrite, not fixed here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="${SCRIPT_DIR}/files"

# --- Configurable bits -------------------------------------------------
KIOSK_USER="${SUDO_USER:-pi}"
SIGNAGE_DIR="/home/${KIOSK_USER}/signage"
CONFIG_FILE="${SIGNAGE_DIR}/config.json"
DEFAULT_URL="https://example.com"
BOOT_CONFIG="/boot/firmware/config.txt"
ADMIN_DIR="/home/${KIOSK_USER}/signage-admin"
ADMIN_PORT=3000
ADMIN_ENV_FILE="/etc/signage-admin.env"
NODE_MAJOR=20
ADMIN_REPO_URL="${ADMIN_REPO_URL:-}"   # set this, e.g. export ADMIN_REPO_URL=git@github.com:you/signage-admin.git

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash setup.sh" >&2
  exit 1
fi

echo "==> Target user: ${KIOSK_USER}"

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

# --- 1. System update ---------------------------------------------------
echo "==> Updating system packages..."
apt-get update -y
apt-get full-upgrade -y

# --- 2. Enable KMS driver (idempotent check) -----------------------------
echo "==> Checking KMS display driver in ${BOOT_CONFIG}..."
if [[ -f "$BOOT_CONFIG" ]] && ! grep -q "^dtoverlay=vc4-kms-v3d" "$BOOT_CONFIG"; then
  echo "dtoverlay=vc4-kms-v3d" >> "$BOOT_CONFIG"
  echo "    Added vc4-kms-v3d overlay. A reboot will be required."
  REBOOT_NEEDED=1
else
  echo "    KMS overlay already present or config.txt not found at expected path."
fi

# --- 3. Install kiosk stack ----------------------------------------------
echo "==> Installing kiosk packages (and git)..."
apt-get install -y weston cog wpewebkit-driver jq git

# --- 4. Group membership for GPU/display access --------------------------
echo "==> Adding ${KIOSK_USER} to video, render, input groups..."
usermod -aG video,render,input "${KIOSK_USER}"

# --- 5. Signage config directory + default config -------------------------
echo "==> Setting up ${SIGNAGE_DIR}..."
mkdir -p "${SIGNAGE_DIR}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  render_template "${FILES_DIR}/config.default.json.tmpl" "$CONFIG_FILE" \
    "DEFAULT_URL=${DEFAULT_URL}"
fi
chown -R "${KIOSK_USER}:${KIOSK_USER}" "${SIGNAGE_DIR}"

# --- 6. Kiosk launch script (reads URL from config.json via jq) ----------
echo "==> Installing /usr/local/bin/start-cog.sh..."
install -m 755 "${FILES_DIR}/start-cog.sh" /usr/local/bin/start-cog.sh

# --- 7. systemd unit: weston --------------------------------------------
echo "==> Rendering weston-kiosk.service..."
render_template "${FILES_DIR}/systemd/weston-kiosk.service.tmpl" \
  /etc/systemd/system/weston-kiosk.service \
  "KIOSK_USER=${KIOSK_USER}"

# --- 8. systemd unit: cog -------------------------------------------------
echo "==> Rendering cog-kiosk.service..."
KIOSK_UID="$(id -u "${KIOSK_USER}")"
render_template "${FILES_DIR}/systemd/cog-kiosk.service.tmpl" \
  /etc/systemd/system/cog-kiosk.service \
  "KIOSK_USER=${KIOSK_USER}" \
  "XDG_RUNTIME_DIR=/run/user/${KIOSK_UID}" \
  "CONFIG_FILE=${CONFIG_FILE}"

# --- 9. sudoers rule so the (future) admin panel can restart cog only ----
echo "==> Rendering narrow sudoers rule for restarting cog-kiosk.service..."
render_template "${FILES_DIR}/sudoers-signage-restart.tmpl" \
  /etc/sudoers.d/signage-restart \
  "KIOSK_USER=${KIOSK_USER}"
chmod 440 /etc/sudoers.d/signage-restart

# --- 10. Install Node.js (only if missing or too old) ---------------------
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
  echo "    Installing Node.js ${NODE_MAJOR}.x via NodeSource..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
fi

# --- 11. Deploy the Express admin app (from your git repo) ----------------
if [[ -z "$ADMIN_REPO_URL" ]]; then
  echo "ERROR: ADMIN_REPO_URL is not set." >&2
  echo "  Run again as: sudo ADMIN_REPO_URL=<your repo url> bash setup.sh" >&2
  exit 1
fi

if [[ -d "${ADMIN_DIR}/.git" ]]; then
  echo "==> ${ADMIN_DIR} already a git repo, pulling latest..."
  sudo -u "${KIOSK_USER}" git -C "${ADMIN_DIR}" pull
else
  echo "==> Cloning ${ADMIN_REPO_URL} into ${ADMIN_DIR}..."
  rm -rf "${ADMIN_DIR}"   # only reached if dir exists but isn't a git repo
  sudo -u "${KIOSK_USER}" git clone "${ADMIN_REPO_URL}" "${ADMIN_DIR}"
fi

echo "==> Installing npm dependencies..."
sudo -u "${KIOSK_USER}" bash -c "cd '${ADMIN_DIR}' && npm install --production"

# --- 12. Admin password (generate once, store in root-only env file) ------
if [[ ! -f "$ADMIN_ENV_FILE" ]]; then
  GENERATED_PASSWORD="$(openssl rand -base64 12)"
  cat > "$ADMIN_ENV_FILE" <<EOF
ADMIN_PASSWORD=${GENERATED_PASSWORD}
EOF
  chmod 600 "$ADMIN_ENV_FILE"
  echo "    Generated admin password (save this now): ${GENERATED_PASSWORD}"
  echo "    It's also stored in ${ADMIN_ENV_FILE} if you lose it."
else
  echo "    Admin password already set in ${ADMIN_ENV_FILE}, leaving as-is."
fi

# --- 13. systemd unit: signage-admin ---------------------------------------
echo "==> Rendering signage-admin.service..."
render_template "${FILES_DIR}/systemd/signage-admin.service.tmpl" \
  /etc/systemd/system/signage-admin.service \
  "KIOSK_USER=${KIOSK_USER}" \
  "ADMIN_DIR=${ADMIN_DIR}" \
  "ADMIN_ENV_FILE=${ADMIN_ENV_FILE}" \
  "CONFIG_FILE=${CONFIG_FILE}" \
  "ADMIN_PORT=${ADMIN_PORT}"

# --- 14. Enable services ---------------------------------------------------
echo "==> Enabling services..."
systemctl daemon-reload
systemctl enable weston-kiosk.service
systemctl enable cog-kiosk.service
systemctl enable signage-admin.service

echo ""
echo "==> Done."
if [[ "${REBOOT_NEEDED:-0}" -eq 1 ]]; then
  echo "    A reboot is required to apply the KMS overlay change."
  echo "    Run: sudo reboot"
else
  echo "    Start now with: sudo systemctl start weston-kiosk cog-kiosk signage-admin"
  echo "    Or reboot to confirm it comes up clean on its own: sudo reboot"
fi
echo ""
echo "    Config file for the URL lives at: ${CONFIG_FILE}"
echo "    Admin panel: http://127.0.0.1:${ADMIN_PORT} (username: admin)"
echo "    Admin password is in ${ADMIN_ENV_FILE} (chmod 600, root-only)."
echo "    Admin app deployed from: ${ADMIN_REPO_URL}"