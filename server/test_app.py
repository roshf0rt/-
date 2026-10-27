from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("DB_PATH", str(tmp_path / "test.db"))
    import app
    return TestClient(app.app)


def register(client, nickname, group_id, group_name):
    response = client.post("/v1/users", json={"nickname": nickname, "group": {"id": group_id, "name": group_name}})
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['token']}"}


def lesson_start(days=1):
    return (datetime.now(timezone.utc) + timedelta(days=days)).replace(microsecond=0).isoformat()


def post(client, headers, groups, text="Прочитать главу 3", days=1):
    return client.post("/v1/homework", headers=headers, json={
        "subject": "Событийный маркетинг", "lesson_start": lesson_start(days), "text": text,
        "audience": [{"id": gid, "name": name} for gid, name in groups],
    })


STREAM = [("65979", "УГИ-433505"), ("65980", "УГИ-433410"), ("65981", "УГИ-433515")]


def test_stream_homework_reaches_every_group(client):
    me = register(client, "Рома", "65979", "УГИ-433505")
    friend = register(client, "Аня", "65981", "УГИ-433515")
    stranger = register(client, "Петя", "70000", "РИ-230001")
    assert post(client, me, STREAM).status_code == 200

    seen = client.get("/v1/homework", params={"groups": "65981"}, headers=friend).json()
    assert len(seen) == 1
    assert seen[0]["author"]["nickname"] == "Рома"
    assert seen[0]["mine"] is False
    assert {g["name"] for g in seen[0]["audience"]} == {name for _, name in STREAM}
    assert client.get("/v1/homework", params={"groups": "70000"}, headers=stranger).json() == []


def test_group_only_homework_stays_in_group(client):
    me = register(client, "Рома", "65979", "УГИ-433505")
    friend = register(client, "Аня", "65981", "УГИ-433515")
    post(client, me, STREAM[:1])
    assert client.get("/v1/homework", params={"groups": "65981"}, headers=friend).json() == []
    assert len(client.get("/v1/homework", params={"groups": "65979"}, headers=me).json()) == 1


def test_only_author_can_edit_or_delete(client):
    me = register(client, "Рома", "65979", "УГИ-433505")
    other = register(client, "Аня", "65979", "УГИ-433505")
    item = post(client, me, STREAM[:1]).json()
    body = {"subject": "X", "lesson_start": lesson_start(), "text": "спам", "audience": [{"id": "65979", "name": "УГИ-433505"}]}
    assert client.put(f"/v1/homework/{item['id']}", headers=other, json=body).status_code == 403
    assert client.delete(f"/v1/homework/{item['id']}", headers=other).status_code == 403
    assert client.delete(f"/v1/homework/{item['id']}", headers=me).status_code == 200
    assert client.get("/v1/homework", params={"groups": "65979"}, headers=me).json() == []


def test_old_homework_is_not_listed(client):
    me = register(client, "Рома", "65979", "УГИ-433505")
    post(client, me, STREAM[:1], days=-10)
    assert client.get("/v1/homework", params={"groups": "65979"}, headers=me).json() == []


def test_rejects_bad_input(client):
    assert client.post("/v1/users", json={"nickname": " ", "group": {"id": "1", "name": "x"}}).status_code == 422
    me = register(client, "Рома", "65979", "УГИ-433505")
    assert post(client, me, [("abc", "x")]).status_code == 422
    assert post(client, me, STREAM, text="   ").status_code == 422
    assert client.get("/v1/homework", params={"groups": "1;drop"}, headers=me).status_code == 422
    assert client.get("/v1/homework", params={"groups": "65979"}).status_code == 401


def test_rate_limit(client, monkeypatch):
    import app
    monkeypatch.setattr(app, "POSTS_PER_HOUR", 2)
    me = register(client, "Рома", "65979", "УГИ-433505")
    assert post(client, me, STREAM[:1]).status_code == 200
    assert post(client, me, STREAM[:1]).status_code == 200
    assert post(client, me, STREAM[:1]).status_code == 429


def test_profile_update(client):
    me = register(client, "Рома", "65979", "УГИ-433505")
    response = client.put("/v1/users/me", headers=me, json={"nickname": "Роман", "group": {"id": "65980", "name": "УГИ-433410"}})
    assert response.json()["nickname"] == "Роман"
    assert response.json()["group"]["name"] == "УГИ-433410"
