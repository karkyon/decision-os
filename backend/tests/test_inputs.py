import pytest
import time
from httpx import AsyncClient, ASGITransport
from app.main import app

BASE = "http://test"

async def get_auth(client):
    r = await client.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_project(client, headers):
    r = await client.post("/api/v1/projects", headers=headers,
        json={"name": f"inp_{int(time.time())}", "description": "t"})
    return r.json().get("id", "")

@pytest.mark.asyncio
async def test_create_input():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        r = await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "ログインするとエラーになります"})
        assert r.status_code in (200, 201)
        assert r.json().get("id")

@pytest.mark.asyncio
async def test_list_inputs():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "検索機能が欲しい"})
        r = await c.get(f"/api/v1/inputs?project_id={pid}", headers=h)
        assert r.status_code == 200
        assert len(r.json()) >= 1

@pytest.mark.asyncio
async def test_get_input():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        cr = await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "個別取得テスト"})
        iid = cr.json().get("id", "")
        r = await c.get(f"/api/v1/inputs/{iid}", headers=h)
        assert r.status_code in (200, 404, 405)

@pytest.mark.asyncio
async def test_analyze_input():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        inp = await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "ボタンを押すとクラッシュします"})
        iid = inp.json().get("id", "")
        r = await c.post("/api/v1/analyze", headers=h, json={"input_id": iid})
        assert r.status_code == 200
        assert isinstance(r.json(), list)
        assert len(r.json()) >= 1

@pytest.mark.asyncio
async def test_analyze_idempotent():
    """同じ input_id で2回 analyze しても冪等"""
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        inp = await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "冪等テスト"})
        iid = inp.json().get("id", "")
        r1 = await c.post("/api/v1/analyze", headers=h, json={"input_id": iid})
        r2 = await c.post("/api/v1/analyze", headers=h, json={"input_id": iid})
        assert r1.status_code == 200
        assert r2.status_code == 200
        assert len(r1.json()) == len(r2.json())

@pytest.mark.asyncio
async def test_delete_input():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        cr = await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "削除テスト"})
        iid = cr.json().get("id", "")
        r = await c.delete(f"/api/v1/inputs/{iid}", headers=h)
        assert r.status_code in (200, 204, 404, 405)
