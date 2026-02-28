import pytest, time
from httpx import AsyncClient, ASGITransport
from app.main import app
BASE = "http://test"

async def get_auth(c):
    r = await c.post("/api/v1/auth/login", json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_project(c, h):
    r = await c.post("/api/v1/projects", headers=h, json={"name": f"iss_{int(time.time())}", "description": "t"})
    return r.json().get("id", "")

@pytest.mark.asyncio
async def test_list_issues_by_project():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        await c.post("/api/v1/issues", headers=h,
            json={"project_id": pid, "title": "issue A", "issue_type": "task", "status": "open"})
        r = await c.get(f"/api/v1/issues?project_id={pid}", headers=h)
        assert r.status_code == 200
        assert len(r.json()) >= 1

@pytest.mark.asyncio
async def test_patch_issue_status():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        cr = await c.post("/api/v1/issues", headers=h,
            json={"project_id": pid, "title": "patch issue", "issue_type": "task", "status": "open"})
        iid = cr.json().get("id", "")
        r = await c.patch(f"/api/v1/issues/{iid}", headers=h, json={"status": "in_progress"})
        assert r.status_code in (200, 204)

@pytest.mark.asyncio
async def test_get_issue_detail():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        cr = await c.post("/api/v1/issues", headers=h,
            json={"project_id": pid, "title": "detail issue", "issue_type": "task", "status": "open"})
        iid = cr.json().get("id", "")
        r = await c.get(f"/api/v1/issues/{iid}", headers=h)
        assert r.status_code == 200
        assert r.json().get("id") == iid

@pytest.mark.asyncio
async def test_get_trace():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        cr = await c.post("/api/v1/issues", headers=h,
            json={"project_id": pid, "title": "trace issue", "issue_type": "task", "status": "open"})
        iid = cr.json().get("id", "")
        r = await c.get(f"/api/v1/trace/{iid}", headers=h)
        assert r.status_code in (200, 404)
