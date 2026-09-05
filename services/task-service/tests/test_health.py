def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_ready(client):
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ready"}


def test_metrics(client):
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert b"task_service_requests_total" in resp.content
