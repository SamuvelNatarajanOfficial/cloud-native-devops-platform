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
    assert b"task_service_http_requests_total" in resp.content
    assert b"task_service_http_request_duration_seconds" in resp.content


def test_metrics_use_route_template_not_resolved_path(client):
    # A request for a specific task ID must NOT create a per-ID label value
    # (unbounded cardinality) - it should be recorded under the route
    # template instead. 404 is expected (no such task); only the metrics
    # labeling is under test here.
    client.get("/tasks/11111111-1111-1111-1111-111111111111")

    body = client.get("/metrics").content
    assert b'path="/tasks/{task_id}"' in body
    assert b"11111111-1111-1111-1111-111111111111" not in body


def test_metrics_label_unmatched_routes_with_a_fixed_value(client):
    client.get("/this-route-does-not-exist")

    body = client.get("/metrics").content
    assert b'path="unmatched"' in body
