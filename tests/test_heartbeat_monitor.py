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


# ---------------------------------------------------------------------------
# Phase 0.a (ADR 34) — declared_state + authoritative_state
# ---------------------------------------------------------------------------


def _reset_monitor_state() -> None:
    heartbeat_monitor.workstation_state = None
    heartbeat_monitor.last_heartbeat_ts = None
    heartbeat_monitor.last_heartbeat = None
    heartbeat_monitor.declared_state = None
    heartbeat_monitor.declared_state_at = None
    heartbeat_monitor.declared_state_source = None


def test_declare_endpoint_accepts_hibernating():
    """POST /state/ws/declare con state='hibernating' aggiorna lo stato dichiarato."""
    _reset_monitor_state()
    client = TestClient(heartbeat_monitor.app)
    r = client.post(
        "/state/ws/declare",
        json={"state": "hibernating", "source": "pre_suspend_hook"},
    )
    assert r.status_code == 200
    assert heartbeat_monitor.declared_state == "hibernating"
    assert heartbeat_monitor.declared_state_source == "pre_suspend_hook"
    assert heartbeat_monitor.declared_state_at is not None


def test_declare_endpoint_accepts_online():
    """POST /state/ws/declare con state='online' (post-wake handler)."""
    _reset_monitor_state()
    client = TestClient(heartbeat_monitor.app)
    r = client.post(
        "/state/ws/declare",
        json={"state": "online", "source": "wake_handler"},
    )
    assert r.status_code == 200
    assert heartbeat_monitor.declared_state == "online"


def test_declare_endpoint_rejects_invalid_state():
    """State non in enum -> 422 validation error."""
    _reset_monitor_state()
    client = TestClient(heartbeat_monitor.app)
    r = client.post(
        "/state/ws/declare",
        json={"state": "frobnicating", "source": "test"},
    )
    assert r.status_code == 422


def test_state_ws_exposes_declared_state():
    """GET /state/ws include declared_state quando settato."""
    _reset_monitor_state()
    client = TestClient(heartbeat_monitor.app)
    client.post(
        "/state/ws/declare",
        json={"state": "hibernating", "source": "pre_suspend_hook"},
    )
    data = client.get("/state/ws").json()
    assert data["declared_state"] == "hibernating"
    assert data["declared_state_source"] == "pre_suspend_hook"
    assert data["declared_state_at"] is not None


def test_authoritative_state_online_when_heartbeat_fresh():
    """Heartbeat fresh -> authoritative='online', declared_state ignorato (heartbeat is truth)."""
    _reset_monitor_state()
    now = datetime.now(timezone.utc)
    heartbeat_monitor.workstation_state = {
        "ts": now.isoformat(),
        "ollama_ready": True,
        "models_loaded": ["qwen3:4b"],
        "models_warm": [],
        "vram_free_mb": 4096,
        "sleep_policy": "manual_only",
    }
    heartbeat_monitor.last_heartbeat_ts = now
    # Anche se declared = "hibernating" (residuo di pre-sleep), heartbeat fresh vince
    heartbeat_monitor.declared_state = "hibernating"
    heartbeat_monitor.declared_state_at = now
    heartbeat_monitor.declared_state_source = "stale_hook"

    data = TestClient(heartbeat_monitor.app).get("/state/ws").json()
    assert data["authoritative_state"] == "online"


def test_authoritative_state_hibernating_when_heartbeat_stale_and_declared():
    """Heartbeat stale (>180s) + declared='hibernating' -> authoritative='hibernating'."""
    _reset_monitor_state()
    old = datetime.now(timezone.utc) - timedelta(seconds=200)
    heartbeat_monitor.last_heartbeat_ts = old
    heartbeat_monitor.workstation_state = {
        "ts": old.isoformat(),
        "ollama_ready": True,
        "models_loaded": ["qwen3:4b"],
        "models_warm": [],
        "vram_free_mb": 4096,
        "sleep_policy": "manual_only",
    }
    heartbeat_monitor.declared_state = "hibernating"
    heartbeat_monitor.declared_state_at = datetime.now(timezone.utc) - timedelta(seconds=10)
    heartbeat_monitor.declared_state_source = "pre_suspend_hook"

    data = TestClient(heartbeat_monitor.app).get("/state/ws").json()
    assert data["authoritative_state"] == "hibernating"


def test_authoritative_state_unknown_when_no_heartbeat_no_declared():
    """Nessun heartbeat, nessuna dichiarazione -> authoritative='unknown'."""
    _reset_monitor_state()
    data = TestClient(heartbeat_monitor.app).get("/state/ws").json()
    assert data["authoritative_state"] == "unknown"


def test_authoritative_state_unknown_when_declared_too_old():
    """Heartbeat stale + declared piu' di 1h fa -> 'unknown' (declared expired)."""
    _reset_monitor_state()
    old = datetime.now(timezone.utc) - timedelta(seconds=400)
    heartbeat_monitor.last_heartbeat_ts = old
    heartbeat_monitor.declared_state = "hibernating"
    # declared > 1h fa -> non piu' affidabile
    heartbeat_monitor.declared_state_at = datetime.now(timezone.utc) - timedelta(hours=2)
    heartbeat_monitor.declared_state_source = "pre_suspend_hook"

    data = TestClient(heartbeat_monitor.app).get("/state/ws").json()
    assert data["authoritative_state"] == "unknown"


def test_declare_endpoint_idempotent_for_same_state():
    """Multiple POST /declare con stesso state aggiornano timestamp ma niente errore."""
    _reset_monitor_state()
    client = TestClient(heartbeat_monitor.app)
    r1 = client.post("/state/ws/declare", json={"state": "hibernating", "source": "x"})
    first_at = heartbeat_monitor.declared_state_at
    # Sleep ridotto -- usiamo solo il fatto che datetime.now avanza ad ogni call
    r2 = client.post("/state/ws/declare", json={"state": "hibernating", "source": "x"})
    second_at = heartbeat_monitor.declared_state_at
    assert r1.status_code == 200 and r2.status_code == 200
    # I due timestamp possono coincidere se la risoluzione e' bassa, ma non
    # devono regredire
    assert second_at >= first_at
