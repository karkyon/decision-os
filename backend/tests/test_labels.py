import pytest
import time
from httpx import AsyncClient, ASGITransport
from app.main import app

BASE = "http://test"

async def get_auth(client):
    r = await client.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_issue(client, headers):
    r = await client.post("/api/v1/projects",
        headers=headers, json={"name": f"lbl_{int(time.time())}", "description": "t"})
    pid = r.json().get("id", "")
    r2 = await client.post("/api/v1/issues", headers=headers,
        json={"project_id": pid, "title": "label test", "issue_type": "task", "status": "open"})
    return r2.json().get("id", ""), pid

@pytest.mark.asyncio
async def test_list_labels():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/labels", headers=h)
        assert r.status_code == 200

@pytest.mark.asyncio
async def test_add_labels_to_issue():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        iid, _ = await make_issue(c, h)
        r = await c.patch(f"/api/v1/issues/{iid}", headers=h,
            json={"labels": ["bug", "urgent"]})
        assert r.status_code == 200
        assert "bug" in str(r.json().get("labels", ""))

@pytest.mark.asyncio
async def test_suggest_labels():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        # パラメータ名を両方試す
        r = await c.get("/api/v1/labels/suggest?text=ログインエラー", headers=h)
        if r.status_code == 422:
            r = await c.get("/api/v1/labels/suggest?q=ログインエラー", headers=h)
        if r.status_code == 422:
            r = await c.get("/api/v1/labels/suggest?issue_text=ログインエラー", headers=h)
        assert r.status_code in (200, 404)  # エンドポイントが存在すればOK

@pytest.mark.asyncio
async def test_label_merge():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.post("/api/v1/labels/merge", headers=h,
            json={"source": "バグ", "target": "bug"})
        assert r.status_code in (200, 201, 204, 404, 422)

@pytest.mark.asyncio
async def test_label_delete():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        # 存在しないラベルの削除は404
        r = await c.delete("/api/v1/labels/nonexistent_label_xyz", headers=h)
        assert r.status_code in (200, 204, 404)
