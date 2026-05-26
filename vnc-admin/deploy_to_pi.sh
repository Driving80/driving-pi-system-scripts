#!/bin/bash
# deploy_to_pi.sh — push vnc-admin config files to driving-pi-01 and reload systemd.
# Idempotent: safe to re-run after edits.

set -euo pipefail

PI_HOST="${PI_HOST:-driving-pi-01}"
PI_USER="${PI_USER:-guido}"
PI_SSH="${PI_USER}@${PI_HOST}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_SRC="${SCRIPT_DIR}/pi"

echo "=== Deploying vnc-admin to ${PI_SSH} ==="

# Step 1: ensure target directories exist on Pi
ssh "${PI_SSH}" "mkdir -p ~/.vnc ~/.local/bin ~/.config/systemd/user"

# Step 2: install apt packages (idempotent)
echo "--- Step 2: apt install (sudo required, may prompt) ---"
ssh -t "${PI_SSH}" "sudo apt-get install -y --no-install-recommends \
  tigervnc-standalone-server \
  tigervnc-common \
  xfce4 \
  xfce4-terminal \
  thunar \
  dbus-x11 \
  xauth \
  x11-xserver-utils"

# Step 3: rsync xstartup + idle-watch (preserve executable bit)
echo "--- Step 3: rsync scripts ---"
rsync -av --chmod=u+x "${PI_SRC}/xstartup" "${PI_SSH}:~/.vnc/xstartup"
rsync -av --chmod=u+x "${PI_SRC}/vnc-admin-idle-watch.sh" "${PI_SSH}:~/.local/bin/vnc-admin-idle-watch.sh"

# Step 4: rsync systemd unit files
echo "--- Step 4: rsync systemd units ---"
rsync -av "${PI_SRC}/vnc-admin.socket" "${PI_SSH}:~/.config/systemd/user/vnc-admin.socket"
rsync -av "${PI_SRC}/vnc-admin-proxy.service" "${PI_SSH}:~/.config/systemd/user/vnc-admin-proxy.service"
rsync -av "${PI_SRC}/vnc-admin.service" "${PI_SSH}:~/.config/systemd/user/vnc-admin.service"

# Step 5: enable linger so user services run without active SSH session
echo "--- Step 5: enable linger (one-time, idempotent) ---"
ssh -t "${PI_SSH}" "sudo loginctl enable-linger ${PI_USER}"

# Step 6: daemon-reload + enable socket
echo "--- Step 6: systemd reload + enable socket ---"
ssh "${PI_SSH}" "systemctl --user daemon-reload && systemctl --user enable --now vnc-admin.socket"

# Step 7: verify socket listening
echo "--- Step 7: verify socket ---"
ssh "${PI_SSH}" "systemctl --user is-active vnc-admin.socket && ss -tlnp | grep ':5901' || (echo 'Socket NOT listening!'; exit 1)"

echo ""
echo "=== Deploy complete ==="
echo "Next step: setup VNC password (one-time):"
echo "  ssh ${PI_SSH} 'vncpasswd ~/.vnc/passwd && chmod 600 ~/.vnc/passwd'"
