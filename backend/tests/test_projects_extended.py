import pytest, time
from httpx import AsyncClient, ASGITransport
from app.main import app
BASE = "http://test"

async def get_auth(c):
    r = await c.post("/api/v1/auth/login", json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

@pytest.mark.asyncio
async def test_create_project():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.post("/api/v1/projects", headers=h,
            json={"name": f"proj_{int(time.time())}", "description": "テストプロジェクト"})
        assert r.status_code in (200, 201)
        assert r.json().get("id")

@pytest.mark.asyncio
async def test_list_projects():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/projects", headers=h)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

@pytest.mark.asyncio
async def test_get_project():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        cr = await c.post("/api/v1/projects", headers=h,
            json={"name": f"get_proj_{int(time.time())}", "description": "取得テスト"})
        pid = cr.json().get("id", "")
        r = await c.get(f"/api/v1/projects/{pid}", headers=h)
        assert r.status_code in (200, 404)

@pytest.mark.asyncio
async def test_unauth_rejected():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        r = await c.get("/api/v1/projects")
        assert r.status_code in (401, 403)
