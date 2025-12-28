from fastapi.testclient import TestClient
from healthos_backend.app import app

def test_health():
    c = TestClient(app)
    r = c.get("/health")
    assert r.status_code == 200
    assert r.json()["ok"] is True
