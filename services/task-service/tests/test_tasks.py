def test_create_and_get_task(client):
    resp = client.post("/tasks", json={"title": "Write README", "description": "Phase 1"})
    assert resp.status_code == 201
    body = resp.json()
    assert body["title"] == "Write README"
    assert body["status"] == "todo"

    task_id = body["id"]
    resp = client.get(f"/tasks/{task_id}")
    assert resp.status_code == 200
    assert resp.json()["id"] == task_id


def test_list_tasks(client):
    client.post("/tasks", json={"title": "Task A"})
    client.post("/tasks", json={"title": "Task B"})

    resp = client.get("/tasks")
    assert resp.status_code == 200
    assert len(resp.json()) == 2


def test_update_task_status(client):
    created = client.post("/tasks", json={"title": "Deploy pipeline"}).json()

    resp = client.patch(f"/tasks/{created['id']}", json={"status": "in_progress"})
    assert resp.status_code == 200
    assert resp.json()["status"] == "in_progress"


def test_delete_task(client):
    created = client.post("/tasks", json={"title": "Temporary"}).json()

    resp = client.delete(f"/tasks/{created['id']}")
    assert resp.status_code == 204

    resp = client.get(f"/tasks/{created['id']}")
    assert resp.status_code == 404


def test_get_missing_task_returns_404(client):
    resp = client.get("/tasks/does-not-exist")
    assert resp.status_code == 404

    resp = client.post("/tasks", json={"title": ""})
    assert resp.status_code == 422
