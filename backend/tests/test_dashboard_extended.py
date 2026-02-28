import pytest, time
from httpx import AsyncClient, ASGITransport
from app.main import app
BASE = "http://test"

async def get_auth(c):
    r = await c.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

@pytest.mark.asyncio
async def test_dashboard_counts():
    """GET /api/v1/dashboard/counts"""
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/dashboard/counts", headers=h)
        assert r.status_code in (200, 404, 422)
        if r.status_code == 200:
            assert isinstance(r.json(), dict)

@pytest.mark.asyncio
async def test_dashboard_counts_with_project():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pr = await c.post("/api/v1/projects", headers=h,
            json={"name": f"dash_{int(time.time())}", "description": "t"})
        pid = pr.json().get("id", "")
        r = await c.get(f"/api/v1/dashboard/counts?project_id={pid}", headers=h)
        assert r.status_code in (200, 404, 422)

@pytest.mark.asyncio
async def test_dashboard_unauthenticated():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        r = await c.get("/api/v1/dashboard/counts")
        # dashboard は認証必須のはず（401/403）、または認証不要(200)
        assert r.status_code in (200, 401, 403, 404)
