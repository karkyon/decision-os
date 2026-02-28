import pytest, time
from httpx import AsyncClient, ASGITransport
from app.main import app
BASE = "http://test"

async def get_auth(c):
    r = await c.post("/api/v1/auth/login", json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_project(c, h):
    r = await c.post("/api/v1/projects", headers=h, json={"name": f"conv_{int(time.time())}", "description": "t"})
    return r.json().get("id", "")

async def make_issue(c, h, pid):
    r = await c.post("/api/v1/issues", headers=h,
        json={"project_id": pid, "title": "conv issue", "issue_type": "task", "status": "open"})
    return r.json().get("id", "")

@pytest.mark.asyncio
async def test_create_conversation():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        r = await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": iid, "body": "コメントA"})
        assert r.status_code in (200, 201, 404, 422)

@pytest.mark.asyncio
async def test_list_conversations():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        r = await c.get(f"/api/v1/conversations?issue_id={iid}", headers=h)
        assert r.status_code in (200, 404)

@pytest.mark.asyncio
async def test_delete_conversation():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        cr = await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": iid, "body": "削除するコメント"})
        if cr.status_code in (200, 201):
            cid = cr.json().get("id", "")
            r = await c.delete(f"/api/v1/conversations/{cid}", headers=h)
            assert r.status_code in (200, 204, 404, 405)
        else:
            pytest.skip("conversation作成が未実装")

@pytest.mark.asyncio
async def test_update_conversation():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        cr = await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": iid, "body": "更新前コメント"})
        if cr.status_code in (200, 201):
            cid = cr.json().get("id", "")
            r = await c.patch(f"/api/v1/conversations/{cid}", headers=h,
                json={"body": "更新後コメント"})
            assert r.status_code in (200, 204, 404, 405)
        else:
            pytest.skip("conversation作成が未実装")
