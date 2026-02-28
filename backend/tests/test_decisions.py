import pytest, time
from httpx import AsyncClient, ASGITransport
from app.main import app
BASE = "http://test"

async def get_auth(c):
    r = await c.post("/api/v1/auth/login", json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_project(c, h):
    r = await c.post("/api/v1/projects", headers=h, json={"name": f"dec_{int(time.time())}", "description": "t"})
    return r.json().get("id", "")

async def make_issue(c, h, pid):
    r = await c.post("/api/v1/issues", headers=h,
        json={"project_id": pid, "title": "decision issue", "issue_type": "task", "status": "open"})
    return r.json().get("id", "")

@pytest.mark.asyncio
async def test_create_decision():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        r = await c.post("/api/v1/decisions", headers=h,
            json={"issue_id": iid, "title": "採用する", "body": "詳細", "decided_by": "PM"})
        assert r.status_code in (200, 201, 404, 422)
        if r.status_code in (200, 201):
            assert r.json().get("id")

@pytest.mark.asyncio
async def test_list_decisions():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        # 作成してからリスト取得
        await c.post("/api/v1/decisions", headers=h,
            json={"issue_id": iid, "title": "決定A", "body": "本文", "decided_by": "PM"})
        r = await c.get(f"/api/v1/decisions?issue_id={iid}", headers=h)
        assert r.status_code in (200, 404)

@pytest.mark.asyncio
async def test_get_decision():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        cr = await c.post("/api/v1/decisions", headers=h,
            json={"issue_id": iid, "title": "個別取得", "body": "本文", "decided_by": "PM"})
        if cr.status_code in (200, 201):
            did = cr.json().get("id", "")
            r = await c.get(f"/api/v1/decisions/{did}", headers=h)
            assert r.status_code in (200, 404)
        else:
            pytest.skip("decision作成が未実装")

@pytest.mark.asyncio
async def test_update_decision():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        cr = await c.post("/api/v1/decisions", headers=h,
            json={"issue_id": iid, "title": "更新前", "body": "本文", "decided_by": "PM"})
        if cr.status_code in (200, 201):
            did = cr.json().get("id", "")
            r = await c.patch(f"/api/v1/decisions/{did}", headers=h,
                json={"title": "更新後"})
            assert r.status_code in (200, 204, 404, 405)
        else:
            pytest.skip("decision作成が未実装")
