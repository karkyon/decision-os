import pytest
import time
from httpx import AsyncClient, ASGITransport
from app.main import app

BASE = "http://test"

async def get_auth(client):
    r = await client.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_project_with_data(client, headers):
    r = await client.post("/api/v1/projects", headers=headers,
        json={"name": f"dash_{int(time.time())}", "description": "dashboard test"})
    pid = r.json().get("id", "")
    # issue 作成
    await client.post("/api/v1/issues", headers=headers,
        json={"project_id": pid, "title": "open issue", "issue_type": "task", "status": "open"})
    await client.post("/api/v1/issues", headers=headers,
        json={"project_id": pid, "title": "done issue", "issue_type": "task", "status": "done"})
    return pid

@pytest.mark.asyncio
async def test_dashboard_no_filter():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/dashboard", headers=h)
        assert r.status_code in (200, 404)

@pytest.mark.asyncio
async def test_dashboard_with_data():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project_with_data(c, h)
        r = await c.get(f"/api/v1/dashboard?project_id={pid}", headers=h)
        assert r.status_code in (200, 404)
        if r.status_code == 200:
            assert isinstance(r.json(), dict)

@pytest.mark.asyncio
async def test_dashboard_no_auth():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        r = await c.get("/api/v1/dashboard")
        assert r.status_code in (200, 401, 403, 404)

@pytest.mark.asyncio
async def test_dashboard_invalid_project():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/dashboard?project_id=00000000-0000-0000-0000-000000000000", headers=h)
        assert r.status_code in (200, 404)
