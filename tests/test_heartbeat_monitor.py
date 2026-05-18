# tests/test_heartbeat_monitor.py
from datetime import datetime, timedelta, timezone
from fastapi.testclient import TestClient
import heartbeat_monitor


def test_state_ws_returns_unknown_when_no_heartbeat():
    """Senza heartbeat ricevuti, /state/ws indica WS sconosciuto."""
    heartbeat_monitor.workstation_state = None
    heartbeat_monitor.last_heartbeat_ts = None
    client = TestClient(heartbeat_monitor.app)
    r = client.get("/state/ws")
    assert r.status_code == 200
    data = r.json()
    assert data["nlu_available"] is False
    assert data["chat_available"] is False
    assert data["ws_state"] is None


def test_state_ws_returns_available_when_rich_payload_received():
    """Con payload ricco fresco + modelli e VRAM ok, nlu_available=True."""
    now = datetime.now(timezone.utc)
    heartbeat_monitor.workstation_state = {
        "ts": now.isoformat(),
        "ollama_ready": True,
        "models_loaded": ["qwen3:4b", "qwen3:14b"],
        "models_warm": ["qwen3:14b"],
        "vram_free_mb": 4096,
        "sleep_policy": "manual_only",
    }
    heartbeat_monitor.last_heartbeat_ts = now
    client = TestClient(heartbeat_monitor.app)
    r = client.get("/state/ws")
    data = r.json()
    assert data["nlu_available"] is True
    assert data["chat_available"] is True
    assert data["ws_state"]["models_loaded"] == ["qwen3:4b", "qwen3:14b"]


def test_state_ws_stale_after_180s():
    """Heartbeat piu' vecchio di 180s -> nlu_available=False."""
    old = datetime.now(timezone.utc) - timedelta(seconds=200)
    heartbeat_monitor.workstation_state = {
        "ts": old.isoformat(),
        "ollama_ready": True,
        "models_loaded": ["qwen3:4b"],
        "models_warm": [],
        "vram_free_mb": 4096,
        "sleep_policy": "manual_only",
    }
    heartbeat_monitor.last_heartbeat_ts = old
    client = TestClient(heartbeat_monitor.app)
    r = client.get("/state/ws")
    data = r.json()
    assert data["nlu_available"] is False
    assert data["freshness_seconds"] > 180


def test_state_ws_unavailable_when_ollama_not_ready():
    """Ollama down -> nlu_available=False anche se heartbeat fresco."""
    now = datetime.now(timezone.utc)
    heartbeat_monitor.workstation_state = {
        "ts": now.isoformat(),
        "ollama_ready": False,
        "models_loaded": [],
        "models_warm": [],
        "vram_free_mb": 4096,
        "sleep_policy": "manual_only",
    }
    heartbeat_monitor.last_heartbeat_ts = now
    client = TestClient(heartbeat_monitor.app)
    assert client.get("/state/ws").json()["nlu_available"] is False


def test_state_ws_unavailable_when_vram_low():
    """VRAM free < 2048 MB -> nlu_available=False (saturation guard)."""
    now = datetime.now(timezone.utc)
    heartbeat_monitor.workstation_state = {
        "ts": now.isoformat(),
        "ollama_ready": True,
        "models_loaded": ["qwen3:4b"],
        "models_warm": [],
        "vram_free_mb": 1024,
        "sleep_policy": "manual_only",
    }
    heartbeat_monitor.last_heartbeat_ts = now
    client = TestClient(heartbeat_monitor.app)
    assert client.get("/state/ws").json()["nlu_available"] is False


def test_post_heartbeat_empty_body_backward_compat():
    """POST /heartbeat con body vuoto deve continuare a funzionare per audio."""
    heartbeat_monitor.last_heartbeat_ts = None
    client = TestClient(heartbeat_monitor.app)
    r = client.post("/heartbeat")
    assert r.status_code == 200
    assert heartbeat_monitor.last_heartbeat_ts is not None


def test_post_heartbeat_rich_payload_stored():
    """POST /heartbeat con JSON body deve aggiornare workstation_state."""
    payload = {
        "ts": "2026-05-18T10:00:00+02:00",
        "ollama_ready": True,
        "models_loaded": ["qwen3:4b"],
        "models_warm": [],
        "vram_free_mb": 3000,
        "sleep_policy": "manual_only",
    }
    client = TestClient(heartbeat_monitor.app)
    r = client.post("/heartbeat", json=payload)
    assert r.status_code == 200
    assert heartbeat_monitor.workstation_state == payload


def test_post_heartbeat_legacy_body_updates_timestamp():
    """Anche con body vuoto, timestamp audio si aggiorna."""
    heartbeat_monitor.last_heartbeat_ts = None
    client = TestClient(heartbeat_monitor.app)
    client.post("/heartbeat")
    after = heartbeat_monitor.last_heartbeat_ts
    assert after is not None
