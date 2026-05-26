# VNC Admin Desktop on driving-pi-01

Second X11 compositor (Xvnc + XFCE) accessible on-demand via VNC :5901 (Tailscale-only),
coexisting with the labwc Wayland kiosk on the DSI 4.3" display.

**Spec:** see `AI Powered/AI Powered/docs/superpowers/specs/2026-05-26-second-compositor-vnc-admin-design.md`

## Layout

- `pi/` — files deployed onto driving-pi-01 (systemd units, xstartup, watchdog)
- `windows/` — files for workstation client (TigerVNC preset, shortcut installer, icon)
- `deploy_to_pi.sh` — one-shot deployment script (rsync + systemctl)
- `tests/` — bats + pytest test suite

## Quick start

```bash
# 1. Deploy to Pi (idempotent)
./deploy_to_pi.sh

# 2. Setup VNC password on Pi (interactive, one-time)
ssh guido@driving-pi-01 'mkdir -p ~/.vnc && vncpasswd ~/.vnc/passwd && chmod 600 ~/.vnc/passwd'

# 3. Generate brand icon (workstation)
python windows/generate_brand_icon.py

# 4. Install Windows shortcut (workstation)
pwsh windows/install_vnc_admin_shortcut.ps1

# 5. Pin to taskbar manually (Start Menu → right-click Admin Pi-01 → Pin to taskbar)
```

## Smoke tests

See `tests/` directory.
