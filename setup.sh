#!/usr/bin/env bash
#
# setup.sh — bootstrap a Cog/WPE WebKit kiosk on Raspberry Pi OS Lite (Bookworm).
#
# Run as root (or with sudo) on a freshly booted Pi. Requires your admin
# panel's git repo URL:
#   sudo ADMIN_REPO_URL=git@github.com:you/signage-admin.git bash setup.sh
#
# Idempotent: safe to re-run. Installs packages, enables the KMS driver,
# creates systemd services for Weston + Cog pointed at a URL that lives in
# a config file, and clones (or pulls, on rerun) your admin panel repo.
#
# Your repo's server.js should read these from process.env:
#   CONFIG_FILE   — path to the signage config JSON (e.g. .../signage/config.json)
#   COG_SERVICE   — systemd unit to restart on config change (cog-kiosk.service)
#   PORT          — port to listen on
#   ADMIN_PASSWORD — basic auth password (from /etc/signage-admin.env)

set -euo pipefail

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
  cat > "$CONFIG_FILE" <<EOF
{
  "url": "${DEFAULT_URL}",
  "refreshSeconds": 0
}
EOF
fi
chown -R "${KIOSK_USER}:${KIOSK_USER}" "${SIGNAGE_DIR}"

# --- 6. Kiosk launch script (reads URL from config.json via jq) ----------
echo "==> Writing /usr/local/bin/start-cog.sh..."
cat > /usr/local/bin/start-cog.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CONFIG_FILE="$1"
URL="$(jq -r '.url' "$CONFIG_FILE")"
exec cog "$URL"
EOF
chmod +x /usr/local/bin/start-cog.sh

# --- 7. systemd unit: weston --------------------------------------------
echo "==> Writing weston-kiosk.service..."
cat > /etc/systemd/system/weston-kiosk.service <<EOF
[Unit]
Description=Weston compositor for kiosk display
After=systemd-user-sessions.service

[Service]
User=${KIOSK_USER}
Group=${KIOSK_USER}
PAMName=login
TTYPath=/dev/tty1
ExecStart=/usr/bin/weston --backend=drm-backend.so
Restart=always
RestartSec=2

[Install]
WantedBy=graphical.target
EOF

# --- 8. systemd unit: cog -------------------------------------------------
echo "==> Writing cog-kiosk.service..."
cat > /etc/systemd/system/cog-kiosk.service <<EOF
[Unit]
Description=Cog kiosk browser
After=weston-kiosk.service
Requires=weston-kiosk.service

[Service]
User=${KIOSK_USER}
Group=${KIOSK_USER}
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u "${KIOSK_USER}")
Environment=WAYLAND_DISPLAY=wayland-1
ExecStart=/usr/local/bin/start-cog.sh ${CONFIG_FILE}
Restart=always
RestartSec=2

[Install]
WantedBy=graphical.target
EOF

# --- 9. sudoers rule so the (future) admin panel can restart cog only ----
echo "==> Writing narrow sudoers rule for restarting cog-kiosk.service..."
cat > /etc/sudoers.d/signage-restart <<EOF
${KIOSK_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl restart cog-kiosk.service
EOF
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
echo "==> Writing signage-admin.service..."
cat > /etc/systemd/system/signage-admin.service <<EOF
[Unit]
Description=Signage admin panel (Express)
After=network.target

[Service]
User=${KIOSK_USER}
WorkingDirectory=${ADMIN_DIR}
EnvironmentFile=${ADMIN_ENV_FILE}
Environment=CONFIG_FILE=${CONFIG_FILE}
Environment=COG_SERVICE=cog-kiosk.service
Environment=PORT=${ADMIN_PORT}
ExecStart=/usr/bin/node ${ADMIN_DIR}/server.js
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

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