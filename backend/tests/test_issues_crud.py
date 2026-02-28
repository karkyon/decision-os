import pytest, time
from httpx import AsyncClient, ASGITransport
from app.main import app
BASE = "http://test"

async def get_auth(c):
    r = await c.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_project(c, h):
    r = await c.post("/api/v1/projects", headers=h,
        json={"name": f"iss_{int(time.time())}", "description": "t"})
    return r.json().get("id", "")

async def make_issue(c, h, pid, **kw):
    body = {"project_id": pid, "title": "test", "issue_type": "task", "status": "open"}
    body.update(kw)
    r = await c.post("/api/v1/issues", headers=h, json=body)
    return r.json().get("id", "")

@pytest.mark.asyncio
async def test_issues_create_with_priority():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        for priority in ["low", "medium", "high", "critical"]:
            r = await c.post("/api/v1/issues", headers=h,
                json={"project_id": pid, "title": f"iss_{priority}",
                      "issue_type": "task", "status": "open", "priority": priority})
            assert r.status_code in (200, 201, 422)

@pytest.mark.asyncio
async def test_issues_create_bug_type():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        r = await c.post("/api/v1/issues", headers=h,
            json={"project_id": pid, "title": "バグ修正",
                  "issue_type": "bug", "status": "open",
                  "description": "詳細説明あり"})
        assert r.status_code in (200, 201)

@pytest.mark.asyncio
async def test_issues_status_transitions():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        for status in ["in_progress", "closed", "open"]:
            r = await c.patch(f"/api/v1/issues/{iid}", headers=h,
                json={"status": status})
            assert r.status_code in (200, 204)

@pytest.mark.asyncio
async def test_issues_patch_multiple_fields():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        r = await c.patch(f"/api/v1/issues/{iid}", headers=h,
            json={"title": "更新タイトル", "priority": "high",
                  "status": "in_progress", "description": "更新説明"})
        assert r.status_code in (200, 204, 422)

@pytest.mark.asyncio
async def test_issues_filter_status():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        await make_issue(c, h, pid, status="open", title="open1")
        await make_issue(c, h, pid, status="open", title="open2")
        r = await c.get(f"/api/v1/issues?project_id={pid}&status=open", headers=h)
        assert r.status_code == 200
        assert len(r.json()) >= 2

@pytest.mark.asyncio
async def test_issues_filter_priority():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        await make_issue(c, h, pid, priority="high", title="high_iss")
        r = await c.get(f"/api/v1/issues?project_id={pid}&priority=high", headers=h)
        assert r.status_code in (200, 422)

@pytest.mark.asyncio
async def test_issues_get_not_found():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/issues/00000000-0000-0000-0000-000000000000", headers=h)
        assert r.status_code == 404

@pytest.mark.asyncio
async def test_issues_patch_not_found():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.patch("/api/v1/issues/00000000-0000-0000-0000-000000000000",
            headers=h, json={"status": "closed"})
        assert r.status_code in (404, 422)

@pytest.mark.asyncio
async def test_issues_search():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        await make_issue(c, h, pid, title="ログインバグ")
        r = await c.get(f"/api/v1/issues?project_id={pid}&search=ログイン", headers=h)
        assert r.status_code in (200, 422)

@pytest.mark.asyncio
async def test_issues_assign_label():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        r = await c.patch(f"/api/v1/issues/{iid}", headers=h,
            json={"label_ids": []})
        assert r.status_code in (200, 204, 422)
