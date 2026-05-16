#!/usr/bin/env python3
"""
Heartbeat monitor on Pi: switches between librespot and GStreamer RTP.

Logic:
  - Receive HTTP POST /heartbeat every 30s from Windows
  - If heartbeat active (within 90s window) → stop librespot, ensure GStreamer running
  - If heartbeat stale (90s+ no update) → stop GStreamer, ensure librespot running
  - Transitions logged to systemd journal
"""

import asyncio
import logging
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

from fastapi import FastAPI, HTTPException
from contextlib import asynccontextmanager

# Config
HEARTBEAT_WINDOW = 90  # seconds — if no update within this window, consider Windows offline
HEARTBEAT_PORT = 5005
HEARTBEAT_HOST = "0.0.0.0"

# Service names
LIBRESPOT_SERVICE = "librespot.service"
GSTREAMER_SERVICE = "audio-receiver.service"

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s: %(message)s"
)
logger = logging.getLogger(__name__)

# State tracking
last_heartbeat: datetime | None = None
windows_online: bool = False
monitor_task: asyncio.Task | None = None


async def systemd_cmd(action: str, service: str) -> bool:
    """Execute systemctl --user {action} {service}. Return True if success."""
    try:
        result = subprocess.run(
            ["systemctl", "--user", action, service],
            capture_output=True,
            timeout=10,
            text=True
        )
        if result.returncode == 0:
            logger.info(f"✓ {action} {service}")
            return True
        else:
            logger.error(f"✗ {action} {service}: {result.stderr}")
            return False
    except subprocess.TimeoutExpired:
        logger.error(f"✗ {action} {service}: timeout")
        return False
    except Exception as e:
        logger.error(f"✗ {action} {service}: {e}")
        return False


async def on_windows_online():
    """Windows PC came online. Stop librespot, ensure GStreamer running."""
    global windows_online
    if windows_online:
        return  # Already in this state

    logger.info("🟢 Windows ONLINE: stopping librespot, starting GStreamer...")
    await systemd_cmd("stop", LIBRESPOT_SERVICE)
    await asyncio.sleep(1)
    await systemd_cmd("start", GSTREAMER_SERVICE)
    windows_online = True


async def on_windows_offline():
    """Windows PC went offline. Stop GStreamer, ensure librespot running."""
    global windows_online
    if not windows_online:
        return  # Already in this state

    logger.info("🔴 Windows OFFLINE: stopping GStreamer, starting librespot...")
    await systemd_cmd("stop", GSTREAMER_SERVICE)
    await asyncio.sleep(1)
    await systemd_cmd("start", LIBRESPOT_SERVICE)
    windows_online = False


async def monitor_heartbeat():
    """Periodically check if heartbeat is stale. Transition state if needed."""
    while True:
        await asyncio.sleep(10)  # Check every 10 seconds

        if last_heartbeat is None:
            continue

        elapsed = (datetime.now() - last_heartbeat).total_seconds()
        is_fresh = elapsed < HEARTBEAT_WINDOW

        if is_fresh and not windows_online:
            await on_windows_online()
        elif not is_fresh and windows_online:
            await on_windows_offline()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Start monitor task on app startup."""
    global monitor_task
    monitor_task = asyncio.create_task(monitor_heartbeat())
    logger.info("✓ Heartbeat monitor started")
    yield
    monitor_task.cancel()
    logger.info("✓ Heartbeat monitor stopped")


app = FastAPI(lifespan=lifespan)


@app.post("/heartbeat")
async def receive_heartbeat():
    """
    Accept heartbeat POST from Windows.
    Usage: curl -X POST http://192.168.68.68:5005/heartbeat
    """
    global last_heartbeat
    last_heartbeat = datetime.now()
    is_fresh = True

    logger.debug(f"💓 Heartbeat received from Windows")
    return {"status": "ok", "timestamp": last_heartbeat.isoformat(), "windows_online": windows_online}


@app.get("/status")
async def get_status():
    """Check current state."""
    elapsed = (datetime.now() - last_heartbeat).total_seconds() if last_heartbeat else None
    return {
        "windows_online": windows_online,
        "last_heartbeat": last_heartbeat.isoformat() if last_heartbeat else None,
        "elapsed_seconds": elapsed,
        "librespot_active": not windows_online,
        "gstreamer_active": windows_online,
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HEARTBEAT_HOST, port=HEARTBEAT_PORT, log_level="info")