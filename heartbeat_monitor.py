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
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
from contextlib import asynccontextmanager

# Config
HEARTBEAT_WINDOW = 90  # seconds — if no update within this window, consider Windows offline
HEARTBEAT_PORT = 5005
HEARTBEAT_HOST = "0.0.0.0"

# Adaptive NLU Routing thresholds (Step 3.4 — see ADR 30 in Driving80/ai-powered)
NLU_VRAM_FREE_THRESHOLD_MB = 2048
CHAT_VRAM_FREE_THRESHOLD_MB = 4096
HEARTBEAT_TTL_SECONDS = 180

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
last_heartbeat: datetime | None = None  # naive local time, used by audio switching
last_heartbeat_ts: Optional[datetime] = None  # timezone-aware UTC, used by /state/ws
workstation_state: Optional[dict] = None  # rich payload from Windows
windows_online: bool = False
monitor_task: asyncio.Task | None = None


class WorkstationStatePayload(BaseModel):
    ts: str
    ollama_ready: bool
    models_loaded: list[str] = []
    models_warm: list[str] = []
    vram_free_mb: Optional[int] = None
    sleep_policy: str = "manual_only"


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
async def receive_heartbeat(request: Request):
    """
    Accept heartbeat POST from Windows.

    Backward-compatible: empty body still works (legacy audio-switching path).
    With a JSON body matching WorkstationStatePayload, also stores the rich
    state used by GET /state/ws (Adaptive NLU Routing — Step 3.4).

    Usage:
      curl -X POST http://192.168.68.68:5005/heartbeat
      curl -X POST http://192.168.68.68:5005/heartbeat \
           -H 'Content-Type: application/json' \
           -d '{"ts":"...","ollama_ready":true,"models_loaded":["qwen3:4b"],"models_warm":[],"vram_free_mb":3000,"sleep_policy":"manual_only"}'
    """
    global last_heartbeat, last_heartbeat_ts, workstation_state

    # Always update both timestamps so audio switching stays unaffected.
    last_heartbeat = datetime.now()
    last_heartbeat_ts = datetime.now(timezone.utc)

    # Best-effort rich payload parsing — empty/invalid body is fine (legacy path).
    try:
        body = await request.body()
        if body:
            data = await request.json()
            if isinstance(data, dict) and data:
                # Validate via Pydantic; on success store the original dict shape
                # the tests expect (preserves the exact keys/values they sent).
                WorkstationStatePayload(**data)
                workstation_state = data
    except Exception as e:
        logger.debug(f"heartbeat: no/invalid rich payload ({e!r}); legacy path")

    logger.debug("heartbeat received from Windows")
    return {
        "status": "ok",
        "timestamp": last_heartbeat.isoformat(),
        "windows_online": windows_online,
    }


def _compute_ws_availability() -> dict:
    """Compute nlu_available / chat_available from workstation_state + freshness."""
    now = datetime.now(timezone.utc)
    freshness: Optional[float] = None
    if last_heartbeat_ts is not None:
        freshness = (now - last_heartbeat_ts).total_seconds()

    nlu_available = False
    chat_available = False

    if (
        workstation_state is not None
        and freshness is not None
        and freshness <= HEARTBEAT_TTL_SECONDS
    ):
        ollama_ready = bool(workstation_state.get("ollama_ready"))
        models_loaded = workstation_state.get("models_loaded") or []
        vram_free_mb = workstation_state.get("vram_free_mb")

        nlu_vram_ok = vram_free_mb is None or vram_free_mb >= NLU_VRAM_FREE_THRESHOLD_MB
        chat_vram_ok = vram_free_mb is None or vram_free_mb >= CHAT_VRAM_FREE_THRESHOLD_MB

        if ollama_ready and "qwen3:4b" in models_loaded and nlu_vram_ok:
            nlu_available = True
        if ollama_ready and "qwen3:14b" in models_loaded and chat_vram_ok:
            chat_available = True

    return {
        "ws_state": workstation_state,
        "freshness_seconds": freshness,
        "nlu_available": nlu_available,
        "chat_available": chat_available,
        "computed_at": now.isoformat(),
    }


@app.get("/state/ws")
async def get_state_ws():
    """
    Workstation state for Adaptive NLU Routing (Step 3.4 — ADR 30).

    Returns availability flags based on freshness (<=180s), ollama_ready,
    required models present, and VRAM headroom.
    """
    return _compute_ws_availability()


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