#!/bin/bash
# vnc-admin-idle-watch.sh
# Stops vnc-admin.service after IDLE_MINUTES with no RFB clients connected.
# Deployed to ~/.local/bin/vnc-admin-idle-watch.sh on driving-pi-01.

set -euo pipefail

IDLE_MINUTES="${VNC_ADMIN_IDLE_MINUTES:-10}"
CHECK_INTERVAL="${VNC_ADMIN_CHECK_INTERVAL:-60}"
RFB_PORT="${VNC_ADMIN_RFB_PORT:-5999}"

idle_seconds=0

logger -t vnc-admin-idle "Watchdog started: idle_minutes=${IDLE_MINUTES} check_interval=${CHECK_INTERVAL}s port=${RFB_PORT}"

while true; do
    # Count established TCP connections to Xvnc internal port
    clients=$(ss -t state established "sport = :${RFB_PORT}" 2>/dev/null | tail -n +2 | wc -l)

    if [ "$clients" -eq 0 ]; then
        idle_seconds=$((idle_seconds + CHECK_INTERVAL))
        if [ "$idle_seconds" -ge $((IDLE_MINUTES * 60)) ]; then
            logger -t vnc-admin-idle "Idle for ${IDLE_MINUTES}min, stopping vnc-admin.service"
            systemctl --user stop vnc-admin.service
            exit 0
        fi
    else
        idle_seconds=0
    fi
    sleep "$CHECK_INTERVAL"
done
